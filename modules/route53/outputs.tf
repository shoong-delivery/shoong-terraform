# modules/route53/outputs.tf

output "zone_id" {
  description = "Route53 호스팅 존 ID(acm, alb, cloudfront에서 참조)"
  value       = data.aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "네임서버 목록(도메인 구매 후 콘솔에서 등록 필요)"
  value       = data.aws_route53_zone.this.name_servers
}
