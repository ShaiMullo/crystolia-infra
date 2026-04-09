provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "crystolia"
      Env        = "production"
      Stack      = "leads"
      Owner      = "shai"
      CostCenter = "final-project"
      ManagedBy  = "Terraform"
    }
  }
}
