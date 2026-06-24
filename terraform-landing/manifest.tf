# -----------------------------------------------------------------------------
# Platform manifest (single source of truth: manifest/domains.lock.json)
# -----------------------------------------------------------------------------
# This standalone crystolia.com stack sources its domain/bucket from the
# manifest's "il-en" market instead of duplicating the literals. The ACM cert
# stays a wildcard data-lookup (manifest acm.source = "wildcard-lookup"), so no
# cert ARN is read here.
locals {
  market = [
    for m in jsondecode(file("${path.module}/../manifest/domains.lock.json")).markets : m
    if m.id == "il-en"
  ][0]

  domain_name = local.market.domain
  bucket_name = local.market.aws.bucket
}
