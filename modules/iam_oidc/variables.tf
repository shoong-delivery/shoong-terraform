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
