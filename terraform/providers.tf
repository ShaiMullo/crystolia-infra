provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "crystolia"
      Env        = var.environment
      Owner      = "shai"
      CostCenter = "final-project"
      ManagedBy  = "Terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster Data Sources
# -----------------------------------------------------------------------------
# Required for Kubernetes and Helm providers to connect to the cluster.

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# -----------------------------------------------------------------------------
# Kubernetes Provider
# -----------------------------------------------------------------------------

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# -----------------------------------------------------------------------------
# Helm Provider
# -----------------------------------------------------------------------------

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
