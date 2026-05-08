# =============================================================================
# 파일 목적: AWS Load Balancer Controller 용 IRSA(IAM Role for Service Account) 설정
#
# [배경 지식]
# EKS 위의 Pod가 AWS API(예: ALB 생성)를 호출하려면 IAM 권한이 필요하다.
# 예전에는 Node EC2 인스턴스에 직접 IAM Role을 붙였지만, 그러면
# 같은 노드의 모든 Pod가 동일 권한을 공유하는 보안 문제가 있었다.
#
# IRSA(IAM Roles for Service Accounts)는 이 문제를 해결한다:
#   1. EKS OIDC Provider가 K8s ServiceAccount에 JWT 토큰을 발급
#   2. Pod는 그 토큰으로 AWS STS에 AssumeRoleWithWebIdentity 요청
#   3. STS가 검증 후 임시 자격증명(AccessKey/SecretKey/SessionToken) 반환
#   4. Pod는 해당 IAM Role의 권한만 갖게 됨 → 최소 권한 원칙 준수
#
# 이 파일에서 만드는 것:
#   - aws_iam_role: LB Controller Pod가 Assume할 IAM Role
#   - aws_iam_role_policy: 그 Role에 붙이는 인라인 정책 (ALB 관리 권한)
# =============================================================================


# -----------------------------------------------------------------------------
# IAM Role - LB Controller Pod가 실제로 Assume(위임받아 사용)하는 역할
#
# [Trust Policy (신뢰 정책)]
# IAM Role은 "누가 이 Role을 사용할 수 있는가"를 Trust Policy로 정의한다.
# 일반적으로 EC2나 Lambda 같은 AWS 서비스가 Principal이지만,
# IRSA에서는 EKS OIDC Provider(Federated)가 Principal이 된다.
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
          # "system:serviceaccount:kube-system:aws-load-balancer-controller"
          # → kube-system 네임스페이스의 aws-load-balancer-controller SA만 허용
          # → 다른 네임스페이스·다른 SA는 이 Role을 사용할 수 없음
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"

          # aud(audience) claim 검증:
          # 이 토큰이 AWS STS용으로 발급된 것인지 확인
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


