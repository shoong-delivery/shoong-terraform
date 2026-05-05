data "aws_route53_zone" "this" {
  name         = var.zone_domain
  private_zone = false
}
