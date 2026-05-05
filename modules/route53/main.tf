resource "aws_route53_zone" "this" {
  name = var.domain

  tags = {
    Name    = var.domain
    Project = var.project
    Env     = var.env
  }
}
