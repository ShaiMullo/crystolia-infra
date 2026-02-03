# Main Infrastructure Entrypoint
# ------------------------------
# Modules will be wired here in Phase 2B.

module "vpc" {
  source      = "./modules/vpc"
  environment = var.environment
  vpc_cidr    = "10.0.0.0/16"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

module "eks" {
  source = "./modules/eks"

  cluster_name = "crystolia-cluster-${var.environment}"
  environment  = var.environment

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}


# module "iam" {
#   source = "./modules/iam"
#   ...
# }
