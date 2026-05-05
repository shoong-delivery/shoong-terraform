output "distribution_arn" {
  description = "CloudFront Distribution ARN"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "CloudFront Distribution 도메인"
  value       = aws_cloudfront_distribution.this.domain_name
}
