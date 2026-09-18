variable "vm_name" {
  description = "Nombre de la VM en VirtualBox"
  type        = string
  default     = "devops-terraform"
}

variable "cpus" {
  description = "Cantidad de CPUs de la VM (actualizable en caliente)"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memoria de la VM (actualizable en caliente)"
  type        = string
  default     = "4.0 gib"
}

variable "image_path" {
  description = "Ruta a la caja local con k3s preinstalado (golden image)"
  type        = string
  default     = "../devops-k8s.box"
}

variable "root_password" {
  description = "Password de root del box devops-server (para aprovisionar k3s)"
  type        = string
  default     = "devops"
}