# Obtener el certificado TLS de GitHub Actions
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Crear el proveedor OIDC en AWS
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# Política de confianza para que solo nuestro repositorio y rama puedan asumir el rol
data "aws_iam_policy_document" "github_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Solo permitimos despliegues desde la rama especificada del repositorio
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-${var.environment}-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

# Para el propósito de CI/CD (Terraform y kubectl), este rol necesita permisos de Admin
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.github_actions.name
}
