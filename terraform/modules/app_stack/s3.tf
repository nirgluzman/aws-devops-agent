# S3 bucket for message storage (unique name using random_pet)

resource "random_pet" "messages_bucket_name" {
  prefix = "messages-bucket"
  length = 2
}

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket = random_pet.messages_bucket_name.id

  # Disables ACLs, bucket owner owns all objects, access via IAM policies only
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  # Destroy bucket contents as well as bucket itself on `terraform destroy`
  force_destroy = true

  tags = var.tags
}
