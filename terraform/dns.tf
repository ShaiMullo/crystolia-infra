data "aws_route53_zone" "com" {
  name = "crystolia.com."
}

resource "aws_route53_record" "www" {
  zone_id         = data.aws_route53_zone.com.zone_id
  name            = "www.crystolia.com"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = "a3372ac68647c44b787810c648b0f68f-c3225cf9f20244f3.elb.us-east-1.amazonaws.com"
    zone_id                = "Z26RNL4JYFTOTI" # Standard Zone ID for NLB in us-east-1
    evaluate_target_health = true
  }

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_route53_record" "staging" {
  zone_id         = data.aws_route53_zone.com.zone_id
  name            = "staging.crystolia.com"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = "k8s-crystoli-crystoli-ca14e383fb-439027048.us-east-1.elb.amazonaws.com"
    zone_id                = "Z35SXDOTRQ7X7K"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "admin_staging" {
  zone_id         = data.aws_route53_zone.com.zone_id
  name            = "admin-staging.crystolia.com"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = "k8s-crystoli-crystoli-ca14e383fb-439027048.us-east-1.elb.amazonaws.com"
    zone_id                = "Z35SXDOTRQ7X7K"
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# api-staging.crystolia.com — staging backend API public entry point
#
# Shares the staging ALB via alb.ingress.kubernetes.io/group.name="staging-alb"
# (same target as staging.crystolia.com and admin-staging.crystolia.com).
# -----------------------------------------------------------------------------
resource "aws_route53_record" "api_staging" {
  zone_id         = data.aws_route53_zone.com.zone_id
  name            = "api-staging.crystolia.com"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = "k8s-crystoli-crystoli-ca14e383fb-439027048.us-east-1.elb.amazonaws.com"
    zone_id                = "Z35SXDOTRQ7X7K"
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# api.crystolia.com — production backend API public entry point
#
# Enable ONLY after the production ALB has been provisioned by the production
# ingress (Helm alb.ingress.kubernetes.io/group.name="production-alb"). Replace
# the alias name/zone_id with the real values from:
#   kubectl -n crystolia get ingress crystolia-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# and the canonical-zone ID (Z35SXDOTRQ7X7K for us-east-1 ALBs).
# -----------------------------------------------------------------------------
# resource "aws_route53_record" "api" {
#   zone_id         = data.aws_route53_zone.com.zone_id
#   name            = "api.crystolia.com"
#   type            = "A"
#   allow_overwrite = true
#
#   alias {
#     name                   = "<production-alb-dns-name>.us-east-1.elb.amazonaws.com"
#     zone_id                = "Z35SXDOTRQ7X7K"
#     evaluate_target_health = true
#   }
# }
#
# resource "aws_route53_record" "admin" {
#   zone_id         = data.aws_route53_zone.com.zone_id
#   name            = "admin.crystolia.com"
#   type            = "A"
#   allow_overwrite = true
#
#   alias {
#     name                   = "<production-alb-dns-name>.us-east-1.elb.amazonaws.com"
#     zone_id                = "Z35SXDOTRQ7X7K"
#     evaluate_target_health = true
#   }
# }

resource "aws_route53_record" "monitoring_staging" {
  zone_id         = data.aws_route53_zone.com.zone_id
  name            = "monitoring-staging.crystolia.com"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = "k8s-monitori-monitori-b8f2c71a0d-537641054.us-east-1.elb.amazonaws.com"
    zone_id                = "Z35SXDOTRQ7X7K"
    evaluate_target_health = true
  }
}
