# ============================================================
# terraform-aws.tfvars
# Actual values for SilverBank AWS infrastructure
# !! THIS FILE IS GITIGNORED — never commit it !!
# ============================================================

# ------------------------------------------------------------
# General
# ------------------------------------------------------------
aws_region             = "eu-west-2"
project_name           = "silverbank"
environment            = "production"
staging_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMHY/tJMan8BJ2CltNqJNf4EJun6gS/GJqFsggcJgpMq silverbank-staging"

# ------------------------------------------------------------
# VPC / Network
# ------------------------------------------------------------
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
availability_zones   = ["eu-west-2a", "eu-west-2b"]

# ------------------------------------------------------------
# EC2 / ASG
# ------------------------------------------------------------
instance_type = "t3.micro"
# terraform-aws.tfvars
asg_min_size       = 1
asg_max_size       = 3
asg_active_desired = 2
asg_idle_desired   = 1

# ------------------------------------------------------------
# RDS
# ------------------------------------------------------------
db_name           = "silverbank"
db_username       = "silverbank_admin"
db_password       = "EconomicViilor#2001!"
db_instance_class = "db.t3.micro"

# ------------------------------------------------------------
# ECR / App
# ------------------------------------------------------------
ecr_repository_name = "silverbank-app"

alarm_email = "dopyno@yahoo.com"

jwt_secret         = "your-strong-jwt-secret-here"
jwt_refresh_secret = "your-strong-jwt-refresh-secret-here"