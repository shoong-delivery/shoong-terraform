output "certificate_arn" {
  description = "ACM 인증서 ARN(ALB, CloudFront에서 참조)"
  value       = aws_acm_certificate_validation.this.certificate_arn
}
