# Root module outputs - aggregate outputs from child modules
# https://developer.hashicorp.com/terraform/language/values/outputs

# Application Stack Outputs
output "api_url" {
  description = "API Gateway invoke URL"
  value       = module.app_stack.api_url
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = module.app_stack.lambda_function_name
}

output "lambda_arn" {
  description = "Lambda function ARN"
  value       = module.app_stack.lambda_arn
}

output "s3_bucket_id" {
  description = "S3 bucket name/ID"
  value       = module.app_stack.s3_bucket_id
}

# Notification Outputs
output "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  value       = module.notification.sns_topic_arn
}

# Observability Outputs
output "error_alarm_arn" {
  description = "CloudWatch error alarm ARN"
  value       = module.observability.error_alarm_arn
}

output "duration_alarm_arn" {
  description = "CloudWatch duration alarm ARN"
  value       = module.observability.duration_alarm_arn
}
