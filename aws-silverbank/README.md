# SilverBank AWS — Project Journal

A working journal of building the SilverBank infrastructure on AWS, mirroring the Proxmox homelab. Updated at the end of each session.

**Goal:** Recreate the Proxmox SilverBank environment on AWS using Terraform + Ansible + GitHub Actions. Two matching projects (Proxmox + AWS) to use for job applications, then move on to the AWS Solutions Architect course.

---

## Architecture

Five EC2 instances mirroring the Proxmox VMs:

| VM | Role | Subnet | Notes |
|---|---|---|---|
| edge-nginx | Reverse proxy + bastion | Public | Has Elastic IP (static) |
| prod-vm1-BLUE | App server (frontend + backend) | Private | Blue/Green |
| prod-vm2-GREEN | App server (frontend + backend) | Private | Blue/Green |
| db-postgresql | PostgreSQL in Docker | Private | |
| monitoring-staging | Prometheus + Grafana | Private | |

Networking: VPC `10.0.0.0/16`, public subnet `10.0.1.0/24`, private subnet `10.0.2.0/24`, NAT Gateway for private outbound, Internet Gateway for public.

Region: `eu-west-2` (London). Terraform state in S3 bucket `silverbank-tfstate-mariusiordan`.

---

## ⭐ Daily restart — from nothing to a working app (~10 min)

Use this every time you start a session (home, school, anywhere). The infra is destroyed between sessions to save cost; this rebuilds it from code.

**Step 1 — Set your current IP** (network changes between home/school):

```bash
cd aws-silverbank/terraform
curl https://checkip.amazonaws.com           # copy this IP
# Edit terraform.tfvars:  your_home_ip = "THE_IP/32"   (don't forget /32)
```

**Step 2 — Build the infrastructure (~4 min):**

```bash
terraform apply        # type yes
```

**Step 3 — Configure VMs + deploy app (~5 min):**

```bash
cd ../ansible
ansible all -m ping                  # confirm SSH works to all 5 VMs
ansible-playbook playbooks/site.yml  # installs Docker, nginx, app, postgres
```

**Step 4 — Open the app:**

```bash
cd ../terraform && terraform output edge_elastic_ip
# open http://<that-ip>/ in a browser
```

**End of session — tear down to save cost:**

```bash
cd aws-silverbank/terraform
terraform destroy     # type yes
```

**Notes:**
- The **Elastic IP is reserved** — the edge URL stays the same across destroy/apply.
- **Images are already on GHCR** — no rebuild needed unless app code changes.
- **`terraform destroy` wipes the database** (db volume is destroyed). Next start = empty DB, Prisma recreates the tables. Accounts/data from the previous session are gone. (The future pipeline will back up to S3 before destroy.)

---

## Common commands

### Terraform (run from `terraform/`)

```bash
terraform init                 # First time / after backend change
terraform validate             # Check syntax
terraform plan                 # Preview changes
terraform apply                # Build/update infrastructure (type yes)
terraform destroy              # Tear everything down to save cost (type yes)
terraform output               # Show all outputs (IPs, etc.)
```

### Pre-apply checklist — home IP

Dynamic ISP IPs change and lock you out of SSH. Always check before applying:

```bash
curl https://checkip.amazonaws.com           # Get current public IP
grep your_home_ip terraform.tfvars           # Compare with what's set
# If different, update terraform.tfvars: your_home_ip = "NEW_IP/32"  (note the /32)
```

### Ansible (run from `ansible/`)

```bash
ansible all -m ping                          # Test SSH to all 5 VMs
ansible-playbook playbooks/site.yml          # Configure everything
ansible-playbook playbooks/site.yml --limit edge    # One group only
ansible <group> -a "<command>"               # Ad-hoc command on a group
```

### Ansible Vault

```bash
ansible-vault view group_vars/all/vault.yml          # View secrets
ansible-vault edit group_vars/all/vault.yml          # Edit secrets
```

Vault password file: `~/.vault-password-aws` (referenced in `ansible.cfg`). **Never commit this file.**

### Docker images (run from app repo `SilverBank-AWS/`)

Build for `linux/amd64` because EC2 is x86_64 (Mac builds ARM by default):

