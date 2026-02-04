# https://registry.terraform.io/providers/hashicorp/aws/latest
# https://registry.terraform.io/providers/hashicorp/random/latest
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Apply default tags to all resources
  default_tags {
    tags = local.default_tags
  }
}

provider "random" {
  # Random provider configuration (if needed)
}
