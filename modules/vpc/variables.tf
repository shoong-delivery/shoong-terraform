variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 목록"
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "DB 서브넷 CIDR 목록"
  type        = list(string)
}

variable "azs" {
  description = "사용할 가용 영역 목록"
  type        = list(string)
}

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름 (dev, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (서브넷 태그용)"
  type        = string
}
