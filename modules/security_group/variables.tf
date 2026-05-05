variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름(dev, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록 (VPC Endpoint SG inbound용)"
  type        = string
}

variable "allow_ssm_db_access" {
  description = "SSM EC2에서 RDS 직접 접근 허용 여부 (dev only)"
  type        = bool
  default     = false
}
