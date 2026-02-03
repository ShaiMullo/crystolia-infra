variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}