# -----------------------------------------------------------------------------
# IAM Role Policy - LB Controller가 AWS에서 실제로 할 수 있는 작업 정의
#
# AWS Load Balancer Controller는 K8s Ingress/Service 리소스를 감지해서
# ALB(Application Load Balancer) / NLB를 자동으로 생성·수정·삭제한다.
# 그 작업들을 수행하려면 아래와 같은 AWS 권한이 필요하다.
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "aws_lb_controller" {
  name = "${var.project}-${var.env}-aws-lb-controller-policy"
  role = aws_iam_role.aws_lb_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # [1] ELB 서비스 연결 역할(Service-Linked Role) 생성 권한
      # ALB를 처음 사용할 때 AWS가 내부적으로 "AWSServiceRoleForElasticLoadBalancing" 역할을 자동 생성한다.
      # LB Controller가 최초 ALB를 만들 때 이 역할 생성을 트리거하므로 필요.
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
      # LB Controller가 ALB를 만들기 전에 현재 VPC, 서브넷, SG, 인스턴스 정보를 읽어야 함.
      # 또한 이미 존재하는 LB·타겟그룹·리스너 상태를 주기적으로 동기화할 때도 사용.
      {
        Effect = "Allow"
        Action = [
          # VPC / 네트워크 구성 조회
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
          # CoIP(Customer-owned IP): AWS Outposts 환경에서 사용, 일반 EKS에선 미사용
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          # ELB 현재 상태 조회
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
      # Ingress에 HTTPS 설정 시 ACM 인증서를 ALB에 연결해야 함.
      # WAF를 Ingress 어노테이션으로 붙이거나 Shield 보호를 설정할 때도 필요.
      {
        Effect = "Allow"
        Action = [
          # ACM(Certificate Manager) 인증서 목록 조회 및 상세 확인
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          # IAM에 업로드된 서버 인증서 조회 (ACM 외 레거시 방식)
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          # WAF Regional (ALB용 WAF v1)
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          # WAFv2 (최신 WAF)
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          # AWS Shield (DDoS 보호)
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },

      # [4] Security Group 인바운드 규칙 수정 권한
      # ALB가 생성되면 LB Controller가 ALB → Pod 간 트래픽을 허용하는
      # Security Group 인바운드 규칙을 자동으로 추가/제거한다.
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "*"
      },

      # [5] Security Group 생성 권한
      # ALB용 전용 Security Group을 신규 생성할 때 필요.
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "*"
      },

      # [6] 신규 생성된 Security Group에 태그 추가 권한
      # LB Controller가 만든 SG임을 식별하기 위해 태그를 붙인다.
      # Condition: CreateSecurityGroup 액션으로 방금 만든 SG에만 태그 가능하도록 제한
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" }
          # "aws:RequestedRegion" = "false" → RequestedRegion 조건이 존재해야 함(null 아님)
          Null = { "aws:RequestedRegion" = "false" }
        }
      },

      # [7] LB Controller가 관리하는 Security Group 태그 수정/삭제 권한
      # "ingress.k8s.aws/cluster" 태그가 있는 SG(= LB Controller가 만든 SG)만 대상으로 제한
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          # "ingress.k8s.aws/cluster" 태그가 존재하는 리소스에만 적용 (Null=false → 태그 있음)
          Null = { "aws:ResourceTag/ingress.k8s.aws/cluster" = "false" }
        }
      },

      # [8] LB Controller가 관리하는 Security Group 삭제 및 규칙 변경 권한
      # 마찬가지로 "ingress.k8s.aws/cluster" 태그가 달린 SG에만 허용
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"]
        Resource = "*"
        Condition = {
          Null = { "aws:ResourceTag/ingress.k8s.aws/cluster" = "false" }
        }
      },

      # [9] ALB / Target Group 생성 권한
      # K8s Ingress 리소스가 생성되면 LB Controller가 실제 ALB와 Target Group을 만든다.
      # Condition: "elbv2.k8s.aws/cluster" 태그를 요청에 포함할 때만 허용 → 임의 ALB 생성 방지
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource = "*"
        Condition = {
          Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },

      # [10] ALB 리스너 및 리스너 규칙 생성/삭제 권한
      # 리스너: ALB가 어떤 포트(80, 443)에서 트래픽을 받을지 정의
      # 리스너 규칙: path-based routing 등 라우팅 규칙 설정
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule"]
        Resource = "*"
      },

      # [11] Target Group / LB 태그 추가/제거 권한 (생성/삭제 과정 외)
      # Condition: 생성 시(RequestTag)가 아닌 기존 리소스(ResourceTag) 태그 수정 제한
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
            # RequestTag가 없고(true) ResourceTag가 있는(false) 경우 → 기존 LB 태그 수정
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
      # K8s Ingress가 변경되거나 삭제될 때 기존 ALB를 업데이트하거나 제거한다.
      # Condition: LB Controller가 만든 리소스("elbv2.k8s.aws/cluster" 태그 있음)만 대상
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
      # [9]번에서 CreateLoadBalancer/CreateTargetGroup을 허용했고,
      # 생성 직후 태그를 붙이는 액션도 별도로 허용해야 함.
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
            # Create 액션과 함께 호출될 때만 허용
            "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"]
          }
          Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },

      # [15] Target Group에 Pod 등록/해제 권한
      # Pod가 생성되거나 삭제될 때(또는 Readiness 변경 시)
      # ALB Target Group에 해당 Pod IP를 등록하거나 제거한다.
      # (IP 모드: Pod IP를 직접 타겟으로 등록, Instance 모드: NodePort 경유)
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },

      # [16] 기타 ALB 고급 설정 권한
      # - SetWebAcl: WAF를 ALB에 연결
      # - ModifyListener: 리스너 포트/프로토콜/인증서 변경
      # - AddListenerCertificates / RemoveListenerCertificates: 다중 도메인 HTTPS 인증서 관리
      # - ModifyRule: 리스너 규칙 우선순위·조건 변경
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:SetWebAcl", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:AddListenerCertificates", "elasticloadbalancing:RemoveListenerCertificates", "elasticloadbalancing:ModifyRule"]
        Resource = "*"
      }
    ]
  })
}
