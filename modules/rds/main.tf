# Secrets Manager - DB 자격증명 저장
# resource "aws_secretsmanager_secret" "db_credentials" {
#   name                    = "${var.project}/${var.env}/db-credentials"
#   recovery_window_in_days = 7

#   tags = {
#     Name    = "${var.project}-${var.env}-db-credentials"
#     Project = var.project
#     Env     = var.env
#   }
# }

# resource "aws_secretsmanager_secret_version" "db_credentials" {
#   secret_id = aws_secretsmanager_secret.db_credentials.id
#   secret_string = jsonencode({
#     username = var.db_username
#     password = var.db_password
#   })
# }

# RDS Primary 인스턴스
resource "aws_db_instance" "primary" {
  identifier     = "${var.project}-${var.env}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class
  db_name        = var.db_name
  username       = var.db_username
  password       = var.db_password

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.rds_sg_id]

  multi_az            = var.multi_az
  publicly_accessible = false
  storage_type        = "gp3"
  allocated_storage   = var.allocated_storage
  storage_encrypted   = true

  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot

  tags = {
    Name    = "${var.project}-${var.env}-db"
    Project = var.project
    Env     = var.env
  }
}

# RDS Read Replica(prod only)
resource "aws_db_instance" "replica" {
  count = var.replica_count

  identifier          = "${var.project}-${var.env}-db-replica-${count.index + 1}"
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = var.db_instance_class
  publicly_accessible = false
  storage_encrypted   = true
  skip_final_snapshot = true

  vpc_security_group_ids = [var.rds_sg_id]

  tags = {
    Name    = "${var.project}-${var.env}-db-replica"
    Project = var.project
    Env     = var.env
  }
}
