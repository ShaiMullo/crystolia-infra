# Market metadata is sourced from the platform manifest (single source of truth,
# manifest/domains.lock.json). Resolve this stack's record by its stable id.
locals {
  market = [
    for m in jsondecode(file("${path.module}/../manifest/domains.lock.json")).markets : m
    if m.id == "il-he"
  ][0]

  # acm.source = "acm-issued" → no imported cert in the manifest (certificateArn
  # is null), so the module creates and DNS-validates a new ACM cert.
  existing_certificate_arn = local.market.aws.acm.certificateArn != null ? local.market.aws.acm.certificateArn : ""
}

module "landing_coil" {
  source = "../modules/landing-domain"

  domain_name     = local.market.domain
  bucket_name     = local.market.aws.bucket
  default_locale  = local.market.defaultLocale
  route53_zone_id = data.aws_route53_zone.coil.zone_id

  # ACM-managed certificate: crystolia.co.il DNS is authoritative in Route53, so
  # ACM can validate via DNS-01 automatically (create the validation CNAMEs).
  # NOTE: at apply time AWS ACM may still return ADDITIONAL_VERIFICATION_REQUIRED
  # for this domain (as it did for crystolia.ru); if so, fall back to Path B
  # (import a Let's Encrypt cert) exactly like terraform-landing-ru.
  existing_certificate_arn       = local.existing_certificate_arn
  create_cert_validation_records = true

  # GO-LIVE switch — see variables.tf. First apply false (no public DNS),
  # validate on *.cloudfront.net, then apply with -var go_live=true.
  create_dns_records = var.go_live

  # No geo redirect on the localized domains (crystolia.com only, in D4.3).
  enable_geo_redirect = false
}
