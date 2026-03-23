# ============================================================
# SILVERBANK DEVOPS - COMMANDS REFERENCE
# ============================================================
# This file covers all operational commands for the SilverBank
# infrastructure across Proxmox and AWS environments.
# ============================================================


# ============================================================
# TERRAFORM - PROXMOX
# ============================================================

cd proxmox-silverbank/terraform

# First time setup
terraform init                                  # download providers
terraform plan                                  # preview what will be created
terraform apply -parallelism=3                  # provision all 5 VMs

# Destroy and recreate everything
terraform destroy -parallelism=3
terraform apply -parallelism=3

# Recreate a single VM (example: blue)
terraform destroy -target='proxmox_virtual_environment_vm.vm["blue"]'
terraform apply -target='proxmox_virtual_environment_vm.vm["blue"]'

# Inspect state
terraform state list
terraform output


# ============================================================
# TERRAFORM - AWS
# ============================================================

cd aws-silverbank/terraform

# Provision AWS infrastructure
terraform apply -auto-approve \
  -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)" \
  -var="your_home_ip=$(curl -4 ifconfig.me)/32"

# Destroy AWS infrastructure (always destroy when not in use - NAT Gateway costs ~$33/month)
terraform destroy -auto-approve \
  -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)" \
  -var="your_home_ip=$(curl -4 ifconfig.me)/32"

# Update Security Group only (e.g. home IP changed)
terraform apply -auto-approve \
  -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)" \
  -var="your_home_ip=$(curl -4 ifconfig.me)/32"

# Check outputs (edge IP, private IPs)
terraform output

# Bootstrap S3 state backend (run ONCE only)
cd aws-silverbank/terraform/bootstrap
terraform init
terraform apply


# ============================================================
# TERRAFORM - STATE MANAGEMENT
# ============================================================

# Proxmox state is local
ls proxmox-silverbank/terraform/terraform.tfstate

# AWS state is remote in S3
# Bucket: silverbank-tfstate-mariusiordan
# Key:    aws-silverbank/terraform.tfstate
# Locking: DynamoDB table silverbank-tf-locks

# Re-initialize backend (after backend config changes)
terraform init -reconfigure

# Migrate local state to S3 backend
terraform init -migrate-state


# ============================================================
# ANSIBLE - PROXMOX FULL SETUP
# ============================================================

cd proxmox-silverbank/ansible

# Test connectivity to all VMs
ansible all -m ping -i inventory.ini

# Configure everything from scratch
ansible-playbook playbooks/site.yml -i inventory.ini

# Configure specific VM only
ansible-playbook playbooks/site.yml --limit edge-nginx -i inventory.ini
ansible-playbook playbooks/site.yml --limit db-postgresql -i inventory.ini
ansible-playbook playbooks/site.yml --limit prod -i inventory.ini
ansible-playbook playbooks/site.yml --limit prod-vm1-BLUE -i inventory.ini
ansible-playbook playbooks/site.yml --limit stage-monitoring -i inventory.ini

# Dry run - preview changes without applying
ansible-playbook playbooks/site.yml --check -i inventory.ini


# ============================================================
# ANSIBLE - AWS FULL SETUP
# ============================================================

cd aws-silverbank/ansible

# Test connectivity to all AWS VMs
ansible all -m ping -i inventory-aws.ini

# Configure everything from scratch (after terraform apply)
ansible-playbook playbooks/site.yml -i inventory-aws.ini

# Configure specific VM only
ansible-playbook playbooks/site.yml --limit edge -i inventory-aws.ini
ansible-playbook playbooks/site.yml --limit prod -i inventory-aws.ini
ansible-playbook playbooks/site.yml --limit db -i inventory-aws.ini


# ============================================================
# ANSIBLE - PROXMOX DEPLOYMENTS
# ============================================================

cd proxmox-silverbank/ansible

# Deploy to idle Blue/Green environment
ansible-playbook playbooks/deploy-idle.yml \
  -e "app_tag=v1.0-sha-abc1234" \
  -e "idle_env=blue" \
  -i inventory.ini

# Run smoke tests on idle environment (bypass nginx)
ansible-playbook playbooks/smoke-tests.yml \
  -e "idle_env=blue" \
  -i inventory.ini

# Switch nginx traffic to new environment
ansible-playbook playbooks/switch-traffic.yml \
  -e "idle_env=blue" \
  -i inventory.ini

# Monitor + auto-rollback (10 minutes, every 30 seconds)
ansible-playbook playbooks/rollback.yml \
  -e "app_tag=v1.0-sha-abc1234" \
  -e "new_env=blue" \
  -e "previous_env=green" \
  -i inventory.ini

# Deploy to staging
ansible-playbook playbooks/deploy-staging.yml \
  -e "app_tag=v1.0-sha-abc1234" \
  -i inventory.ini

