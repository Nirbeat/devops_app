# ==============================================================================
# VARIABLES DEL EJEMPLO AWS EC2
# Equivalente local: variables.tf del demo (vm_name, cpus, memory, image_path...)
# ==============================================================================

variable "region" {
  description = "Región de AWS (equivalente a 'la computadora' en la demo local)"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI de base. En producción usarías una homeada con k3s (Packer) = tu devops-k8s.box"
  type        = string
  default     = "ami-0abcdef1234567890" # reemplazar por una AMI Ubuntu real de tu región
}

variable "instance_type" {
  description = "Tamaño de la máquina (equivale a cpus + memory de VirtualBox)"
  type        = string
  default     = "t3.medium" # 2 vCPU / 4 GiB (equivalente a nuestra VM escalada)
}

variable "key_name" {
  description = "Nombre de la key pair de EC2 (la llave SSH pública de tu cuenta AWS)"
  type        = string
  default     = "mi-clave-devops"
}