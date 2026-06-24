# crystolia.ru hosted zone (Z00331382Z69L1TYT5RCL) — already delegated to
# Route53, so ACM DNS validation resolves here automatically.
data "aws_route53_zone" "ru" {
  name         = "crystolia.ru."
  private_zone = false
}
