# ALB SG
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.env}-alb-sg"
  description = "ALB Security Group"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-${var.env}-alb-sg"
    Project = var.project
    Env     = var.env
  }
}

# EKS Node SG
resource "aws_security_group" "eks_node" {
  name        = "${var.project}-${var.env}-eks-node-sg"
  description = "EKS Node Security Group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "ALB traffic including health check"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Inter-node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-${var.env}-eks-node-sg"
    Project = var.project
    Env     = var.env
  }
}

# SSM EC2 SG
resource "aws_security_group" "ssm_ec2" {
  name        = "${var.project}-${var.env}-ssm-ec2-sg"
  description = "SSM EC2 Security Group - RDS access"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow HTTPS outbound for SSM"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-${var.env}-ssm-ec2-sg"
    Project = var.project
    Env     = var.env
  }
}

# RDS SG
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.env}-rds-sg"
  description = "RDS Security Group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS Node"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_node.id]
  }

  ingress {
    description     = "PostgreSQL from SSM EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ssm_ec2.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-${var.env}-rds-sg"
    Project = var.project
    Env     = var.env
  }
}

# VPC Endpoint SG
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.project}-${var.env}-vpc-endpoint-sg"
  description = "VPC Endpoint Security Group"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-${var.env}-vpc-endpoint-sg"
    Project = var.project
    Env     = var.env
  }
}

# EKS Node SG에 SSM EC2에서 오는 443 허용 추가
resource "aws_security_group_rule" "eks_from_ssm" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.ssm_ec2.id
  description              = "SSM EC2 to EKS API"
}
