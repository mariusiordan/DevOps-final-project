# ============================================================
# SILVERBANK DEVOPS — COMMANDS REFERENCE
# ============================================================
# Proxmox: 7 VMs | AWS: 4 VMs | 3 GitHub Actions pipelines
# ============================================================


# ============================================================
# TERRAFORM — PROXMOX
# ============================================================

cd terraform-ansible-infrastructure/proxmox-silverbank/terraform

terraform init                              # download providers (first time)
terraform plan                              # preview changes
terraform apply -parallelism=3              # create/update all VMs
terraform destroy -parallelism=3            # destroy all VMs
terraform state list                        # list managed resources
terraform output                            # show VM IPs

# Recreate a single VM (example: blue)
terraform destroy -target='proxmox_virtual_environment_vm.vm["blue"]'
terraform apply   -target='proxmox_virtual_environment_vm.vm["blue"]'


# ============================================================
# TERRAFORM — AWS
# ============================================================

# ⚠️ NAT Gateway costs ~$33/month — always destroy when not using

# Before starting: update your IP (changes every session on hotspot)
curl ifconfig.me
nano aws-silverbank/terraform/terraform.tfvars
# set: your_home_ip = "YOUR_IP/32"

cd terraform-ansible-infrastructure/aws-silverbank/terraform

terraform apply                             # start AWS (~10 min)
terraform destroy                           # stop AWS (saves money)
terraform output                            # show public IP and DNS


# ============================================================
# ANSIBLE — PROXMOX — FULL SETUP
# ============================================================

cd terraform-ansible-infrastructure/proxmox-silverbank/ansible

# Test connectivity to all VMs
ansible all -m ping -i inventory.ini

# Configure everything from scratch
ansible-playbook playbooks/site.yml -i inventory.ini

# Configure specific VMs only
ansible-playbook playbooks/site.yml --limit edge -i inventory.ini
ansible-playbook playbooks/site.yml --limit edge-backup -i inventory.ini
ansible-playbook playbooks/site.yml --limit prod -i inventory.ini
ansible-playbook playbooks/site.yml --limit db -i inventory.ini
ansible-playbook playbooks/site.yml --limit db_replica -i inventory.ini
ansible-playbook playbooks/site.yml --limit monitoring -i inventory.ini

# Dry run — see what would change without doing it
ansible-playbook playbooks/site.yml --check -i inventory.ini


# ============================================================
# ANSIBLE — PROXMOX — DEPLOYMENTS
# ============================================================

cd proxmox-silverbank/ansible

# Auto Blue/Green (used by CI/CD — detects idle env automatically)
ansible-playbook playbooks/deploy-production.yml \
  -e "app_tag=sha-abc123" -i inventory.ini

# Deploy to staging only
ansible-playbook playbooks/deploy-staging.yml \
  -e "app_tag=sha-abc123" -i inventory.ini

# Manual deploy to specific environment
ansible-playbook playbooks/deploy-green.yml -e "app_tag=sha-abc123" -i inventory.ini
ansible-playbook playbooks/deploy-blue.yml  -e "app_tag=sha-abc123" -i inventory.ini

# Manual rollback monitor (10 min watch + auto rollback on failure)
ansible-playbook playbooks/rollback.yml \
  -e "new_env=green previous_env=blue" -i inventory.ini

# Emergency: switch app to DB replica (when primary DB is down)
ansible-playbook playbooks/db-failover.yml -i inventory.ini

# Trigger CI without code change
git commit --allow-empty -m "ci: trigger workflow" && git push origin main


# ============================================================
# ANSIBLE — AWS
# ============================================================

cd terraform-ansible-infrastructure/aws-silverbank/ansible

# Test connectivity
ansible all -i inventory-aws.ini -m ping

# Configure all AWS VMs
ansible-playbook playbooks/site.yml -i inventory-aws.ini

# Fix docker group permission error (happens after fresh VM creation)
ansible prod -i inventory-aws.ini -m meta -a "reset_connection"
ansible db   -i inventory-aws.ini -m meta -a "reset_connection"
ansible-playbook playbooks/site.yml -i inventory-aws.ini


# ============================================================
# ANSIBLE — VAULT
# ============================================================

