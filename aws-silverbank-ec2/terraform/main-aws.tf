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

# ------------------------------------------------------------
# Security Groups
# ------------------------------------------------------------

module "security" {
  source = "./modules/security-aws"

  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr_block
  project_name = var.project_name
  environment  = var.environment
}

# ------------------------------------------------------------
# ECR
# ------------------------------------------------------------

module "ecr" {
  source = "./modules/ecr-aws"

  repository_name = var.ecr_repository_name
  project_name    = var.project_name
  environment     = var.environment
}

# ------------------------------------------------------------
# RDS
# ------------------------------------------------------------

module "rds" {
  source = "./modules/rds-aws"

  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security.rds_sg_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  db_instance_class  = var.db_instance_class
}