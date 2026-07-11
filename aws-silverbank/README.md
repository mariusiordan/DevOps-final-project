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
| db-postgresql | PostgreSQL in Docker | Private | IAM role for S3 backups |
| monitoring-staging | Prometheus + Grafana + Loki | Private | Grafana on port 3001 |

Networking: VPC `10.0.0.0/16`, public subnet `10.0.1.0/24`, private subnet `10.0.2.0/24`, NAT Gateway for private outbound, Internet Gateway for public.

Region: `eu-west-2` (London). Terraform state in S3 bucket `silverbank-tfstate-mariusiordan`.
DB backups live under the `db-backups/` prefix in the same bucket (30-day lifecycle rule).

**DB credentials** (from the vault, injected into the postgres container): user `devop_db`, database `appdb`.

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

**Step 3 — Configure VMs + deploy app + monitoring (~5 min):**

```bash
cd ../ansible
ansible all -m ping                  # confirm SSH works to all 5 VMs
ansible-playbook playbooks/site.yml  # Docker, nginx, app, postgres, monitoring
```

**Step 4 — Restore the database from S3** (brings back last session's data):

```bash
ansible db -m shell -a "/opt/restore-db.sh" --become
```

**Step 5 — Open the app:**

```bash
cd ../terraform && terraform output edge_elastic_ip
# open http://<that-ip>/ in a browser
```

**If Prometheus targets show "down" after a rebuild** — restart it once:

```bash
ansible monitoring -m shell -a "cd /opt/monitoring && docker compose restart prometheus"
```

**End of session — back up, then tear down:**

```bash
cd ../ansible
ansible db -m shell -a "/opt/backup-db.sh" --become   # save data to S3 FIRST
cd ../terraform
terraform destroy     # type yes
```

**Notes:**
- The **Elastic IP is reserved** — the edge URL stays the same across destroy/apply.
- **Images are already on GHCR** — no rebuild needed unless app code changes.
- **`terraform destroy` wipes the DB volume.** Always run `/opt/backup-db.sh` before destroy,
  and `/opt/restore-db.sh` after the next apply, to keep your data.

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
ansible-playbook playbooks/site.yml --limit edge        # One group only
ansible-playbook playbooks/site.yml --limit monitoring  # Just monitoring
ansible <group> -a "<command>"               # Ad-hoc command on a group
```

### Ansible Vault

```bash
ansible-vault view group_vars/all/vault.yml          # View secrets
ansible-vault edit group_vars/all/vault.yml          # Edit secrets
```

Vault password file: `~/.vault-password-aws` (referenced in `ansible.cfg`). **Never commit this file.**

### Database backup / restore (S3, via IAM role on the db VM)

```bash
# Back up: data-only dump -> gzip -> S3 (timestamped + "latest")
ansible db -m shell -a "/opt/backup-db.sh" --become

# Restore: download latest -> truncate tables -> load data (idempotent)
ansible db -m shell -a "/opt/restore-db.sh" --become

# Confirm the IAM role works (no stored credentials needed)
ansible db -m shell -a "aws sts get-caller-identity" --become

# List backups in S3
ansible db -m shell -a "aws s3 ls s3://silverbank-tfstate-mariusiordan/db-backups/" --become
```

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
ansible db -m shell -a "docker exec postgres psql -U devop_db -d appdb -c '\dt'"   # List tables
```

### Blue/Green switching (the switch script lives on the edge VM)

Nginx forwards traffic to whichever colour is active. `switch-backend.sh` toggles between
BLUE and GREEN, tests the nginx config, then reloads with zero downtime.

```bash
# Check which colour is active
ansible edge -m shell -a "cat /opt/current-env 2>/dev/null || echo 'not set (defaults to blue)'"

# See the live upstream config
ansible edge -m shell -a "cat /etc/nginx/conf.d/upstream.conf"

# Switch traffic
ansible edge -m shell -a "sudo /opt/switch-backend.sh green" --become   # to GREEN
ansible edge -m shell -a "sudo /opt/switch-backend.sh blue"  --become   # to BLUE

# Confirm the app still responds after switching
curl -s http://<EDGE_ELASTIC_IP>/api/health
```

### Monitoring checks (run from `ansible/`)

```bash
# Confirm node-exporter runs on every VM
ansible all -m shell -a "docker ps | grep node-exporter || echo NONE"

# Count Prometheus targets up vs down (expect 6 up: 5 node-exporters + Prometheus)
ansible monitoring -m shell -a "curl -s http://localhost:9090/api/v1/targets | grep -o '\"health\":\"[a-z]*\"' | sort | uniq -c"

# The two :4000 app-backend targets are expected to be DOWN
# (they return JSON, not Prometheus metrics — harmless)

# Restart Prometheus if it's holding stale IPs after a rebuild
ansible monitoring -m shell -a "cd /opt/monitoring && docker compose restart prometheus"
```

### Access Grafana / Prometheus (private subnet — needs SSH tunnel)

Monitoring lives in the private subnet, so reach it through an SSH tunnel via the edge bastion.
Open the tunnel in its own terminal and **leave it running** (it looks frozen — that's correct):

```bash
# Grafana (login admin / changeme)
ssh -N -L 3001:<MONITORING_PRIVATE_IP>:3001 ubuntu@<EDGE_ELASTIC_IP> -i ~/.ssh/id_ed25519
# then open http://127.0.0.1:3001  (use 127.0.0.1, not localhost)

# Prometheus
ssh -N -L 9090:<MONITORING_PRIVATE_IP>:9090 ubuntu@<EDGE_ELASTIC_IP> -i ~/.ssh/id_ed25519
# then open http://127.0.0.1:9090/targets
```

---

## 🔧 Troubleshooting (things that went wrong and how they were fixed)

**SSH times out to all VMs / "context deadline exceeded"**
Home IP changed. Update `your_home_ip` in `terraform.tfvars` (with `/32`) and `terraform apply`.

**`aws: command not found` on a VM**
AWS CLI not installed. It's in the `common` role now (needs the `unzip` package too — the
`unarchive` module fails without it). Re-run `ansible-playbook playbooks/site.yml`.

**Prometheus targets down after rebuild**
```bash
ansible monitoring -m shell -a "cd /opt/monitoring && docker compose restart prometheus"
```
If a specific VM stays down, suspect a missing security-group rule for port 9100.

**Grafana tunnel won't load in the browser (Grafana itself is fine)**
Check Grafana is healthy on the VM first:
```bash
ansible monitoring -m shell -a "curl -s -o /dev/null -w '%{http_code}' http://localhost:3001/login" --become
```
If that returns `200`, the problem is the local tunnel/browser, not Grafana. Try:
- use `http://127.0.0.1:3001` (not `localhost`)
- clear a stuck port: `lsof -ti:3001 | xargs kill -9`
- open the tunnel with `-N` in a fresh terminal and leave it running

**Backup uploaded a tiny (~20 byte) file**
Old bug: `pg_dump | gzip` hid pg_dump failures. Fixed — the script now dumps to a file,
checks it's ≥100 bytes, and aborts on empty. Also reads the DB user from the container
(`devop_db`), so it can't use the wrong username.

**Restore errors: "relation already exists" / "duplicate key"**
The backup is **data-only** (Prisma owns the schema) and **excludes `_prisma_migrations`**.
The restore script **truncates the tables first**, then loads — so it's safe to run repeatedly.
If you see duplicate-key errors, you're running an old version of the script; redeploy with
`ansible-playbook playbooks/site.yml --limit db`.

**Can't delete rows: "violates foreign key constraint"**
The schema chains User → Account → Transaction → CashEntry. To clear everything at once:
```bash
ansible db -m shell -a "docker exec postgres psql -U devop_db -d appdb -c 'TRUNCATE \"User\", \"Account\", \"Transaction\", \"CashEntry\" CASCADE;'" --become
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
- **Backend `/api/health` reports `database: connected`** — quick way to confirm the full app→DB chain works.
- **Security groups fail silently** — a blocked port shows as "context deadline exceeded" (timeout), not a clear error. When Prometheus targets are down, suspect a missing SG rule first.
- **Grafana runs on 3001 on AWS** — port 3000 is taken by the app frontend. Container is still 3000 internally, mapped to 3001 on the host (`"3001:3000"`).
- **Prometheus must scrape private IPs**, not the edge public IP. Added `edge_private_ip` to group_vars for this.
- **Prometheus caches targets** — after changing scrape config, a `docker compose restart prometheus` is sometimes needed to pick up new IPs.
- **node-exporter needs port 9100 open from the monitoring SG** on every other SG (app, db, edge).
- **Blue/Green switch = one script, zero downtime.** `switch-backend.sh` rewrites the upstream, runs `nginx -t` before reloading, and logs every switch to `/var/log/nginx/switches.log`. `/opt/current-env` records the active colour.
- **IAM role beats stored keys.** The db VM reaches S3 via an attached IAM instance profile — no access keys anywhere. Least privilege: only the `db-backups/` prefix.
- **A backup that "succeeds" can still be empty.** Always add a sanity check (size, row count). The `pg_dump | gzip` pattern hides pg_dump failures — dump to a file and check it first.
- **Back up data only when an ORM owns the schema.** Prisma creates the tables via migrations; the backup carries just the rows (`--data-only`, exclude `_prisma_migrations`). Restore truncates then loads.

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

### Session 3
- Enabled the monitoring play in `site.yml` (was commented out)
- Added node-exporter to the `common` role so it runs on all 5 VMs
- Removed UFW from the monitoring role
- Fixed Grafana to run on port 3001 (3000 used by app frontend)
- Rewrote `prometheus.yml.j2` to use AWS private IPs from group_vars
- Added `edge_private_ip` output + used it for the edge scrape target
- Added port 9100 ingress rules to app, db, and edge security groups (Prometheus scraping)
- Debugged scrape failures one VM at a time — traced to missing SG rules ("context deadline exceeded" = blocked)
- **All 5 node-exporters scraped successfully; Grafana healthy (HTTP 200)** ✅
- Committed monitoring work
- Destroyed infra at end of session

### Session 4
- Rebuilt infra (`terraform apply` + `site.yml`) — app + monitoring came up clean
- Monitoring healthy on first try: 6 targets up, 2 expected down
- Found the nginx role was still the old single-VM DR version (no Blue/Green, no switch script)
- Upgraded the nginx role for Blue/Green:
  - Rewrote `upstream.conf.j2` with blue + green upstreams (blue active by default)
  - Added `switch-backend.sh.j2` — the traffic-switch script
  - Removed UFW from the nginx role; added a task to deploy the switch script to `/opt`
- **Tested Blue/Green end-to-end:** switched BLUE → GREEN → BLUE, app healthy on both, zero downtime ✅
- Committed the nginx Blue/Green work

### Session 5
- Explained the four nginx files line by line (switch script, upstream, tasks, site config)
- Built S3 database backups with an IAM role:
  - `iam.tf`: IAM role + least-privilege policy (db-backups/ only) + instance profile, attached to the db VM
  - Added AWS CLI install to the `common` role (plus the missing `unzip` package)
  - `backup-db.sh`: data-only dump, excludes `_prisma_migrations`, size-check safety net, uploads timestamped + latest to S3
  - `restore-db.sh`: downloads latest, truncates tables, loads data (idempotent)
- Debugged along the way: silent 20-byte backup, wrong DB user (`devop_db` not `silverbank_admin`), foreign-key chain, Prisma migrations table, duplicate keys
- **Tested backup → wipe → restore end-to-end: data survives cleanly, repeatable with no errors** ✅
- Committed the S3 backup work
- Added a Troubleshooting section to this README


### Session 6 — Stage 1 CI (GitHub Actions)
- Wrote `.github/workflows/pipeline-1-ci.yml`: three **parallel** jobs — Lint (frontend, `eslint .`), Backend tests, Frontend tests
  - Trigger: pull request to `main`/`staging`; Node 20; `npm ci`; `defaults.run.working-directory` sets the folder once per job
  - Backend tests need no DB — Prisma is **mocked** in the tests (9 backend + 6 frontend all green locally)
- **Architectural decision:** found three old pipeline files (`pipeline-1/2/3`) built for a *different* cloud-native stack (ALB + ASG + ECR + RDS + CloudWatch) — incompatible with the current EC2 + nginx + Ansible + GHCR setup. Confirmed via Terraform outputs (none of `alb_listener_arn`, `ecr_*`, `rds_endpoint`, `*_asg_name` exist here)
  - Kept the current architecture (stays matched with the Proxmox mirror). Archived `pipeline-2-staging.yml` + `pipeline-3-deploy.yml` to `.github/old-workflow/` as reference (GitHub only runs YAML under `.github/workflows/`)
- First PR (`cleanup/remove-duplicate-jwt-test`): removed a duplicate `frontend/jwt.test.ts` (verified identical with `diff` first)
  - Recovered a commit made on the wrong branch using `git switch -c` + `git branch -f` — branches are movable labels
- **Caught a real lint failure:** Next.js 16 removed `next lint` → changed the frontend lint script from `next lint` to `eslint .`. Silence from ESLint = success
- **Branch protection Ruleset on `main`:** require a PR + 3 required status checks (Lint, Backend tests, Frontend tests), enforcement Active
  - **Verified by a rejected direct push** — "Changes must be made through a pull request / 3 of 3 required status checks are expected" ✅


  ### Session 7 — Stage 2 Build & Push (GHCR)
- Wrote `.github/workflows/pipeline-2-build.yml`: build + push frontend & backend images to GHCR
  - Trigger: push to `main` **or** manual `workflow_dispatch` (safe way to test without merging junk)
  - Tags each image twice: `v1.0-sha-<short-commit>` (traceable) + `latest` (moving pointer)
  - Auth via the auto-provided `GITHUB_TOKEN` + `permissions: packages: write` — **no stored PAT in CI**
  - Builds `linux/amd64` (EC2 is x86)
- **Frontend API URL decision:** built with `NEXT_PUBLIC_API_URL=` (empty) → app calls **relative `/api`** paths, routed by the edge nginx. Deliberately did NOT bake the Elastic IP, so the image is environment-agnostic and reusable on the Proxmox mirror
  - Confirmed the code supports it: `process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000"` + `fetch(\`${API_URL}/api/...\`)` → empty string yields `/api/...`
  - (Deploy-time TODO for Stage 3: edge nginx needs a `location /api/` block forwarding to the app upstream)
- **Debugged first-push 403 Forbidden:** the image *built* fine; only the *push* was denied (403 = authenticated but not authorised)
  - Repo Actions permission was read-only → switched to **Read and write**; still 403
  - Real cause: the GHCR package didn't exist yet, so the repo token had nothing to own. Seeded both packages once — fresh classic PAT with `write:packages` → `docker login ghcr.io` → built + pushed with a throwaway `:seed` tag → then linked each package to the repo (Package settings → **Manage Actions access** → add `SilverBank-AWS` with **Write**)
- **Re-ran the workflow → green.** Both images live in GHCR: `v1.0-sha-1832e43` + `latest` ✅
---

## TODO / Next steps

- [x] Run `site.yml` and deploy app to BLUE + GREEN
- [x] Verify app works end-to-end (open edge IP in browser, log in)
- [x] Enable monitoring role in `site.yml` — Prometheus + Grafana + Loki
- [x] Test Blue/Green switch script manually (`sudo /opt/switch-backend.sh green`)
- [x] Set up S3 DB backups from postgres VM (data survives destroy)
- [ ] Build GitHub Actions pipeline: dev → PR tests → staging → manual test → prod (manager approval) → S3 backup → deploy idle VM → switch traffic → monitor 10 min → rollback on failure
       - [x] **Stage 1 — CI:** lint + backend/frontend tests on every PR, enforced by branch protection
       - [x] **Stage 2 — Build:** push to `main` builds + pushes versioned images to GHCR
       - [ ] **Stage 3 — Deploy:** pull images to idle blue/green VM (Ansible), nginx traffic switch, monitor + rollback
- [ ] Fix Grafana SSH tunnel access from the browser (Grafana returns 200 on the VM; local tunnel won't render)
- [ ] Add Prometheus as a Grafana data source + import a node-exporter dashboard
- [ ] Clean up deprecated `dynamodb_table` (use `use_lockfile` instead)
- [ ] Portfolio polish: architecture diagram + top-level project README