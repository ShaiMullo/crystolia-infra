variable "domain_name" {
  description = "Apex domain for this landing site (e.g. crystolia.ru)."
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for this domain's static export (private, OAC-only)."
  type        = string
}

variable "default_locale" {
  description = "Locale served at the bare apex (en|he|ru). The edge function rewrites / -> /{default_locale} when rewrite_root_to_locale = true."
  type        = string
}

variable "rewrite_root_to_locale" {
  description = "When true (default), the edge function rewrites / -> /{default_locale}. Set false to preserve the legacy crystolia.com behaviour (www->apex only, no root rewrite)."
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100" # US + Europe (cheapest)
}

variable "existing_certificate_arn" {
  description = "Reuse an existing ACM certificate (us-east-1, covering apex + www) instead of creating one. When empty (default), the module creates and validates a new certificate."
  type        = string
  default     = ""
}

variable "create_cert_validation_records" {
  description = "Create the ACM DNS-validation CNAMEs in Route53. Set false when the domain's DNS is still hosted elsewhere (e.g. crystolia.co.il on Vercel pre-cutover) — validation is then handled out-of-band."
  type        = bool
  default     = true
}

variable "create_dns_records" {
  description = "Create the apex + www A-ALIAS records pointing at the distribution. This is the GO-LIVE switch — keep false until the distribution is validated on its *.cloudfront.net domain."
  type        = bool
  default     = false
}

variable "enable_geo_redirect" {
  description = "Enable the smart geo/language 302 at the edge (crystolia.com only)."
  type        = bool
  default     = false
}

variable "geo_redirects" {
  description = "Country-code -> target apex domain map, used only when enable_geo_redirect (e.g. { IL = \"crystolia.co.il\", RU = \"crystolia.ru\" })."
  type        = map(string)
  default     = {}
}

variable "ru_accept_language_domain" {
  description = "Target apex domain when Accept-Language starts with 'ru' (fallback when the viewer-country header is absent). Used only when enable_geo_redirect."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags applied to taggable resources."
  type        = map(string)
  default     = {}
}
