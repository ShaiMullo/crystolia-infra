output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (needed for cache invalidation in CI)"
  value       = aws_cloudfront_distribution.landing.id
}

output "cloudfront_domain" {
  description = "CloudFront domain name"
  value       = aws_cloudfront_distribution.landing.domain_name
}

output "s3_bucket" {
  description = "S3 bucket name for landing site files"
  value       = aws_s3_bucket.landing.bucket
}


output "site_url" {
  description = "Live site URL"
  value       = "https://${var.domain_name}"
}