cd proxmox-silverbank/ansible

ansible-vault view group_vars/all/vault.yml     # view secrets
ansible-vault edit group_vars/all/vault.yml     # edit secrets
ansible-vault rekey group_vars/all/vault.yml    # change vault password

# Debug: check variable is loaded correctly
ansible all -m debug -a "var=vault_db_user" -i inventory.ini

# Run without vault password file (manual entry)
ansible-playbook playbooks/site.yml --ask-vault-pass -i inventory.ini


# ============================================================
# BLUE/GREEN — MANUAL SWITCH
# ============================================================

ssh devop@192.168.7.50                          # SSH to edge-nginx

sudo /opt/switch-backend.sh blue                # send traffic to BLUE
sudo /opt/switch-backend.sh green               # send traffic to GREEN
cat /opt/current-env                            # check who is active
cat /etc/nginx/conf.d/upstream.conf             # check nginx upstream
sudo tail -f /var/log/nginx/switches.log        # switch history

# Check health of each environment directly (bypass nginx)
curl http://10.10.20.11:3000/api/health         # BLUE direct
curl http://10.10.20.12:3000/api/health         # GREEN direct
curl http://192.168.7.50/api/health             # through nginx (active env)


# ============================================================
# DATABASE — PRIMARY (192.168.7.60)
# ============================================================

ssh devop@192.168.7.60

docker ps                                       # check postgres is running
docker logs postgres --tail 50                  # view logs
docker exec postgres pg_isready -U appuser      # check DB is ready

# Connect to postgres
docker exec -it postgres psql -U appuser -d appdb
# inside psql: \dt (tables), \l (databases), \q (quit)

# Manual backup
docker exec postgres pg_dump -U appuser appdb > /opt/backups/manual_$(date +%Y%m%d).sql

# Check sync logs
tail -f /var/log/db-sync.log

# Trigger manual sync to replica
/opt/scripts/db-sync.sh

# Restart postgres
cd /opt/postgres && docker compose down && docker compose up -d


# ============================================================
# DATABASE — REPLICA (192.168.7.61)
# ============================================================

ssh devop@192.168.7.61

docker ps                                       # check replica is running
docker logs postgres --tail 50

# Verify replica has data (should match primary)
docker exec -it postgres psql -U appuser -d appdb \
  -c 'SELECT COUNT(*) FROM "User";'

# If primary DB goes down — switch app to replica:
cd proxmox-silverbank/ansible
ansible-playbook playbooks/db-failover.yml -i inventory.ini


# ============================================================
# SSH — PROXMOX VMs
# ============================================================

ssh devop@192.168.7.50      # edge-nginx (primary)
ssh devop@192.168.7.51      # edge-backup
ssh devop@192.168.7.101     # prod-vm1-BLUE
ssh devop@192.168.7.102     # prod-vm2-GREEN
ssh devop@192.168.7.60      # db-postgresql (primary)
ssh devop@192.168.7.61      # db-replica
ssh devop@192.168.7.70      # monitoring-staging


# ============================================================
# SSH — AWS VMs (via ProxyJump through edge)
# ============================================================

# Get edge public IP
cd aws-silverbank/terraform && terraform output edge_public_ip

# Connect to private VMs via bastion
ssh -J ubuntu@EDGE_PUBLIC_IP ubuntu@PRIVATE_IP

# Or use ~/.ssh/config aliases:
ssh aws-edge
ssh aws-blue
ssh aws-green
ssh aws-db


# ============================================================
# TROUBLESHOOTING — NGINX
# ============================================================

ssh devop@192.168.7.50

sudo systemctl status nginx             # check nginx status
sudo nginx -t                           # test config syntax
sudo systemctl reload nginx             # reload without downtime
sudo systemctl restart nginx            # full restart

sudo tail -f /var/log/nginx/access.log  # live traffic
sudo tail -f /var/log/nginx/error.log   # errors
sudo tail -f /var/log/nginx/switches.log # Blue/Green switch history

# Test backends directly from edge VM
curl http://10.10.20.11:3000/api/health  # test BLUE directly
curl http://10.10.20.12:3000/api/health  # test GREEN directly


