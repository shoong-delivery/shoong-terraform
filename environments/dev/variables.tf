variable "aws_region" {
  description = "리소스를 배포할 AWS 리전"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI에서 사용할 프로필"
  type        = string
  default     = "my-profile"
}

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
}

variable "azs" {
  description = "가용 영역 목록"
  type        = list(string)
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

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes 버전"
  type        = string
}

variable "node_instance_type" {
  description = "EKS 노드 인스턴스 타입"
  type        = string
}

variable "node_ami_type" {
  description = "EKS 노드 AMI 타입"
  type        = string
}

variable "node_desired_size" {
  description = "EKS 노드 desired 수"
  type        = number
}

variable "node_min_size" {
  description = "EKS 노드 최소 수"
  type        = number
}

variable "node_max_size" {
  description = "EKS 노드 최대 수"
  type        = number
}

variable "db_engine_version" {
  description = "PostgreSQL 버전"
  type        = string
}

variable "db_instance_class" {
  description = "RDS 인스턴스 타입"
  type        = string
}

variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
}

# variable "db_username" {
#   description = "DB 마스터 사용자 이름"
#   type        = string
# }

# variable "db_password" {
#   description = "DB 마스터 비밀번호"
#   type        = string
#   sensitive   = true
# }

variable "multi_az" {
  description = "Multi-AZ 활성화 여부"
  type        = bool
}

variable "replica_count" {
  description = "Read Replica 개수"
  type        = number
}

variable "allocated_storage" {
  description = "RDS 스토리지 용량(GB)"
  type        = number
}

variable "backup_retention_period" {
  description = "백업 보존 기간(일)"
  type        = number
}

variable "skip_final_snapshot" {
  description = "삭제 시 최종 스냅샷 생략 여부"
  type        = bool
}

variable "dev_image_count" {
  description = "ECR dev 이미지 보관 개수"
  type        = number
}

variable "domain" {
  description = "도메인 이름"
  type        = string
}

variable "zone_domain" {
  description = "Route53 호스팅 존 루트 도메인"
  type        = string
}

variable "price_class" {
  description = "CloudFront Price Class"
  type        = string
}

# ssm
variable "ssm_ec2_ami" {
  description = "SSM EC2 AMI ID(Amazon Linux 2023)"
  type        = string
}

variable "ssm_ec2_instance_type" {
  description = "SSM EC2 인스턴스 타입"
  type        = string
}
