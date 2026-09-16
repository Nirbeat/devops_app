# DevOps - App (Node + Express + MongoDB en k3s, con GitOps)

Proyecto de la clase DevOps: una app Node/Express con MongoDB, desplegada en una
VM con k3s (Kubernetes) **y** gestionada con GitOps real (CI/CD + ArgoCD).

## Instalación Terraform (depende SO):
  ```bash
  winget install HashiCorp.Terraform
  ```

## Inicialización Terraform
  ```bash
    terraform init
  ```
## Ver detalles de la implementacion
  ```bash
    terraform plan
  ```

## Crear VM
  ```bash
    terraform apply
  ```

---

## GitOps: ¿qué es y qué hace acá?

GitOps = **Git es la única fuente de verdad**. El clúster (k3s) se mantiene
SIEMPRE en el estado que dice Git. Nadie toca la VM a mano: si el estado de
Git cambia, el clúster cambia automáticamente.

El ciclo completo (todo automático, sin tocar la VM):

```
push a rama "gitops"
   ↓
CI/CD (GitHub Actions / .github/workflows/ci-cd.yml)
   ├─ tests (node + mongodb efímero + supertest)
   ├─ build + push de la imagen a GHCR (ghcr.io/nirbeat/devops-app:<SHA>)
   └─ actualiza kubernetes.yaml en Git con esa imagen (commit "[skip ci]")
   ↓
ArgoCD detecta el cambio en Git
   ↓
ArgoCD auto-sincroniza el clúster (kubectl apply) → app actualizada
```

Flujo en la demo:
1. Hacés `git push` a la rama `gitops`.
2. GitHub Actions testea, compila y sube la imagen a GHCR.
3. El workflow actualiza `kubernetes.yaml` (ramal `gitops`) con la nueva imagen.
4. ArgoCD (instalado en la VM por el bootstrap) ve el cambio y **auto-despliega**.
5. La app queda disponible en `http://<ip-de-la-vm>:30000` sin tocar nada a mano.

## Bootstrap (provision-k8s.ps1) — qué hace cada paso

| Paso | Qué hace |
|------|----------|
| 1-5 | Conecta a la VM, configura sudo, verifica internet, instala k3s |
| 6 | Aplica `kubernetes.yaml` (Mongo + app) al clúster |
| 7 | Espera a que los deployments estén listos |
| 7b | Instala **ArgoCD** en la VM (GitOps) |
| 7c | Crea la `Application` de ArgoCD: vigila el repo (rama `gitops`) |
| 8 | Descarga el kubeconfig al host |
| 9 | Verifica desde el host con `kubectl` |

## ArgoCD a mano (si preferís mostrarlo sin el bootstrap)

El bootstrap ya instala ArgoCD por vos. Si quisieras hacerlo a mano (por
ejemplo para explicarlo en clase):

```bash
# 1) Instalar el namespace + ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.5/manifests/install.yaml

# 2) Esperar al servidor
kubectl rollout status deployment/argocd-server -n argocd

# 3) (Opcional) CLI de ArgoCD
curl -sfL -o argocd https://github.com/argoproj/argo-cd/releases/download/v2.13.5/argocd-linux-amd64
chmod +x argocd

# 4) Ver la Application que crea el bootstrap (el "vigilante" de Git)
kubectl -n argocd get application
```

La `Application` de ArgoCD (la crea `provision-k8s.ps1`, paso 7c) apunta al
propio repo, rama `gitops`, y sincroniza **solo** `kubernetes.yaml`
(excluye `docker-compose.yml` y manifestes que no son de k8s). Con
`syncPolicy.automated` + `selfHeal` + `prune`, Git es la única verdad.

## Imagen

La imagen se publica en GHCR como `ghcr.io/nirbeat/devops-app:<SHA del commit>`
(con el SHA exacto para que ArgoCD despliegue exactamente lo que testearon).
`kubernetes.yaml` se actualiza automáticamente con el SHA en cada push a
`gitops`.