# ============================================================
# TROUBLESHOOTING — APP CONTAINERS
# ============================================================

ssh devop@192.168.7.101     # or .102 for green

docker ps                               # check if container is running
docker logs app --tail 50               # last 50 lines
docker logs app -f                      # follow live

# Restart app
cd /opt/app && docker compose down && docker compose up -d

# Pull latest image and restart
docker compose up -d --pull always

# Check environment variables
cat /opt/app/.env
cat /opt/app/docker-compose.yml

# Test locally
curl http://localhost:3000/api/health


# ============================================================
# TROUBLESHOOTING — DOCKER
# ============================================================

sudo systemctl status docker            # check docker daemon
docker ps -a                            # all containers including stopped
docker system df                        # disk usage
docker system prune                     # free up space

# Login to ghcr.io manually on VM
echo "YOUR_TOKEN" | docker login ghcr.io -u mariusiordan --password-stdin

# Pull image manually
docker pull ghcr.io/mariusiordan/silverbank:latest
docker images | grep silverbank


# ============================================================
# TROUBLESHOOTING — FIREWALL
# ============================================================

sudo ufw status verbose                 # check all rules
sudo ufw status | grep 3000             # check specific port
sudo ufw status | grep 5432

# If locked out of SSH — use Proxmox console
sudo ufw allow 22 && sudo ufw reload


# ============================================================
# TROUBLESHOOTING — GITHUB ACTIONS
# ============================================================

# Trigger workflow without code change
git commit --allow-empty -m "ci: trigger workflow" && git push origin main

# Trigger staging pipeline
git commit --allow-empty -m "ci: trigger staging" && git push origin staging

# Required secrets: PROXMOX_SSH_KEY, GHCR_TOKEN, VAULT_PASSWORD
# GitHub → Settings → Secrets → Actions


# ============================================================
# QUICK HEALTH CHECK — ALL VMs
# ============================================================

cd proxmox-silverbank/ansible

# Check all VMs are reachable
ansible all -m ping -i inventory.ini

# Check all containers are running
ansible all -m command \
  -a "docker ps --format 'table {{.Names}}\t{{.Status}}'" -i inventory.ini

# Check nginx config
ansible edge -m command -a "sudo nginx -t" -i inventory.ini

# Check DB is ready
ansible db -m command \
  -a "docker exec postgres pg_isready -U appuser -d appdb" -i inventory.ini

# Check replica has data
ansible db_replica -m command \
  -a "docker exec postgres psql -U appuser -d appdb -c 'SELECT COUNT(*) FROM \"User\";'" \
  -i inventory.ini

# Check sync is working
ansible db -m command -a "tail -3 /var/log/db-sync.log" -i inventory.ini

# Full end-to-end test
curl http://192.168.7.50/api/health         # through nginx (active env)
curl http://192.168.7.101:3000/api/health   # BLUE direct
curl http://192.168.7.102:3000/api/health   # GREEN direct
curl http://192.168.7.70:3000/api/health    # staging direct


# ============================================================
# DISASTER RECOVERY
# ============================================================

# Scenario 1: Blue VM down → switch to Green (5 seconds)
ssh devop@192.168.7.50
sudo /opt/switch-backend.sh green

# Scenario 2: DB primary down → switch to replica (1 minute)
cd proxmox-silverbank/ansible
ansible-playbook playbooks/db-failover.yml -i inventory.ini

# Scenario 3: Full Proxmox rebuild from scratch
cd proxmox-silverbank/terraform
terraform destroy -parallelism=3 && terraform apply -parallelism=3

cd ../ansible
ansible all -m ping -i inventory.ini        # wait for VMs to boot (~60s)
ansible-playbook playbooks/site.yml -i inventory.ini
curl http://192.168.7.50/api/health

# Scenario 4: Start AWS backup environment (15 minutes)
curl ifconfig.me
nano aws-silverbank/terraform/terraform.tfvars   # update your_home_ip

cd aws-silverbank/terraform
terraform apply

cd ../ansible
ansible-playbook playbooks/site.yml -i inventory-aws.ini
curl http://$(terraform output -raw edge_public_dns)/api/health

# Stop AWS when done (saves ~$33/month)
terraform destroy