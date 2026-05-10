variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "github_org" {
  type = string
}

variable "github_repos" {
  description = "허용할 GitHub 레포 목록"
  type        = list(string)
}

variable "ecr_repository_names" {
  description = "GitHub Actions가 push 가능한 ECR 리포지토리 이름 목록"
  type        = list(string)
  default = [
    "shoong-order",
    "shoong-kitchen",
    "shoong-notification",
    "shoong-delivery",
    "shoong-batch",
  ]
}
