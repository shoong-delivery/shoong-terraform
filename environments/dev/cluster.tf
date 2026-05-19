# =============================================================================
# 파일 목적: EKS 클러스터와 그 위/주변에서 동작하는 모든 리소스
#   - EKS 모듈
#   - OIDC Provider (IRSA 공통 의존성)
#   - IRSA 3종: AWS Load Balancer Controller / EBS CSI Driver / External Secrets
#   - EBS CSI Driver Addon
#   - 클러스터 접근용 Bastion EC2 (SSM Session Manager)
#   - RDS SG에 EKS cluster primary SG 인바운드 허용 패치
# =============================================================================


# -----------------------------------------------------------------------------
# EKS 모듈
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  project                = var.project
  env                    = var.env
  cluster_name           = var.cluster_name
  cluster_version        = var.cluster_version
  private_subnet_ids     = module.vpc.private_subnet_ids
  eks_node_sg_id         = module.security_group.eks_node_sg_id
  node_instance_type     = var.node_instance_type
  node_ami_type          = var.node_ami_type
  node_desired_size      = var.node_desired_size
  node_min_size          = var.node_min_size
  node_max_size          = var.node_max_size
  ssm_ec2_role_arn       = aws_iam_role.ssm_ec2.arn
  ssm_ec2_sg_id          = module.security_group.ssm_ec2_sg_id
  endpoint_public_access = true
  alb_sg_id              = module.security_group.alb_sg_id
}

# EKS 워커 노드는 EKS가 자동 생성한 cluster primary SG를 사용함.
# (modules/security_group의 eks_node SG는 컨트롤플레인 추가 SG일 뿐 노드에 안 붙음)
# → RDS SG에 cluster primary SG로부터의 5432 인바운드를 명시적으로 허용해야 EKS Pod가 RDS 접근 가능.
resource "aws_security_group_rule" "rds_from_eks_cluster_sg" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.security_group.rds_sg_id
  source_security_group_id = module.eks.cluster_primary_security_group_id
  description              = "PostgreSQL from EKS cluster primary SG (worker nodes)"
}


# -----------------------------------------------------------------------------
# OIDC Provider - IRSA의 공통 의존성
#
# [배경 지식]
# EKS 위의 Pod가 AWS API를 호출하려면 IAM 권한이 필요하다.
# 예전에는 Node EC2 인스턴스에 직접 IAM Role을 붙였지만, 그러면
# 같은 노드의 모든 Pod가 동일 권한을 공유하는 보안 문제가 있었다.
#
# IRSA(IAM Roles for Service Accounts)는 이 문제를 해결한다:
#   1. EKS OIDC Provider가 K8s ServiceAccount에 JWT 토큰을 발급
#   2. Pod는 그 토큰으로 AWS STS에 AssumeRoleWithWebIdentity 요청
#   3. STS가 검증 후 임시 자격증명(AccessKey/SecretKey/SessionToken) 반환
#   4. Pod는 해당 IAM Role의 권한만 갖게 됨 → 최소 권한 원칙 준수
# -----------------------------------------------------------------------------
data "tls_certificate" "eks" {
  url = module.eks.cluster_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = module.eks.cluster_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = {
    Project = var.project
    Env     = var.env
  }
}


