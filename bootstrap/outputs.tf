# 이후 environments/dev(prod)/backend.tf 에 붙여넣을 값들
output "state_bucket_name" {
  description = "Terraform state 저장 S3 버킷 이름"
  value       = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  description = "Terraform state 잠금 DynamoDB 테이블 이름"
  value       = aws_dynamodb_table.terraform_state_lock.name
}
