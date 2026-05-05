output "alb_arn" {
  description = "ALB ARN(CloudFront 오리진용)"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "ALB DNS 이름(CloudFront 오리진으로 설정)"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID(Route53 A 레코드용)"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "타겟 그룹 ARN"
  value       = aws_lb_target_group.this.arn
}
