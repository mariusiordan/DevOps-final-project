# ============================================================
# AWS SILVERBANK - COMMANDS REFERENCE
# ============================================================


# ============================================================
# TERRAFORM
# ============================================================

cd terraform-ansible-infrastructure/aws-silverbank/terraform

# First time setup
terraform init
terraform plan
terraform apply

# Destroy everything
# ⚠️  NAT Gateway costs ~$33/month even when idle - destroy when not using
terraform destroy

# Recreate a single instance
terraform destroy -target='aws_instance.blue'
terraform apply -target='aws_instance.blue'

# Check outputs (public IP, private IPs)
terraform output


# ============================================================
# ANSIBLE - FULL SETUP
# ============================================================

cd terraform-ansible-infrastructure/aws-silverbank/ansible

# Test connectivity to all VMs
ansible all -i inventory-aws.ini -m ping

# Configure everything from scratch
ansible-playbook playbooks/site.yml -i inventory-aws.ini

# Configure specific VM only
ansible-playbook playbooks/site.yml -i inventory-aws.ini --limit edge
ansible-playbook playbooks/site.yml -i inventory-aws.ini --limit db
ansible-playbook playbooks/site.yml -i inventory-aws.ini --limit prod
ansible-playbook playbooks/site.yml -i inventory-aws.ini --limit prod-vm1-BLUE
ansible-playbook playbooks/site.yml -i inventory-aws.ini --limit prod-vm2-GREEN

# Dry run - see what would change without doing anything
ansible-playbook playbooks/site.yml -i inventory-aws.ini --check


# ============================================================
# ANSIBLE - DEPLOYMENTS
# ============================================================

# Deploy new version to GREEN and switch traffic
ansible-playbook playbooks/deploy-green.yml -i inventory-aws.ini

# Deploy specific version tag
ansible-playbook playbooks/deploy-green.yml -i inventory-aws.ini -e "app_tag=v1.2"

# Rollback - switch traffic back to BLUE
ansible-playbook playbooks/deploy-blue.yml -i inventory-aws.ini


# ============================================================
# ANSIBLE - VAULT
# ============================================================

# View decrypted secrets
ansible-vault view group_vars/all/vault.yml

# Edit secrets
ansible-vault edit group_vars/all/vault.yml

# Check a specific variable is loaded correctly
ansible all -i inventory-aws.ini -m debug -a "var=vault_db_user"

# Run playbook and ask for vault password manually (if ~/.vault-password missing)
ansible-playbook playbooks/site.yml -i inventory-aws.ini --ask-vault-pass


# ============================================================
# SSH - CONNECTING TO VMs
# ============================================================

# Edge nginx - direct SSH (has public IP)
ssh ubuntu@<edge_public_ip>
# get IP with: cd ../terraform && terraform output edge_public_ip

# Blue, Green, DB - via ProxyJump through edge (private subnet, no public IP)
ssh -J ubuntu@<edge_public_ip> ubuntu@10.0.2.204    # blue
ssh -J ubuntu@<edge_public_ip> ubuntu@10.0.2.249    # green
ssh -J ubuntu@<edge_public_ip> ubuntu@10.0.2.60     # db


# ============================================================
# BLUE/GREEN - MANUAL SWITCH
# ============================================================

ssh ubuntu@<edge_public_ip>

sudo /opt/switch-backend.sh blue        # send traffic to BLUE
sudo /opt/switch-backend.sh green       # send traffic to GREEN
sudo /opt/switch-backend.sh             # auto-switch to the other one

cat /etc/nginx/conf.d/upstream.conf     # check which is currently active


# ============================================================
# FILE LOCATIONS - WHERE EVERYTHING LIVES ON VMs
# ============================================================

# ── EDGE NGINX VM ────────────────────────────────────────────
/etc/nginx/conf.d/upstream.conf         # active backend (blue or green IP)
/etc/nginx/sites-enabled/app.conf       # reverse proxy configuration
/opt/switch-backend.sh                  # blue/green switch script
/var/log/nginx/access.log               # incoming request logs
/var/log/nginx/error.log                # nginx error logs

# ── APP VMs (blue / green) ───────────────────────────────────
/opt/app/                               # app root directory
/opt/app/docker-compose.yml            # how the container is started
/opt/app/.env                          # secrets: DB URL, JWT secret, port

# ── DATABASE VM ──────────────────────────────────────────────
/opt/postgres/                          # postgres root directory
/opt/postgres/docker-compose.yml       # how postgres container is started
/opt/postgres/data/                    # PostgreSQL data files
                                        # ⚠️  all database data lives here
                                        # ⚠️  never delete this folder


# ============================================================
# TROUBLESHOOTING - ANSIBLE
# ============================================================

# Run with verbose output
ansible-playbook playbooks/site.yml -i inventory-aws.ini -v      # verbose
ansible-playbook playbooks/site.yml -i inventory-aws.ini -vvv    # full debug

# Check what variables Ansible sees for a host
ansible prod-vm1-BLUE -i inventory-aws.ini -m debug -a "var=hostvars[inventory_hostname]"

# Run a single command on all VMs
ansible all -i inventory-aws.ini -m command -a "uptime"
ansible all -i inventory-aws.ini -m command -a "docker ps"


# ============================================================
# TROUBLESHOOTING - NGINX (edge VM)
# ============================================================

ssh ubuntu@<edge_public_ip>

sudo systemctl status nginx             # check if nginx is running
sudo nginx -t                           # test config for syntax errors
sudo systemctl reload nginx             # reload without downtime
sudo systemctl restart nginx            # full restart

