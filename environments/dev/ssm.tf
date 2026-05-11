resource "aws_iam_role" "ssm_ec2" {
  name = "${var.project}-${var.env}-ssm-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name    = "${var.project}-${var.env}-ssm-ec2-role"
    Project = var.project
    Env     = var.env
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ssm_eks_access" {
  name = "${var.project}-${var.env}-ssm-eks-access"
  role = aws_iam_role.ssm_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ssm_ec2" {
  name = "${var.project}-${var.env}-ssm-ec2-profile"
  role = aws_iam_role.ssm_ec2.name
}

# SSM EC2 인스턴스
resource "aws_instance" "ssm" {
  ami                    = var.ssm_ec2_ami
  instance_type          = var.ssm_ec2_instance_type
  subnet_id              = module.vpc.private_subnet_ids[0]
  iam_instance_profile   = aws_iam_instance_profile.ssm_ec2.name
  vpc_security_group_ids = [module.security_group.ssm_ec2_sg_id]

  # 공인 IP 없음
  associate_public_ip_address = false

  user_data = <<-EOF
    #!/bin/bash
    # 패키지 업데이트
    yum update -y

    # kubectl 설치
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/

    # psql 설치
    yum install -y postgresql15

    # aws cli 최신화
    yum install -y unzip
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install --update

    # kubeconfig 설정
    aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
  EOF

  tags = {
    Name    = "${var.project}-${var.env}-ssm-ec2"
    Project = var.project
    Env     = var.env
  }
}
