
variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름(dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "프라이빗 라우팅 테이블 ID 목록(S3 Gateway 엔드포인트용)"
  type        = list(string)
}

variable "vpc_endpoint_sg_id" {
  description = "VPC Endpoint Security Group ID"
  type        = string
}
