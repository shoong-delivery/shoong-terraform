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
  description = "서비스 도메인(레코드 생성에 사용)"
  type        = string
}

variable "zone_domain" {
  description = "Route53 호스팅 존 조회용 루트 도메인"
  type        = string
}
