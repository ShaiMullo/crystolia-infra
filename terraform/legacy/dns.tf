resource "aws_route53_zone" "main" {
  name = "crystolia.com"
}

resource "aws_route53_zone" "il" {
  name = "crystolia.co.il"
}

resource "aws_acm_certificate" "main" {
  domain_name       = "crystolia.com"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.crystolia.com",
    "crystolia.co.il",
    "*.crystolia.co.il"
  ]

  tags = {
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}
