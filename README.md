# DevOps Final Project - Proxmox + Terraform + Ansible

This is my final DevOps project where I set up a full infrastructure on a Proxmox home server.
The idea is to have a proper blue/green deployment setup with Nginx as a reverse proxy,
PostgreSQL as the database, and a monitoring stack - all provisioned with Terraform and configured with Ansible.

---

## What I Built

```
Proxmox Home Server
├── vm-edge-nginx       192.168.7.50    → reverse proxy, blue/green traffic switch
├── vm-prod-BLUE        192.168.7.101   → production app (Node.js + React in Docker)
├── vm-prod-GREEN       192.168.7.102   → production app (Node.js + React in Docker)
├── vm-db-postgresql    192.168.7.60    → PostgreSQL in Docker
└── vm-monitoring       192.168.7.70    → Prometheus + Grafana + Loki (coming soon)
```

Each VM has two network interfaces:
- `vmbr0` (LAN) → external access, SSH, management
- `vmbr1` (APP network 10.10.20.0/24) → internal communication between app and DB

---

## Tech Stack

- **Proxmox** - hypervisor running on home server
- **Terraform** (bpg/proxmox provider) - provisions all VMs
- **Ansible** - configures VMs after provisioning
- **Docker + docker-compose** - runs all services inside VMs
- **Nginx** - reverse proxy with blue/green switching script
- **PostgreSQL 16** - database running in Docker
- **Prometheus + Grafana + Loki** - monitoring and logging (coming soon)

---

## Step 1 - Preparing the Template VM

I started by creating a clean Ubuntu 24.04 VM in Proxmox (VMID 10000),
installing everything needed, cleaning it up, and converting it to a template.

### Clone existing template and start VM

```bash
# On Proxmox shell
qm clone 9999 10000 --name ubuntu-clean --full 1
qm start 10000
```

### SSH into the VM and install packages

```bash
ssh devop@<vm-ip>

# Update system
sudo apt update && sudo apt upgrade -y

# Install base packages
sudo apt install -y \
    qemu-guest-agent \
    cloud-init \
    curl wget git \
    ca-certificates gnupg \
    lsb-release \
    net-tools htop \
    python3 python3-pip

# Enable qemu-guest-agent (needed for Proxmox + Terraform)
sudo systemctl enable qemu-guest-agent
sudo systemctl start qemu-guest-agent
```

### Install Docker

```bash
# Add Docker GPG key
sudo install -m 0755 -d /usr/share/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
sudo chmod a+r /usr/share/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Enable Docker
sudo systemctl enable docker
sudo systemctl start docker
```

### Create devop user and add to docker group

```bash
sudo adduser devop --gecos "" --disabled-password
sudo passwd devop

# Add to docker group only (no sudo - not needed)
sudo usermod -aG docker devop

# Verify
id devop
# should show: groups=...,docker
```

### Cleanup before making template

```bash
# Remove SSH keys (Terraform will inject them via cloud-init)
sudo rm -f /home/devop/.ssh/authorized_keys

# Clear bash history
history -c
sudo truncate -s 0 /root/.bash_history
truncate -s 0 /home/devop/.bash_history

# Clear logs
sudo truncate -s 0 /var/log/syslog
sudo truncate -s 0 /var/log/auth.log
sudo truncate -s 0 /var/log/cloud-init.log
sudo truncate -s 0 /var/log/cloud-init-output.log
sudo find /var/log -type f -name "*.log" -exec sudo truncate -s 0 {} \;

# Reset machine-id (very important - without this all cloned VMs
# will have the same ID and cause network conflicts)
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

# Clean cloud-init state
sudo cloud-init clean

# Clean apt cache
sudo apt clean
sudo apt autoremove -y

# Zero-fill disk (makes clones smaller and faster)
sudo dd if=/dev/zero of=/tmp/zeros bs=1M || true
sudo rm -f /tmp/zeros
sync

# Shutdown
sudo poweroff
```

### Convert VM to template

```bash
# On Proxmox shell - after VM is fully stopped
qm template 10000
```

---

## Step 2 - Terraform Infrastructure

Terraform provisions all 5 VMs from the template using full clones,
assigns static IPs via cloud-init, and generates the Ansible inventory file automatically.

### Project structure

```
terraform/
├── main.tf                    # VM resources
├── variables.tf               # variable declarations
├── outputs.tf                 # outputs + ansible inventory generation
├── ansible.tf                 # generates ansible/inventory.ini
├── terraform.tfvars           # actual values - NOT in git
└── terraform.tfvars.example   # example values - in git
```

### Setup secrets

I keep secrets out of the project in a separate file:

```bash
# Create secrets file in home directory
touch ~/.tf-secrets
chmod 600 ~/.tf-secrets

# Edit it
vim ~/.tf-secrets
```

```bash
# ~/.tf-secrets
export TF_VAR_proxmox_api_token="root@pam!terraform=xxxx-xxxx"
export TF_VAR_ci_password="your-vm-password"
export TF_VAR_ssh_public_key="ssh-ed25519 AAAA..."
```

```bash
# Add to ~/.zshrc
echo 'source ~/.tf-secrets' >> ~/.zshrc
source ~/.zshrc

# Verify Terraform can see them
env | grep TF_VAR
```

Non-sensitive values go in `terraform.tfvars`:

```hcl
proxmox_endpoint = "https://192.168.7.12:8006"
node_name        = "pve"
template_vmid    = 10000
vm_storage       = "zfs-nvmeT500-vm"
ci_user          = "devop"
lan_gateway      = "192.168.7.1"
```

### VM configuration (main.tf)

All 5 VMs are defined in a single `locals` block and created with `for_each`:

