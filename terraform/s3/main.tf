terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration will be provided via backend.config file
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = var.environment
      Owner       = var.owner
      CreatedBy   = var.created_by
      CreatedAt   = var.created_at
    }
  }
}

# S3 bucket using official AWS module
module "s3_bucket" {
  # terraform-aws-s3-bucket v4.2.2
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=8b855f886e3f7f27ea4cdb692c94805fdf25f9e3"

  bucket = var.bucket_name

  versioning = {
    enabled = var.versioning_enabled
  }

  # Server-side encryption
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = var.encryption_type == "aws:kms" ? "aws:kms" : "AES256"
        kms_master_key_id = var.encryption_type == "aws:kms" ? var.kms_key_id : null
      }
    }
  }

  # Block public access
  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access

  # Lifecycle rules
  lifecycle_rule = var.lifecycle_enabled ? [
    {
      id      = "transition-to-ia"
      enabled = true

      transition = [
        {
          days          = var.lifecycle_transition_days
          storage_class = "STANDARD_IA"
        },
        {
          days          = var.lifecycle_transition_days * 2
          storage_class = "GLACIER"
        }
      ]
    }
  ] : []

  tags = merge(
    var.tags,
    {
      Name = var.bucket_name
    }
  )
}
