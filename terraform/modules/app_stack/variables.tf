# app_stack module input variables

variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
}

variable "stage_name" {
  description = "Stage/environment name (e.g., dev, test, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources in this module"
  type        = map(string)
  default     = {}
}
