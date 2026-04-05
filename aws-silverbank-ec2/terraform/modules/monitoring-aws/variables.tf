# ============================================================
# modules/monitoring-aws/variables.tf
# ============================================================

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment for tagging"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix — used in CloudWatch metric dimensions"
  type        = string
}

variable "blue_tg_arn_suffix" {
  description = "Blue target group ARN suffix — used in CloudWatch metrics"
  type        = string
}

variable "green_tg_arn_suffix" {
  description = "Green target group ARN suffix — used in CloudWatch metrics"
  type        = string
}

variable "blue_asg_name" {
  description = "Name of the Blue ASG — used in CloudWatch metrics"
  type        = string
}

variable "green_asg_name" {
  description = "Name of the Green ASG — used in CloudWatch metrics"
  type        = string
}

variable "rds_instance_id" {
  description = "RDS instance identifier — used in CloudWatch metrics"
  type        = string
}

variable "alarm_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
}

variable "blue_scale_up_policy_arn" {
  description = "Blue ASG scale up policy ARN"
  type        = string
}

variable "blue_scale_down_policy_arn" {
  description = "Blue ASG scale down policy ARN"
  type        = string
}

variable "green_scale_up_policy_arn" {
  description = "Green ASG scale up policy ARN"
  type        = string
}

variable "green_scale_down_policy_arn" {
  description = "Green ASG scale down policy ARN"
  type        = string
}