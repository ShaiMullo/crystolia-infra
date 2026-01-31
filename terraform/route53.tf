resource "aws_route53_zone" "main_zone" {
  name = "crystolia.com"
}

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.main_zone.zone_id
  name    = "crystolia.com"
  type    = "A"

  alias {
    name                   = "a7cee3e3e055742929f54010b96c165e-2042701401.us-east-1.elb.amazonaws.com"
    zone_id                = "Z35SXDOTRQ7X7K" # Classic ELB Zone ID for us-east-1
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main_zone.zone_id
  name    = "www.crystolia.com"
  type    = "A"

  alias {
    name                   = "a7cee3e3e055742929f54010b96c165e-2042701401.us-east-1.elb.amazonaws.com"
    zone_id                = "Z35SXDOTRQ7X7K"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "facebook_verification" {
  zone_id         = aws_route53_zone.main_zone.zone_id
  name            = "crystolia.com"
  type            = "TXT"
  ttl             = 300
  records         = ["facebook-domain-verification=theo5f8cqs6nmsp7h0vexg13vqz47d"]
  allow_overwrite = true
}

output "nameservers" {
  value = aws_route53_zone.main_zone.name_servers
}
