# Main Infrastructure Entrypoint
# ------------------------------
# Cost-optimized EKS cluster with Spot nodes for demo/evaluation.
#
# COST WARNING:
# - EKS Control Plane: ~$0.10/hour (~$72/month) - FIXED COST while cluster exists
# - NAT Gateway: ~$0.045/hour + data transfer
# - Spot Nodes: Variable, typically 60-90% cheaper than On-Demand
#
# To stop all costs: terraform destroy

locals {
  cluster_name = "${var.project_name}-cluster-${var.environment}"
}

# -----------------------------------------------------------------------------
# VPC Module - 2 AZs, Single NAT Gateway
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  environment  = var.environment
  project_name = var.project_name
  vpc_cidr     = "10.0.0.0/16"
  common_tags  = var.common_tags
}

# -----------------------------------------------------------------------------
# EKS Module - Spot Node Group
# -----------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  cluster_name = local.cluster_name
  environment  = var.environment

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  common_tags = var.common_tags
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs (nodes run here)"
  value       = module.vpc.private_subnets
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_region" {
  description = "AWS region where cluster is deployed"
  value       = var.aws_region
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

# -----------------------------------------------------------------------------
# Kubeconfig Command
# -----------------------------------------------------------------------------
output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}"
}
