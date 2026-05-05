output "web_acl_arn" {
  description = "WAF WebACL ARN(CloudFront에서 참조)"
  value       = aws_wafv2_web_acl.this.arn
}
