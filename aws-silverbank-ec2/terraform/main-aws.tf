# ============================================================
# main-aws.tf
# Entry point for SilverBank AWS (EC2 + ASG architecture)
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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

# ------------------------------------------------------------
# VPC
# ------------------------------------------------------------

module "vpc" {
  source = "./modules/vpc-aws"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  project_name         = var.project_name
  environment          = var.environment
}