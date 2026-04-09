# -----------------------------------------------------------------------------
# DNS Records — Point apex + www at CloudFront
# -----------------------------------------------------------------------------
#
# NOTE: The main infra stack (terraform/dns.tf) has a "www" record pointing
# at the EKS NLB with lifecycle { ignore_changes = all }. That record will
# NOT conflict with this one because:
#   1. If the main stack is destroyed, the record is gone — no conflict.
#   2. If the main stack is still applied, its ignore_changes means it won't
#      try to revert this record. However, you should avoid running
#      terraform apply in BOTH stacks for the same DNS name simultaneously.
#
# When the full platform goes live, either:
#   a. Remove these records and let the main stack manage DNS, or
#   b. Keep CloudFront as the public entry point and route /api/* to the ALB
#      via CloudFront origin groups.

resource "aws_route53_record" "apex" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = var.domain_name
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.landing.domain_name
    zone_id                = aws_cloudfront_distribution.landing.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = "www.${var.domain_name}"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.landing.domain_name
    zone_id                = aws_cloudfront_distribution.landing.hosted_zone_id
    evaluate_target_health = false
  }
}
