module "landing_ru" {
  source = "../modules/landing-domain"

  domain_name     = "crystolia.ru"
  bucket_name     = "crystolia-landing-ru"
  default_locale  = "ru"
  route53_zone_id = data.aws_route53_zone.ru.zone_id

  # ACM refused to auto-issue for crystolia.ru (ADDITIONAL_VERIFICATION_REQUIRED),
  # so we issued the cert via Let's Encrypt (DNS-01) and imported it into ACM
  # us-east-1. Supply that imported cert instead of having the module create one.
  existing_certificate_arn       = "arn:aws:acm:us-east-1:268456953512:certificate/84c4444d-5ab9-4539-b78f-8e450cf5af6b"
  create_cert_validation_records = false

  # GO-LIVE switch — see variables.tf. First apply false (no public DNS),
  # validate on *.cloudfront.net, then apply with -var go_live=true.
  create_dns_records = var.go_live

  # No geo redirect on the localized domains (crystolia.com only, in D4.3).
  enable_geo_redirect = false
}
