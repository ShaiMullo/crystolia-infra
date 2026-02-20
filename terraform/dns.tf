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
