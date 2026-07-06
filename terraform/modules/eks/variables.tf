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
