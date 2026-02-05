# Global tags applied to all AWS resources via provider default_tags
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags
locals {
  default_tags = {
    Project     = "DevOpsAgentDemo"
    Terraform   = "true"
    Environment = var.stage_name
  }
}
