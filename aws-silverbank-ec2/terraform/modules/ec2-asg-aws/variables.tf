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

variable "ecr_repository_url" {
  description = "ECR repository URL — used in user data to pull images"
  type        = string
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