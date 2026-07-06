terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.53"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Generamos un sufijo aleatorio para el nombre del bucket, 
# ya que los nombres de S3 deben ser globalmente únicos en todo AWS.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 1. El Bucket S3 que guardará los archivos de estado
resource "aws_s3_bucket" "terraform_state" {
  bucket = "avatars-generator-tfstate-${random_id.bucket_suffix.hex}"

  # Protegemos el bucket de ser borrado por accidente mediante Terraform
  lifecycle {
    prevent_destroy = true
  }
}

# 2. Activamos el versionamiento obligatorio
# Si corrompemos el state, siempre podemos descargar la versión de ayer desde S3.
resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Forzamos encriptación del lado del servidor (KMS/AES256)
# Nadie, ni siquiera AWS, podrá leer los secretos en texto plano.
resource "aws_s3_bucket_server_side_encryption_configuration" "default" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 4. Bloqueamos ABSOLUTAMENTE cualquier acceso público
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


