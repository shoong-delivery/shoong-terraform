variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름(dev, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes 버전"
  type        = string
}

variable "private_subnet_ids" {
  description = "EKS 노드 그룹이 배치될 프라이빗 서브넷 ID 목록"
  type        = list(string)
}

variable "eks_node_sg_id" {
  description = "EKS 노드 Security Group ID"
  type        = string
}

variable "node_instance_type" {
  description = "노드 그룹 인스턴스 타입"
  type        = string
}

variable "node_ami_type" {
  description = "노드 그룹 AMI 타입"
  type        = string
}

variable "node_desired_size" {
  description = "노드 그룹 desired 수"
  type        = number
}

variable "node_min_size" {
  description = "노드 그룹 최소 수"
  type        = number
}

variable "node_max_size" {
  description = "노드 그룹 최대 수"
  type        = number
}

variable "ssm_ec2_role_arn" {
  description = "SSM EC2 IAM Role ARN (EKS 접근용)"
  type        = string
}
