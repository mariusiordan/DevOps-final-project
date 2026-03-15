# SilverBank DevOps Infrastructure

> Full CI/CD ecosystem for a 3-tier banking application — provisioned with Terraform, configured with Ansible, containerized with Docker, and deployed via GitHub Actions with Blue/Green strategy on a Proxmox homelab. AWS used as backup environment.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Tech Stack](#tech-stack)
- [Infrastructure (Terraform)](#infrastructure-terraform)
- [Configuration (Ansible)](#configuration-ansible)
- [Application (Docker)](#application-docker)
- [CI/CD Pipelines (GitHub Actions)](#cicd-pipelines-github-actions)
- [Blue/Green Deployment](#bluegreen-deployment)
- [Database Replica & Sync](#database-replica--sync)
- [AWS Backup Environment](#aws-backup-environment)
- [Secrets Management](#secrets-management)
- [Getting Started](#getting-started)
- [Disaster Recovery](#disaster-recovery)
- [Status](#status)

---

## Architecture Overview

```
                    ┌──────────────────────────────────────────────────────────┐
                    │                  Proxmox Home Server                    │
                    │                                                          │
Internet / LAN      │  ┌──────────────────┐      ┌──────────────────┐         │
192.168.7.x ────────┼─▶│   edge-nginx     │      │   edge-backup    │         │
                    │  │   192.168.7.50   │      │   192.168.7.51   │         │
                    │  │   Primary proxy  │      │   Backup proxy   │         │
                    │  └────────┬─────────┘      └──────────────────┘         │
                    │           │                                              │
                    │  ┌────────▼──────┐     ┌────────────────┐               │
                    │  │ prod-vm1-BLUE │     │ prod-vm2-GREEN │               │
                    │  │ 192.168.7.101 │     │ 192.168.7.102  │               │
                    │  │   Active ✅   │     │    Idle 💤     │               │
                    │  └──────┬────────┘     └───────┬────────┘               │
                    │         └──────────┬────────────┘                        │
APP Network         │                   │                                      │
10.10.20.x ─────────┼───────────────────┼──────────────────────────────────── │
                    │         ┌──────────▼──────────┐                         │
                    │         │    db-postgresql     │                         │
                    │         │    192.168.7.60      │◄── sync every 30min    │
                    │         │    PostgreSQL 16     │                         │
                    │         └─────────────────────-┘                        │
                    │                   │                                      │
                    │         ┌─────────▼──────────┐                          │
                    │         │    db-replica       │                          │
                    │         │    192.168.7.61     │                          │
                    │         │    PostgreSQL 16    │                          │
                    │         └────────────────────┘                          │
                    │                                                          │
                    │  ┌───────────────────────────────────────────────────┐  │
                    │  │   monitoring-staging   192.168.7.70               │  │
                    │  │   Staging environment + Prometheus/Grafana        │  │
                    │  └───────────────────────────────────────────────────┘  │
                    └──────────────────────────────────────────────────────────┘
```

### Network Design

Each VM has **two network interfaces** for security isolation:

| Interface | Network | Purpose |
|---|---|---|
| `vmbr0` | `192.168.7.0/24` (LAN) | External access, SSH, management |
| `vmbr1` | `10.10.20.0/24` (APP) | Internal app ↔ DB communication only |

The database is **not reachable from LAN** — only from the APP network.

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
| Backup Env | AWS EC2 + VPC | Full infrastructure backup |
| Monitoring | Prometheus + Grafana | Metrics *(coming soon)* |

---

## Infrastructure (Terraform)

Terraform provisions all 7 VMs from a single Ubuntu 24.04 template using `for_each`.
After apply, it automatically generates `ansible/inventory.ini`.

### VM Layout

| VM | VMID | LAN IP | APP IP | Specs | Role |
|---|---|---|---|---|---|
| `edge-nginx` | 850 | 192.168.7.50 | 10.10.20.10 | 2 vCPU / 2GB | Primary reverse proxy |
| `edge-backup` | 851 | 192.168.7.51 | 10.10.20.51 | 2 vCPU / 2GB | Backup reverse proxy |
| `prod-vm1-BLUE` | 810 | 192.168.7.101 | 10.10.20.11 | 2 vCPU / 4GB | Production (Blue) |
| `prod-vm2-GREEN` | 811 | 192.168.7.102 | 10.10.20.12 | 2 vCPU / 4GB | Production (Green) |
| `db-postgresql` | 860 | 192.168.7.60 | 10.10.20.20 | 2 vCPU / 4GB | Primary database |
| `db-replica` | 861 | 192.168.7.61 | 10.10.20.21 | 2 vCPU / 4GB | Database replica (standby) |
| `monitoring-staging` | 800 | 192.168.7.70 | 10.10.20.30 | 2 vCPU / 4GB | Staging + Monitoring |

### Project Structure

```
proxmox-silverbank/
├── main.tf                   # VM resources (for_each on locals.vms)
├── variables.tf              # variable declarations
├── outputs.tf                # outputs + inventory generation
├── ansible.tf                # auto-generates ansible/inventory.ini
├── terraform.tfvars          # actual values — NOT in git
└── terraform.tfvars.example  # example values — safe to commit
```

### Quick Start

```bash
cd proxmox-silverbank/terraform
terraform init
terraform plan
terraform apply -parallelism=3
terraform destroy -parallelism=3
```

### Preparing the Base Template

```bash
# On Proxmox shell — create Ubuntu 24.04 template (VMID 9999)
qm clone 9999 10000 --name ubuntu-template --full 1
qm start 10000

# SSH into VM
sudo apt update && sudo apt upgrade -y
sudo apt install -y qemu-guest-agent cloud-init curl wget git python3
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker devop

# Clean before templating — CRITICAL to prevent network conflicts on clones
sudo cloud-init clean
sudo truncate -s 0 /etc/machine-id
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
proxmox-silverbank/ansible/
├── ansible.cfg                       # vault_password_file = ~/.vault-password
├── inventory.ini                     # auto-generated by Terraform
├── group_vars/
│   ├── all/
│   │   ├── main.yml                  # global vars (IPs, ports, docker user)
│   │   └── vault.yml                 # ENCRYPTED secrets (Ansible Vault)
│   ├── prod.yml                      # app image, tag, DB connection for blue+green
│   ├── db.yml                        # postgres vars for primary DB
│   ├── db_replica.yml                # postgres vars for replica (IP: 10.10.20.21)
│   └── monitoring.yml                # app vars for staging VM
├── roles/
│   ├── common/                       # all VMs: Docker, UFW, packages, timezone
│   ├── nginx/                        # edge: nginx + upstream config + switch script
│   ├── postgres/                     # db: PostgreSQL + DB sync script + cron
│   ├── app/                          # blue+green+staging: app container + .env
│   └── monitoring/                   # staging: Prometheus + Grafana (coming soon)
└── playbooks/
    ├── site.yml                      # full setup from scratch
    ├── deploy-blue.yml               # manual deploy to BLUE + switch nginx
    ├── deploy-green.yml              # manual deploy to GREEN + switch nginx
    ├── deploy-staging.yml            # deploy to staging VM + health check
    ├── deploy-production.yml         # auto Blue/Green + smoke tests + switch
    ├── rollback.yml                  # monitor 10min + auto rollback if unhealthy
    └── db-failover.yml               # emergency: switch app to DB replica
```

### Roles

| Role | Target VMs | What it does |
|---|---|---|
| `common` | All VMs | Docker install, UFW firewall, packages, UTC timezone, reset_connection |
| `nginx` | edge-nginx, edge-backup | Nginx, upstream config, Blue/Green switch script |
| `postgres` | db-postgresql, db-replica | PostgreSQL 16 in Docker, DB sync cron job (primary only) |
| `app` | blue, green, staging | Pull Docker image from ghcr.io, write `.env`, start container |
| `monitoring` | monitoring-staging | Prometheus + Grafana *(coming soon)* |

### Usage

```bash
cd proxmox-silverbank/ansible

# Test connectivity
ansible all -m ping -i inventory.ini

# Full setup from scratch
ansible-playbook playbooks/site.yml -i inventory.ini

# Configure specific VMs only
ansible-playbook playbooks/site.yml --limit edge -i inventory.ini
ansible-playbook playbooks/site.yml --limit prod -i inventory.ini
ansible-playbook playbooks/site.yml --limit db -i inventory.ini
ansible-playbook playbooks/site.yml --limit db_replica -i inventory.ini
ansible-playbook playbooks/site.yml --limit monitoring -i inventory.ini
```

---

## Application (Docker)

SilverBank is a Next.js 16 app with Prisma ORM and PostgreSQL.
The Docker image is built for `linux/amd64` (Proxmox VMs) and pushed to GitHub Container Registry.

### Image

```
ghcr.io/mariusiordan/silverbank:<tag>
```

Tags use short Git SHA: `sha-a1b2c3d`. Staging builds also push `staging` tag.

### Build & Push

```bash
# Build for linux/amd64 (required - Mac is arm64, Proxmox is amd64)
docker buildx build --platform linux/amd64 \
  -t ghcr.io/mariusiordan/silverbank:v1.x \
  --push ./silver-bank
```

### Multi-stage Dockerfile

```
Stage 1 (builder) → npm ci, prisma generate, npm run build
Stage 2 (runner)  → copy production artifacts, prisma migrate deploy, node server.js
```

---

## CI/CD Pipelines (GitHub Actions)

Three distinct pipelines matching the project requirements.

### Branch Strategy

| Branch | Purpose | Workflow triggered |
|---|---|---|
| `dev` | Daily development | `test.yml` — lint + tests on every push |
| `staging` | Pre-production testing | `staging.yml` — build + deploy staging + health check |
| `main` | Production | `deploy.yml` — build + manual approval + Blue/Green |

### Pipeline 1 — Continuous Integration (`test.yml`)

**Trigger:** Every push and pull request to any branch

```
lint
  ├── JWT Tests      ──► pass/fail
  ├── Auth Tests     ──► pass/fail  (login + register)
  └── Account Tests  ──► pass/fail

All 3 tests run IN PARALLEL after lint passes.
If any test fails → PR comment added + merge blocked.
```

### Pipeline 2 — Staging Deployment (`staging.yml`)

**Trigger:** Push to `staging` branch

```
lint
  ├── JWT Tests     ┐
  ├── Auth Tests    ├──► build Docker image ──► push to ghcr.io ──► deploy to staging VM ──► health check
  └── Account Tests ┘       (tag: sha-xxx + staging)
```

### Pipeline 3 — Production Deployment (`deploy.yml`)

**Trigger:** Push to `main` branch → **Manual Approval required**

```
lint
  ├── JWT Tests     ┐
  ├── Auth Tests    ├──► build Docker image ──► ⏳ Manual Approval
  └── Account Tests ┘       (tag: sha-xxx)            │
                                                       ▼
                                          detect idle environment
                                                       │
                                          deploy to idle env
                                                       │
                                          smoke tests on idle
                                                       │
                                          switch nginx traffic
                                                       │
                                          monitor 10 minutes
                                          ├── healthy → ✅ done
                                          └── 3 failures → auto rollback
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
Only one environment is active at a time — the other is on standby for instant rollback.

```
┌─────────────────────────────────────────────────────────────────┐
│                       Blue/Green Flow                           │
│                                                                 │
│  1. Read /opt/current-env on edge → find which is active        │
│  2. Calculate idle environment (opposite of active)             │
│  3. Deploy new Docker image to IDLE environment                 │
│  4. Smoke test directly on IDLE (bypassing nginx)               │
│     curl http://10.10.20.11:3000/api/health   (if idle=blue)    │
│  5. Switch nginx traffic → IDLE becomes LIVE                    │
│  6. Monitor for 10 minutes (check every 30 seconds)             │
│     ✅ healthy → deployment complete, old env stays as fallback  │
│     ❌ 3 consecutive failures → auto rollback to previous env    │
└─────────────────────────────────────────────────────────────────┘
```

### Manual Traffic Switch

```bash
ssh devop@192.168.7.50
sudo /opt/switch-backend.sh green    # switch to GREEN
sudo /opt/switch-backend.sh blue     # switch to BLUE (rollback)
cat /opt/current-env                 # check who is currently active
```

### Ansible Deployments

```bash
cd proxmox-silverbank/ansible

# Auto Blue/Green — used by CI/CD (detects idle automatically)
ansible-playbook playbooks/deploy-production.yml -e "app_tag=sha-abc123" -i inventory.ini

# Manual deploy to specific environment
ansible-playbook playbooks/deploy-green.yml -e "app_tag=sha-abc123" -i inventory.ini
ansible-playbook playbooks/deploy-blue.yml  -e "app_tag=sha-abc123" -i inventory.ini
```

---

## Database Replica & Sync

To protect against database failure, a replica VM automatically syncs from the primary every 30 minutes via cron.

```
db-postgresql (10.10.20.20) — PRIMARY
        │
        │  cron every 30 minutes:
        │  1. pg_dump from primary Docker container
        │  2. scp dump file to replica VM
        │  3. psql restore on replica Docker container
        │  4. cleanup temp files
        ▼
db-replica (10.10.20.21) — STANDBY
        max 30 minutes behind primary
        ready to serve if primary fails
```

### Failover — if primary DB goes down

```bash
cd proxmox-silverbank/ansible

# Automatically switches all app VMs to use db-replica
ansible-playbook playbooks/db-failover.yml -i inventory.ini
```

### Monitor sync

```bash
ssh devop@192.168.7.60
tail -f /var/log/db-sync.log    # see sync history and any errors
```

---

## AWS Backup Environment

Full duplicate infrastructure on AWS (eu-west-2, London) for disaster recovery.
Start when Proxmox is unavailable or for demo purposes.

> ⚠️ **Cost warning:** NAT Gateway costs ~$33/month. Always run `terraform destroy` when done.

### AWS VM Layout

| VM | Subnet | Role |
|---|---|---|
| `edge-nginx` | Public (has public IP) | Reverse proxy + SSH bastion |
| `prod-vm1-BLUE` | Private | Production Blue |
| `prod-vm2-GREEN` | Private | Production Green |
| `db-postgresql` | Private | Database |

Private VMs are accessible only via ProxyJump through edge (bastion pattern).

### Start AWS Environment

```bash
# Step 1 — update your IP (required every session on hotspot)
curl ifconfig.me
nano aws-silverbank/terraform/terraform.tfvars
# your_home_ip = "YOUR_IP/32"

# Step 2 — provision
cd aws-silverbank/terraform
terraform apply

# Step 3 — configure
cd ../ansible
ansible-playbook playbooks/site.yml -i inventory-aws.ini

# Step 4 — verify
curl http://$(terraform output -raw edge_public_dns)/api/health
```

### Stop AWS Environment

```bash
cd aws-silverbank/terraform
terraform destroy
```

---

## Secrets Management

### Terraform Secrets (`~/.tf-secrets`)

Kept outside the project directory, never committed to git.

```bash
export TF_VAR_proxmox_api_token="root@pam!terraform=xxxx-xxxx"
export TF_VAR_ci_password="your-vm-password"
export TF_VAR_ssh_public_key="ssh-ed25519 AAAA..."
```

```bash
echo 'source ~/.tf-secrets' >> ~/.zshrc && source ~/.zshrc
```

### Ansible Vault (`group_vars/all/vault.yml`)

All application secrets are encrypted at rest with Ansible Vault.

```bash
ansible-vault edit proxmox-silverbank/ansible/group_vars/all/vault.yml
ansible-vault view proxmox-silverbank/ansible/group_vars/all/vault.yml
```

Vault password stored in `~/.vault-password` (never committed).
For GitHub Actions, stored as `VAULT_PASSWORD` secret.

---

## Getting Started

### Prerequisites

- Proxmox VE with Ubuntu 24.04 template (VMID 9999)
- Terraform >= 1.5
- Ansible >= 2.14
- Docker with buildx
- SSH key pair at `~/.ssh/id_ed25519`

### 1. Clone the repos

```bash
git clone https://github.com/mariusiordan/DevOps-final-project.git
git clone https://github.com/mariusiordan/SilverBank-App.git
```

### 2. Set up Terraform secrets

```bash
cat > ~/.tf-secrets << 'EOF'
export TF_VAR_proxmox_api_token="root@pam!terraform=YOUR_TOKEN"
export TF_VAR_ci_password="YOUR_VM_PASSWORD"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
EOF
chmod 600 ~/.tf-secrets && source ~/.tf-secrets
```

### 3. Provision VMs

```bash
cd terraform-ansible-infrastructure/proxmox-silverbank/terraform
terraform init && terraform apply -parallelism=3
```

### 4. Set up Ansible Vault password

```bash
echo "your-vault-password" > ~/.vault-password
chmod 600 ~/.vault-password
```

### 5. Configure all VMs

```bash
cd ../ansible
ansible all -m ping -i inventory.ini
ansible-playbook playbooks/site.yml -i inventory.ini
```

### 6. Verify

```bash
curl http://192.168.7.50/api/health    # should return {"status":"ok","database":"connected"}
```

### SSH Config (recommended)

```
# ~/.ssh/config
Host 192.168.7.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    User devop
    IdentityFile ~/.ssh/id_ed25519
```

---

## Disaster Recovery

| Scenario | Solution | Recovery Time |
|---|---|---|
| Blue VM down | `switch-backend.sh green` | ~5 seconds |
| Green VM down | `switch-backend.sh blue` | ~5 seconds |
| Edge nginx down | Start VM from Proxmox UI | ~2 minutes |
| DB primary down | `db-failover.yml` → use replica | ~1 minute |
| Full Proxmox down | Start AWS environment | ~15 minutes |

---

## Status

| Component | VM | Status |
|---|---|---|
| Terraform — 7 VMs provisioned | all | ✅ Done |
| Common role (Docker, UFW, timezone) | all | ✅ Done |
| Nginx + Blue/Green switch script | edge-nginx | ✅ Done |
| edge-backup (nginx standby) | edge-backup | ✅ Done |
| App container (Blue) | prod-vm1-BLUE | ✅ Done |
| App container (Green) | prod-vm2-GREEN | ✅ Done |
| PostgreSQL 16 primary | db-postgresql | ✅ Done |
| db-replica + pg_dump sync every 30min | db-replica | ✅ Done |
| Staging VM deployment | monitoring-staging | ✅ Done |
| Health check endpoint `/api/health` | app | ✅ Done |
| GitHub Actions — CI (lint + parallel tests) | — | ✅ Done |
| GitHub Actions — Staging pipeline | — | ✅ Done |
| GitHub Actions — Build + Push to ghcr.io | — | ✅ Done |
| Manual approval gate (GitHub Environments) | — | ✅ Done |
| Auto Blue/Green detection | — | ✅ Done |
| Smoke tests before traffic switch | — | ✅ Done |
| Auto rollback after 10 minutes | — | ✅ Done |
| AWS backup environment | — | ✅ Done |
| PR comment on test failure | — | 🔲 Planned |
| SSL / Let's Encrypt | edge-nginx | 🔲 Planned |
| Prometheus + Grafana | monitoring-staging | 🔲 Planned |

---

## Repo Structure

```
terraform-ansible-infrastructure/
├── proxmox-silverbank/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── ansible.tf
│   └── ansible/
│       ├── ansible.cfg
│       ├── inventory.ini
│       ├── group_vars/
│       ├── roles/
│       └── playbooks/
├── aws-silverbank/
│   ├── terraform/
│   └── ansible/
├── COMMANDS.md
└── README.md
```

---

*App repository: [mariusiordan/SilverBank-App](https://github.com/mariusiordan/SilverBank-App)*
*Infra repository: [mariusiordan/DevOps-final-project](https://github.com/mariusiordan/DevOps-final-project)*