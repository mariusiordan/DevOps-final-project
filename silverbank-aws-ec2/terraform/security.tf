# ============================================================
# security.tf
# Security groups for all EC2 instances
# ============================================================

# ============================================================
# EDGE NGINX
# ============================================================

# Accepts HTTP from internet, SSH from your home IP only
resource "aws_security_group" "edge" {
  name        = "silverbank-edge"
  description = "Edge nginx - HTTP public, SSH restricted"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from home only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_home_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "silverbank-edge-sg" }
}

# ============================================================
# APP SERVERS (BLUE + GREEN)
# ============================================================

# Accepts app traffic from edge only, SSH through edge (bastion)
resource "aws_security_group" "app" {
  name        = "silverbank-app"
  description = "App servers - ports 3000/4000 from edge, SSH via bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Frontend port from edge"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.edge.id]
  }

  ingress {
    description     = "Backend API port from edge"
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [aws_security_group.edge.id]
  }

  ingress {
    description     = "SSH via edge bastion"
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

  tags = { Name = "silverbank-app-sg" }
}

# ============================================================
# DATABASE
# ============================================================

# Accepts PostgreSQL from app servers only, SSH via edge bastion
resource "aws_security_group" "db" {
  name        = "silverbank-db"
  description = "PostgreSQL - port 5432 from app servers only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from app servers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "SSH via edge bastion"
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
# MONITORING
# ============================================================

# Accepts Grafana from home IP, node-exporter from VPC, SSH via edge
resource "aws_security_group" "monitoring" {
  name        = "silverbank-monitoring"
  description = "Monitoring - Grafana from home, node-exporter from VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Grafana from home only"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = [var.your_home_ip]
  }

  ingress {
    description = "Prometheus scrape from VPC"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Prometheus internal port from VPC"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description     = "SSH via edge bastion"
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

  tags = { Name = "silverbank-monitoring-sg" }
}