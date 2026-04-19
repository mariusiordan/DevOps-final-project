# ============================================================
# modules/ecr-aws/variables.tf
# ============================================================

variable "repository_name" {
  description = "Name of the ECR repository"
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