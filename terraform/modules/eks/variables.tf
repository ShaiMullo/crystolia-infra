variable "cluster_name" {
  description = "Name of the EKS Cluster"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}
