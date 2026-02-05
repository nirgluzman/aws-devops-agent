# app_stack module outputs

output "stage_name" {
  description = "Stage name"
  value       = var.stage_name
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = module.lambda_function.lambda_function_name
}

output "lambda_role_arn" {
  description = "Lambda execution role ARN"
  value       = module.lambda_function.lambda_role_arn
}

output "api_url" {
  description = "API Gateway invoke URL"
  value       = module.api_gateway.stage_invoke_url
}

output "s3_bucket_id" {
  description = "S3 bucket name/ID"
  value       = module.s3_bucket.s3_bucket_id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.s3_bucket.s3_bucket_arn
}