sudo cat /etc/nginx/conf.d/upstream.conf        # check active backend
sudo cat /etc/nginx/sites-enabled/app.conf      # check proxy config
sudo tail -f /var/log/nginx/access.log          # live traffic logs
sudo tail -f /var/log/nginx/error.log           # live error logs

# Test backends directly from edge
curl -v http://localhost                 # nginx itself
curl http://10.0.2.204:3000             # blue directly
curl http://10.0.2.249:3000             # green directly


# ============================================================
# TROUBLESHOOTING - APP (blue / green VMs)
# ============================================================

ssh -J ubuntu@<edge_public_ip> ubuntu@10.0.2.204    # blue
ssh -J ubuntu@<edge_public_ip> ubuntu@10.0.2.249    # green

docker ps                               # check if container is running
docker ps -a                            # show all including stopped
docker logs app                         # view app logs
docker logs app --tail 50               # last 50 lines
docker logs app -f                      # follow live logs

# Check app files
cat /opt/app/.env                       # env vars - DB URL, JWT secret
cat /opt/app/docker-compose.yml         # container config

# Restart app container
cd /opt/app
docker compose down
docker compose up -d

# Pull latest image and restart
docker compose up -d --pull always

# Force recreate (useful if .env changed)
docker compose up -d --force-recreate

# Test app locally from inside VM
curl http://localhost:3000
curl http://localhost:3000/api/health

# Check app can reach the database
docker exec app curl http://10.0.2.60:5432 2>&1 | head -5


# ============================================================
# TROUBLESHOOTING - POSTGRES (db VM)
# ============================================================

ssh -J ubuntu@<edge_public_ip> ubuntu@10.0.2.60

docker ps                               # check if postgres is running
docker logs postgres                    # view postgres logs

# Check postgres is ready
docker exec postgres pg_isready -U devop_db -d appdb

# Connect to postgres directly
docker exec -it postgres psql -U devop_db -d appdb

# Inside psql:
# \dt                              - list tables
# \l                               - list databases
# \du                              - list users
# \q                               - quit
# SELECT * FROM "User" LIMIT 5;   - check data
# SELECT COUNT(*) FROM "User";    - count total users

# Reset user password
docker exec postgres psql -U devop_db -d appdb \
  -c "ALTER USER devop_db WITH PASSWORD 'newpassword';"

# Check data folder size
ls -la /opt/postgres/data/
du -sh /opt/postgres/data/

# Restart postgres
cd /opt/postgres
docker compose down
docker compose up -d

# Backup database
docker exec postgres pg_dump -U devop_db appdb > backup_$(date +%Y%m%d).sql

# Restore database from backup
docker exec -i postgres psql -U devop_db appdb < backup_20260101.sql


# ============================================================
# TROUBLESHOOTING - FIREWALL
# ============================================================

sudo ufw status verbose                 # check all rules
sudo ufw status | grep 3000            # check specific port
sudo ufw status | grep 5432

# If locked out of SSH:
# AWS Console → EC2 → select instance → Connect → EC2 Instance Connect
sudo ufw allow 22
sudo ufw reload

# Temporarily disable for debugging
sudo ufw disable
sudo ufw enable


# ============================================================
# TROUBLESHOOTING - DOCKER
# ============================================================

sudo systemctl status docker            # check docker is running
docker ps -a                            # all containers
docker images | grep silverbank         # check image exists locally
docker system df                        # disk usage
docker system prune                     # free up space

# Pull image manually
docker pull ghcr.io/mariusiordan/silverbank:latest

# Login to ghcr.io manually
echo "YOUR_TOKEN" | docker login ghcr.io -u mariusiordan --password-stdin


# ============================================================
# TROUBLESHOOTING - SSH KEYS
# ============================================================

# Check key exists
ls -la ~/.ssh/id_ed25519

# Test connection verbose
ssh -v ubuntu@<edge_public_ip>

# Check SSH agent
ssh-add -l
ssh-add ~/.ssh/id_ed25519


# ============================================================
# QUICK HEALTH CHECK - ALL VMs
# ============================================================

# From local machine
ansible all -i inventory-aws.ini -m command -a "uptime"
ansible all -i inventory-aws.ini -m command -a \
  "docker ps --format 'table {{.Names}}\t{{.Status}}'"
ansible db -i inventory-aws.ini -m command -a \
  "docker exec postgres pg_isready -U devop_db -d appdb"

# End-to-end
curl http://<edge_public_ip>                    # nginx responds
curl http://<edge_public_ip>/api/health         # app health check

# Blue/green direct (from local machine via SSH)
ssh -J ubuntu@<edge_public_ip> ubuntu@10.0.2.204 \
  "curl http://localhost:3000/api/health"
ssh -J ubuntu@<edge_public_ip> ubuntu@10.0.2.249 \
  "curl http://localhost:3000/api/health"


# ============================================================
# DISASTER RECOVERY - FULL REBUILD
# ============================================================

# 1. Destroy everything
cd terraform-ansible-infrastructure/aws-silverbank/terraform
terraform destroy

# 2. Recreate everything
terraform apply

# 3. Wait ~2 minutes for instances to boot and NAT Gateway to be ready

# 4. Configure all VMs
cd ../ansible
ansible all -i inventory-aws.ini -m ping        # verify connectivity first
ansible-playbook playbooks/site.yml -i inventory-aws.ini

# 5. Verify
curl http://$(cd ../terraform && terraform output -raw edge_public_ip)/api/health
ansible all -i inventory-aws.ini -m command -a "docker ps"