# Emergency DB failover
ansible-playbook playbooks/db-failover.yml -i inventory.ini


# ============================================================
# ANSIBLE - AWS DEPLOYMENTS
# ============================================================

cd aws-silverbank/ansible

# Update app on AWS DR (pulls :latest from ghcr.io)
ansible-playbook playbooks/deploy-production.yml \
  -i inventory-aws.ini \
  -e "app_tag=latest" \
  --vault-password-file ~/.vault-password


# ============================================================
# ANSIBLE - VAULT
# ============================================================

# View decrypted secrets
ansible-vault view proxmox-silverbank/ansible/group_vars/all/vault.yml
ansible-vault view aws-silverbank/ansible/group_vars/all/vault.yml

# Edit secrets
ansible-vault edit proxmox-silverbank/ansible/group_vars/all/vault.yml

# Re-encrypt vault with new password
ansible-vault rekey proxmox-silverbank/ansible/group_vars/all/vault.yml

# Run playbook and ask for vault password manually (if ~/.vault-password missing)
ansible-playbook playbooks/site.yml --ask-vault-pass -i inventory.ini

# Check a specific variable is loaded correctly
ansible all -m debug -a "var=vault_db_user" -i inventory.ini


# ============================================================
# BLUE/GREEN - MANUAL TRAFFIC CONTROL
# ============================================================

ssh devop@192.168.7.50                          # SSH into edge-nginx

sudo /opt/switch-backend.sh blue                # route traffic to BLUE
sudo /opt/switch-backend.sh green               # route traffic to GREEN
sudo /opt/switch-backend.sh                     # auto-switch to the other one

cat /opt/current-env                            # check which env is active
cat /etc/nginx/conf.d/upstream.conf             # check nginx upstream config
sudo cat /var/log/nginx/switches.log            # view switch history


# ============================================================
# HEALTH CHECKS
# ============================================================

# Production (via nginx)
curl http://192.168.7.50/api/health

# Blue VM direct (bypass nginx)
curl http://192.168.7.101:4000/api/health
curl http://10.10.20.11:4000/api/health         # via APP network from edge

# Green VM direct (bypass nginx)
curl http://192.168.7.102:4000/api/health
curl http://10.10.20.12:4000/api/health         # via APP network from edge

# Staging
curl http://192.168.7.70:4000/api/health

# AWS DR (IP changes on each terraform apply - check terraform output)
curl http://$(cd aws-silverbank/terraform && terraform output -raw edge_elastic_ip)/api/health

# Expected response includes deployment metadata:
# {"status":"ok","database":"connected","environment":"blue","image_tag":"v1.0-sha-abc1234"}


# ============================================================
# MONITORING - ACCESS
# ============================================================

# Grafana dashboard
# URL:      http://192.168.7.70:3001
# Username: admin
# Password: stored in Ansible Vault as vault_grafana_password

# Prometheus targets and metrics
# URL: http://192.168.7.70:9090
# Check all scrape targets: http://192.168.7.70:9090/targets

# All 5 node-exporter targets should show UP:
# 192.168.7.50:9100   edge-nginx
# 192.168.7.60:9100   db-postgresql
# 192.168.7.70:9100   monitoring-staging
# 192.168.7.101:9100  prod-vm1-BLUE
# 192.168.7.102:9100  prod-vm2-GREEN


# ============================================================
# MONITORING - GRAFANA SETUP (after fresh install)
# ============================================================

# Step 1 - Add Prometheus data source
# Grafana → Connections → Data Sources → Add data source → Prometheus
# URL: http://localhost:9090
# Click Save & Test → should say "Successfully queried the Prometheus API"

# Step 2 - Import Node Exporter Full dashboard
# Grafana → Dashboards → New → Import
# Dashboard ID: 1860
# Click Load → select the Prometheus data source → Import

# Step 3 - Select VM to monitor
# Use the "nodename" dropdown at the top of the dashboard
# Shows CPU usage, memory, disk space, network throughput per VM


# ============================================================
# MONITORING - TROUBLESHOOTING
# ============================================================

ssh devop@192.168.7.70

# Check all monitoring containers are running
docker ps | grep -E "prometheus|grafana|loki|node-exporter"

# Check Prometheus logs
docker logs prometheus --tail 30

# Check Grafana logs
docker logs grafana --tail 30

# Restart monitoring stack
cd /opt/monitoring
docker compose down
docker compose up -d

# Test node-exporter reachability from monitoring VM
curl -s http://192.168.7.101:9100/metrics | head -5   # BLUE
curl -s http://192.168.7.102:9100/metrics | head -5   # GREEN
curl -s http://192.168.7.50:9100/metrics  | head -5   # edge
curl -s http://192.168.7.60:9100/metrics  | head -5   # db

