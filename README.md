# shoong-terraform

Shoong 서비스의 AWS 인프라를 프로비저닝하는 Terraform 레포지토리입니다.
VPC부터 EKS·RDS·CloudFront·CI/CD용 OIDC까지, 클러스터가 올라가기 전 단계의 모든 클라우드 리소스를 코드로 관리합니다.

---

## Shoong 프로젝트

Shoong은 음식 배달 도메인을 여러 개의 마이크로서비스로 나눠 구현하고,
Kubernetes(EKS) 위에서 GitOps로 배포·운영하는 클라우드 인프라 프로젝트입니다.

주문 → 조리 → 배달 → 알림으로 이어지는 흐름을 서비스 단위로 분리하고,
그 아래 인프라(IaC) → 이미지 빌드(CI) → 배포(GitOps/CD)까지의 파이프라인을 직접 구성했습니다.

### 레포지토리 구성

전체 시스템은 역할별로 레포지토리가 나뉘어 있습니다.

**플랫폼 / 인프라**

| 레포 | 역할 |
| --- | --- |
| [shoong-terraform](https://github.com/shoong-delivery/shoong-terraform) | AWS 인프라 프로비저닝 (IaC) |
| [shoong-gitops](https://github.com/shoong-delivery/shoong-gitops) | ArgoCD 앱 정의 / Helm 차트 관리 (CD) |

**애플리케이션**

| 레포 | 역할 | 포트 |
| --- | --- | --- |
| [shoong-order-api](https://github.com/shoong-delivery/shoong-order-api) | 주문 서비스 | 3001 |
| [shoong-kitchen-api](https://github.com/shoong-delivery/shoong-kitchen-api) | 주방 서비스 | 3002 |
| [shoong-delivery-api](https://github.com/shoong-delivery/shoong-delivery-api) | 배달 서비스 | 3003 |
| [shoong-notification-api](https://github.com/shoong-delivery/shoong-notification-api) | 알림 서비스 | 3004 |
| [shoong-batch](https://github.com/shoong-delivery/shoong-batch) | 오래된 주문 정리 배치 (CronJob) | - |
| [shoong-frontend](https://github.com/shoong-delivery/shoong-frontend) | 프론트엔드 | - |

### 레포 간 관계

```
shoong-terraform ──(EKS / ECR / RDS / OIDC / SSM 생성)──┐
                                                        ▼
  앱 레포 (order·kitchen·delivery·notification·batch·frontend)
        └─ GitHub Actions(OIDC)로 이미지 빌드 → ECR push
                                                        ▼
                                                shoong-gitops
                                    (ArgoCD가 Helm 차트로 EKS에 배포)
```

- **shoong-terraform** 이 클러스터·레지스트리·DB·CI 인증 기반을 먼저 만든다.
- 각 **앱 레포**는 GitHub Actions에서 OIDC로 AWS에 인증해 이미지를 빌드하고 ECR에 푸시한다.
- **shoong-gitops** 의 ArgoCD가 변경을 감지해 EKS에 배포한다.

---

## 이 레포의 역할

Terraform으로 다음 계층을 관리합니다.

- **네트워크** — VPC, 퍼블릭/프라이빗/DB 서브넷(3 AZ), VPC Endpoint, Security Group
- **컴퓨트** — EKS 클러스터 + 관리형 노드그룹, IRSA(서비스 어카운트 IAM)
- **데이터** — RDS(PostgreSQL), 자격증명은 Secrets Manager에서 주입
- **엣지** — Route53, ACM, ALB, CloudFront, WAF
- **파이프라인** — ECR, GitHub Actions용 IAM OIDC, SSM Parameter Store(앱 환경변수)
- **운영** — SSM Session Manager 전용 Bastion EC2 (공인 IP 없는 점프 호스트)

## 디렉토리 구조

```
shoong-terraform/
├── bootstrap/          # 원격 상태 저장소 부트스트랩 (S3 + DynamoDB Lock)
├── environments/
│   ├── dev/            # 개발 환경 (실제 운영 중)
│   │   ├── network.tf      # VPC / SG / VPC Endpoint
│   │   ├── cluster.tf      # EKS / OIDC / IRSA / EBS CSI / Bastion
│   │   ├── database.tf     # RDS (PostgreSQL)
│   │   ├── edge.tf         # Route53 / ACM / ALB / CloudFront / WAF / S3
│   │   ├── pipeline.tf     # ECR / GitHub OIDC / SSM Parameter
│   │   └── Makefile        # 비용 절감용 선택적 destroy
│   └── prod/           # 운영 환경 정의 (구성 템플릿)
└── modules/            # 재사용 모듈
    ├── vpc/  security_group/  vpc_endpoint/
    ├── eks/  iam_oidc/
    ├── rds/
    ├── acm/  route53/  alb/  cloudfront/  waf/  s3/
    └── ecr/
```

## 주요 설계 포인트

### 원격 상태 (Remote Backend)
`bootstrap/` 에서 상태 저장용 S3 버킷과 잠금용 DynamoDB 테이블을 먼저 생성합니다.
S3는 버전 관리·암호화·퍼블릭 차단을 적용하고, 60일 지난 이전 버전은 라이프사이클로 자동 정리합니다.
backend는 변수 사용이 불가능해 값을 직접 명시합니다([backend.tf](environments/dev/backend.tf) 참고).

### IRSA로 Pod 권한 최소화
노드 EC2에 IAM Role을 붙이지 않고, EKS OIDC Provider를 통해 **ServiceAccount 단위로 권한을 부여**합니다.
- AWS Load Balancer Controller — Ingress/Service 감지 후 ALB 자동 생성
- EBS CSI Driver — PersistentVolume 동적 프로비저닝
- External Secrets Operator — SSM/Secrets Manager 값을 Pod에 동기화

### 설정·시크릿 분리
앱 환경변수는 **SSM Parameter Store**, DB 자격증명은 **Secrets Manager**에 두고,
클러스터 내부에서는 External Secrets Operator가 이를 K8s Secret/ConfigMap으로 동기화합니다.
Terraform 코드에는 비밀값을 직접 두지 않습니다.

### CI/CD 인증 (OIDC)
GitHub Actions가 장기 액세스 키 없이 OIDC로 AWS에 인증하도록 IAM을 구성합니다.
신뢰 대상 레포는 [pipeline.tf](environments/dev/pipeline.tf) 의 `github_repos` 로 제한됩니다.

### 비공개 접근 경로
운영 작업(kubectl, psql)은 공인 IP가 없는 **Bastion EC2 + SSM Session Manager**로만 접근합니다.
프라이빗 서브넷에서 AWS API 호출은 VPC Endpoint를 경유합니다.

### 비용 절감용 destroy
개인 운영 환경 특성상 매일 클러스터를 내렸다 올립니다.
[Makefile](environments/dev/Makefile) 의 `make destroy` 는 과금되는 리소스만 삭제하고
S3·CloudFront·ECR·Route53·ACM·OIDC 등 재생성 비용/대기가 큰 리소스는 보존합니다.

## 사용법

### 1. 상태 저장소 부트스트랩 (최초 1회)

```bash
cd bootstrap
terraform init
terraform apply
```

### 2. 환경 배포

```bash
cd environments/dev
terraform init      # S3 backend 초기화
terraform plan
terraform apply
```

### 3. 비용 절감용 정리 / 완전 삭제

```bash
make destroy        # 과금 리소스만 삭제 (S3/CF/ECR/DNS 보존)
make destroy-all    # 전체 삭제 (주의: S3 파일·ECR 이미지 포함)
```

## 환경 정보

| 항목 | dev |
| --- | --- |
| 리전 | us-east-1 (3 AZ) |
| Terraform | ~> 1.14 |
| AWS Provider | ~> 6.0 |
| EKS | v1.35 / 노드 2~4대 (c7i-flex.large) |
| RDS | PostgreSQL 18.3 / db.t3.micro |
| 도메인 | dev.shoong.cloud |

> dev/prod 차이: dev는 EKS 엔드포인트 퍼블릭 접근 허용·단일 AZ RDS, prod는 엔드포인트 프라이빗·Multi-AZ 등 가용성 우선 구성을 전제로 합니다.

> 현재 dev 환경을 운영 중이며, prod 구성은 진행 중입니다.
