# ============================================================
# modules/ec2-asg-aws/variables.tf
# ============================================================

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment for tagging"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of public subnets — ALB lives here"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs of private subnets — EC2 instances live here"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "ec2_sg_id" {
  description = "Security group ID for EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in the ASG"
  type        = number
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances the ASG can scale to"
  type        = number
}

variable "asg_active_desired" {
  description = "Desired instances for the active color"
  type        = number
}

variable "asg_idle_desired" {
  description = "Desired instances for the idle color"
  type        = number
}

variable "ecr_frontend_url" {
  description = "ECR frontend repository URL"
  type        = string
}

variable "ecr_backend_url" {
  description = "ECR backend repository URL"
  type        = string
}

variable "jwt_secret" {
  description = "JWT secret for the backend"
  type        = string
  sensitive   = true
}

variable "jwt_refresh_secret" {
  description = "JWT refresh secret for the backend"
  type        = string
  sensitive   = true
}

# variable "alb_dns_name" {
#   description = "ALB DNS name — passed to frontend as NEXT_PUBLIC_API_URL"
#   type        = string
# }

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "rds_endpoint" {
  description = "RDS endpoint — passed to app as DATABASE_URL"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region — used in user data for ECR login"
  type        = string
}

variable "staging_ssh_public_key" {
  description = "SSH public key for ephemeral staging EC2"
  type        = string
}