```bash
# Login to GHCR first
echo "GHCR_TOKEN" | docker login ghcr.io -u mariusiordan --password-stdin

# Backend
cd backend
docker build --platform linux/amd64 -t ghcr.io/mariusiordan/silverbank-backend:latest .
docker push ghcr.io/mariusiordan/silverbank-backend:latest

# Frontend
cd ../frontend
docker build --platform linux/amd64 -t ghcr.io/mariusiordan/silverbank-frontend:latest .
docker push ghcr.io/mariusiordan/silverbank-frontend:latest
```

### Verify deployment

```bash
curl -v http://<EDGE_ELASTIC_IP>/            # Should serve the app (502 if app not deployed yet)
ansible prod -a "docker ps"                  # Check app containers on blue/green
ansible prod-vm1-BLUE -a "curl -s http://localhost:4000/api/health"   # Backend health + DB connection
ansible db -a "docker exec postgres psql -U silverbank_admin -d appdb -c '\l'"   # List databases
```

---

## App local development (run from `SilverBank-AWS/`)

Use `dev` mode locally, not `start` (start needs a production build first):

```bash
# Backend (needs .env with DATABASE_URL, JWT_SECRET, PORT, FRONTEND_URL)
cd backend
npm run dev

# Frontend
cd frontend
npm run dev
```

Local PostgreSQL via Homebrew: `brew services start postgresql@16`

---

## Key lessons learned

- **No UFW on AWS.** Security Groups handle the firewall. UFW adds risk (lockout) with no benefit.
- **AWS network interface is `ens5`, not `eth1`.** Don't bind services to eth1.
- **Default SSH user is `ubuntu`** on the Ubuntu AMI, not `devop`.
- **Elastic IP stays static** across destroy/apply; private IPs change every time — that's why Terraform auto-generates the inventory.
- **Build images for `linux/amd64`** — Mac (Apple Silicon) builds ARM64 by default which won't run on EC2.
- **Home IP changes** lock you out of SSH — check before every apply.
- **Idempotency** — running a playbook twice should show `changed=0` the second time.
- **`terraform destroy` wipes the DB volume** — data does not survive teardown until S3 backups are wired in.
- **Backend `/api/health` reports `database: connected`** — quick way to confirm the full app→DB chain works.

---

## Session log

### Session 1
- Built Terraform: VPC, subnets, security groups, NAT, 3 EC2 instances (edge, blue, db)
- Set up S3 backend for state
- Created Ansible roles: common (with Docker), nginx, app, postgres, monitoring
- Set up Ansible Vault for secrets
- Destroyed infra at end of session to save cost

### Session 2
- Recreated infra with `terraform apply`
- Added GREEN app server and monitoring VM to Terraform (now 5 VMs total)
- Updated `outputs.tf` to include GREEN + monitoring in inventory and group_vars
- Got SilverBank-AWS app running locally (dev mode)
- Added `/health` route to frontend
- Fixed Ansible roles: removed UFW from common + app, fixed app .env.j2 (added FRONTEND_URL + health vars)
- Created fresh GHCR token, updated vault
- Built and pushed frontend + backend images (linux/amd64) to GHCR
- Ran `site.yml` — all 5 VMs configured, app deployed to BLUE + GREEN
- **Verified app end-to-end through edge IP — signup/login working, DB connected** ✅
- Committed both repos (app: health route; infra: 5-VM setup + role fixes)
- Added "Daily restart" section to this README

---

## TODO / Next steps

- [x] Run `site.yml` and deploy app to BLUE + GREEN
- [x] Verify app works end-to-end (open edge IP in browser, log in)
- [ ] Enable monitoring role in `site.yml` (currently commented out) — Prometheus + Grafana
- [ ] Test Blue/Green switch script manually (`sudo /opt/switch-backend.sh green`)
- [ ] Build GitHub Actions pipeline: dev → PR tests → staging → manual test → prod (manager approval) → S3 backup → deploy idle VM → switch traffic → monitor 10 min → rollback on failure
- [ ] Set up S3 DB backups from postgres VM (also enables data to survive destroy)
- [ ] Clean up deprecated `dynamodb_table` (use `use_lockfile` instead)