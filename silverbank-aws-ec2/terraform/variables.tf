# ============================================================
# variables.tf
# Toate variabilele proiectului
# ============================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "ssh_public_key" {
  description = "SSH public key pentru EC2 instances"
  type        = string
  sensitive   = true
}

variable "your_home_ip" {
  description = "Please enter your home IP address (format: x.x.x.x/32): "
  type        = string
}

variable "instance_type_edge" {
  description = "EC2 instance type pentru edge-nginx"
  type        = string
  default     = "t3.micro"
}

variable "instance_type_app" {
  description = "EC2 instance type pentru blue si green"
  type        = string
  default     = "t3.small"
}

variable "instance_type_db" {
  description = "EC2 instance type pentru postgresql"
  type        = string
  default     = "t3.small"
}

variable "instance_type_monitoring" {
  description = "EC2 instance type pentru monitoring-staging"
  type        = string
  default     = "t3.small"
}
