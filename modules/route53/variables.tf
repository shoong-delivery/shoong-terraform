# modules/route53/variables.tf

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름(dev, prod)"
  type        = string
}

variable "domain" {
  description = "Route53 호스팅 존 도메인"
  type        = string
}
