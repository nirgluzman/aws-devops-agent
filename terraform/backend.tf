# S3 backend configuration for Terraform remote state
# https://developer.hashicorp.com/terraform/language/backend/s3

terraform {
  backend "s3" {
    # Default bucket for local runs; CI overrides via -backend-config="bucket=..." (TF_STATE_BUCKET).
    bucket         = "terraform-backend-demo-ue1"
    key            = "devops-agent-demo/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    use_lockfile   = true # S3 State Locking

    # Note that DynamoDB State Locking is deprecated and will be removed in a future release.
    # https://developer.hashicorp.com/terraform/language/backend/s3#state-locking
  }
}
