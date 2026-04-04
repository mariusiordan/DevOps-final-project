#!/bin/bash
# ============================================================
# user-data.sh
# Runs on EC2 instance first boot — Ubuntu 24.04 LTS
# Installs Docker, pulls SilverBank images from ECR, starts app
# ============================================================

set -e

# ------------------------------------------------------------
# 1. Update system and install Docker and AWS CLI
# ------------------------------------------------------------
apt-get update -y
apt-get install -y ca-certificates curl unzip

# Docker official install for Ubuntu
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

# ------------------------------------------------------------
# 2. Log into ECR
# ------------------------------------------------------------
aws ecr get-login-password --region ${aws_region} | \
  docker login --username AWS --password-stdin ${ecr_frontend_url}

# ------------------------------------------------------------
# 3. Pull images
# ------------------------------------------------------------
docker pull ${ecr_frontend_url}:${image_tag}
docker pull ${ecr_backend_url}:${image_tag}

# ------------------------------------------------------------
# 4. Create docker-compose file
# ------------------------------------------------------------
mkdir -p /opt/silverbank

cat > /opt/silverbank/docker-compose.yml << EOF
services:
  frontend:
    image: ${ecr_frontend_url}:${image_tag}
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - ENVIRONMENT=${environment}
      - NEXT_PUBLIC_API_URL=http://${alb_dns_name}
    depends_on:
      - backend

  backend:
    image: ${ecr_backend_url}:${image_tag}
    restart: unless-stopped
    ports:
      - "4000:4000"
    environment:
      - NODE_ENV=production
      - ENVIRONMENT=${environment}
      - DATABASE_URL=postgresql://${db_username}:${db_password}@${rds_endpoint}/${db_name}
      - JWT_SECRET=${jwt_secret}
      - JWT_REFRESH_SECRET=${jwt_refresh_secret}
      - PORT=4000
EOF

# ------------------------------------------------------------
# 5. Start containers
# ------------------------------------------------------------
cd /opt/silverbank
docker compose up -d