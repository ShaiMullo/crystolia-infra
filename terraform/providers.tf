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

# Helm and Kubernetes providers - configured for future addons
# Uncomment when ready to deploy addons via Terraform

# data "aws_eks_cluster" "cluster" {
#   name = module.eks.cluster_name
# }
#
# data "aws_eks_cluster_auth" "cluster" {
#   name = module.eks.cluster_name
# }
#
# provider "kubernetes" {
#   host                   = data.aws_eks_cluster.cluster.endpoint
#   cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
#   token                  = data.aws_eks_cluster_auth.cluster.token
# }
#
# provider "helm" {
#   kubernetes {
#     host                   = data.aws_eks_cluster.cluster.endpoint
#     cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
#     token                  = data.aws_eks_cluster_auth.cluster.token
#   }
# }
