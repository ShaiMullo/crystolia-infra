output "acm_certificate_arn" {
  description = "The ARN of the certificate"
  value       = aws_acm_certificate.main.arn
}
output "certificate_arn" {
  description = "The ARN of the certificate"
  value       = aws_acm_certificate.main.arn
}
