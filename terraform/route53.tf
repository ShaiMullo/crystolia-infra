resource "aws_route53_zone" "main_zone" {
  name = "crystolia.com"
}

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.main_zone.zone_id
  name    = "crystolia.com"
  type    = "A"

  alias {
    name                   = "a688566243f2f4eca8e3c1fff17b811d-1197e3da15cc27fc.elb.us-east-1.amazonaws.com"
    zone_id                = "Z26RNL4JYFTOTI"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "facebook_verification" {
  zone_id = aws_route53_zone.main_zone.zone_id
  name    = "crystolia.com"
  type    = "TXT"
  ttl     = 300
  records = ["facebook-domain-verification=theo5f8cqs6nmsp7h0vexg13vqz47d"]
  allow_overwrite = true
}

output "nameservers" {
  value = aws_route53_zone.main_zone.name_servers
}
