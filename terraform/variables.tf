# Root module input variables
# https://developer.hashicorp.com/terraform/language/values/variables

variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "stage_name" {
  description = "Stage/environment name (e.g., dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications via SNS"
  type        = string
  # No default - this is a required variable
}
