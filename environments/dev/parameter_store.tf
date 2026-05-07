locals {
  common_parameters = {
    "/shoong/dev/NODE_ENV"             = "production"
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

