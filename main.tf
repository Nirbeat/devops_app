terraform {
  required_providers {
    virtualbox = {
      source  = "terra-farm/virtualbox"
      version = "0.2.2-alpha.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
  }
}

# =============================================================================
# 1. Virtual Machine (crear si no existe / actualizar capacidades si existe)
#    - cpus y memory son actualizables en caliente por el provider
#      (poweroff -> modify -> start).
#    - nic1 hostonly: red privada donde exponemos la app y el API de k8s.
#    - nic2 nat: salida a internet para instalar k3s y bajar imágenes.
# =============================================================================
resource "virtualbox_vm" "servidor_clase" {
  name   = var.vm_name
  cpus   = var.cpus
  memory = var.memory

  image = var.image_path

  network_adapter {
    type           = "hostonly"
    host_interface = "VirtualBox Host-Only Ethernet Adapter"
  }

  network_adapter {
    type = "nat"
  }
}

# =============================================================================
# 2. Kubernetes: instala k3s dentro de la VM y aplica kubernetes.yaml
#    El provider no llega a reportar la IP (Guest Additions v6 rotas), así que
#    el script descubre la IP por MAC + ARP y entra por SSH (Posh-SSH).
#    Se dispara de forma declarativa con:
#      terraform apply -target=null_resource.k8s_bootstrap
# =============================================================================
resource "null_resource" "k8s_bootstrap" {
  triggers = {
    script = filemd5("${path.module}/provision-k8s.ps1")
    yaml   = filemd5("${path.module}/kubernetes.yaml")
    cpus   = var.cpus
    memory = var.memory
    vm_id  = virtualbox_vm.servidor_clase.id
  }

  provisioner "local-exec" {
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File ${abspath(path.module)}/provision-k8s.ps1 -VMName ${var.vm_name} -YamlFile ${abspath(path.module)}/kubernetes.yaml -KubeconfigHost ${abspath(path.module)}/kubeconfig-devops"

    environment = {
      ROOT_PASSWORD = var.root_password
    }
  }

  depends_on = [virtualbox_vm.servidor_clase]
}

output "nombre_vm" {
  value       = virtualbox_vm.servidor_clase.name
  description = "Nombre de la instancia clonada desde la imagen base local"
}

output "url_app" {
  value       = "http://${virtualbox_vm.servidor_clase.network_adapter[0].ipv4_address}:30000"
  description = "URL de la aplicación web expuesta por Kubernetes (NodePort 30000)"
}