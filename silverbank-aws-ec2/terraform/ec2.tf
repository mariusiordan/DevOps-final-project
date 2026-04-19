# ============================================================
# ec2.tf
# All EC2 instances + SSH key pair + Elastic IP for edge
# ============================================================

# ============================================================
# SSH KEY PAIR
# ============================================================

resource "aws_key_pair" "silverbank" {
  key_name   = "silverbank-key"
  public_key = var.ssh_public_key

  tags = { Name = "silverbank-key" }
}

# ============================================================
# AMI
# ============================================================

# Latest Ubuntu 24.04 LTS from Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

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
# ELASTIC IP - EDGE
# ============================================================

# Static IP that persists across destroy/apply cycles
# Used by GitHub Actions to check if AWS DR is active
resource "aws_eip" "edge" {
  domain = "vpc"

  tags = { Name = "silverbank-edge-eip" }
}

resource "aws_eip_association" "edge" {
  instance_id   = aws_instance.edge.id
  allocation_id = aws_eip.edge.id
}

# ============================================================
# EC2 INSTANCES
# ============================================================

# Edge Nginx - public subnet, entry point for all traffic
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
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "db-postgresql" }
}

# Monitoring + Staging - private subnet
resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_monitoring
  key_name               = aws_key_pair.silverbank.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.monitoring.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "monitoring-staging" }
}