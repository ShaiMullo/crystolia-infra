# =============================================================================
# landing-domain — one localized landing domain on S3 + CloudFront.
#
# Mirrors the proven crystolia.com stack (terraform-landing/) and adds:
#   - per-domain ACM cert (apex + www), DNS-validated
#   - an edge function that does www->apex (301) + root->/{default_locale},
#     and (optionally, for crystolia.com) a geo/language 302.
#
# Content is pushed separately by landing/deploy-landing.sh (S3 sync +
# extensionless clean-URL objects). This module only creates infrastructure.
# =============================================================================

locals {
  name_slug = replace(var.domain_name, ".", "-")

  # Create + validate a new ACM cert only when no existing ARN is supplied.
  create_cert = var.existing_certificate_arn == ""

  function_code = templatefile("${path.module}/function.js.tftpl", {
    domain_name               = var.domain_name
    default_locale            = var.default_locale
    rewrite_root_to_locale    = var.rewrite_root_to_locale
    enable_geo_redirect       = var.enable_geo_redirect
    geo_redirects             = var.geo_redirects
    ru_accept_language_domain = var.ru_accept_language_domain
  })

  # Certificate attached to the distribution:
  #   - a supplied existing cert, else
  #   - the validated cert (when this module manages validation), else
  #   - the created cert ARN (when validation is handled out-of-band, e.g.
  #     crystolia.co.il on Vercel pre-cutover).
  certificate_arn = (
    var.existing_certificate_arn != "" ? var.existing_certificate_arn :
    var.create_cert_validation_records ? one(aws_acm_certificate_validation.this[*].certificate_arn) :
    one(aws_acm_certificate.this[*].arn)
  )
}

# ── S3 (private, OAC-only) ───────────────────────────────────────────────────
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.this.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}

# ── ACM certificate (apex + www), DNS-validated, us-east-1 ───────────────────
resource "aws_acm_certificate" "this" {
  count = local.create_cert ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  # Static for_each keys (the cert's domains are known at plan time); the record
  # name/type/value come from domain_validation_options as VALUES (known after
  # apply — allowed). Deriving the keys from a count'd ACM cert's
  # domain_validation_options instead trips "Invalid for_each argument".
  for_each = (local.create_cert && var.create_cert_validation_records) ? toset(concat([var.domain_name], ["www.${var.domain_name}"])) : toset([])

  zone_id = var.route53_zone_id
  name    = one([for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.resource_record_name if dvo.domain_name == each.value])
  type    = one([for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.resource_record_type if dvo.domain_name == each.value])
  records = [one([for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.resource_record_value if dvo.domain_name == each.value])]

  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count                   = (local.create_cert && var.create_cert_validation_records) ? 1 : 0
  certificate_arn         = one(aws_acm_certificate.this[*].arn)
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ── CloudFront ───────────────────────────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${local.name_slug}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "edge" {
  name    = "${local.name_slug}-edge"
  runtime = "cloudfront-js-2.0"
  comment = "www->apex + root->/${var.default_locale}${var.enable_geo_redirect ? " + geo" : ""} (${var.domain_name})"
  publish = true
  code    = local.function_code
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.domain_name, "www.${var.domain_name}"]
  price_class         = var.price_class
  http_version        = "http2and3"
  tags                = var.tags

  origin {
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id                = "s3-${local.name_slug}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-${local.name_slug}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.edge.arn
    }

    min_ttl     = 0
    default_ttl = 86400    # 24h
    max_ttl     = 31536000 # 1y
  }

  # Clean URLs are pre-uploaded by deploy-landing.sh, so missing objects are
  # real 404s (no soft-404 SPA fallback).
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  viewer_certificate {
    acm_certificate_arn      = local.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# ── DNS (apex + www A-ALIAS) — GO-LIVE switch (gated by create_dns_records) ───
resource "aws_route53_record" "apex" {
  count           = var.create_dns_records ? 1 : 0
  zone_id         = var.route53_zone_id
  name            = var.domain_name
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  count           = var.create_dns_records ? 1 : 0
  zone_id         = var.route53_zone_id
  name            = "www.${var.domain_name}"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
