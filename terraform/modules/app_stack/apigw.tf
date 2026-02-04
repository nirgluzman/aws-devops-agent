# HTTP API Gateway v2 with Lambda proxy integration
# https://registry.terraform.io/modules/terraform-aws-modules/apigateway-v2/aws/latest

module "api_gateway" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "~> 6.0"

  name          = "messages_http_apigw"
  protocol_type = "HTTP"
  stage_name    = var.stage_name

  create_domain_name = false # disable creation of the domain name

  routes = {
    "GET /messages" = {
      integration = {
        type                   = "AWS_PROXY"
        uri                    = module.lambda_function.lambda_function_invoke_arn
        payload_format_version = "2.0"
      }
    }
    "POST /messages" = {
      integration = {
        type                   = "AWS_PROXY"
        uri                    = module.lambda_function.lambda_function_invoke_arn
        payload_format_version = "2.0"
      }
    }
  }

  tags = var.tags
}
