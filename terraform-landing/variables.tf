variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# domain_name / bucket_name are no longer variables — they come from the
# platform manifest (see manifest.tf, market "il-en").
