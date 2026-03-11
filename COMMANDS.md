# ============================================================
# DEVOPS PROJECT - COMMANDS REFERENCE
# ============================================================


# ============================================================
# TERRAFORM
# ============================================================

# First time setup
terraform init                          # download providers
terraform plan                          # preview what will be created
terraform apply -parallelism=3          # create all VMs

# Destroy and recreate everything
terraform destroy -parallelism=3
terraform apply -parallelism=3

# Recreate a single VM (example: blue)
terraform destroy -target='proxmox_virtual_environment_vm.vm["blue"]'
terraform apply -target='proxmox_virtual_environment_vm.vm["blue"]'

# Check what's deployed
terraform state list
terraform output


# ============================================================
# ANSIBLE - FULL SETUP
# ============================================================

cd ansible

# Test connectivity to all VMs
ansible all -m ping

# Configure everything from scratch
ansible-playbook playbooks/site.yml

# Configure specific VM only
ansible-playbook playbooks/site.yml --limit edge
ansible-playbook playbooks/site.yml --limit db
ansible-playbook playbooks/site.yml --limit prod
ansible-playbook playbooks/site.yml --limit prod-vm1-BLUE
ansible-playbook playbooks/site.yml --limit stage-monitoring

# Dry run - see what would change without doing anything
ansible-playbook playbooks/site.yml --check


# ============================================================
# ANSIBLE - DEPLOYMENTS
# ============================================================

# Deploy new version to BLUE and switch traffic
ansible-playbook playbooks/deploy-blue.yml

# Deploy new version to GREEN and switch traffic
ansible-playbook playbooks/deploy-green.yml

# Deploy specific version tag
ansible-playbook playbooks/deploy-green.yml -e "app_tag=v1.2"

# Rollback - switch traffic back to blue
ansible-playbook playbooks/deploy-blue.yml


# ============================================================
# ANSIBLE - VAULT
# ============================================================

# View decrypted secrets
ansible-vault view group_vars/all/vault.yml

# Edit secrets
ansible-vault edit group_vars/all/vault.yml

# Check a specific variable is loaded correctly
ansible all -m debug -a "var=vault_db_user"
ansible all -m debug -a "var=vault_postgres_password"

# Re-encrypt vault with new password
ansible-vault rekey group_vars/all/vault.yml

# Run playbook and ask for vault password manually (if ~/.vault-password missing)
ansible-playbook playbooks/site.yml --ask-vault-pass


# ============================================================
# BLUE/GREEN - MANUAL SWITCH
# ============================================================

ssh devop@192.168.7.50                  # SSH into edge-nginx

sudo /opt/switch-backend.sh blue        # send traffic to BLUE
sudo /opt/switch-backend.sh green       # send traffic to GREEN
sudo /opt/switch-backend.sh             # auto-switch to the other one

cat /etc/nginx/conf.d/upstream.conf     # check which is active


# ============================================================
# TROUBLESHOOTING - ANSIBLE
# ============================================================

# Run with verbose output to see what's happening
ansible-playbook playbooks/site.yml -v      # verbose
ansible-playbook playbooks/site.yml -vv     # more verbose
ansible-playbook playbooks/site.yml -vvv    # full debug

# Test SSH connection manually
ssh devop@192.168.7.50
ssh devop@192.168.7.101
ssh devop@192.168.7.102
ssh devop@192.168.7.60
ssh devop@192.168.7.70

# Check if Ansible can reach all VMs
ansible all -m ping

# Run a single command on all VMs
ansible all -m command -a "uptime"
ansible all -m command -a "docker ps"
ansible prod -m command -a "docker ps"

# Check what variables Ansible sees for a host
ansible prod-vm1-BLUE -m debug -a "var=hostvars[inventory_hostname]"


# ============================================================
# TROUBLESHOOTING - NGINX (edge VM 192.168.7.50)
# ============================================================

ssh devop@192.168.7.50

sudo systemctl status nginx             # check if nginx is running
sudo nginx -t                           # test config for syntax errors
sudo systemctl reload nginx             # reload config without downtime
sudo systemctl restart nginx            # full restart

sudo cat /etc/nginx/conf.d/upstream.conf        # check active backend
sudo cat /etc/nginx/sites-enabled/app.conf      # check proxy config
sudo tail -f /var/log/nginx/access.log          # live traffic logs
sudo tail -f /var/log/nginx/error.log           # live error logs

# Check nginx is forwarding to the right port
curl -v http://localhost                         # from inside edge VM
curl http://10.10.20.11:3000                    # test blue directly from edge
curl http://10.10.20.12:3000                    # test green directly from edge


# ============================================================
# TROUBLESHOOTING - APP (blue 192.168.7.101 / green 192.168.7.102)
# ============================================================

ssh devop@192.168.7.101   # blue
ssh devop@192.168.7.102   # green

docker ps                               # check if container is running
docker ps -a                            # show all containers including stopped
docker logs app                         # view app logs
docker logs app --tail 50               # last 50 lines
docker logs app -f                      # follow live logs

docker inspect app                      # full container details

