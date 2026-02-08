# GitHub OIDC Provider and IAM Role for Terraform CI
# --------------------------------------------------
# This file creates the infrastructure for secure GitHub Actions authentication.
#
# WHY OIDC?
# - No static AWS credentials stored in GitHub Secrets
# - Short-lived tokens (15 min) generated per workflow run
# - AWS CloudTrail shows exact repo/branch that assumed the role
# - AWS-recommended best practice for CI/CD
#
# SECURITY MODEL:
# - This role can ONLY be assumed by the ShaiMullo/crystolia-infra repo
# - This role can ONLY be assumed from the main branch
# - This role can ONLY read/write Terraform state (S3 + DynamoDB)
# - This role CANNOT create/modify AWS infrastructure
#
# WHY NO APPLY IN CI?
# - terraform apply is intentionally excluded from CI
# - Apply runs locally only for cost control and safety
# - This role has no permissions to create infrastructure anyway

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# GitHub OIDC Provider
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's official OIDC thumbprint
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(var.common_tags, {
    Name    = "github-actions-oidc-provider"
    Purpose = "GitHub Actions OIDC authentication"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for Terraform CI (PLAN ONLY)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "github_actions_terraform" {
  name        = "github-actions-terraform-role"
  description = "IAM role for GitHub Actions Terraform CI (plan only)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Repo + branch restriction
            "token.actions.githubusercontent.com:sub" = "repo:ShaiMullo/crystolia-infra:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name       = "github-actions-terraform-role"
    Purpose    = "Terraform-CI-plan-only"
    Repository = "crystolia-infra"
  })
}

# -----------------------------------------------------------------------------
# IAM Policy — Terraform State + Read-Only for Plan
# -----------------------------------------------------------------------------
# terraform plan requires read access to refresh state against live resources.
# This policy grants:
# - State bucket access (S3 + DynamoDB) 
# - Read-only access to resources managed by this Terraform configuration
# - NO write/create/delete permissions for AWS infrastructure

resource "aws_iam_policy" "terraform_state_access" {
  name        = "terraform-ci-policy"
  description = "Terraform CI: state access + read-only for plan"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # --- Terraform State Backend ---
      {
        Sid    = "S3StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::crystolia-tf-state-main",
          "arn:aws:s3:::crystolia-tf-state-main/*"
        ]
      },
      {
        Sid    = "DynamoDBLockAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:us-east-1:${data.aws_caller_identity.current.account_id}:table/crystolia-tf-locks"
      },
      # --- Read-Only for terraform plan ---
      {
        Sid    = "EC2ReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:Describe*"
        ]
        Resource = "*"
      },
      {
        Sid    = "EKSReadOnly"
        Effect = "Allow"
        Action = [
          "eks:Describe*",
          "eks:List*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMSReadOnly"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:ListAliases"
        ]
        Resource = "*"
      },
      {
        Sid    = "LogsReadOnly"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "STSGetCallerIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "terraform-ci-policy"
  })
}

# -----------------------------------------------------------------------------
# Policy Attachment
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "github_actions_terraform" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = aws_iam_policy.terraform_state_access.arn
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions_terraform.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}