# Check node-exporter container on a specific VM
ssh devop@192.168.7.101 "docker ps --filter name=node-exporter"

# Restart node-exporter on ALL VMs at once
ansible all -m command -a "docker restart node-exporter" -b \
  -i proxmox-silverbank/ansible/inventory.ini


# ============================================================
# TROUBLESHOOTING - NGINX (edge VM 192.168.7.50)
# ============================================================

ssh devop@192.168.7.50

sudo systemctl status nginx                     # check if nginx is running
sudo nginx -t                                   # test config for syntax errors
sudo systemctl reload nginx                     # reload config without downtime
sudo systemctl restart nginx                    # full restart

sudo cat /etc/nginx/conf.d/upstream.conf        # check active backend
sudo cat /etc/nginx/sites-enabled/app.conf      # check proxy config
sudo tail -f /var/log/nginx/access.log          # live traffic logs
sudo tail -f /var/log/nginx/error.log           # live error logs

# Test upstream VMs directly from edge
curl http://10.10.20.11:3000                    # test blue frontend from edge
curl http://10.10.20.11:4000/api/health         # test blue backend from edge
curl http://10.10.20.12:3000                    # test green frontend from edge
curl http://10.10.20.12:4000/api/health         # test green backend from edge


# ============================================================
# TROUBLESHOOTING - APP VMs (BLUE/GREEN)
# ============================================================

ssh devop@192.168.7.101                         # BLUE VM
ssh devop@192.168.7.102                         # GREEN VM

docker ps                                       # running containers
docker ps -a                                    # all containers including stopped
docker logs silverbank-frontend --tail 50       # frontend logs
docker logs silverbank-backend --tail 50        # backend logs
docker logs silverbank-frontend -f              # follow live logs

# Restart containers
cd /opt/app
docker compose down --remove-orphans
docker compose up -d

# Pull latest image and restart
docker compose pull
docker compose up -d --pull always --remove-orphans

# Force recreate (useful if env vars changed)
docker compose up -d --force-recreate

# Check .env and docker-compose files
cat /opt/app/.env
cat /opt/app/docker-compose.yml

# Test app responds locally
curl http://localhost:3000
curl http://localhost:4000/api/health

# Free up disk space (run before pulling large images)
docker system prune -f


# ============================================================
# TROUBLESHOOTING - POSTGRES (db VM 192.168.7.60)
# ============================================================

ssh devop@192.168.7.60

docker ps                                       # check if postgres is running
docker logs postgres --tail 50                  # view postgres logs

# Check postgres is ready
docker exec postgres pg_isready -U devop_db -d appdb

# Connect to postgres directly
docker exec -it postgres psql -U devop_db -d appdb

# Inside psql:
# \dt              - list tables
# \l               - list databases
# \du              - list users
# \q               - quit
# SELECT * FROM "User" LIMIT 5;

# Check persistent data directory
ls -la /opt/postgres/data

# Restart postgres
cd /opt/postgres
docker compose down
docker compose up -d


# ============================================================
# TROUBLESHOOTING - AWS VMs
# ============================================================

# Get current edge IP from Terraform state
cd aws-silverbank/terraform
terraform output edge_elastic_ip

# SSH into edge-nginx (direct)
ssh -i ~/.ssh/id_ed25519 ubuntu@$(terraform output -raw edge_elastic_ip)

# SSH into private VMs (via ProxyJump through edge)
ssh -i ~/.ssh/id_ed25519 \
  -o ProxyJump=ubuntu@$(terraform output -raw edge_elastic_ip) \
  ubuntu@$(terraform output -raw blue_private_ip)

ssh -i ~/.ssh/id_ed25519 \
  -o ProxyJump=ubuntu@$(terraform output -raw edge_elastic_ip) \
  ubuntu@$(terraform output -raw db_private_ip)

# Check if home IP has changed (causes SSH timeout to edge)
curl -4 ifconfig.me
# If changed → run terraform apply with new IP to update Security Group


# ============================================================
# TROUBLESHOOTING - FIREWALL
# ============================================================

# Check firewall rules on any VM
sudo ufw status verbose

# Check if a specific port is open
sudo ufw status | grep 3000
sudo ufw status | grep 5432

# If SSH locked out — use Proxmox UI console to login directly
sudo ufw allow 22
sudo ufw reload

# Temporarily disable firewall for debugging
sudo ufw disable
sudo ufw enable                                 # re-enable after debugging


# ============================================================
# TROUBLESHOOTING - GITHUB ACTIONS RUNNER
# ============================================================

# Check runner status
ssh devop@192.168.7.70
sudo systemctl status actions.runner.mariusiordan-SilverBank-App.monitoring-staging.service

