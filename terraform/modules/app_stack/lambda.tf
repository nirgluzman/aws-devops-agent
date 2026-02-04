# Lambda function for message handling with X-Ray tracing

module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.0"

  function_name = "handle_messages"
  handler       = "dist/index.handler"
  runtime       = "nodejs24.x"
  memory_size   = 128
  timeout       = 6

  # X-Ray active tracing
  tracing_mode = "Active"

  # Source code — all deps (SDK, Powertools, X-Ray) are bundled into dist/index.js
  source_path = [
    {
      path = var.lambda_source_path
      patterns = [
        "!.*",
        "!src",
        "!build\\.js",
        "!tsconfig\\.json",
        "!package-lock\\.json",
        "!README\\.md",
        "!node_modules",
        "dist/index\\.js",
        "package\\.json",
      ]
    }
  ]

  # Versioning configuration
  publish                                    = true
  create_current_version_allowed_triggers    = false
  create_unqualified_alias_allowed_triggers  = true

  # Environment variables for the Lambda function
  environment_variables = {
    MESSAGES_BUCKET = module.s3_bucket.s3_bucket_id
  }

  # IAM: S3 access
  attach_policy_json = true
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })

  # IAM: X-Ray tracing policy (managed by module)
  attach_tracing_policy = true

  # Lambda trigger permissions - allows API Gateway to invoke this Lambda function
  allowed_triggers = {
    APIGatewayGet = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.api_execution_arn}/${var.stage_name}/GET/messages"
    }
    APIGatewayPost = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.api_execution_arn}/${var.stage_name}/POST/messages"
    }
  }

  # CloudWatch Logs retention to control costs
  cloudwatch_logs_retention_in_days = 3

  tags = var.tags
}
