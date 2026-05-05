# modules/cloudfront/variables.tf

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름(dev, prod)"
  type        = string
}

variable "domain" {
  description = "도메인 이름(예: shoong.cloud)"
  type        = string
}

variable "zone_id" {
  description = "Route53 호스팅 존 ID"
  type        = string
}

variable "certificate_arn" {
  description = "ACM 인증서 ARN"
  type        = string
}

variable "web_acl_arn" {
  description = "WAF WebACL ARN"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS 이름"
  type        = string
}

variable "frontend_bucket_id" {
  description = "Frontend S3 버킷 ID"
  type        = string
}

variable "frontend_bucket_arn" {
  description = "Frontend S3 버킷 ARN"
  type        = string
}

variable "frontend_bucket_domain_name" {
  description = "Frontend S3 버킷 도메인"
  type        = string
}

variable "price_class" {
  description = "CloudFront Price Class"
  type        = string
}
