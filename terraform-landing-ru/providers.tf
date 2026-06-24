provider "aws" {
  region = var.aws_region # us-east-1 — required for CloudFront ACM certs

  default_tags {
    tags = {
      Project    = "crystolia"
      Env        = "production"
      Stack      = "landing-ru"
      Owner      = "shai"
      CostCenter = "final-project"
      ManagedBy  = "Terraform"
    }
  }
}
