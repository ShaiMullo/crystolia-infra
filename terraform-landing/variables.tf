variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "crystolia.com"
}

variable "bucket_name" {
  description = "S3 bucket name for landing site"
  type        = string
  default     = "crystolia-landing-site"
}
