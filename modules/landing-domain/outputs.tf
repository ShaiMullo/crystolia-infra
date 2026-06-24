output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (needed for cache invalidation in deploy-landing.sh)."
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain (validate here BEFORE flipping DNS)."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_hosted_zone_id" {
  value = aws_cloudfront_distribution.this.hosted_zone_id
}

output "s3_bucket" {
  description = "Target bucket for deploy-landing.sh."
  value       = aws_s3_bucket.this.bucket
}

output "certificate_arn" {
  description = "ACM certificate ARN attached to the distribution (existing one if supplied, else the module-created cert)."
  value       = local.certificate_arn
}

output "acm_validation_options" {
  description = "DNS-validation records for the module-created cert — use when create_cert_validation_records=false (e.g. add these to Vercel DNS for crystolia.co.il). Empty when an existing cert is supplied."
  value = [
    for dvo in flatten([for c in aws_acm_certificate.this : c.domain_validation_options]) : {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  ]
}

output "site_url" {
  value = "https://${var.domain_name}"
}
