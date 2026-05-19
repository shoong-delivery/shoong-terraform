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

  project             = var.project
  env                 = var.env
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = var.vpc_cidr
  allow_ssm_db_access = true
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
