module "vpc" {
  source = "../../modules/vpc"

  project              = var.project
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  db_subnet_cidrs      = var.db_subnet_cidrs
  cluster_name         = var.cluster_name
}

module "security_group" {
  source = "../../modules/security_group"

  project  = var.project
  env      = var.env
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr
}

module "eks" {
  source = "../../modules/eks"

  project            = var.project
  env                = var.env
  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  private_subnet_ids = module.vpc.private_subnet_ids
  eks_node_sg_id     = module.security_group.eks_node_sg_id
  node_instance_type = var.node_instance_type
  node_ami_type      = var.node_ami_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  ssm_ec2_role_arn   = aws_iam_role.ssm_ec2.arn

}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = "/shoong/dev/db-credentials"
}

locals {
  db_credentials = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)
}

module "rds" {
  source = "../../modules/rds"

  project           = var.project
  env               = var.env
  db_engine_version = var.db_engine_version
  db_instance_class = var.db_instance_class
  db_name           = var.db_name
  db_username       = local.db_credentials["username"]
  db_password       = local.db_credentials["password"]
  # db_username             = var.db_username
  # db_password             = var.db_password
  db_subnet_group_name    = module.vpc.db_subnet_group_name
  rds_sg_id               = module.security_group.rds_sg_id
  multi_az                = var.multi_az
  replica_count           = var.replica_count
  allocated_storage       = var.allocated_storage
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
}

module "ecr" {
  source = "../../modules/ecr"

  project         = var.project
  env             = var.env
  dev_image_count = var.dev_image_count
}

module "route53" {
  source = "../../modules/route53"

  project = var.project
  env     = var.env
  domain  = var.domain
}

module "acm" {
  source = "../../modules/acm"

  project = var.project
  env     = var.env
  domain  = var.domain
  zone_id = module.route53.zone_id
}

module "waf" {
  source = "../../modules/waf"

  project = var.project
  env     = var.env
}

module "alb" {
  source = "../../modules/alb"

  project           = var.project
  env               = var.env
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_group.alb_sg_id
  certificate_arn   = module.acm.certificate_arn
}

module "s3" {
  source = "../../modules/s3"

  project = var.project
  env     = var.env
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  project                     = var.project
  env                         = var.env
  domain                      = var.domain
  zone_id                     = module.route53.zone_id
  certificate_arn             = module.acm.certificate_arn
  web_acl_arn                 = module.waf.web_acl_arn
  alb_dns_name                = module.alb.alb_dns_name
  frontend_bucket_id          = module.s3.frontend_bucket_id
  frontend_bucket_arn         = module.s3.frontend_bucket_arn
  frontend_bucket_domain_name = module.s3.frontend_bucket_domain_name
  price_class                 = var.price_class
}

module "vpc_endpoint" {
  source = "../../modules/vpc_endpoint"

  project                 = var.project
  env                     = var.env
  aws_region              = var.aws_region
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids
  vpc_endpoint_sg_id      = module.security_group.vpc_endpoint_sg_id
}
