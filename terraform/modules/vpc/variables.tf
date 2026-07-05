variable "environment" {
  description = "Nombre del entorno (ej. staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block de la VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Lista de CIDR blocks para las subredes públicas"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Lista de CIDR blocks para las subredes privadas"
  type        = list(string)
}

variable "azs" {
  description = "Lista de Zonas de Disponibilidad"
  type        = list(string)
}
