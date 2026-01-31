variable "environment" {}
variable "oidc_provider_arn" {}
variable "cluster_name" {}

# Secrets placeholder
resource "aws_secretsmanager_secret" "backend_secrets" {
  name        = "${var.environment}-backend-secrets"
  description = "Secrets for Crystolia Backend (Green Invoice, DB, Payment)"
}

# IAM Role for Backend Service Account (IRSA)
# Allows the backend pod to assume this role via OIDC
data "aws_iam_policy_document" "backend_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "https://", "")}:sub"
      values   = ["system:serviceaccount:crystolia:backend-sa"]
    }
  }
}

resource "aws_iam_role" "backend_role" {
  name               = "${var.environment}-backend-role"
  assume_role_policy = data.aws_iam_policy_document.backend_trust.json
}

# Policy to read secrets
resource "aws_iam_policy" "secrets_read" {
  name        = "${var.environment}-secrets-read"
  description = "Allow reading secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.backend_secrets.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backend_secrets" {
  role       = aws_iam_role.backend_role.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

output "backend_role_arn" {
  value = aws_iam_role.backend_role.arn
}

output "secret_arn" {
  value = aws_secretsmanager_secret.backend_secrets.arn
}
