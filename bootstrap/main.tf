/*
bootstrap 구성
- aws_s3_bucket
- aws_s3_bucket_versioning
- aws_s3_bucket_server_side_encryption_configuration
- aws_s3_bucket_public_access_block
- aws_dynamodb_table
- aws_s3_bucket_lifecycle_configuration
# - aws_s3_bucket_logging(현재 혼자 운영 중이므로 불필요)
*/


# S3 버킷 - Terraform State 저장
resource "aws_s3_bucket" "terraform_state" {
  bucket = "shoong-terraform-state"

  tags = {
    Name    = "shoong-terraform-state"
    Project = "shoong"
  }
}

# S3 버킷 버전 관리 - State 파일 이력 보관
# 파일 덮어써도 이전 버전이 남아서 롤백 가능
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 버킷 암호화 설정
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id # 암호화를 적용할 S3 버킷 ID

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # 서버 사이드 암호화 알고리즘 설정(AES256)
      # SSE-S3가 Terraform state용으로 충분하다고 판단
      # 보안 강화하려면 SSE-KMS 사용하면 됨. 비용 발생
    }
  }
}

# S3 퍼블릭 액세스 차단
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB 테이블 - State 잠금(동시 실행 방지)
resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "shoong-terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST" # 사용량 기반 과금 설정
  hash_key     = "LockID"          # 해시 키 설정(잠금 식별)

  attribute {
    name = "LockID"
    type = "S" # 해시 키 데이터 타입 설정(문자열)
  }

  tags = {
    Name    = "shoong-terraform-state-lock"
    Project = "shoong"
  }
}


# 오래된 state 버전 자동 삭제(비용 절감)
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 60
    }
  }
}
