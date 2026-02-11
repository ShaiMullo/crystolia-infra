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

  # Stable Node Group for Bootstrap Phase
  eks_managed_node_groups = {
    general = {
      name = "general-${var.environment}"

      # ON_DEMAND for stability during bootstrap
      capacity_type = "ON_DEMAND"

      # Medium instances only (17 pods capacity vs 11 for small)
      instance_types = [
        "t3.medium",
        "t3a.medium"
      ]

      # Scaling for workloads
      min_size     = 2
      max_size     = 3
      desired_size = 2

      # Disk configuration
      disk_size = 20

      # Labels for workload identification
      labels = {
        env      = "demo"
        workload = "general"
      }

      # Tags specific to node group
      tags = merge(var.common_tags, {
        NodeGroup = "general"
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
