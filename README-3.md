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
- [Database & Persistence](#database--persistence)
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
Internet / LAN      │  ┌──────────────────────────────┐                       │
192.168.7.x ────────┼─▶│         edge-nginx           │                       │
                    │  │         192.168.7.50          │                       │
                    │  │  /api/* → backend :4000       │                       │
                    │  │  /*     → frontend :3000      │                       │
                    │  └────────────┬─────────────────┘                       │
                    │               │                                          │
                    │  ┌────────────▼──────┐     ┌────────────────────┐       │
                    │  │  prod-vm1-BLUE    │     │  prod-vm2-GREEN    │       │
                    │  │  192.168.7.101    │     │  192.168.7.102     │       │
                    │  │  ┌─────────────┐  │     │  ┌─────────────┐   │       │
                    │  │  │  frontend   │  │     │  │  frontend   │   │       │
                    │  │  │  :3000      │  │     │  │  :3000      │   │       │
                    │  │  ├─────────────┤  │     │  ├─────────────┤   │       │
                    │  │  │  backend    │  │     │  │  backend    │   │       │
                    │  │  │  :4000      │  │     │  │  :4000      │   │       │
                    │  │  └─────────────┘  │     │  └─────────────┘   │       │
                    │  │    Active ✅      │     │    Idle 💤         │       │
                    │  └──────────┬────────┘     └──────────┬─────────┘       │
                    │             └──────────┬───────────────┘                 │
APP Network         │                        │                                 │
10.10.20.x ─────────┼────────────────────────┼─────────────────────────────── │
                    │             ┌───────────▼────────────┐                  │
                    │             │      db-postgresql     │                  │
                    │             │      192.168.7.60      │                  │
                    │             │      PostgreSQL 16     │                  │
                    │             │   persistent volume    │                  │
                    │             └────────────────────────┘                  │
                    │                                                          │
                    │  ┌───────────────────────────────────────────────────┐  │
                    │  │   monitoring-staging   192.168.7.70               │  │
                    │  │   ┌──────────┐ ┌──────────┐ ┌──────────────┐     │  │
                    │  │   │ frontend │ │ backend  │ │  postgres db │     │  │
                    │  │   │  :3000   │ │  :4000   │ │   :5432      │     │  │
                    │  │   └──────────┘ └──────────┘ └──────────────┘     │  │
                    │  │   Staging environment + CI/CD self-hosted runner  │  │
                    │  └───────────────────────────────────────────────────┘  │
                    └──────────────────────────────────────────────────────────┘
```

### 3-Tier Application Architecture

The application is split into three separate containers:

| Tier | Container | Port | Technology |
|---|---|---|---|
| Frontend | `silverbank-frontend` | 3000 | Next.js 16 (React) |
| Backend | `silverbank-backend` | 4000 | Express.js + Prisma |
| Database | `silverbank-db` / `postgres` | 5432 | PostgreSQL 16 |

Nginx routes traffic based on path:
- `/api/*` → backend container (Express API)
- `/*` → frontend container (Next.js)

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
| Database | PostgreSQL 16 | Application database with persistent volume |
| Frontend | Next.js 16 | SilverBank UI (React) |
| Backend | Express.js + Prisma | SilverBank API |
| CI/CD | GitHub Actions | Automated testing and deployment |
| Backup Env | AWS EC2 + VPC | Full infrastructure backup |
| Monitoring | Prometheus + Grafana | Metrics *(coming soon)* |

---

## Infrastructure (Terraform)

Terraform provisions all VMs from a single Ubuntu 24.04 template using `for_each`.
After apply, it automatically generates `ansible/inventory.ini`.

### Active VM Layout

| VM | VMID | LAN IP | APP IP | Specs | Role |
|---|---|---|---|---|---|
| `edge-nginx` | 850 | 192.168.7.50 | 10.10.20.10 | 2 vCPU / 2GB | Primary reverse proxy |
| `prod-vm1-BLUE` | 810 | 192.168.7.101 | 10.10.20.11 | 2 vCPU / 4GB | Production (Blue) |
| `prod-vm2-GREEN` | 811 | 192.168.7.102 | 10.10.20.12 | 2 vCPU / 4GB | Production (Green) |
| `db-postgresql` | 860 | 192.168.7.60 | 10.10.20.20 | 2 vCPU / 4GB | Primary database |
| `monitoring-staging` | 800 | 192.168.7.70 | 10.10.20.30 | 2 vCPU / 4GB | Staging + CI/CD runner |

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

---

## Configuration (Ansible)

Ansible configures each VM based on its role. Inventory is auto-generated by Terraform.

### Structure

```
proxmox-silverbank/ansible/
├── ansible.cfg                       # vault_password_file = ~/.vault-password
├── inventory.ini                     # auto-generated by Terraform
├── files/
│   ├── docker-compose.staging.yml    # 3-tier compose for staging (with DB)
│   └── docker-compose.prod.yml       # 2-tier compose for prod (no DB)
├── group_vars/
│   ├── all/
│   │   ├── main.yml                  # global vars (IPs, ports, docker user)
│   │   └── vault.yml                 # ENCRYPTED secrets (Ansible Vault)
│   ├── prod.yml                      # app image, tag, DB connection for blue+green
│   ├── db.yml                        # postgres vars for primary DB
│   └── monitoring.yml                # app vars for staging VM
├── roles/
│   ├── common/                       # all VMs: Docker, UFW, packages, timezone
│   ├── nginx/                        # edge: nginx + upstream config + switch script
│   ├── postgres/                     # db: PostgreSQL + persistent volume
│   ├── app/                          # blue+green: app containers + .env
│   └── monitoring/                   # staging: Prometheus + Grafana (coming soon)
└── playbooks/
    ├── site.yml                      # full setup from scratch
    ├── deploy-blue.yml               # manual deploy to BLUE + switch nginx
    ├── deploy-green.yml              # manual deploy to GREEN + switch nginx
    ├── deploy-staging.yml            # deploy 3-tier to staging VM + health check
    ├── deploy-production.yml         # auto Blue/Green + smoke tests + switch
    ├── rollback.yml                  # monitor 10min + auto rollback if unhealthy
    └── db-failover.yml               # emergency: switch app to DB replica
```

### Roles

| Role | Target VMs | What it does |
|---|---|---|
| `common` | All VMs | Docker install, UFW firewall, packages, UTC timezone |
| `nginx` | edge-nginx | Nginx, upstream config, Blue/Green switch script |
| `postgres` | db-postgresql | PostgreSQL 16 in Docker, persistent volume |
| `app` | blue, green | Pull Docker images from ghcr.io, write `.env`, start containers |
| `monitoring` | monitoring-staging | Prometheus + Grafana *(coming soon)* |

### Usage

```bash
cd proxmox-silverbank/ansible

# Test connectivity
ansible all -m ping -i inventory.ini

# Full setup from scratch
ansible-playbook playbooks/site.yml -i inventory.ini

# Configure specific VMs only
ansible-playbook playbooks/site.yml --limit edge-nginx -i inventory.ini
ansible-playbook playbooks/site.yml --limit prod -i inventory.ini
ansible-playbook playbooks/site.yml --limit db -i inventory.ini
ansible-playbook playbooks/site.yml --limit monitoring -i inventory.ini
```

---

## Application (Docker)

SilverBank is a 3-tier application: Next.js frontend, Express.js backend, and PostgreSQL database.
Each tier runs in its own Docker container and is built as a separate image.

### Docker Images

```
ghcr.io/mariusiordan/silverbank-frontend:<tag>   # Next.js UI
ghcr.io/mariusiordan/silverbank-backend:<tag>    # Express API + Prisma
```

Tags use short Git SHA: `sha-a1b2c3d`. Also tagged as `staging` or `latest` per environment.

### docker-compose files

| File | Used for | Includes DB? |
|---|---|---|
| `docker-compose.yml` | Local development | ✅ Yes |
| `docker-compose.staging.yml` | Staging VM | ✅ Yes |
| `docker-compose.prod.yml` | Production VMs | ❌ No (uses dedicated DB VM) |

### Multi-stage Dockerfiles

**Frontend (`Dockerfile`):**
```
Stage 1 (builder) → npm ci, npm run build (Next.js)
Stage 2 (runner)  → copy .next/standalone, node server.js
```

**Backend (`backend/Dockerfile`):**
```
Stage 1 (builder) → npm ci, prisma generate, tsc (TypeScript compile)
Stage 2 (runner)  → copy dist/, prisma migrate deploy, node dist/index.js
```

### Build & Push

```bash
# Frontend
docker buildx build --platform linux/amd64 \
  -t ghcr.io/mariusiordan/silverbank-frontend:v1.x \
  --push ./silver-bank

# Backend
docker buildx build --platform linux/amd64 \
  -t ghcr.io/mariusiordan/silverbank-backend:v1.x \
  --push ./silver-bank/backend
```

---

## CI/CD Pipelines (GitHub Actions)

Three distinct pipelines matching the project requirements.

### Branch Strategy

| Branch | Purpose | Workflow triggered |
|---|---|---|
| `dev` | Daily development | `test.yml` — lint + tests on PR only |
| `staging` | Pre-production testing | `staging.yml` — build + deploy staging + integration tests |
| `main` | Production | `deploy.yml` — build + manual approval + Blue/Green |

### Pipeline 1 — Continuous Integration (`test.yml`)

**Trigger:** Pull Request to `staging` or `main`

```
lint (ESLint)
  ├── JWT Tests        ──► pass/fail
  ├── Auth Tests       ──► pass/fail  (login + register — Docker container)
  └── Account Tests    ──► pass/fail  (Docker container)

All 3 tests run IN PARALLEL after lint passes.
If any test fails → PR comment added automatically + merge blocked.
```

> Auth and Account tests run inside a Docker container (same environment as local) to ensure consistent dependency resolution.

### Pipeline 2 — Staging Deployment (`staging.yml`)

**Trigger:** Push to `staging` branch

```
lint
  ├── JWT Tests      ┐
  ├── Auth Tests     ├──► build frontend image ──► push to ghcr.io (tag: sha-xxx + staging)
  └── Account Tests  ┘──► build backend image  ──►
                                    │
                                    ▼
                         deploy to monitoring-staging VM
                         (frontend + backend + postgres)
                                    │
                                    ▼
                         integration tests (self-hosted runner):
                           ✅ health check  → /api/health
                           ✅ register      → POST /api/auth/register
                           ✅ login         → POST /api/auth/login
                           ✅ cleanup       → DELETE /api/auth/delete
```

### Pipeline 3 — Production Deployment (`deploy.yml`)

**Trigger:** Push to `main` branch → **Manual Approval required**

```
lint
  ├── JWT Tests      ┐
  ├── Auth Tests     ├──► build frontend + backend images ──► ⏳ Manual Approval
  └── Account Tests  ┘       (tag: sha-xxx + latest)               │
                                                                    ▼
                                                     detect idle environment
                                                     (read /opt/current-env on edge)
                                                                    │
                                                     deploy frontend + backend to idle VM
                                                     (docker-compose.prod.yml)
                                                                    │
                                                     smoke tests on idle VM (bypass nginx):
                                                       curl http://10.10.20.11:4000/api/health
                                                                    │
                                                     switch nginx traffic to new environment
                                                       /opt/switch-backend.sh [blue|green]
                                                                    │
                                                     monitor 10 minutes (every 30 seconds)
                                                       ├── healthy → ✅ deployment complete
                                                       └── 3 consecutive failures → auto rollback
```

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `GHCR_TOKEN` | GitHub PAT with `write:packages` permission |
| `PROXMOX_SSH_KEY` | Private SSH key (`~/.ssh/id_ed25519`) |
| `VAULT_PASSWORD` | Ansible Vault password |

### Self-Hosted Runner

The deployment jobs run on a self-hosted GitHub Actions runner installed on `monitoring-staging` (192.168.7.70).
This allows the runner to SSH into all production VMs on the internal `10.10.20.x` network.

```bash
# Check runner status
ssh devop@192.168.7.70
sudo systemctl status actions.runner.mariusiordan-SilverBank-App.monitoring-staging.service
```

---

## Blue/Green Deployment

Traffic is controlled by Nginx upstream config on the edge VM.
Only one environment is active at a time — the other is on standby for instant rollback.

Nginx routes both frontend and API traffic to the same active VM:

```nginx
upstream app_frontend {
    server 10.10.20.11:3000;   # BLUE frontend - active
}

upstream app_backend_api {
    server 10.10.20.11:4000;   # BLUE backend API - active
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                       Blue/Green Flow                           │
│                                                                 │
│  1. Read /opt/current-env on edge → find which is active        │
│  2. Calculate idle environment (opposite of active)             │
│  3. Deploy new frontend + backend images to IDLE VM             │
│  4. Smoke test directly on IDLE (bypassing nginx)               │
│     curl http://10.10.20.11:4000/api/health  (if idle=blue)     │
│  5. Switch nginx upstreams → IDLE becomes LIVE                  │
│     /opt/switch-backend.sh [blue|green]                         │
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

# Rollback — monitor 10 min + auto switch if unhealthy
ansible-playbook playbooks/rollback.yml -i inventory.ini
```

---

## Database & Persistence

The database runs on a dedicated VM (`db-postgresql`) with a persistent Docker volume.
The application never touches the database during deployment — only frontend and backend are redeployed.

### Production DB

```
db-postgresql (192.168.7.60 / 10.10.20.20)
  └── postgres:16-alpine container
      └── /opt/postgres/data (persistent volume — survives container restarts)
```

On **staging**, PostgreSQL runs as a third container alongside frontend and backend:

```yaml
# docker-compose.staging.yml
services:
  db:       # PostgreSQL — staging only
  backend:  # Express API
  frontend: # Next.js
```

On **production**, the backend connects to the dedicated DB VM:

```yaml
# docker-compose.prod.yml
services:
  backend:  # connects to DB_HOST=10.10.20.20
  frontend:
```

### DB Failover — if primary DB goes down

```bash
cd proxmox-silverbank/ansible

# Automatically switches all app VMs to use DB replica
ansible-playbook playbooks/db-failover.yml -i inventory.ini
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
# Step 1 — update your IP
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
curl http://192.168.7.50/api/health
# → {"status":"ok","database":"connected","version":"1.0.0"}
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
| Bad deploy | Auto rollback after 10 min monitoring | ~10 minutes |
| Edge nginx down | Start VM from Proxmox UI | ~2 minutes |
| DB primary down | `db-failover.yml` → use replica | ~1 minute |
| Full Proxmox down | Start AWS environment | ~15 minutes |

---

## Status

| Component | VM | Status |
|---|---|---|
| Terraform — 5 VMs provisioned | all | ✅ Done |
| Common role (Docker, UFW, timezone) | all | ✅ Done |
| Nginx + Blue/Green switch script | edge-nginx | ✅ Done |
| Nginx routing /api/ → backend, / → frontend | edge-nginx | ✅ Done |
| Frontend container (Next.js :3000) | prod-vm1-BLUE, prod-vm2-GREEN | ✅ Done |
| Backend container (Express :4000) | prod-vm1-BLUE, prod-vm2-GREEN | ✅ Done |
| PostgreSQL 16 + persistent volume | db-postgresql | ✅ Done |
| Staging VM — 3-tier deployment | monitoring-staging | ✅ Done |
| Health check endpoint `/api/health` | backend | ✅ Done |
| GitHub Actions — CI (lint + parallel tests) | — | ✅ Done |
| Tests run in Docker container | — | ✅ Done |
| PR comment on test failure | — | ✅ Done |
| GitHub Actions — Staging pipeline | — | ✅ Done |
| Integration tests (register + login + cleanup) | — | ✅ Done |
| Build + Push 2 images to ghcr.io | — | ✅ Done |
| Manual approval gate (GitHub Environments) | — | ✅ Done |
| Auto Blue/Green detection | — | ✅ Done |
| Smoke tests before traffic switch | — | ✅ Done |
| Auto rollback after 10 minutes | — | ✅ Done |
| AWS backup environment | — | ✅ Done |
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
│       ├── files/
│       │   ├── docker-compose.staging.yml
│       │   └── docker-compose.prod.yml
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