# ============================================================
# DATA SOURCES
# ============================================================

# Get the latest Ubuntu 24.04 LTS AMI automatically from Canonical
# This avoids hardcoding AMI IDs which change per region and expire
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ============================================================
# VPC AND NETWORKING
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "silverbank-vpc" }
}

# Public subnet - edge nginx lives here (accessible from internet)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "silverbank-public" }
}

# Private subnet - app VMs and DB live here (no direct internet access) 
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = { Name = "silverbank-private" }
}

# Internet Gateway - allows public subnet to reach the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "silverbank-igw" }
}

# Route table for public subnet - sends traffic to internet gateway
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

# ============================================================
# SSH KEY PAIR
# ============================================================

resource "aws_key_pair" "silverbank" {
  key_name   = "silverbank-key"
  public_key = var.ssh_public_key

  tags = { Name = "silverbank-key" }
}

# ============================================================
# SECURITY GROUPS
# ============================================================

# Edge Nginx - accepts HTTP from internet + SSH from your IP only
resource "aws_security_group" "edge" {
  name        = "silverbank-edge"
  description = "Edge nginx - HTTP public, SSH restricted"
  vpc_id      = aws_vpc.main.id

  # HTTP from anywhere (no HTTPS yet - no SSL certificate)
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH only from your home IP - never open SSH to 0.0.0.0/0
  ingress {
    description = "SSH from home"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_home_ip]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "silverbank-edge-sg" }
}

# App VMs (blue + green) - accepts traffic from nginx and SSH from edge only
resource "aws_security_group" "app" {
  name        = "silverbank-app"
  description = "App servers - port 3000 from nginx, SSH from edge"
  vpc_id      = aws_vpc.main.id

  # App port from nginx edge only (not from internet directly)
  ingress {
    description     = "App port from nginx"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.edge.id]
  }

  # SSH from edge VM only (bastion pattern - no direct SSH from internet)
  ingress {
    description     = "SSH from edge (bastion)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.edge.id]
  }

  # Allow all outbound (needed to pull Docker images from ghcr.io)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "silverbank-app-sg" }
}

# Database - accepts PostgreSQL only from app VMs
resource "aws_security_group" "db" {
  name        = "silverbank-db"
  description = "PostgreSQL - port 5432 from app servers only"
  vpc_id      = aws_vpc.main.id

  # PostgreSQL from app VMs only - DB is never exposed to internet
  ingress {
    description     = "PostgreSQL from app servers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # SSH from edge VM only
  ingress {
    description     = "SSH from edge (bastion)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.edge.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "silverbank-db-sg" }
}

# ============================================================
# EC2 INSTANCES
# ============================================================

# Edge Nginx - public subnet, has public IP
resource "aws_instance" "edge" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_edge
  key_name               = aws_key_pair.silverbank.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.edge.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "edge-nginx" }
}

# Prod BLUE - private subnet
resource "aws_instance" "blue" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_app
  key_name               = aws_key_pair.silverbank.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "prod-vm1-BLUE" }
}

# Prod GREEN - private subnet
resource "aws_instance" "green" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_app
  key_name               = aws_key_pair.silverbank.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "prod-vm2-GREEN" }
}

# Database PostgreSQL - private subnet
resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_db
  key_name               = aws_key_pair.silverbank.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.db.id]

  root_block_device {
    volume_size = 30 # more space for DB data
    volume_type = "gp3"
  }

  tags = { Name = "db-postgresql" }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = { Name = "silverbank-nat-eip" }
}

# NAT Gateway - allows private subnet to reach internet (for apt, docker pull)
# Lives in public subnet, routes outbound traffic for private instances
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags = { Name = "silverbank-nat" }
  depends_on = [aws_internet_gateway.main]
}

# Route table for private subnet - sends traffic through NAT Gateway
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