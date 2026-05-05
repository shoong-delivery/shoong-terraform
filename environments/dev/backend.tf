# backend.tf 에서는 변수 사용 불가능. 하드코딩해야함
# 테라폼이 backend를 초기화할 때 변수가 로드되기 전
# 실행순서
# 1. backend 초기화 (terraform init)
# 2. provider 초기화
# 3. 변수 로드 (var.xxx 사용 가능)
# 4. 리소스 생성
terraform {
  backend "s3" {
    bucket         = "shoong-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "shoong-terraform-state-lock"
    encrypt        = true
  }
}
