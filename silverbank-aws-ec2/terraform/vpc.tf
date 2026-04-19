# ============================================================
# vpc.tf
# VPC, subnets, internet gateway, NAT gateway, route tables
# ============================================================

# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "silverbank-vpc" }
}

# ============================================================
# SUBNETS
# ============================================================

# Public subnet - edge-nginx lives here (reachable from internet)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "silverbank-public" }
}

# Private subnet - app VMs, DB, monitoring live here
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = { Name = "silverbank-private" }
}

# ============================================================
# INTERNET GATEWAY
# ============================================================

# Allows public subnet to reach the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "silverbank-igw" }
}

# ============================================================
# NAT GATEWAY
# ============================================================

# Static IP for NAT gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "silverbank-nat-eip" }
}

# Allows private subnet instances to reach internet (apt, docker pull)
# Lives in public subnet - routes outbound traffic for private instances
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  depends_on = [aws_internet_gateway.main]

  tags = { Name = "silverbank-nat" }
}

# ============================================================
# ROUTE TABLES
# ============================================================

# Public route table - sends all traffic to internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "silverbank-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table - sends all traffic through NAT gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "silverbank-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}