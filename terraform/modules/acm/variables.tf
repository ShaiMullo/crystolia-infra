variable "domain_name" {
  description = "Primary domain name for the certificate"
  type        = string
}

variable "alternative_name" {
  description = "List of alternative domains"
  type        = list(string)
  default     = []
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "zone_id" {
  description = "The Route53 Zone ID for DNS validation"
  type        = string
}
