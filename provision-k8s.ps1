<#
.SYNOPSIS
  Aprovisiona Kubernetes (k3s) dentro de la VM devops-terraform y aplica
  kubernetes.yaml. Descubre la IP de la VM por MAC usando, en orden:
    1) leases DHCP de VirtualBox (fiable),
    2) ping broadcast + tabla ARP,
    3) SSH via NAT port-forward (127.0.0.1:2222) consultando `ip`.
  Usa el usuario del box (devops-server) + sudo NOPASSWD (se autoconfigura).
#>
param(
  [string]$VMName = 'devops-terraform',
  [string]$YamlFile = '',
  [string]$RootPassword = 'devops',
  [string]$KubeconfigHost = '',
  [string]$SshUser = 'devops-server'
)

if ($env:ROOT_PASSWORD) { $RootPassword = $env:ROOT_PASSWORD }

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Import-Module Posh-SSH -ErrorAction Stop

if ($YamlFile -and -not [System.IO.Path]::IsPathRooted($YamlFile)) {
  $YamlFile = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $YamlFile))
}
if (-not $KubeconfigHost) { $KubeconfigHost = Join-Path (Get-Location) 'kubeconfig-devops' }
if (-not [System.IO.Path]::IsPathRooted($KubeconfigHost)) {
  $KubeconfigHost = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $KubeconfigHost))
}
if ($YamlFile -and -not (Test-Path $YamlFile)) { throw "YamlFile no existe: $YamlFile" }

Write-Output "== VM: $VMName"

function Get-VMMac {
  try {
    $out = & VBoxManage showvminfo $VMName --machinereadable 2>$null
    $line = ($out | Where-Object { $_ -match '^macaddress1=' }) | Select-Object -First 1
    if (-not $line) { return $null }
    $hex = $line -replace '^macaddress1="?([0-9A-Fa-f]+)"?$', '$1'
    $pairs = for ($i = 0; $i -lt $hex.Length; $i += 2) { $hex.Substring($i, 2) }
    return (($pairs -join ':')).ToLower()
  } catch { return $null }
}

function Get-VMState {
  try {
    $out = & VBoxManage showvminfo $VMName --machinereadable 2>$null
    $line = ($out | Where-Object { $_ -match '^VMState=' }) | Select-Object -First 1
    if ($line) { return $line.Trim() }
  } catch { }
  return ''
}

function Get-HasNatPf {
  try {
    $out = & VBoxManage showvminfo $VMName --machinereadable 2>$null
    return [bool]($out | Where-Object { $_ -match '^natpf' })
  } catch { return $false }
}

function Get-VMIPFromLeases([string]$Mac) {
  $dirs = @(
    (Join-Path $env:USERPROFILE '.VirtualBox'),
    (Join-Path $env:USERPROFILE '.config\VirtualBox'),
    (Join-Path $env:LOCALAPPDATA 'VirtualBox')
  )
  foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { continue }
    $files = Get-ChildItem -Path $d -Filter '*-Dhcpd.leases*' -ErrorAction SilentlyContinue
    foreach ($f in $files) {
      try {
        [xml]$leases = Get-Content $f.FullName -Raw -ErrorAction Stop
        foreach ($l in $leases.Leases.Lease) {
          if ($l.mac -eq $Mac -and $l.state -eq 'acked') {
            $addr = $l.Address.value.Trim()
            if ($addr -and $addr -notmatch '^0\.0\.0\.0') {
              Write-Host "  [leases] $($f.Name) -> $addr" -ForegroundColor DarkGray
              return $addr
            }
          }
        }
      } catch { }
    }
  }
  return $null
}

function Get-VMIPByArp([string]$Mac) {
  for ($i = 0; $i -lt 36; $i++) {
    ping -n 1 -w 300 192.168.56.255 | Out-Null
    if ($i % 3 -eq 0) {
      20..140 | ForEach-Object { $x = "192.168.56.$_"; Start-Job -ScriptBlock { ping -n 1 -w 200 $using:x | Out-Null } | Out-Null }
      Start-Sleep -Seconds 2
    }
    $arp = arp -a -N 192.168.56.1 2>$null
    foreach ($line in $arp) {
      if ($line -match ($Mac -replace ':','-')) {
        $ip = ($line -split '\s+') | Where-Object { $_ -match '^192\.168\.56\.' } | Select-Object -First 1
        if ($ip) { Write-Host "  [arp] $ip" -ForegroundColor DarkGray; return $ip }
      }
    }
    Start-Sleep -Seconds 5
  }
  return $null
}

