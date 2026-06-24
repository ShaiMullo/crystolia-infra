# crystolia.co.il hosted zone (Z00702083FKV46OHW88RZ) — already delegated to
# Route53, so ACM DNS validation resolves here automatically.
data "aws_route53_zone" "coil" {
  name         = "crystolia.co.il."
  private_zone = false
}
