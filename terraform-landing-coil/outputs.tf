output "cloudfront_distribution_id" {
  value = module.landing_coil.cloudfront_distribution_id
}

output "cloudfront_domain" {
  description = "Validate the site here (with Host: crystolia.co.il) BEFORE go_live=true."
  value       = module.landing_coil.cloudfront_domain
}

output "s3_bucket" {
  value = module.landing_coil.s3_bucket
}

output "site_url" {
  value = module.landing_coil.site_url
}