function Get-Cred {
  $secure = ConvertTo-SecureString $RootPassword -AsPlainText -Force
  return New-Object System.Management.Automation.PSCredential($SshUser, $secure)
}

function New-SshWithRetry([string]$HostName, [int]$Port = 22, [int]$Tries = 50) {
  $cred = Get-Cred
  for ($i = 0; $i -lt $Tries; $i++) {
    try {
      $s = New-SSHSession -ComputerName $HostName -Port $Port -Credential $cred -AcceptKey -ConnectionTimeout 20 -ErrorAction Stop
      if ($s) { return $s }
    } catch {
      Start-Sleep -Seconds 10
    }
  }
  return $null
}

function Get-VMIPViaNat([string]$Mac) {
  if (-not (Get-HasNatPf)) { return $null }
  $s = New-SshWithRetry '127.0.0.1' 2222 10
  if (-not $s) { return $null }
  try {
    $r = Invoke-SSHCommand -SessionId $s.SessionId -Command 'ip -4 addr show | grep -oE "inet 192\.168\.56\.[0-9]+" | head -n1'
    if ($r.Output) {
      $ip = (($r.Output -join '') -replace 'inet\s+', '').Trim()
      if ($ip) { Write-Host "  [nat-ssh] $ip" -ForegroundColor DarkGray; return $ip }
    }
  } finally {
    Remove-SSHSession -SessionId $s.SessionId | Out-Null
  }
  return $null
}

# 1) Esperar que la VM exista y esté corriendo
Write-Output '== 1) Esperando VM corriendo...'
$running = $false
for ($i = 0; $i -lt 180; $i++) {
  if ((Get-VMState) -match 'running') { $running = $true; break }
  Start-Sleep -Seconds 5
}
if (-not $running) { throw 'La VM no pasó a estado running' }

# 2) Descubrir IP
$mac = Get-VMMac
if (-not $mac) { throw 'No pude leer la MAC de la VM' }
Write-Output "MAC: $mac"
$ip = Get-VMIPFromLeases $mac
if (-not $ip) {
  Write-Output '  leases no dio IP, probando ARP broadcast...'
  $ip = Get-VMIPByArp $mac
}
if (-not $ip) {
  Write-Output '  ARP no dio IP, probando NAT ssh (port-forward 2222)...'
  $ip = Get-VMIPViaNat $mac
}
if (-not $ip) { throw "No pude descubrir la IP de la VM (MAC $mac)" }
Write-Output "IP de la VM: $ip"

# 3) Sesión SSH por la IP descubierta
Write-Output '== 2) Conectando por SSH...'
# Poblar ARP antes de conectar (evita SYN perdido con ARP fría)
Write-Output "  ping warmup a $ip ..."
ping -n 2 -w 1000 $ip | Out-Null
Start-Sleep -Seconds 2
$session = New-SshWithRetry $ip 22 60
if (-not $session) { throw 'No pude abrir sesión SSH' }
Write-Output ("Sesión abierta: {0} (id {1})" -f $session.Host, $session.SessionId)

function Invoke-Remote {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [int]$TimeOut = 1200,
    [bool]$Check = $true,
    [string]$Label = ''
  )
  if ($Label) { Write-Output "-- $Label" }
  $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $Command -TimeOut $TimeOut
  if ($r.Output) { Write-Output ($r.Output -join [Environment]::NewLine) }
  if ($r.Error)  { Write-Output ('[stderr] ' + ($r.Error -join [Environment]::NewLine)) }
  if ($Check -and $r.ExitStatus -ne 0) {
    throw "Comando falló (exit $($r.ExitStatus)): $Command"
  }
  return $r
}

# 4) Habilitar sudo NOPASSWD para el usuario (requiere password una vez vía stdin)
Write-Output '== 3) Configurando sudo NOPASSWD...'
$noPassSudo = "printf '%s\n' `"$RootPassword`" | sudo -S -p '' bash -c `"echo '$SshUser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/devops-no-passwd && chmod 440 /etc/sudoers.d/devops-no-passwd`""
Invoke-Remote $noPassSudo 60 $true 'sudo NOPASSWD'
Invoke-Remote 'sudo -n true' 30 $true 'verificando sudo'

