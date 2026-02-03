variable "cluster_name" {
  description = "Name of the EKS Cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster and workers will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the worker nodes (Private Subnets recommended)"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}
