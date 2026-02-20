# -----------------------------------------------------------------------------
# Route53 Hosted Zone Lookups
# -----------------------------------------------------------------------------
data "aws_route53_zone" "com" {
  name         = "crystolia.com."
  private_zone = false
}

# -----------------------------------------------------------------------------
# ACM Certificate
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "main" {
  domain_name       = "crystolia.com"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.crystolia.com"
  ]

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      Name        = "${var.environment}-cert"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# DNS Validation Records
# -----------------------------------------------------------------------------
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => dvo
  }

  allow_overwrite = true
  name            = each.value.resource_record_name
  records         = [each.value.resource_record_value]
  ttl             = 60
  type            = each.value.resource_record_type
  zone_id         = data.aws_route53_zone.com.zone_id
}

# -----------------------------------------------------------------------------
# Certificate Validation
# -----------------------------------------------------------------------------
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
