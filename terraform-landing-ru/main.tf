module "landing_ru" {
  source = "../modules/landing-domain"

  domain_name     = "crystolia.ru"
  bucket_name     = "crystolia-landing-ru"
  default_locale  = "ru"
  route53_zone_id = data.aws_route53_zone.ru.zone_id

  # .ru DNS is authoritative in Route53 → validate the ACM cert automatically.
  create_cert_validation_records = true

  # GO-LIVE switch — see variables.tf. First apply false (no public DNS),
  # validate on *.cloudfront.net, then apply with -var go_live=true.
  create_dns_records = var.go_live

  # No geo redirect on the localized domains (crystolia.com only, in D4.3).
  enable_geo_redirect = false
}
