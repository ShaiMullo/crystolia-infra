# -----------------------------------------------------------------------------
# Shared Resources (managed by the main infra stack)
# These already exist — we only reference them, never create or modify them.
# -----------------------------------------------------------------------------

# Route53 hosted zone — created when domain was registered
data "aws_route53_zone" "main" {
  name         = "${var.domain_name}."
  private_zone = false
}

# ACM wildcard certificate — created by terraform/modules/acm/
data "aws_acm_certificate" "wildcard" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# GitHub OIDC provider is NOT referenced here.
# The IAM role for GitHub Actions CI/CD will be added in a later step,
# after the OIDC provider is created by the main infra stack.