# Restart app container
cd /opt/app
docker compose down
docker compose up -d

# Pull latest image and restart
docker compose pull
docker compose up -d --pull always

# Force recreate container (useful if env vars changed)
docker compose up -d --force-recreate

# Check .env file
cat /opt/app/.env
cat /opt/app/docker-compose.yml

# Test app responds locally (from inside the VM)
curl http://localhost:3000
curl http://localhost:3000/api/health

# Check app can reach the database
docker exec app curl http://10.10.20.20:5432 2>&1 | head -5


# ============================================================
# TROUBLESHOOTING - POSTGRES (db VM 192.168.7.60)
# ============================================================

ssh devop@192.168.7.60

docker ps                               # check if postgres is running
docker logs postgres                    # view postgres logs
docker logs postgres --tail 50

# Check postgres is ready to accept connections
docker exec postgres pg_isready -U devop_db -d appdb

# Connect to postgres directly
docker exec -it postgres psql -U devop_db -d appdb

# Inside psql:
# \dt              - list tables
# \l               - list databases
# \du              - list users
# \q               - quit
# SELECT * FROM "User" LIMIT 5;   - check data

# Reset user password (if auth fails)
docker exec postgres psql -U devop_db -d appdb -c "ALTER USER devop_db WITH PASSWORD 'newpassword';"

# Check postgres data folder
ls -la /opt/postgres/data

# Restart postgres
cd /opt/postgres
docker compose down
docker compose up -d

# Test connection from blue VM
ssh devop@192.168.7.101
curl http://10.10.20.20:5432            # should return something (not refused)


# ============================================================
# TROUBLESHOOTING - FIREWALL
# ============================================================

# Check firewall rules on any VM
sudo ufw status verbose

# Check if a specific port is open
sudo ufw status | grep 3000
sudo ufw status | grep 5432

# If you locked yourself out of SSH
# Go to Proxmox UI -> VM -> Console -> login directly
sudo ufw allow 22
sudo ufw reload

# Temporarily disable firewall for debugging
sudo ufw disable
# Re-enable after debugging
sudo ufw enable


# ============================================================
# TROUBLESHOOTING - DOCKER
# ============================================================

# Check docker is running
sudo systemctl status docker

# Check all containers across the system
docker ps -a

# Remove stopped containers
docker container prune

# Check disk usage
docker system df

# Free up space (removes unused images, containers, networks)
docker system prune

# Pull a specific image manually
docker pull ghcr.io/mariusiordan/silverbank:latest

# Check if image exists locally
docker images | grep silverbank

# Login to ghcr.io manually on VM
echo "YOUR_TOKEN" | docker login ghcr.io -u mariusiordan --password-stdin


# ============================================================
# TROUBLESHOOTING - GITHUB ACTIONS
# ============================================================

# Trigger workflow without code changes
git commit --allow-empty -m "ci: trigger workflow"
git push origin main

# Check workflow file syntax locally (install act first)
# brew install act
act push --dry-run

# Re-run failed workflow
# GitHub → Actions → failed workflow → Re-run jobs

# Check secrets are set correctly
# GitHub → Settings → Secrets → Actions
# Required: PROXMOX_SSH_KEY, GHCR_TOKEN, VAULT_PASSWORD


# ============================================================
# TROUBLESHOOTING - SSH KEYS
# ============================================================

# Check your SSH key exists
ls -la ~/.ssh/id_ed25519
ls -la ~/.ssh/id_ed25519.pub

# Test SSH connection with verbose output
ssh -v devop@192.168.7.50

# If SSH key rejected - check authorized_keys on VM
ssh devop@192.168.7.50 "cat ~/.ssh/authorized_keys"

# Add your key to a VM manually
ssh-copy-id -i ~/.ssh/id_ed25519.pub devop@192.168.7.50

# Check SSH agent has your key loaded
ssh-add -l
ssh-add ~/.ssh/id_ed25519                # add if missing


# ============================================================
# QUICK HEALTH CHECK - ALL VMs
# ============================================================

# Run from your local machine - checks everything at once
ansible all -m command -a "uptime"
ansible all -m command -a "docker ps --format 'table {{.Names}}\t{{.Status}}'"
ansible edge -m command -a "sudo nginx -t"
ansible db -m command -a "docker exec postgres pg_isready -U devop_db -d appdb"

# Full end-to-end test
curl http://192.168.7.50                        # nginx responds
curl http://192.168.7.50/api/health             # app health check
curl http://192.168.7.101:3000/api/health       # blue direct
curl http://192.168.7.102:3000/api/health       # green direct


# ============================================================
# DISASTER RECOVERY - FULL REBUILD
# ============================================================

# 1. Destroy all VMs
cd proxmox
terraform destroy -parallelism=3

# 2. Recreate all VMs
terraform apply -parallelism=3

# 3. Wait ~60 seconds for VMs to boot

# 4. Configure everything
cd ../ansible
ansible all -m ping                             # verify connectivity first
ansible-playbook playbooks/site.yml             # configure everything

# 5. Verify
curl http://192.168.7.50
ansible all -m command -a "docker ps"