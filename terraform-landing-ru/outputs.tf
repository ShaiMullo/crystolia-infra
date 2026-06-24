output "cloudfront_distribution_id" {
  value = module.landing_ru.cloudfront_distribution_id
}

output "cloudfront_domain" {
  description = "Validate the site here (with Host: crystolia.ru) BEFORE go_live=true."
  value       = module.landing_ru.cloudfront_domain
}

output "s3_bucket" {
  value = module.landing_ru.s3_bucket
}

output "site_url" {
  value = module.landing_ru.site_url
}
