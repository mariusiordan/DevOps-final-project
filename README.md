# SilverBank DevOps Infrastructure

> Full CI/CD ecosystem for a 3-tier banking application — provisioned with Terraform, configured with Ansible, containerized with Docker, and deployed via GitHub Actions with Blue/Green strategy on a Proxmox homelab.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Tech Stack](#tech-stack)
- [Infrastructure (Terraform)](#infrastructure-terraform)
- [Configuration (Ansible)](#configuration-ansible)
- [Application (Docker)](#application-docker)
- [CI/CD Pipelines (GitHub Actions)](#cicd-pipelines-github-actions)
- [Blue/Green Deployment](#bluegreen-deployment)
- [Secrets Management](#secrets-management)
- [Getting Started](#getting-started)
- [Status](#status)

---

## Architecture Overview

```
                          ┌─────────────────────────────────────────────┐
                          │           Proxmox Home Server               │
                          │                                             │
  Internet / LAN          │  ┌──────────────────────────────────────┐   │
  192.168.7.x  ───────────┼─▶│  vm-edge-nginx   192.168.7.50        │   │
                          │  │  Nginx reverse proxy + Blue/Green     │   │
                          │  └──────────┬───────────────┬────────────┘   │
                          │             │               │               │
                          │   ┌─────────▼────┐  ┌──────▼──────┐        │
                          │   │ vm-prod-BLUE │  │ vm-prod-GREEN│        │
                          │   │ 192.168.7.101│  │ 192.168.7.102│        │
                          │   │ SilverBank   │  │ SilverBank   │        │
                          │   │ (Active) ✅  │  │ (Idle)  💤   │        │
                          │   └──────┬───────┘  └──────┬───────┘        │
                          │          │                  │               │
                          │          └────────┬─────────┘               │
   APP Network            │                   │                         │
   10.10.20.x  ───────────┼───────────────────┼─────────────────────    │
                          │          ┌─────────▼────────┐               │
                          │          │  vm-db-postgresql │               │
                          │          │  192.168.7.60     │               │
                          │          │  PostgreSQL 16    │               │
                          │          └──────────────────┘               │
                          │                                             │
                          │  ┌──────────────────────────────────────┐   │
                          │  │  vm-monitoring   192.168.7.70        │   │
                          │  │  Prometheus + Grafana (coming soon)  │   │
                          │  └──────────────────────────────────────┘   │
                          └─────────────────────────────────────────────┘
```

### Network Design

Each VM has **two network interfaces** for security isolation:

| Interface | Network | Purpose |
|---|---|---|
| `vmbr0` | `192.168.7.0/24` (LAN) | External access, SSH, management |
| `vmbr1` | `10.10.20.0/24` (APP) | Internal app ↔ DB communication only |

The database is **not reachable from the LAN** — only from the APP network.

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Hypervisor | Proxmox VE | Host for all VMs |
| Provisioning | Terraform + bpg/proxmox | Create and manage VMs |
| Configuration | Ansible + Ansible Vault | Configure VMs and deploy secrets |
| Containerization | Docker + docker-compose | Run all services in containers |
| Registry | GitHub Container Registry (ghcr.io) | Store and version Docker images |
| Reverse Proxy | Nginx | Route traffic, Blue/Green switching |
| Database | PostgreSQL 16 | Application database |
| App | Next.js 16 + Prisma | SilverBank application |
| CI/CD | GitHub Actions | Automated testing and deployment |
| Monitoring | Prometheus + Grafana | Metrics and dashboards *(coming soon)* |

---

## Infrastructure (Terraform)

Terraform provisions all 5 VMs from a single Ubuntu 24.04 template using `for_each`.
After apply, it automatically generates `ansible/inventory.ini`.

### VM Layout

| VM | VMID | LAN IP | APP IP | Specs | Role |
|---|---|---|---|---|---|
| `edge-nginx` | 850 | 192.168.7.50 | 10.10.20.10 | 2 vCPU / 2GB | Reverse proxy |
| `prod-vm1-BLUE` | 810 | 192.168.7.101 | 10.10.20.11 | 2 vCPU / 4GB | Production (Blue) |
| `prod-vm2-GREEN` | 811 | 192.168.7.102 | 10.10.20.12 | 2 vCPU / 4GB | Production (Green) |
| `db-postgresql` | 860 | 192.168.7.60 | 10.10.20.20 | 2 vCPU / 4GB | Database |
| `monitoring-staging` | 800 | 192.168.7.70 | 10.10.20.30 | 2 vCPU / 4GB | Monitoring / Staging |

### Project Structure

```
terraform/
├── main.tf                   # VM resources (for_each on locals.vms)
├── variables.tf              # variable declarations
├── outputs.tf                # outputs
├── ansible.tf                # generates ansible/inventory.ini automatically
├── terraform.tfvars          # actual values — NOT in git
└── terraform.tfvars.example  # example values — committed to git
```

### Quick Start

```bash
cd terraform
terraform init
terraform validate
terraform fmt
terraform plan
terraform apply -parallelism=3
or
terraform destroy -parallelism=3
```

### Preparing the Base Template

Before running Terraform, create a clean Ubuntu 24.04 template (VMID 10000) in Proxmox:

```bash
# On Proxmox shell
qm clone 9999 10000 --name ubuntu-template --full 1
qm start 10000

# SSH into VM and install packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y qemu-guest-agent cloud-init curl wget git python3

# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker devop

# Clean up before templating
sudo cloud-init clean
sudo truncate -s 0 /etc/machine-id      # CRITICAL - prevents network conflicts on clones
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
sudo poweroff

# Back on Proxmox shell
qm template 10000
```

---

## Configuration (Ansible)

Ansible configures each VM based on its role. Inventory is auto-generated by Terraform.

### Structure

```
ansible/
├── ansible.cfg                    # vault_password_file = ~/.vault-password
├── inventory.ini                  # auto-generated by Terraform
├── group_vars/
│   ├── all/
│   │   ├── main.yml               # global vars (ports, IPs, docker user)
│   │   └── vault.yml              # ENCRYPTED secrets (Ansible Vault)
│   ├── db.yml                     # postgres vars
│   └── prod.yml                   # app image, tag, DB connection
├── roles/
│   ├── common/                    # all VMs: firewall (UFW), packages, timezone
│   ├── nginx/                     # edge: nginx, upstream config, switch script
│   ├── postgres/                  # db: PostgreSQL in Docker
│   ├── app/                       # blue+green: app container, .env file
│   └── monitoring/                # staging: Prometheus + Grafana (coming soon)
└── playbooks/
    ├── site.yml                   # full setup from scratch
    ├── deploy-blue.yml            # deploy to BLUE + switch nginx
    └── deploy-green.yml           # deploy to GREEN + switch nginx
```

### Roles

| Role | Target VMs | What it does |
|---|---|---|
| `common` | All VMs | UFW firewall, base packages, UTC timezone |
| `nginx` | edge-nginx | Install Nginx, upstream config, Blue/Green switch script |
| `postgres` | db-postgresql | PostgreSQL 16 in Docker, accessible only on APP network |
| `app` | blue + green | Pull Docker image from ghcr.io, write `.env`, start container |
| `monitoring` | monitoring-staging | Prometheus + Grafana *(coming soon)* |

### Usage

```bash
cd ansible

# Test connectivity
ansible all -m ping

# Full setup from scratch
ansible-playbook playbooks/site.yml

# Configure specific VM only
ansible-playbook playbooks/site.yml --limit edge
ansible-playbook playbooks/site.yml --limit db
ansible-playbook playbooks/site.yml --limit prod
```

---

## Application (Docker)

SilverBank is a Next.js 16 app with Prisma ORM and PostgreSQL.
The Docker image is built for `linux/amd64` (Proxmox VMs) and pushed to GitHub Container Registry.

### Image

```
ghcr.io/mariusiordan/silverbank:<tag>
```

Tags use short Git SHA: `sha-a1b2c3d`

### Build & Push

```bash
# Build for linux/amd64 (required - Mac is arm64, Proxmox is amd64)
docker buildx build --platform linux/amd64 \
  -t ghcr.io/mariusiordan/silverbank:v1.x \
  --push .
```

### Multi-stage Dockerfile

```
Stage 1 (builder) → install deps, generate Prisma client, build Next.js
Stage 2 (runner)  → copy only production artifacts, run migrations + start server
```

---

## CI/CD Pipelines (GitHub Actions)

Three distinct pipelines matching the project requirements:

### Pipeline 1 — Continuous Integration (`test.yml`)

**Trigger:** Every push and pull request

```
lint ──────────────────────────────────────────────────────► pass/fail
  ├── JWT Tests      ──────────────────────────────────────► pass/fail
  ├── Auth Tests     (login + register) ──────────────────► pass/fail
  └── Account Tests  ──────────────────────────────────────► pass/fail
```

All test jobs run **in parallel** after lint passes. Each test file has its own job so failures are immediately visible.

### Pipeline 2 — Staging + Build (`deploy.yml`)

**Trigger:** Push to `main` branch

```
lint
  ├── JWT Tests     ┐
  ├── Auth Tests    ├──► build Docker image ──► push to ghcr.io ──► deploy to Proxmox
  └── Account Tests ┘

Build is blocked if ANY test fails.
```

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `GHCR_TOKEN` | GitHub PAT with `write:packages` permission |
| `PROXMOX_SSH_KEY` | Private SSH key (`~/.ssh/id_ed25519`) |
| `VAULT_PASSWORD` | Ansible Vault password |

---

## Blue/Green Deployment

Traffic is controlled by Nginx upstream config on the edge VM.
Only one environment is active at a time.

```
┌──────────────────────────────────────────────────────────────┐
│                    Blue/Green Flow                           │
│                                                              │
│  1. Deploy new version to IDLE environment (e.g. GREEN)      │
│  2. Run health check directly on GREEN                       │
│     curl http://10.10.20.12:3000/api/health                  │
│  3. Switch Nginx traffic → GREEN becomes LIVE                │
│  4. Monitor for 5-10 minutes                                 │
│  5a. ✅ Healthy  → BLUE remains as instant rollback          │
│  5b. ❌ Unhealthy → run switch script → back to BLUE         │
└──────────────────────────────────────────────────────────────┘
```

### Traffic Switch

```bash
ssh devop@192.168.7.50

sudo /opt/switch-backend.sh green   # switch to GREEN
sudo /opt/switch-backend.sh blue    # switch to BLUE (rollback)
sudo /opt/switch-backend.sh         # auto-switch to the other one
```

### Ansible Deploy

```bash
# Deploy new version to GREEN and switch traffic
ansible-playbook playbooks/deploy-green.yml -e "app_tag=sha-a1b2c3d"

# Rollback to BLUE
ansible-playbook playbooks/deploy-blue.yml
```

---

## Secrets Management

Two separate secrets systems — one for infrastructure, one for the application.

### Terraform Secrets (`~/.tf-secrets`)

Kept outside the project directory, never committed.

```bash
# ~/.tf-secrets
export TF_VAR_proxmox_api_token="root@pam!terraform=xxxx-xxxx"
export TF_VAR_ci_password="your-vm-password"
export TF_VAR_ssh_public_key="ssh-ed25519 AAAA..."
```

```bash
echo 'source ~/.tf-secrets' >> ~/.zshrc
source ~/.zshrc
```

### Ansible Vault (`group_vars/all/vault.yml`)

All application secrets are encrypted with Ansible Vault.

```bash
# Edit secrets
ansible-vault edit ansible/group_vars/all/vault.yml

# View secrets
ansible-vault view ansible/group_vars/all/vault.yml
```

Vault password stored in `~/.vault-password` (not committed).  
For GitHub Actions, stored as `VAULT_PASSWORD` secret.

---

## Getting Started

### Prerequisites

- Proxmox VE server with an Ubuntu 24.04 template (VMID 10000)
- Terraform >= 1.5
- Ansible >= 2.14
- Docker with buildx
- SSH key pair at `~/.ssh/id_ed25519`

### 1. Clone the repo

```bash
git clone https://github.com/mariusiordan/DevOps-final-project.git
cd DevOps-final-project
```

### 2. Set up Terraform secrets

```bash
cat > ~/.tf-secrets << 'EOF'
export TF_VAR_proxmox_api_token="root@pam!terraform=YOUR_TOKEN"
export TF_VAR_ci_password="YOUR_VM_PASSWORD"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
EOF
chmod 600 ~/.tf-secrets
source ~/.tf-secrets
```

### 3. Provision VMs

```bash
cd terraform
terraform init
terraform apply -parallelism=3
```

### 4. Set up Ansible Vault password

```bash
echo "your-vault-password" > ~/.vault-password
chmod 600 ~/.vault-password
```

### 5. Configure all VMs

```bash
cd ansible
ansible all -m ping         # verify connectivity
ansible-playbook playbooks/site.yml
```

### 6. Verify

```bash
curl http://192.168.7.50            # app via nginx
curl http://192.168.7.50/api/health # health check
```

### SSH Config (optional but recommended)

Avoids known_hosts issues when VMs are recreated with Terraform:

```
# ~/.ssh/config
Host 192.168.7.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    User devop
    IdentityFile ~/.ssh/id_ed25519
```

---

## Status

| Component | VM | IP | Status |
|---|---|---|---|
| Terraform provisioning | all VMs | — | ✅ Done |
| Common (firewall + packages) | all VMs | — | ✅ Done |
| Nginx + Blue/Green switch | edge-nginx | 192.168.7.50 | ✅ Done |
| App container (Blue) | prod-vm1-BLUE | 192.168.7.101 | ✅ Done |
| App container (Green) | prod-vm2-GREEN | 192.168.7.102 | ✅ Done |
| PostgreSQL 16 | db-postgresql | 192.168.7.60 | ✅ Done |
| GitHub Actions — CI tests | — | — | ✅ Done |
| GitHub Actions — Build + Push | — | — | ✅ Done |
| GitHub Actions — Deploy | — | — | ✅ Done |
| Manual approval gate (prod) | — | — | 🔲 Planned |
| Smoke tests before switch | — | — | 🔲 Planned |
| Rollback after 10 min | — | — | 🔲 Planned |
| SSL / Let's Encrypt | edge-nginx | 192.168.7.50 | 🔲 Planned |
| Prometheus + Grafana | monitoring-staging | 192.168.7.70 | 🔲 Planned |

---

## Repo Structure

```
DevOps-final-project/
├── terraform/                 # VM provisioning
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── ansible/                   # VM configuration and deployments
│   ├── ansible.cfg
│   ├── inventory.ini          # auto-generated by Terraform
│   ├── group_vars/
│   ├── roles/
│   └── playbooks/
├── docs/
│   └── templates/             # nginx configs, switch script templates
├── COMMANDS.md                # full command reference and troubleshooting
├── PROJECT-STATUS.md          # requirements checklist vs implementation
└── README.md
```

---

*SilverBank app repository: [mariusiordan/SilverBank-App](https://github.com/mariusiordan/SilverBank-App)*