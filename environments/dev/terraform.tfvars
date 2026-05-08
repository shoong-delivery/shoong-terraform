# 공통
project = "shoong"
env     = "dev"

# 네트워크
vpc_cidr             = "10.0.0.0/16"
azs                  = ["us-east-1a", "us-east-1c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
db_subnet_cidrs      = ["10.0.21.0/24", "10.0.22.0/24"]

# eks
cluster_name       = "shoong-dev-cluster"
cluster_version    = "1.35"
node_instance_type = "c7i-flex.large" # c7i-flex.large(2C/4G), m7i-flex.large(2c/8G)
node_ami_type      = "AL2023_x86_64_STANDARD"
node_desired_size  = 2
node_min_size      = 2
node_max_size      = 4

# db
db_engine_version       = "18.3"
db_instance_class       = "db.t3.micro"
db_name                 = "shoong_dev"
multi_az                = false
replica_count           = 0
allocated_storage       = 20
backup_retention_period = 1
skip_final_snapshot     = true

# ecr
dev_image_count = 20

# 도메인
domain      = "dev.shoong.cloud"
zone_domain = "shoong.cloud"

# cloudfront
price_class = "PriceClass_200"

# ssm
ssm_ec2_ami           = "ami-0c02fb55956c7d316" # us-east-1 Amazon Linux 2023
ssm_ec2_instance_type = "t3.micro"
