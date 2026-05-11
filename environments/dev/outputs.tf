output "cluster_name" {
  value = module.eks.cluster_name
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "cloudfront_domain" {
  value = module.cloudfront.distribution_domain_name
}

output "cloudfront_distribution_id" {
  value = module.cloudfront.distribution_id
}

output "github_actions_role_arn" {
  value = module.iam_oidc.github_actions_role_arn
}

output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "target_group_arn" {
  value = module.alb.target_group_arn
}

output "aws_lb_controller_role_arn" {
  value = aws_iam_role.aws_lb_controller.arn
}
