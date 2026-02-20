variable "environment" {
  description = "Environment name"
  type        = string
}


variable "common_tags" {
  description = "Common tags applied to ACM resources"
  type        = map(string)
  default     = {}
}
