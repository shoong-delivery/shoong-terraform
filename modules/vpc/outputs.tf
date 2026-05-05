output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록 (EKS 노드 그룹용)"
  value       = aws_subnet.private[*].id
}

output "db_subnet_ids" {
  description = "DB 서브넷 ID 목록"
  value       = aws_subnet.db[*].id
}

output "db_subnet_group_name" {
  description = "RDS 모듈에서 사용할 DB 서브넷 그룹 이름"
  value       = aws_db_subnet_group.this.name
}

output "private_route_table_ids" {
  description = "프라이빗 라우팅 테이블 ID 목록"
  value       = aws_route_table.private[*].id
}


