terraform {
  backend "s3" {
    bucket       = "avatars-generator-tfstate-8cac6d82"
    key          = "env/staging/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.53"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- LLAMADA AL MÓDULO VPC ---

module "vpc" {
  source = "../../modules/vpc"

  environment = var.environment
  vpc_cidr    = "10.0.0.0/16"

  # El módulo usará su lógica 'count' para crear 2 de cada una automáticamente
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

  # Asignamos explícitamente en qué zonas queremos que vivan
  azs = ["${var.aws_region}a", "${var.aws_region}b"]
}
