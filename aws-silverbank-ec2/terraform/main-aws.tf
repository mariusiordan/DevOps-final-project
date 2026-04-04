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

# ------------------------------------------------------------
# EC2 + ASG + ALB
# ------------------------------------------------------------

module "ec2_asg" {
  source = "./modules/ec2-asg-aws"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  alb_sg_id          = module.security.alb_sg_id
  ec2_sg_id          = module.security.ec2_sg_id
  instance_type      = var.instance_type
  asg_min_size       = var.asg_min_size
  asg_max_size       = var.asg_max_size
  asg_active_desired = var.asg_active_desired
  asg_idle_desired   = var.asg_idle_desired
  ecr_frontend_url   = module.ecr.frontend_repository_url
  ecr_backend_url    = module.ecr.backend_repository_url
  rds_endpoint       = module.rds.rds_endpoint
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  jwt_secret         = var.jwt_secret
  jwt_refresh_secret = var.jwt_refresh_secret
  alb_dns_name       = module.ec2_asg.alb_dns_name
  aws_region         = var.aws_region
}

# ------------------------------------------------------------
# Monitoring
# ------------------------------------------------------------

module "monitoring" {
  source = "./modules/monitoring-aws"

  project_name        = var.project_name
  environment         = var.environment
  alb_arn_suffix      = module.ec2_asg.alb_arn_suffix
  blue_tg_arn_suffix  = module.ec2_asg.blue_tg_arn_suffix
  green_tg_arn_suffix = module.ec2_asg.green_tg_arn_suffix
  blue_asg_name       = module.ec2_asg.blue_asg_name
  green_asg_name      = module.ec2_asg.green_asg_name
  rds_instance_id     = module.rds.rds_instance_id
  alarm_email         = var.alarm_email
}

