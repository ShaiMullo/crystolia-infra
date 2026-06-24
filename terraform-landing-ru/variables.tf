variable "aws_region" {
  description = "AWS region (CloudFront certs must live in us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "go_live" {
  description = <<-EOT
    GO-LIVE switch. When true, creates the apex + www A-ALIAS records that point
    crystolia.ru at CloudFront (makes the domain live).

    Two-apply sequence:
      1. apply with go_live=false  -> creates S3 + ACM + CloudFront (no DNS).
         Deploy content, then validate on the *.cloudfront.net domain.
      2. apply with -var go_live=true -> adds the A-ALIAS records (go live).
  EOT
  type        = bool
  default     = false
}
