variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름(dev, prod)"
  type        = string
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

variable "db_username" {
  description = "DB 마스터 사용자 이름"
  type        = string
}

variable "db_password" {
  description = "DB 마스터 비밀번호"
  type        = string
  sensitive   = true
}

variable "db_subnet_group_name" {
  description = "DB 서브넷 그룹 이름(vpc 모듈 output)"
  type        = string
}

variable "rds_sg_id" {
  description = "RDS Security Group ID"
  type        = string
}

variable "multi_az" {
  description = "Multi-AZ 활성화 여부"
  type        = bool
}

variable "replica_count" {
  description = "Read Replica 갯수"
  type        = number
}

variable "allocated_storage" {
  description = "스토리지 용량(GB)"
  type        = number
}

variable "backup_retention_period" {
  description = "백업 보존 기간(일)"
  type        = number
}

variable "skip_final_snapshot" {
  description = "삭제 시 최종 스냅샷 생략 여부(dev: true, prod: false)"
  type        = bool
}