# -----------------------------------------------------------------------------
# IRSA #1 - AWS Load Balancer Controller
#
# K8s Ingress/Service 리소스를 감지해서 ALB/NLB를 자동 생성·수정·삭제하는 컨트롤러.
# 그 작업들을 수행하려면 ALB·SG·ACM·WAF 등 광범위한 AWS 권한이 필요.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "aws_lb_controller" {
  name = "${var.project}-${var.env}-aws-lb-controller-role"

  # AssumeRolePolicyDocument: 이 Role을 "누가" "어떤 조건"으로 Assume할 수 있는지 정의
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"

      # Federated: AWS IAM User/Role이 아닌 외부 IdP(OIDC Provider)를 신뢰
      # → EKS가 발급한 OIDC JWT 토큰을 가진 주체(Pod)만 Assume 가능
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }

      # AssumeRoleWithWebIdentity: OIDC 토큰으로 Role을 Assume하는 STS 액션
      Action = "sts:AssumeRoleWithWebIdentity"

      # Condition: OIDC 토큰 안의 claim 값을 검증해서 특정 ServiceAccount만 허용
      Condition = {
        StringEquals = {
          # sub(subject) claim 검증:
          # kube-system 네임스페이스의 aws-load-balancer-controller SA만 허용
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"

          # aud(audience) claim 검증: 이 토큰이 AWS STS용으로 발급된 것인지 확인
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name    = "${var.project}-${var.env}-aws-lb-controller-role"
    Project = var.project
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "aws_lb_controller" {
  name = "${var.project}-${var.env}-aws-lb-controller-policy"
  role = aws_iam_role.aws_lb_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # [1] ELB 서비스 연결 역할(Service-Linked Role) 생성 권한
      # ALB를 처음 사용할 때 AWS가 내부적으로 "AWSServiceRoleForElasticLoadBalancing" 역할을 자동 생성한다.
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },

      # [2] EC2 / ELB 조회(Describe) 권한
      # LB Controller가 ALB를 만들기 전에 VPC, 서브넷, SG, 인스턴스 정보를 읽어야 함.
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeTrustStores"
        ]
        Resource = "*"
      },

      # [3] HTTPS 인증서 및 WAF/Shield 관련 권한
      {
        Effect = "Allow"
        Action = [
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },

      # [4] Security Group 인바운드 규칙 수정 권한
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "*"
      },

      # [5] Security Group 생성 권한
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "*"
      },

      # [6] 신규 생성된 Security Group에 태그 추가 권한
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" }
          Null         = { "aws:RequestedRegion" = "false" }
        }
      },

      # [7] LB Controller가 관리하는 Security Group 태그 수정/삭제 권한
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = { "aws:ResourceTag/ingress.k8s.aws/cluster" = "false" }
        }
      },

      # [8] LB Controller가 관리하는 Security Group 삭제 및 규칙 변경 권한
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"]
        Resource = "*"
        Condition = {
          Null = { "aws:ResourceTag/ingress.k8s.aws/cluster" = "false" }
        }
      },

      # [9] ALB / Target Group 생성 권한
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource = "*"
        Condition = {
          Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },

      # [10] ALB 리스너 및 리스너 규칙 생성/삭제 권한
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule"]
        Resource = "*"
      },

      # [11] Target Group / LB 태그 추가/제거 권한 (생성/삭제 과정 외)
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },

      # [12] 리스너 / 리스너 규칙 태그 추가/제거 권한
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },

      # [13] ALB / Target Group 수정 및 삭제 권한
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },

      # [14] Target Group / LB 생성 시 태그 추가 권한
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"]
          }
          Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },

      # [15] Target Group에 Pod 등록/해제 권한
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },

      # [16] 기타 ALB 고급 설정 권한
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:SetWebAcl", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:AddListenerCertificates", "elasticloadbalancing:RemoveListenerCertificates", "elasticloadbalancing:ModifyRule"]
        Resource = "*"
      }
    ]
  })
}


# -----------------------------------------------------------------------------
# IRSA #2 - EBS CSI Driver (PersistentVolume용 EBS 동적 프로비저닝)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ebs_csi" {
  name = "${var.project}-${var.env}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Project = var.project
    Env     = var.env
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]
}


# -----------------------------------------------------------------------------
# IRSA #3 - External Secrets Operator (SSM Parameter Store / Secrets Manager 동기화)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "eso" {
  name = "${var.project}-${var.env}-eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Project = var.project
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "eso" {
  name = "${var.project}-${var.env}-eso-policy"
  role = aws_iam_role.eso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/shoong/dev/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:/shoong/dev/*"
      }
    ]
  })
}


# -----------------------------------------------------------------------------
# Bastion EC2 (SSM Session Manager 접속 전용, 공인 IP 없음)
# kubectl / psql / aws cli 설치된 점프 호스트
# -----------------------------------------------------------------------------
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
