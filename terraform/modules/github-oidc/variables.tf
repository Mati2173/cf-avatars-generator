variable "github_repo" {
  description = "Nombre del repositorio (e.g. mati2173/cf-avatars-generator)"
  type        = string
}

variable "github_branch" {
  description = "Rama autorizada (e.g. staging)"
  type        = string
}

variable "environment" {
  description = "Entorno (e.g. staging)"
  type        = string
}
