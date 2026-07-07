variable "environment" {
  description = "Nombre del entorno (ej. staging, prod)"
  type        = string
}

variable "public_subnet_ids" {
  description = "Lista de IDs de las subredes públicas"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Lista de IDs de las subredes privadas"
  type        = list(string)
}

variable "ci_cd_role_arn" {
  description = "ARN del rol de IAM de CI/CD para darle permisos de administrador en el clúster EKS"
  type        = string
  default     = ""
}
