data "aws_secretsmanager_secret_version" "db" {
  secret_id = "/shoong/dev/db-credentials"
}

locals {
  db_credentials = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)
}

module "rds" {
  source = "../../modules/rds"

  project                 = var.project
  env                     = var.env
  db_engine_version       = var.db_engine_version
  db_instance_class       = var.db_instance_class
  db_name                 = var.db_name
  db_username             = local.db_credentials["username"]
  db_password             = local.db_credentials["password"]
  db_subnet_group_name    = module.vpc.db_subnet_group_name
  rds_sg_id               = module.security_group.rds_sg_id
  multi_az                = var.multi_az
  replica_count           = var.replica_count
  allocated_storage       = var.allocated_storage
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
}
