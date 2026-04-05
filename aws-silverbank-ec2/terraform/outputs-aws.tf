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
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.rds_endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = module.rds.rds_port
}

# ------------------------------------------------------------
# ECR
# ------------------------------------------------------------

output "ecr_frontend_url" {
  description = "ECR frontend repository URL"
  value       = module.ecr.frontend_repository_url
}

output "ecr_backend_url" {
  description = "ECR backend repository URL"
  value       = module.ecr.backend_repository_url
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

# ------------------------------------------------------------
# Staging — ephemeral EC2 for integration tests
# ------------------------------------------------------------

output "staging_sg_id" {
  description = "Security group ID for ephemeral staging EC2"
  value       = module.security.staging_sg_id
}

output "staging_subnet_id" {
  description = "Public subnet ID for ephemeral staging EC2"
  value       = module.vpc.public_subnet_ids[0]
}

output "staging_key_pair_name" {
  description = "SSH key pair name for staging EC2"
  value       = module.ec2_asg.staging_key_pair_name
}