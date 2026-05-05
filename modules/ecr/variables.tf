# modules/ecr/variables.tf

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "env" {
  description = "환경 이름(dev, prod)"
  type        = string
}

variable "dev_image_count" {
  description = "dev 이미지 보관 개수"
  type        = number
}
