output "alb_sg_id" {
  description = "ALB Security Group ID"
  value       = aws_security_group.alb.id
}

output "eks_node_sg_id" {
  description = "EKS Node Security Group ID"
  value       = aws_security_group.eks_node.id
}

output "ssm_ec2_sg_id" {
  description = "SSM EC2 Security Group ID"
  value       = aws_security_group.ssm_ec2.id
}

output "rds_sg_id" {
  description = "RDS Security Group ID"
  value       = aws_security_group.rds.id
}

output "vpc_endpoint_sg_id" {
  description = "VPC Endpoint Security Group ID"
  value       = aws_security_group.vpc_endpoint.id
}
