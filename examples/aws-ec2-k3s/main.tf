# ==============================================================================
# EJEMPLO EDUCATIVO: EL MISMO STACK EN AWS EC2 (con k3s autogestionado)
# ==============================================================================
#
# PARALELISMO CON LO QUE HICIMOS EN LA DEMO:
#   virtualbox_vm.servidor_clase  <--> aws_instance.devops_k3s
#   caja devops-k8s.box           <--> AMI de base (imagen de sistema operativo)
#   NIC1 hostonly + NIC2 NAT      <--> subred VPC + reglas de Security Group
#   provision-k8s.ps1 (SSH host)  <--> user_data / cloud-init (dentro de la VM)
#   paso 8: descargar kubeconfig  <--> comando kubectl en el host (o AWS EKS)
#   kubernetes.yaml               <--> EL MISMO archivo kubernetes.yaml
#
# DATO CLAVE PARA EXPLICAR EN CLASE:
# En AWS el proveedor escribe el script de instalación como `user_data`
# (cloud-init): se ejecuta DENTRO de la máquina en su primer arranque,
# por eso NO hace falta SSH desde el host (adiós a Posh-SSH, SCP y al
# trabajo de descubrir la IP por MAC/ARP que necesitábamos en VirtualBox).
# En un servicio administrado (EKS/AKS/GKE) ni siquiera existiría este
# script: los nodos ya vienen "horneados" con kubelet + containerd.
# ==============================================================================

terraform {
  required_providers {
    # Proveedor "con más funcionalidades": AWS declara máquinas, redes,
    # load balancers, DNS, permisos... y además puede CIERTO estado del sistema
    # (vía provisioners). El proveedor VirtualBox solo sabe crear la VM.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# REGION (equivalente a "tu computadora" en la demo: decide dónde corre todo)
# ------------------------------------------------------------------------------
provider "aws" {
  region = var.region
}

# ------------------------------------------------------------------------------
# RED VPC + SUBNET
# Equivalente local: NIC1 hostonly (red privada donde vive la VM).
# En AWS sin VPC no existe la instancia; elegimos una subnet pública para
# que tenga IP elástica/IP pública y se pueda acceder por SSH y por el navegador.
# ------------------------------------------------------------------------------
resource "aws_vpc" "devops_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = { Name = "vpc-devops" }
}

resource "aws_subnet" "devops_subnet" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = { Name = "subnet-devops" }
}

# Gateway de internet: el equivalente de la NIC2 NAT (salida a internet).
# Sin él, la instancia no baja imágenes de Docker ni ejecuta el instalador.
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.devops_vpc.id
  tags   = { Name = "igw-devops" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.devops_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.devops_subnet.id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------------------------
# SECURITY GROUP (firewall)
# Equivalente local: las reglas que "abríamos" para llegar a la VM desde el host:
#   - 22    -> ssh a la VM (igual que en la demo)
#   - 30000 -> la app (NodePort de app-service, igual que http://IP:30000)
#   - 6443  -> API Server de k3s (igual que kubectl --kubeconfig contra :6443)
# En AWS esto NO se abre con `controlvm` ni con config local: es un recurso.
# ------------------------------------------------------------------------------
resource "aws_security_group" "devops_sg" {
  name   = "devops-sg"
  vpc_id = aws_vpc.devops_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # en producción restringir a tu IP
  }
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 30000
    to_port     = 30000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------------------
# LA MÁQUINA
# Equivalente local: resource "virtualbox_vm" "servidor_clase".
#   -> ami           : la "caja" (imagen de SO). Acá una Ubuntu 22.04 estándar;
#                      en la vida real usarías una AMI "horneada" (Packer)
#                      con k3s preinstalado = tu devops-k8s.box.
#   -> instance_type : equivale a cpu/memory (t2.micro = 1 vCPU/1 GiB).
#   -> key_name      : la llave SSH pública para poder entrar (nuestro
#                      Posh-SSH usaba password; acá la nube exige llaves).
#   -> user_data     : EL REEMPLAZO DE provision-k8s.ps1 (ver abajo).
# ------------------------------------------------------------------------------
resource "aws_instance" "devops_k3s" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.devops_subnet.id
  vpc_security_group_ids = [aws_security_group.devops_sg.id]
  key_name               = var.key_name

  # Almacenamiento de la app (equivalente al PVC mongo-pvc: persistencia).
  # mongo guarda /data/db acá y sobrevive a reinicios de la instancia.
  root_block_device {
    volume_size = 20 # GiB
  }

  user_data = <<-EOF
    #!/bin/bash
    set -ex

    # --- Equivalente a las secciones del provision-k8s.ps1:
    #     1) "sudo NOPASSWD"   -> ya tenemos root (ejecutamos como root)
    #     2) "verificando internet" -> cloud-init ya esperó la red
    #     3) "instalando k3s (tls-san)" -> solo hace falta la IP:
    export IP=$(curl -s http://checkip.amazonaws.com)

    # Instalación de k3s igual que en la demo. En un entorno real con Load
    # Balancer usarías --tls-san <dns-del-balancer>
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san $IP" K3S_KUBECONFIG_MODE=644 sh -

    # Esperar nodo listo (el paso "wait --for=condition=Ready node --all")
    kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml wait --for=condition=Ready node --all --timeout=300s

    # 4) "aplicar kubernetes.yaml" -> EL MISMO ARCHIVO DE LA DEMO.
    # En la nube se sube antes (S3, repo Git) o se embe-be en la AMI.
    kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply -f /opt/kubernetes.yaml

    # 5) esperar deployments (rollout status)
    kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml rollout status deployment/app-deployment --timeout=600s
  EOF

  tags = { Name = "devops-k3s" }
}

# ------------------------------------------------------------------------------
# IMPRIMIR ACCESOS (equivalente al resumen final de provision-k8s.ps1)
#    "App web: http://IP:30000   API k8s: https://IP:6443"
# ------------------------------------------------------------------------------
output "url_app" {
  description = "URL de la app (NodePort 30000)"
  value       = "http://${aws_instance.devops_k3s.public_ip}:30000"
}

output "api_k8s" {
  description = "API Server de k3s"
  value       = "https://${aws_instance.devops_k3s.public_ip}:6443"
}

output "como_obtener_kubeconfig" {
  description = "Paso 8 de la demo (descargar kubeconfig) en AWS self-managed"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.devops_k3s.public_ip} 'sudo cat /etc/rancher/k3s/k3s.yaml' > kubeconfig-aws && sed -i 's#https://127.0.0.1:6443#https://${aws_instance.devops_k3s.public_ip}:6443#' kubeconfig-aws"
}