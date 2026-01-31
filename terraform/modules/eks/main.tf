variable "cluster_name" {}
variable "environment" {}
variable "vpc_id" {}
variable "subnet_ids" {
  type = list(string)
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.32"

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_public_access  = true
  enable_cluster_creator_admin_permissions = true

  # OIDC Provider for IRSA
  enable_irsa = true

  eks_managed_node_groups = {
    spot = {
      name = "${var.environment}-nodes-spot"

      min_size     = 1
      max_size     = 5
      desired_size = 2

      instance_types = ["t3.medium", "t3.large"]
      capacity_type  = "SPOT"
    }
  }

  tags = {
    Environment = var.environment
  }
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}
