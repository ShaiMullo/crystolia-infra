# Market metadata is sourced from the platform manifest (single source of truth,
# manifest/domains.lock.json). Resolve this stack's record by its stable id.
locals {
  market = [
    for m in jsondecode(file("${path.module}/../manifest/domains.lock.json")).markets : m
    if m.id == "ru-ru"
  ][0]
}

module "landing_ru" {
  source = "../modules/landing-domain"

  domain_name     = local.market.domain
  bucket_name     = local.market.aws.bucket
  default_locale  = local.market.defaultLocale
  route53_zone_id = data.aws_route53_zone.ru.zone_id

  # ACM refused to auto-issue for crystolia.ru (ADDITIONAL_VERIFICATION_REQUIRED),
  # so we issued the cert via Let's Encrypt (DNS-01) and imported it into ACM
  # us-east-1. The imported cert ARN comes from the manifest (acm.source=imported).
  existing_certificate_arn       = local.market.aws.acm.certificateArn
  create_cert_validation_records = false

  # GO-LIVE switch — see variables.tf. First apply false (no public DNS),
  # validate on *.cloudfront.net, then apply with -var go_live=true.
  create_dns_records = var.go_live

  # No geo redirect on the localized domains (crystolia.com only, in D4.3).
  enable_geo_redirect = false
}
