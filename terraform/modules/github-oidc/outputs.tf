output "role_arn" {
  description = "ARN del rol que GitHub Actions debe asumir"
  value       = aws_iam_role.github_actions.arn
}
