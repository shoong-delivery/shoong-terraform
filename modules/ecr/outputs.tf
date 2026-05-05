# modules/ecr/outputs.tf

output "repository_urls" {
  description = "ECR 레포지토리 URL 맵(서비스명 -> URL)"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "ECR 레포지토리 ARN 맵(GitHub Actions IAM 정책용)"
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}