# 5) Internet (NAT) para k3s
Write-Output '== 4) Verificando salida a internet (NAT)...'
$inet = $false
for ($i = 0; $i -lt 20; $i++) {
  $r = Invoke-Remote 'curl -sI --max-time 12 https://get.k3s.io | head -n1' -TimeOut 30 -Check $false
  if ($r.Output -match '200|301|302|40[0-9]') { $inet = $true; break }
  Start-Sleep -Seconds 10
}
if ($inet) { Write-Output 'Internet OK' } else { Write-Output '[warn] Sin confirmación de internet; continuo igual' }

# 6) Instalar k3s (idempotente), con tls-san para acceso externo por IP
Write-Output '== 5) Instalando k3s (tls-san)...'
$chk = Invoke-Remote 'command -v k3s || true' -Check $false
if ($chk.Output -match '/k3s') {
  Write-Output 'k3s ya instalado, actualizo tls-san e IP del nodo (config.yaml)'
  Invoke-Remote "printf 'tls-san:\n  - $ip\n' | sudo tee /etc/rancher/k3s/config.yaml > /dev/null"
  Invoke-Remote "sudo sed -i 's#--node-ip [^ ]*#--node-ip $ip#g' /etc/systemd/system/k3s.service 2>/dev/null || true" -Check $false
  Invoke-Remote "sudo systemctl daemon-reload && sudo systemctl restart k3s || true" -Check $false -TimeOut 600
} else {
  Invoke-Remote 'curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh' 300 $true 'descargando instalador'
  Invoke-Remote "sudo env INSTALL_K3S_EXEC=`"server --tls-san $ip`" K3S_KUBECONFIG_MODE=644 bash /tmp/k3s-install.sh" 1200 $true 'instalando k3s'
}
Invoke-Remote 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml wait --for=condition=Ready node --all --timeout=420s' -TimeOut 600 -Label 'esperando nodo Ready'

# 7) Subir y aplicar kubernetes.yaml
if ($YamlFile) {
  Write-Output '== 6) Subiendo kubernetes.yaml...'
  $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($YamlFile))
  $pushYaml = "echo $b64 | base64 -d | sudo tee /opt/kubernetes.yaml > /dev/null"
  Invoke-Remote $pushYaml 300 $true 'enviando yaml (base64)'
  Invoke-Remote 'sudo chown root:root /opt/kubernetes.yaml' 30 $true 'permisos yaml'
  Invoke-Remote 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply -f /opt/kubernetes.yaml' 300 $true 'aplicando kubernetes.yaml'

  Write-Output '== 7) Esperando deployments...'
  Invoke-Remote 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml rollout status deployment/mongo-deployment --timeout=600s' -TimeOut 900
  Invoke-Remote 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml rollout status deployment/app-deployment --timeout=900s' -TimeOut 1200
}

# ------------------------------------------------------------------------------
# == 7b) INSTALAR ARGOCD (GitOps) — CLASE DEV
# ------------------------------------------------------------------------------
# Qué es ArgoCD: una herramienta de "GITOPS". Su función PRINCIPAL es que Git
# sea la ÚNICA fuente de verdad: ArgoCD vigila un repo Git y mantiene EL
# CLÚSTER en el estado que Git dice. Si alguien cambia el clúster a mano,
# ArgoCD lo revierte (selfHeal). Si cambia Git, ArgoCD lo aplica (auto-sync).
#
# Nota: aquí lo instalamos PERO el objetivo de la clase es que quede operativo
# y que se explique su existencia y función. La app la despliega k3s normal
# (rollout status de arriba); ArgoCD queda instalado por si quieres mostrarlo.
Write-Output '== 7b) Instalando ArgoCD (GitOps)...'
Invoke-Remote 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml create namespace argocd --dry-run=client -o yaml | kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply -f -' -TimeOut 120 $true 'creando namespace argocd (idempotente)'
Invoke-Remote 'curl -sfL https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.5/manifests/install.yaml -o /tmp/argocd-install.yaml' 300 $true 'descargando install.yaml de ArgoCD'
Invoke-Remote 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply -n argocd -f /tmp/argocd-install.yaml' 300 $true 'aplicando ArgoCD'
Invoke-Remote 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml rollout status deployment/argocd-server -n argocd --timeout=300s' -TimeOut 420 $true 'esperando argocd-server'

# ---------------- Solo CLI: descargar argocd (sin UI) ----------------
Invoke-Remote 'sudo curl -sfL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/v2.13.5/argocd-linux-amd64 && sudo chmod +x /usr/local/bin/argocd' 300 $true 'instalando CLI de ArgoCD'
Invoke-Remote 'argocd version --client 2>&1 | head -n 2' -Check $false -TimeOut 60

# ------------------------------------------------------------------------------
# == 7c) Application de ArgoCD: EL OjO QUE VIGILA GIT (GitOps real)
# ------------------------------------------------------------------------------
# Hasta aca ArgoCD esta INSTALADO, pero nO mira nada. Con este objeto le decimos:
#   - que repo vigilar (este mismo, publico, sin credenciales)
#   - que rama (gitops: ahi hace push el CI cuando hay una imagen nueva)
#   - que carpeta (la raiz ".", donde vive kubernetes.yaml)
#   - que haga auto-sync + selfHeal + prune (Git = unica fuente de verdad)
# Como el repo es publico no hace falta login. Si git ops y VM son lo mismo repo.
Write-Output '== 7c) Creando Application de ArgoCD (GitOps real)...'
$argoApp = @'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: devops-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Nirbeat/devops_app.git
    targetRevision: gitops
    path: .
    directory:
      recurse: false
      exclude: '{docker-compose.yml,*.bak,*.md,*.tf}'
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
'@
$appB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($argoApp))
Invoke-Remote "echo $appB64 | base64 -d | sudo tee /tmp/argocd-application.yaml > /dev/null" 60 $true 'escribiendo Application de ArgoCD en la VM'
Invoke-Remote 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply -n argocd -f /tmp/argocd-application.yaml' 120 $true 'aplicando Application de ArgoCD'
Invoke-Remote 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get application -n argocd' -Check $false -TimeOut 60

# 8) Descargar kubeconfig al host (server apuntando a la IP de la VM)
Write-Output '== 8) Descargando kubeconfig al host...'
$cfg = Invoke-Remote 'cat /etc/rancher/k3s/k3s.yaml' -Check $false
if (-not ($cfg.Output -join '')) { throw 'No pude leer k3s.yaml' }
$content = ($cfg.Output -join "`n")
$content = $content -replace 'https://127\.0\.0\.1:6443', "https://$ip`:6443"
$header = @(
  '# =============================================================',
  '# KUBECONFIG GENERADO AUTOMATICAMENTE (no editar).',
  '#',
  '# QUE ES: archivo local que le dice a tu kubectl del HOST cómo',
  '#   conectarse a la API de Kubernetes que corre DENTRO de la VM.',
  '#',
  '# QUIEN LO USA: solo tu host (kubectl --kubeconfig kubeconfig-devops).',
  '#   La VM NO lo usa: ella trabaja con su copia interna',
  '#   /etc/rancher/k3s/k3s.yaml.',
  '#',
  '# COMO SE GENERA: paso 8 del bootstrap (provision-k8s.ps1): lee',
  '#   /etc/rancher/k3s/k3s.yaml de la VM y reemplaza 127.0.0.1 por',
  '#   la IP actual de la VM (cambia en cada import = MAC nueva).',
  '#',
  '# COMO SE USA:  kubectl --kubeconfig kubeconfig-devops get nodes',
  '#   Ver más: https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/',
  '# =============================================================',
  ''
) -join "`n"
$content = $header + $content
$dir = Split-Path $KubeconfigHost -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -Path $KubeconfigHost -Value $content -Encoding UTF8
Write-Output "kubeconfig host: $KubeconfigHost"

# 9) Guardar la URL de la app en url.txt (vigente aunque cambie la IP)
$urlFile = Join-Path (Get-Location) 'url.txt'
$url = "http://$ip`:30000"
Set-Content -Path $urlFile -Value $url -Encoding UTF8
Write-Output "URL guardada en: $urlFile"

# 10) Verificar desde el host con kubectl
$kc = Get-Command kubectl -ErrorAction SilentlyContinue
if ($kc) {
  Write-Output '== 9) Verificación desde el host (kubectl)...'
  kubectl --kubeconfig $KubeconfigHost get nodes | Out-String | Write-Output
  kubectl --kubeconfig $KubeconfigHost get pods -o wide | Out-String | Write-Output
  kubectl --kubeconfig $KubeconfigHost get svc | Out-String | Write-Output
  kubectl --kubeconfig $KubeconfigHost get pvc | Out-String | Write-Output
}

Remove-SSHSession -SessionId $session.SessionId | Out-Null

Write-Output ''
Write-Output '=================================================='
Write-Output "  App web:      http://$ip`:30000"
Write-Output "  API de k8s:   https://$ip`:6443"
Write-Output "  kubeconfig:   $KubeconfigHost"
Write-Output "  kubectl:      kubectl --kubeconfig $KubeconfigHost get nodes"
Write-Output '=================================================='