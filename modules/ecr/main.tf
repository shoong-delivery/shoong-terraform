locals {
  repositories = [
    "shoong-order",
    "shoong-kitchen",
    "shoong-notification",
    "shoong-delivery",
    "shoong-batch",
  ]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.repositories)

  name                 = each.key
  image_tag_mutability = "MUTABLE" # 이미지 태그를 덮어쓸 수 있는지 여부

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name    = each.key
    Project = var.project
    Env     = var.env
  }
}

# 이미지 lifecycle policy(dev는 일정 갯수만 유지, prod는 전부 남겨두기)
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = toset(local.repositories)

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "dev 태그 이미지 최근 ${var.dev_image_count}개 유지"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev"]
          countType     = "imageCountMoreThan"
          countNumber   = var.dev_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "untagged 이미지 1일 후 삭제"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
