module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29" # User Requested Stable Version

  # API Access Policy
  # -----------------
  # For this Dev environment, we allow 0.0.0.0/0 (Public Access).
  # In a strict Production setup, we would restrict this to specific CIDRs 
  # (Office VPN, Bastion) using `cluster_endpoint_public_access_cidrs`.
  cluster_endpoint_public_access = true

  # VPC Configuration
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # OIDC Provider for IRSA
  enable_irsa = true

  # Managed Node Groups
  eks_managed_node_groups = {
    # 1. System Node Group (Core Components like CoreDNS, VPC CNI, etc.)
    system = {
      name           = "system-nodes"
      instance_types = ["t3.medium"] # Upsized from t3.small
      min_size       = 1
      max_size       = 2
      desired_size   = 1

      labels = {
        role = "system"
      }
    }

    # 2. Application Node Group (User Workloads)
    app = {
      name           = "app-nodes"
      instance_types = ["t3.medium"] # Slightly larger for apps
      min_size       = 1
      max_size       = 3
      desired_size   = 1

      labels = {
        role = "app"
      }
    }
  }

  # Cluster Access
  enable_cluster_creator_admin_permissions = true

  tags = {
    Environment = var.environment
    Project     = "Crystolia"
    ManagedBy   = "Terraform"
  }
}
