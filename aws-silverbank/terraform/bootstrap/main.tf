# bootstrap/main.tf
# Creates S3 bucket and DynamoDB table for Terraform remote state
# Run ONCE manually: terraform init && terraform apply
# This file itself uses local state (no remote backend needed for bootstrapping)

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"  # London — same region as all SilverBank infrastructure
}

# S3 bucket to store Terraform state files
# One bucket for all environments (proxmox + aws), separated by key prefix
resource "aws_s3_bucket" "tfstate" {
  bucket = "silverbank-tfstate-mariusiordan"  # must be globally unique

  tags = {
    Project   = "silverbank"
    ManagedBy = "terraform"
    Purpose   = "terraform-state"
  }
}

# Enable versioning — keeps full history of state files
# If an apply breaks something, you can restore a previous state version
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption — state files contain secrets (passwords, tokens)
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — state must never be publicly accessible
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
# Prevents concurrent terraform apply runs from corrupting state
# Terraform automatically acquires and releases the lock on every operation
resource "aws_dynamodb_table" "tf_locks" {
  name         = "silverbank-tf-locks"
  billing_mode = "PAY_PER_REQUEST"  # no provisioned capacity needed — pay per use
  hash_key     = "LockID"           # required field name for Terraform locking

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = "silverbank"
    ManagedBy = "terraform"
    Purpose   = "terraform-state-locking"
  }
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.tfstate.bucket
  description = "S3 bucket name to use in backend configuration"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.tf_locks.name
  description = "DynamoDB table name to use in backend configuration"
}
