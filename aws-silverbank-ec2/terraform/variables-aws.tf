# ============================================================
# variables-aws.tf
# All input variables for SilverBank AWS infrastructure
# ============================================================

# ------------------------------------------------------------
# General
# ------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "silverbank"
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
  default     = "production"
}

# ------------------------------------------------------------
# VPC / Network
# ------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to deploy subnets into"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
}

# ------------------------------------------------------------
# EC2 / ASG
# ------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for application servers"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in the ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances the ASG can scale to"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances running at any time"
  type        = number
  default     = 2
}

# ------------------------------------------------------------
# RDS
# ------------------------------------------------------------

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "silverbank"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "silverbank_admin"
}

variable "db_password" {
  description = "Master password for the RDS instance"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# ------------------------------------------------------------
# ECR / App
# ------------------------------------------------------------

variable "ecr_repository_name" {
  description = "Name of the ECR repository for SilverBank app images"
  type        = string
  default     = "silverbank-app"
}