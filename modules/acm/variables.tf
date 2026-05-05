variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름(dev, prod)"
  type        = string
}

variable "domain" {
  description = "인증서 도메인(예: shoong.cloud)"
  type        = string
}

variable "zone_id" {
  description = "Route53 호스팅 존 ID"
  type        = string
}
