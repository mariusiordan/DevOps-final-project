terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── VPC & NETWORKING ───────────────────────────────
resource "aws_vpc" "silverbank" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "silverbank-vpc" }
}

resource "aws_internet_gateway" "silverbank" {
  vpc_id = aws_vpc.silverbank.id
  tags   = { Name = "silverbank-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.silverbank.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "silverbank-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.silverbank.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.silverbank.id
  }
  tags = { Name = "silverbank-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─── SECURITY GROUPS ────────────────────────────────
resource "aws_security_group" "jenkins" {
  name   = "silverbank-jenkins-sg"
  vpc_id = aws_vpc.silverbank.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "silverbank-jenkins-sg" }
}

resource "aws_security_group" "app" {
  name   = "silverbank-app-sg"
  vpc_id = aws_vpc.silverbank.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "silverbank-app-sg" }
}

# ─── EC2 INSTANCES ──────────────────────────────────
resource "aws_instance" "jenkins" {
  ami                    = "ami-08eb150f611ca277f" # Ubuntu 22.04 eu-north-1
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  key_name               = var.key_name

  tags = { Name = "silverbank-jenkins" }
}

resource "aws_instance" "staging" {
  ami                    = "ami-08eb150f611ca277f"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_name

  tags = { Name = "silverbank-staging" }
}

resource "aws_instance" "prod_blue" {
  ami                    = "ami-08eb150f611ca277f"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_name

  tags = { Name = "silverbank-prod-blue" }
}

resource "aws_instance" "prod_green" {
  ami                    = "ami-08eb150f611ca277f"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_name

  tags = { Name = "silverbank-prod-green" }
}

resource "aws_instance" "nginx" {
  ami                    = "ami-08eb150f611ca277f"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_name

  tags = { Name = "silverbank-nginx" }
}