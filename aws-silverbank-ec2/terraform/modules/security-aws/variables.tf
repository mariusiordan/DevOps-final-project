# ============================================================
# modules/security-aws/variables.tf
# Inputs that the security groups module accepts
# ============================================================

variable "vpc_id" {
  description = "ID of the VPC to create security groups in"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC — used to restrict internal traffic"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment for tagging"
  type        = string
}