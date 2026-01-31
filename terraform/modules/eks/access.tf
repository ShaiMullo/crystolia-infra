# Emergency Access for Root User
resource "aws_eks_access_entry" "root" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::268456953512:root"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "root" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.root.principal_arn

  access_scope {
    type = "cluster"
  }
}
