variable "environment" {
  type = string
}

variable "oidc_provider_arn" {
  description = "Connects IAM to K8s Service Accounts"
  type        = string
}
