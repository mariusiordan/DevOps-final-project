#!/bin/bash
# ============================================================
# user-data.sh
# Runs on EC2 instance first boot — Ubuntu 24.04 LTS
# Installs Docker, pulls SilverBank image from ECR, starts app
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
apt-get install -y docker-ce docker-ce-cli containerd.io

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
  docker login --username AWS --password-stdin ${ecr_repository_url}

# ------------------------------------------------------------
# 3. Pull the latest stable image
# ------------------------------------------------------------
docker pull ${ecr_repository_url}:latest

# ------------------------------------------------------------
# 4. Start the container
# ------------------------------------------------------------
docker run -d \
  --name silverbank-${environment} \
  --restart unless-stopped \
  -p 3000:3000 \
  -e NODE_ENV=production \
  -e ENVIRONMENT=${environment} \
  -e DATABASE_URL="postgresql://${db_username}:${db_password}@${rds_endpoint}/${db_name}" \
  ${ecr_repository_url}:latest