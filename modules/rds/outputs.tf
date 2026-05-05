output "db_endpoint" {
  description = "RDS Primary 엔드포인트"
  value       = aws_db_instance.primary.endpoint
}

output "db_name" {
  description = "데이터베이스 이름"
  value       = aws_db_instance.primary.db_name
}

output "replica_endpoint" {
  description = "RDS Replica 엔드포인트"
  value       = var.replica_count > 0 ? aws_db_instance.replica[0].endpoint : null
}

# output "secret_arn" {
#   description = "Secrets Manager ARN(앱에서 자격증명 참조용)"
#   value       = aws_secretsmanager_secret.db_credentials.arn
# }