```hcl
locals {
  vms = {
    edge  = { name = "edge-nginx",         vmid = 850, cores = 2, ram_mb = 2048, lan_ip = "192.168.7.50",  app_ip = "10.10.20.10" }
    blue  = { name = "prod-vm1-BLUE",      vmid = 810, cores = 2, ram_mb = 4096, lan_ip = "192.168.7.101", app_ip = "10.10.20.11" }
    green = { name = "prod-vm2-GREEN",     vmid = 811, cores = 2, ram_mb = 4096, lan_ip = "192.168.7.102", app_ip = "10.10.20.12" }
    db    = { name = "db-postgresql",      vmid = 860, cores = 2, ram_mb = 4096, lan_ip = "192.168.7.60",  app_ip = "10.10.20.20" }
    stage = { name = "monitoring-staging", vmid = 800, cores = 2, ram_mb = 4096, lan_ip = "192.168.7.70",  app_ip = "10.10.20.30" }
  }
}
```

### Run Terraform

```bash
cd terraform

terraform init
terraform plan
terraform apply -parallelism=3
```

After apply, Terraform automatically creates `ansible/inventory.ini`.

### Verify all VMs are up

```bash
ssh devop@192.168.7.50    # edge-nginx
ssh devop@192.168.7.101   # prod-blue
ssh devop@192.168.7.102   # prod-green
ssh devop@192.168.7.60    # db
ssh devop@192.168.7.70    # monitoring

# On each VM check cloud-init finished
sudo cloud-init status
# expected: status: done
```

---

## Step 3 - Ansible Configuration

Ansible configures each VM based on its role.
The inventory is auto-generated by Terraform so I don't have to manage it manually.

### How Ansible is structured

```
ansible/
├── ansible.cfg                # Ansible settings (SSH user, key, inventory path)
├── inventory.ini              # auto-generated by Terraform - list of VMs and IPs
├── group_vars/
│   ├── all.yml                # variables available to ALL VMs
│   ├── db.yml                 # variables only for the db VM (postgres credentials)
│   └── prod.yml               # variables only for blue/green (app image, db connection)
├── roles/
│   ├── common/                # runs on every VM - firewall, base packages, timezone
│   ├── nginx/                 # runs on edge VM - install nginx, configs, switch script
│   ├── postgres/              # runs on db VM - start PostgreSQL in Docker
│   ├── app/                   # runs on blue+green - start app container in Docker
│   └── monitoring/            # runs on staging VM - Prometheus + Grafana (coming soon)
└── playbooks/
    ├── site.yml               # configure everything from scratch
    ├── deploy-blue.yml        # deploy new version to blue + switch nginx traffic
    └── deploy-green.yml       # deploy new version to green + switch nginx traffic
```

### What each role does

**common** - runs on ALL VMs
- apt update and install base packages (curl, wget, git, htop)
- setup UFW firewall - deny everything except SSH port 22
- set timezone to UTC

**nginx** - runs on edge VM (192.168.7.50)
- install Nginx
- deploy upstream config pointing to BLUE by default
- deploy reverse proxy config
- deploy blue/green switch script at `/opt/switch-backend.sh`

**postgres** - runs on db VM (192.168.7.60)
- create `/opt/postgres` directory
- deploy docker-compose.yml with PostgreSQL config
- start postgres container - only accessible from APP network (10.10.20.0/24)

**app** - runs on blue and green VMs
- create `/opt/app` directory
- deploy docker-compose.yml and .env file with database connection
- pull and start the app container

### Test connectivity first

```bash
cd ansible
ansible all -m ping
# all VMs should return pong
```

### Run full configuration

```bash
ansible-playbook playbooks/site.yml
```

### Run on specific VMs only

```bash
ansible-playbook playbooks/site.yml --limit edge
ansible-playbook playbooks/site.yml --limit db
ansible-playbook playbooks/site.yml --limit prod
```

### Blue/Green deployment

```bash
# Deploy new version to green, nginx switches traffic automatically
ansible-playbook playbooks/deploy-green.yml -e "app_tag=v1.2"

# Something went wrong? Rollback to blue instantly
ansible-playbook playbooks/deploy-blue.yml
```

### Manual traffic switch on the nginx VM

```bash
ssh devop@192.168.7.50
sudo /opt/switch-backend.sh green   # switch to green
sudo /opt/switch-backend.sh blue    # switch back to blue
sudo /opt/switch-backend.sh         # auto-switch to the other one
```

---

## SSH Config (Quality of Life)

To avoid known_hosts issues when VMs are recreated with Terraform:

```
# ~/.ssh/config
Host 192.168.7.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    User devop
    IdentityFile ~/.ssh/id_ed25519
```

---

## Current Status

| Component         | VM                   | Status           |
|-------------------|----------------------|------------------|
| common (firewall) | all VMs              | ✅ done          |
| nginx             | edge  192.168.7.50   | ✅ done          |
| app container     | blue  192.168.7.101  | ✅ done          |
| app container     | green 192.168.7.102  | ✅ done          |
| PostgreSQL        | db    192.168.7.60   | ✅ done          |
| monitoring        | stage 192.168.7.70   | ⏳ coming soon   |
| Dockerfile        | app                  | ⏳ coming soon   |
| CI/CD pipeline    | GitHub Actions       | ⏳ coming soon   |

---

## What's Next

- Dockerfile for the Node.js + React app
- Push Docker image to GitHub Container Registry (ghcr.io)
- GitHub Actions CI/CD pipeline (build image → push to registry → trigger Ansible deploy)
- SSL certificate with Let's Encrypt on Nginx
- Grafana dashboards for app and infrastructure metrics