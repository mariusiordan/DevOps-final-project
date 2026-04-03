# ============================================================
# outputs-aws.tf
# Values printed after terraform apply — used by pipelines,
# Ansible, and app configuration
# ============================================================

# ------------------------------------------------------------
# VPC
# ------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB lives here)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (EC2 + RDS live here)"
  value       = module.vpc.private_subnet_ids
}

# ------------------------------------------------------------
# ALB
# ------------------------------------------------------------

output "alb_dns_name" {
  description = "Public DNS name of the ALB — use this to access the app"
  value       = module.ec2_asg.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB — needed for Route53 alias records"
  value       = module.ec2_asg.alb_zone_id
}

# ------------------------------------------------------------
# Blue / Green Target Groups
# ------------------------------------------------------------

output "blue_target_group_arn" {
  description = "ARN of the Blue target group"
  value       = module.ec2_asg.blue_target_group_arn
}

output "green_target_group_arn" {
  description = "ARN of the Green target group"
  value       = module.ec2_asg.green_target_group_arn
}

# ------------------------------------------------------------
# RDS
# ------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint — used in app DATABASE_URL"
  value       = module.rds.rds_endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = module.rds.rds_port
}

# ------------------------------------------------------------
# ECR
# ------------------------------------------------------------

output "ecr_repository_url" {
  description = "ECR repository URL — used in GitHub Actions to push images"
  value       = module.ecr.repository_url
}

# ------------------------------------------------------------
# EC2 / ASG
# ------------------------------------------------------------

output "blue_asg_name" {
  description = "Name of the Blue ASG — used in deployment pipeline"
  value       = module.ec2_asg.blue_asg_name
}

output "green_asg_name" {
  description = "Name of the Green ASG — used in deployment pipeline"
  value       = module.ec2_asg.green_asg_name
}