output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS 클러스터 API 엔드포인트"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "EKS 클러스터 CA 인증서(kubeconfig용)"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "IRSA용 OIDC issuer URL"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "node_group_role_arn" {
  description = "노드 그룹 IAM Role ARN"
  value       = aws_iam_role.node_group.arn
}

output "cluster_primary_security_group_id" {
  description = "EKS가 자동 생성한 클러스터 Primary SG (워커 노드에 자동으로 붙음)"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
