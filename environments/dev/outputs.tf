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
