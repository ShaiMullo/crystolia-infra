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

# module "eks" {
#   source = "./modules/eks"
#   ...
# }

# module "iam" {
#   source = "./modules/iam"
#   ...
# }
