variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-2" # London 
}

variable "ssh_public_key" {
  description = "SSH public key to inject into EC2 instances"
  type        = string
  sensitive   = true
}

variable "your_home_ip" {
  description = "Your home IP for SSH access (format: x.x.x.x/32). Find it at https://checkip.amazonaws.com"
  type        = string
}

variable "instance_type_app" {
  description = "EC2 instance type for app servers (blue/green)"
  type        = string
  default     = "t3.small" # 2 vCPU, 2GB RAM - enough for Next.js
}

variable "instance_type_edge" {
  description = "EC2 instance type for nginx edge server"
  type        = string
  default     = "t3.micro" # 2 vCPU, 1GB RAM - enough for nginx
}

variable "instance_type_db" {
  description = "EC2 instance type for PostgreSQL server"
  type        = string
  default     = "t3.small" # 2 vCPU, 2GB RAM - enough for PostgreSQL
}
