module "route53" {
  source = "../../modules/route53"

  project     = var.project
  env         = var.env
  domain      = var.domain
  zone_domain = var.zone_domain
}

module "acm" {
  source = "../../modules/acm"

  providers = {
    aws = aws.us_east_1
  }

  project    = var.project
  env        = var.env
  domain     = var.domain
  zone_id    = module.route53.zone_id
  extra_sans = ["internal.${var.domain}", "*.internal.${var.domain}"]
}

resource "aws_route53_record" "internal_wildcard" {
  zone_id = module.route53.zone_id
  name    = "*.internal.${var.domain}"
  type    = "CNAME"
  ttl     = 300
  records = [module.alb.alb_dns_name]
}

module "waf" {
  source = "../../modules/waf"

  providers = {
    aws = aws.us_east_1
  }

  project = var.project
  env     = var.env
}

module "alb" {
  source = "../../modules/alb"

  project           = var.project
  env               = var.env
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_group.alb_sg_id
  certificate_arn   = module.acm.certificate_arn
}

module "s3" {
  source = "../../modules/s3"

  project = var.project
  env     = var.env
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  project                     = var.project
  env                         = var.env
  domain                      = var.domain
  zone_id                     = module.route53.zone_id
  certificate_arn             = module.acm.certificate_arn
  web_acl_arn                 = module.waf.web_acl_arn
  alb_dns_name                = module.alb.alb_dns_name
  frontend_bucket_id          = module.s3.frontend_bucket_id
  frontend_bucket_arn         = module.s3.frontend_bucket_arn
  frontend_bucket_domain_name = module.s3.frontend_bucket_domain_name
  price_class                 = var.price_class
}