# Restart runner if stuck
sudo systemctl restart actions.runner.mariusiordan-SilverBank-App.monitoring-staging.service

# Reinstall runner after infrastructure rebuild
# 1. Go to GitHub → SilverBank-App → Settings → Actions → Runners → New runner
# 2. Select Linux x64 and follow the download + configure instructions
# 3. Install and start as a service:
sudo ./svc.sh install
sudo ./svc.sh start
sudo systemctl status actions.runner.mariusiordan-SilverBank-App.monitoring-staging.service

# Trigger workflow without code changes
git commit --allow-empty -m "ci: trigger pipeline"
git push origin dev

# Required GitHub Secrets (Settings → Secrets → Actions)
# GHCR_TOKEN            - GitHub PAT with write:packages
# PROXMOX_SSH_KEY       - private SSH key
# VAULT_PASSWORD        - Ansible Vault password
# AWS_ACCESS_KEY_ID     - AWS IAM key
# AWS_SECRET_ACCESS_KEY - AWS IAM secret


# ============================================================
# TROUBLESHOOTING - SSH
# ============================================================

# Check your SSH key exists
ls -la ~/.ssh/id_ed25519
ls -la ~/.ssh/id_ed25519.pub

# Test SSH with verbose output
ssh -v devop@192.168.7.50

# Check SSH agent has key loaded
ssh-add -l
ssh-add ~/.ssh/id_ed25519                       # add if missing

# Add key to a VM manually
ssh-copy-id -i ~/.ssh/id_ed25519.pub devop@192.168.7.50


# ============================================================
# QUICK HEALTH CHECK - ALL VMs
# ============================================================

cd proxmox-silverbank/ansible

# Connectivity
ansible all -m ping -i inventory.ini

# Uptime
ansible all -m command -a "uptime" -i inventory.ini

# Nginx config
ansible edge-nginx -m command -a "sudo nginx -t" -i inventory.ini

# DB readiness
ansible db-postgresql -m command \
  -a "docker exec postgres pg_isready -U devop_db -d appdb" \
  -i inventory.ini

# node-exporter running on all VMs
ansible all -m command \
  -a "docker ps --filter name=node-exporter" \
  -i inventory.ini

# End-to-end from local machine
curl http://192.168.7.50/api/health             # via nginx (production)
curl http://192.168.7.101:4000/api/health       # blue direct
curl http://192.168.7.102:4000/api/health       # green direct
curl http://192.168.7.70:4000/api/health        # staging direct

# Monitoring stack
curl -s http://192.168.7.70:9090/-/healthy      # Prometheus health
curl -s http://192.168.7.70:3001/api/health     # Grafana health


# ============================================================
# DISASTER RECOVERY - PROXMOX FULL REBUILD
# ============================================================

# 1. Destroy all VMs
cd proxmox-silverbank/terraform
terraform destroy -parallelism=3

# 2. Recreate all VMs
terraform apply -parallelism=3

# 3. Wait ~60 seconds for VMs to boot

# 4. Configure everything from scratch
cd ../ansible
ansible all -m ping -i inventory.ini            # verify connectivity first
ansible-playbook playbooks/site.yml -i inventory.ini

# 5. Reinstall GitHub Actions runner (lost after rebuild)
# Go to GitHub → SilverBank-App → Settings → Actions → Runners → New runner
# SSH into staging VM and follow the instructions, then:
# sudo ./svc.sh install && sudo ./svc.sh start

# 6. Reconfigure Grafana (if Docker volume was lost)
# Grafana → Connections → Data Sources → Add → Prometheus
# URL: http://localhost:9090 → Save & Test
# Grafana → Dashboards → New → Import → ID: 1860 → Import

# 7. Verify everything
curl http://192.168.7.50/api/health             # application health
curl http://192.168.7.70:9090/targets           # all 5 Prometheus targets UP


# ============================================================
# DISASTER RECOVERY - AWS ACTIVATION
# ============================================================

# 1. Provision AWS infrastructure (~3 minutes)
cd aws-silverbank/terraform
terraform apply -auto-approve \
  -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)" \
  -var="your_home_ip=$(curl -4 ifconfig.me)/32"

# 2. Wait ~60 seconds for EC2 instances to boot

# 3. Configure VMs (~10 minutes)
cd ../ansible
ansible all -m ping -i inventory-aws.ini        # verify connectivity first
ansible-playbook playbooks/site.yml -i inventory-aws.ini

# 4. Verify (~15 minutes total from step 1)
cd ../terraform
curl http://$(terraform output -raw edge_elastic_ip)/api/health

# 5. When done - destroy to stop costs
terraform destroy -auto-approve \
  -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)" \
  -var="your_home_ip=$(curl -4 ifconfig.me)/32"