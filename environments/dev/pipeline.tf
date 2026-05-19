# =============================================================================
# 파일 목적: 배포 파이프라인이 사용하는 리소스
#   - ECR (이미지 저장소) + 기존 리소스 import 블록
#   - GitHub Actions용 IAM OIDC (CI에서 AWS 인증)
#   - SSM Parameter Store (앱 환경변수, External Secrets로 Pod에 주입)
# =============================================================================


# -----------------------------------------------------------------------------
# ECR - 컨테이너 이미지 저장소
# -----------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  project         = var.project
  env             = var.env
  dev_image_count = var.dev_image_count
}

# 기존 ECR 리포지토리를 모듈 상태로 import
import {
  to = module.ecr.aws_ecr_repository.this["shoong-batch"]
  id = "shoong-batch"
}
import {
  to = module.ecr.aws_ecr_repository.this["shoong-delivery"]
  id = "shoong-delivery"
}
import {
  to = module.ecr.aws_ecr_repository.this["shoong-notification"]
  id = "shoong-notification"
}
import {
  to = module.ecr.aws_ecr_repository.this["shoong-kitchen"]
  id = "shoong-kitchen"
}
import {
  to = module.ecr.aws_ecr_repository.this["shoong-order"]
  id = "shoong-order"
}


# -----------------------------------------------------------------------------
# GitHub Actions OIDC - CI에서 장기 자격증명 없이 AWS에 인증
# -----------------------------------------------------------------------------
module "iam_oidc" {
  source = "../../modules/iam_oidc"

  project    = var.project
  env        = var.env
  github_org = "shoong-delivery"
  github_repos = [
    "shoong-order-api",
    "shoong-kitchen-api",
    "shoong-delivery-api",
    "shoong-notification-api",
    "shoong-batch",
    "shoong-frontend"
  ]
}


# -----------------------------------------------------------------------------
# SSM Parameter Store - 앱 환경변수
# External Secrets Operator가 동기화해서 Pod에 ConfigMap/Secret으로 주입
# -----------------------------------------------------------------------------
locals {
  common_parameters = {
    "/shoong/dev/NODE_ENV"             = "development"
    "/shoong/dev/ORDER_API_URL"        = "http://dev-shoong-order:3001"
    "/shoong/dev/KITCHEN_API_URL"      = "http://dev-shoong-kitchen:3002"
    "/shoong/dev/DELIVERY_API_URL"     = "http://dev-shoong-delivery:3003"
    "/shoong/dev/NOTIFICATION_API_URL" = "http://dev-shoong-notification:3004"
  }

  service_parameters = {
    "/shoong/dev/order/PORT"        = "3001"
    "/shoong/dev/kitchen/PORT"      = "3002"
    "/shoong/dev/delivery/PORT"     = "3003"
    "/shoong/dev/notification/PORT" = "3004"
    "/shoong/dev/batch/ORDER_URL"   = "http://dev-shoong-order:3001"
  }
}

resource "aws_ssm_parameter" "common" {
  for_each = local.common_parameters

  name  = each.key
  type  = "String"
  value = each.value

  tags = {
    Project = var.project
    Env     = var.env
  }
}

resource "aws_ssm_parameter" "service" {
  for_each = local.service_parameters

  name  = each.key
  type  = "String"
  value = each.value

  tags = {
    Project = var.project
    Env     = var.env
  }
}

resource "aws_ssm_parameter" "alb_target_group_arn" {
  name  = "/shoong/${var.env}/alb-target-group-arn"
  type  = "String"
  value = module.alb.target_group_arn

  tags = {
    Project = var.project
    Env     = var.env
  }
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/shoong/${var.env}/vpc-id"
  type  = "String"
  value = module.vpc.vpc_id

  tags = {
    Project = var.project
    Env     = var.env
  }
}
