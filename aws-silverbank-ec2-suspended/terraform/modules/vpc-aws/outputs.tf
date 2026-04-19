# ============================================================
# modules/vpc-aws/outputs-aws.tf
# Values exposed to the root module and other modules
# ============================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC — used by security groups"
  value       = aws_vpc.main.cidr_block
}