provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "Crystolia"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Helm Provider will be configured after EKS module is ready
# provider "helm" { ... }

# Kubernetes Provider will be configured after EKS module is ready
# provider "kubernetes" { ... }
