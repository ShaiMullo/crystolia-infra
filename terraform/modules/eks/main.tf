# EKS Module - Cost Optimized with Spot Nodes
# --------------------------------------------
# Uses Spot instances for significant cost savings in demo/dev environments.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  # API Access - Public for demo (restrict in production)
  cluster_endpoint_public_access = true

  # VPC Configuration
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # OIDC Provider for future IRSA support
  enable_irsa = true

  # Cost-Optimized Spot Node Group
  eks_managed_node_groups = {
    spot-nodes = {
      name = "spot-nodes-${var.environment}"

      # SPOT capacity for cost savings
      capacity_type = "SPOT"

      # Diverse instance types for Spot availability
      instance_types = [
        "t3a.small",
        "t3.small",
        "t2.small",
        "t3a.medium",
        "t3.medium",
        "t2.medium"
      ]

      # Minimal scaling for demo
      min_size     = 1
      max_size     = 2
      desired_size = 1

      # Disk configuration
      disk_size = 20

      # Labels for workload identification
      labels = {
        env      = "demo"
        workload = "general"
      }

      # Tags specific to node group
      tags = merge(var.common_tags, {
        NodeGroup = "spot-nodes"
      })
    }
  }

  # Cluster Access
  enable_cluster_creator_admin_permissions = true

  # Cluster-level tags
  tags = merge(var.common_tags, {
    Name        = var.cluster_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}
