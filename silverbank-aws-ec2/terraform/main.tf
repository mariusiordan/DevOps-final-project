# ============================================================
# main.tf
# Entry point - provider, backend, terraform block
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "silverbank-tfstate-mariusiordan"
    key            = "silverbank-aws/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "silverbank-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "SilverBank"
      ManagedBy = "Terraform"
    }
  }
}