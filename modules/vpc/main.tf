# VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # VPC 안의 리소스에 DNS 이름을 자동 부여
  enable_dns_support   = true # VPC에서 DNS 자체 사용 가능 여부. 있으면 s3.amazonaws.com -> IP 변환 가능

  tags = {
    Name    = "${var.project}-${var.env}-vpc"
    project = var.project
    Env     = var.env
  }
}


# 퍼블릭 서브넷
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true # 이 서브넷에서 생성되는 인스턴스는 자동으로 Public IP를 부여해줄 것인가 여부

  tags = {
    Name                                        = "${var.project}-${var.env}-public-${count.index + 1}"
    Project                                     = var.project
    Env                                         = var.env
    "kubernetes.io/role/elb"                    = "1"      # ALB가 사용할 퍼블릭 서브넷을 EKS가 이 태그 보거 판단함
    "kubernetes.io/cluster/${var.cluster_name}" = "shared" # EKS 여러 클러스터가 공유 가능하면 "shared", 한 클러스터만 쓰면 "owned"
  }
}

# 프라이빗 서브넷
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name                                        = "${var.project}-${var.env}-private-${count.index + 1}"
    Project                                     = var.project
    Env                                         = var.env
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# DB 서브넷
resource "aws_subnet" "db" {
  count             = length(var.db_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name    = "${var.project}-${var.env}-db-${count.index + 1}"
    Project = var.project
    Env     = var.env
  }
}

# Elastic IP(NAT Gateway용) AWS에서 제공하는 고정 퍼블릭 IP 주소
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = {
    Name    = "${var.project}-${var.env}-eip-${count.index + 1}"
    Project = var.project
    Env     = var.env
  }
}

# NAT Gateway
resource "aws_nat_gateway" "this" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name    = "${var.project}-${var.env}-nat-${count.index + 1}"
    Project = var.project
    Env     = var.env
  }
}

# 인터넷 게이트웨이
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name    = "${var.project}-${var.env}-igw"
    Project = var.project
    Env     = var.env
  }
}

# 퍼블릭 라우팅 테이블
# 퍼블릭 서브넷은 전부 인터넷 게이트웨이 하나로 나가므로 라우팅 테이블 한 개임.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route { # 트래픽을 어디로 보낼지 정함
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name    = "${var.project}-${var.env}-public-rt"
    Project = var.project
    Env     = var.env
  }
}

# 퍼블릭 서브넷과 라우팅 테이블 연결
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 프라이빗 라우팅 테이블(AZ 별)
# 프라이빗 서브넷은 각 AZ의 NAT Gateway로 나가야해서 여러개 필요.
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name    = "${var.project}-${var.env}-private-rt-${count.index + 1}"
    Project = var.project
    Env     = var.env
  }
}

# 프라이빗 서브넷과 라우팅 테이블 연결
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# DB는 인터넷으로 나갈 일 없으므로 라우팅 테이블 필요 없음
resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.env}-db-subnet-group"
  subnet_ids = aws_subnet.db[*].id

  tags = {
    Name    = "${var.project}-${var.env}-db-subnet-group"
    Project = var.project
    Env     = var.env
  }
}
