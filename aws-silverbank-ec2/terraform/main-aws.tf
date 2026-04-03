# ============================================================
# main-aws.tf
# Entry point for SilverBank AWS (EC2 + ASG architecture)
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "silverbank-tfstate-mariusiordan"
    key     = "aws-silverbank-ec2/terraform/terraform.tfstate"
    region  = "eu-west-2"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}