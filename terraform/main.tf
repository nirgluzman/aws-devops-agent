# Root module - orchestrates all infrastructure components
# Calls three child modules: app_stack, notification, and observability

# Module: Application Stack (API Gateway, Lambda, S3)
module "app_stack" {
  source = "./modules/app_stack"

  aws_region  = var.aws_region
  stage_name  = var.stage_name
  tags        = local.default_tags
}

# Module: Notification (SNS topic and email subscription)
module "notification" {
  source = "./modules/notification"

  alert_email = var.alert_email
  tags        = local.default_tags
}

# Module: Observability (CloudWatch alarms, log metric filters)
module "observability" {
  source = "./modules/observability"

  lambda_function_name = module.app_stack.lambda_function_name
  sns_topic_arn        = module.notification.sns_topic_arn
  tags                 = local.default_tags
}
