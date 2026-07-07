output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "El nombre del bucket S3 para guardar el state"
}
