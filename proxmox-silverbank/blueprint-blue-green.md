# Blue/Green Deployment — SilverBank Implementation
#
# This document explains the complete Blue/Green deployment strategy
# implemented in the SilverBank project, including every component,
# how they interact, and why each decision was made.
#
# ============================================================
# WHAT IS BLUE/GREEN DEPLOYMENT?
# ============================================================
#
# Blue/Green is a deployment strategy that eliminates downtime and
# reduces risk by running two identical production environments.
#
# At any given time:
#   - ONE environment is ACTIVE  → receives all user traffic
#   - ONE environment is IDLE    → sits on standby, ready for next deploy
#
# When deploying a new version:
#   1. Deploy to IDLE environment  (no user impact)
#   2. Test IDLE directly          (bypass nginx, users unaffected)
#   3. Switch nginx traffic        (instant, ~milliseconds of downtime)
#   4. Monitor for 10 minutes      (auto-rollback if unhealthy)
#   5. Old environment stays up    (instant rollback if needed)
#
# ============================================================
# SILVERBANK INFRASTRUCTURE
# ============================================================
#
# Five Proxmox VMs, each with a dedicated role:
#
#   192.168.7.50   edge-nginx       — reverse proxy, traffic controller
#   192.168.7.101  prod-vm1-BLUE    — production environment BLUE
#   192.168.7.102  prod-vm2-GREEN   — production environment GREEN
#   192.168.7.60   db-postgresql    — shared PostgreSQL database
#   192.168.7.70   monitoring-staging — staging + CI/CD runner
#
# Each VM has two network interfaces:
#   vmbr0  192.168.7.x   — LAN (SSH, external access)
#   vmbr1  10.10.20.x    — APP (internal app ↔ DB communication)
#
# APP network IPs (used for container communication):
#   10.10.20.10   edge-nginx
#   10.10.20.11   prod-vm1-BLUE
#   10.10.20.12   prod-vm2-GREEN
#   10.10.20.20   db-postgresql
#
# The database is NOT reachable from the LAN network.
# Only the APP network (vmbr1) can reach PostgreSQL port 5432.
# This is enforced by UFW firewall rules on the DB VM.


# ============================================================
# COMPONENT 1 — NGINX UPSTREAM CONFIGURATION
# ============================================================
#
# File: /etc/nginx/conf.d/upstream.conf  (on edge-nginx VM)
# Template: proxmox-silverbank/ansible/roles/nginx/templates/upstream.conf.j2
#
# This file tells nginx WHERE to send incoming traffic.
# It defines two upstream groups — one for frontend, one for backend.
# Both always point to the SAME VM (Blue or Green).
#
# Why two separate upstreams?
# Because frontend (Next.js) runs on port 3000
# and backend (Express) runs on port 4000.
# Nginx needs to know where to route /api/* vs /* separately.

upstream app_frontend {
    server 10.10.20.11:3000;      # BLUE frontend — active
    # server 10.10.20.12:3000;   # GREEN frontend — inactive (commented out)
}

upstream app_backend_api {
    server 10.10.20.11:4000;      # BLUE backend API — active
    # server 10.10.20.12:4000;   # GREEN backend API — inactive (commented out)
}

# When we switch to GREEN, this file becomes:
#
# upstream app_frontend {
#     # server 10.10.20.11:3000;  # BLUE frontend — inactive
#     server 10.10.20.12:3000;    # GREEN frontend — active
# }
#
# upstream app_backend_api {
#     # server 10.10.20.11:4000;  # BLUE backend API — inactive
#     server 10.10.20.12:4000;    # GREEN backend API — active
# }
#
# The switch script rewrites this file and reloads nginx.
# Nginx reload is graceful — existing connections finish normally,
# new connections go to the new environment.


# ============================================================
# COMPONENT 2 — NGINX SITE CONFIGURATION
# ============================================================
#
# File: /etc/nginx/sites-enabled/app.conf  (on edge-nginx VM)
# Template: proxmox-silverbank/ansible/roles/nginx/templates/app.conf.j2
#
# This file defines HOW nginx routes incoming requests.
# It reads from the upstream config above to know WHERE to send them.
#
# Routing rules:
#   /api/*  → backend Express container (port 4000)
#   /*      → frontend Next.js container (port 3000)

server {
    listen 80;
    server_name _;   # accept requests for any domain or IP

    # API requests → backend Express container
    # Must be defined BEFORE location / to take priority
    location /api/ {
        proxy_pass http://app_backend_api;     # reads from upstream config
        proxy_http_version 1.1;

        # Pass real client information to the Express app
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Cookie            $http_cookie;   # needed for auth cookies

        # How long nginx waits before giving up
        proxy_connect_timeout 60s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }

    # All other requests → frontend Next.js container
    location / {
        proxy_pass http://app_frontend;        # reads from upstream config
        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support — needed for Next.js hot reload in development
        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        "upgrade";

        proxy_connect_timeout 60s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }
}


# ============================================================
# COMPONENT 3 — TRAFFIC SWITCH SCRIPT
# ============================================================
#
# File: /opt/switch-backend.sh  (on edge-nginx VM)
# Template: proxmox-silverbank/ansible/roles/nginx/templates/switch-backend.sh.j2
#
# This script performs the actual Blue/Green traffic switch.
# It rewrites upstream.conf and reloads nginx.
#
# Usage:
#   sudo /opt/switch-backend.sh blue    → route all traffic to BLUE
#   sudo /opt/switch-backend.sh green   → route all traffic to GREEN
#   sudo /opt/switch-backend.sh         → auto-switch to the other one
#
# The script also writes to /opt/current-env so Ansible can read
# which environment is currently active before the next deployment.

#!/bin/bash

NGINX_CONF="/etc/nginx/conf.d/upstream.conf"
BLUE_IP="10.10.20.11"    # prod-vm1-BLUE internal APP network IP
GREEN_IP="10.10.20.12"   # prod-vm2-GREEN internal APP network IP

TARGET=${1:-""}

# If no argument — read current env and switch to the other one
if [ -z "$TARGET" ]; then
    CURRENT=$(cat /opt/current-env 2>/dev/null || echo "green")
    if [ "$CURRENT" = "blue" ]; then
        TARGET="green"
    else
        TARGET="blue"
    fi
fi

if [ "$TARGET" = "blue" ]; then
    # Write new upstream.conf pointing to BLUE
    cat > $NGINX_CONF << CONF
upstream app_frontend {
    server ${BLUE_IP}:3000;       # BLUE frontend — active
    # server ${GREEN_IP}:3000;    # GREEN frontend — inactive
}
upstream app_backend_api {
    server ${BLUE_IP}:4000;       # BLUE backend API — active
    # server ${GREEN_IP}:4000;    # GREEN backend API — inactive
}
CONF
    echo "blue" | sudo tee /opt/current-env > /dev/null
    echo "Traffic switched to BLUE (${BLUE_IP})"

elif [ "$TARGET" = "green" ]; then
    # Write new upstream.conf pointing to GREEN
    cat > $NGINX_CONF << CONF
upstream app_frontend {
    # server ${BLUE_IP}:3000;     # BLUE frontend — inactive
    server ${GREEN_IP}:3000;      # GREEN frontend — active
}
upstream app_backend_api {
    # server ${BLUE_IP}:4000;     # BLUE backend API — inactive
    server ${GREEN_IP}:4000;      # GREEN backend API — active
}
CONF
    echo "green" | sudo tee /opt/current-env > /dev/null
    echo "Traffic switched to GREEN (${GREEN_IP})"
fi

# Validate nginx config before reloading
# If config is invalid, nginx will NOT reload — current traffic unaffected
nginx -t && systemctl reload nginx

if [ $? -eq 0 ]; then
    echo "Nginx reloaded successfully"
    echo "[$TARGET] $(date)" >> /var/log/nginx/switches.log
else
    echo "Nginx reload failed — check config"
    exit 1
fi


# ============================================================
# COMPONENT 4 — ANSIBLE PLAYBOOKS
# ============================================================
#
# The deployment is split into four separate Ansible playbooks,
# each called as a separate GitHub Actions job.
# This gives full visibility in the pipeline — each step is
# clearly visible in the GitHub Actions UI.
#
# proxmox-silverbank/ansible/playbooks/
#   deploy-idle.yml      — deploy new image to idle VM
#   smoke-tests.yml      — test idle VM directly (bypass nginx)
#   switch-traffic.yml   — switch nginx traffic to idle VM
#   rollback.yml         — monitor 10 min + auto-rollback if unhealthy


# ── deploy-idle.yml ──────────────────────────────────────────
#
# Deploys the new Docker image to whichever VM is currently idle.
# Traffic is still flowing to the active environment — zero user impact.
#
# Key decisions:
# - docker system prune -f before pulling: prevents disk space issues
#   on long-running VMs (does NOT remove active containers)
# - docker compose down before up: removes old containers cleanly
# - wait_for port 4000/3000: ensures containers are actually listening
#   before marking deployment as complete

- name: Deploy to idle environment
  hosts: "{{ 'prod-vm1-BLUE' if idle_env == 'blue' else 'prod-vm2-GREEN' }}"
  # idle_env is passed from GitHub Actions: -e "idle_env=blue"
  # This dynamically selects which VM to target
  become: true
  vars:
    app_dir: /opt/app
    app_tag: "{{ app_tag | default('latest') }}"
    deploy_env: "{{ idle_env }}"   # passed to .env as DEPLOY_ENV

  tasks:
    - name: Create app directory
      # Ensures /opt/app exists with correct ownership
      # idempotent — safe to run multiple times

    - name: Deploy .env file
      # Writes secrets and config to /opt/app/.env
      # mode 0600 — only the docker user can read it
      # Contains: DATABASE_URL, JWT_SECRET, DEPLOY_ENV, IMAGE_TAG

    - name: Copy docker-compose.prod.yml
      # Production compose file uses APP network IPs for DB
      # Does NOT include a DB service — uses dedicated DB VM

    - name: Login to GitHub Container Registry
      # Authenticates with ghcr.io to pull private images
      # Uses vault_ghcr_token (encrypted in Ansible Vault)

    - name: Stop existing containers
      # docker compose down --remove-orphans
      # Stops and removes old containers including renamed ones
      # ignore_errors: true — safe if nothing is running

    - name: Clean up unused Docker images
      # docker system prune -f
      # Removes dangling images and stopped containers
      # Prevents disk space exhaustion on long-running VMs
      # Does NOT remove images used by running containers

    - name: Pull new images
      # docker compose pull
      # Pulls frontend and backend images with the new tag
      # Runs BEFORE starting containers to avoid startup delays

    - name: Start frontend + backend containers
      # docker compose up -d
      # Starts both containers in detached mode
      # ENV vars passed: APP_TAG, DB_USER, DB_PASSWORD, DB_HOST, etc.

    - name: Wait for backend to be ready
      # wait_for port 4000 — ensures backend is actually listening
      # delay: 10s, timeout: 90s

    - name: Wait for frontend to be ready
      # wait_for port 3000 — ensures frontend is actually listening
      # delay: 5s, timeout: 60s


# ── smoke-tests.yml ──────────────────────────────────────────
#
# Runs health checks DIRECTLY on the idle VM, bypassing nginx.
# This means if smoke tests fail, NO traffic switch occurs.
# Users on the active environment are completely unaffected.
#
# The test hits the backend health endpoint which verifies:
#   - The Express server is running
#   - The database connection is alive
#   - Returns: {"status":"ok","database":"connected","environment":"blue"}

- name: Smoke tests on idle environment
  hosts: edge-nginx
  # Runs FROM edge-nginx because it has access to the APP network (10.10.20.x)
  # The idle VMs are only accessible from the APP network, not directly from LAN
  become: true
  tasks:

    - name: Set idle IP
      # Determines the APP network IP of the idle VM
      # blue → 10.10.20.11, green → 10.10.20.12
      set_fact:
        idle_ip: "{{ blue_app_ip if idle_env == 'blue' else green_app_ip }}"

    - name: Smoke test — backend health check
      # Hits http://10.10.20.11:4000/api/health (if idle=blue)
      # retries: 5, delay: 10s — gives containers time to stabilize
      # If this fails → playbook fails → no traffic switch → pipeline fails
      uri:
        url: "http://{{ idle_ip }}:4000/api/health"
        status_code: 200
      retries: 5
      delay: 10

    - name: Smoke test passed
      # Logs which environment passed and confirms DB connection
      debug:
        msg: "Smoke test passed on {{ idle_env }} - DB: {{ smoke.json.database }}"


# ── switch-traffic.yml ───────────────────────────────────────
#
# Calls /opt/switch-backend.sh on the edge-nginx VM.
# This rewrites upstream.conf and reloads nginx.
# The traffic switch itself takes milliseconds.
# From this point, the new environment is LIVE.

- name: Switch nginx traffic to new environment
  hosts: edge-nginx
  become: true
  tasks:

    - name: Switch traffic to new environment
      # Runs: /opt/switch-backend.sh blue (or green)
      # Script: rewrites upstream.conf + nginx -t + systemctl reload nginx
      # nginx reload is GRACEFUL — in-flight requests complete normally
      command: "/opt/switch-backend.sh {{ idle_env }}"

    - name: Confirm traffic switch
      debug:
        msg: "Traffic switched to {{ idle_env }}"


# ── rollback.yml ─────────────────────────────────────────────
#
# The most critical playbook — monitors the new environment for 10 minutes.
# Checks health every 30 seconds.
# If 3 CONSECUTIVE failures occur → auto-rollback to previous environment.
# If 10 minutes pass without failure → promote image to :latest.
#
# Why 3 consecutive failures (not total)?
# A single failed health check could be a momentary blip (network, GC pause).
# Requiring 3 in a row avoids false positives while still catching real issues.
#
# Why 10 minutes?
# Long enough to catch startup issues, memory leaks, and slow DB queries.
# Short enough to not delay the pipeline excessively.
#
# Why promote to :latest after success?
# The :latest tag is used by AWS DR to always pull the most recent
# stable version. It is NEVER applied before health check passes.

- name: Monitor and auto rollback if needed
  hosts: edge-nginx
  become: true
  vars:
    monitor_duration: 600    # 600 seconds = 10 minutes
    check_interval: 30       # check every 30 seconds = 20 checks total
    max_failures: 3          # rollback after 3 consecutive failures

  tasks:
    - name: Monitor new environment
      block:
        # The monitoring loop — runs on edge-nginx via shell
        # Checks http://localhost/api/health (goes through nginx → active env)
        - name: Run health checks for {{ monitor_duration }}s
          shell: |
            failures=0
            elapsed=0

            while [ $elapsed -lt {{ monitor_duration }} ]; do
              if curl -sf http://localhost/api/health > /dev/null 2>&1; then
                echo "[OK] [$elapsed s] Health check passed"
                failures=0                          # reset on success
              else
                failures=$((failures + 1))
                echo "[FAIL] [$elapsed s] Health check failed ($failures/{{ max_failures }})"

                if [ $failures -ge {{ max_failures }} ]; then
                  echo "ROLLBACK_NEEDED"
                  exit 1                            # triggers rescue block
                fi
              fi

              sleep {{ check_interval }}
              elapsed=$((elapsed + {{ check_interval }}))
            done

            echo "Monitoring complete — deployment stable"

        # Only reached if monitoring loop completes without failure
        - name: Promote image to :latest
          # Uses docker buildx imagetools create to retag without pulling/pushing layers
          # This is efficient — only metadata is updated in the registry
          # :latest is now available for AWS DR to pull
          shell: |
            echo "{{ vault_ghcr_token }}" | docker login ghcr.io -u mariusiordan --password-stdin

            docker buildx imagetools create \
              -t ghcr.io/mariusiordan/silverbank-frontend:latest \
              ghcr.io/mariusiordan/silverbank-frontend:{{ app_tag }}

            docker buildx imagetools create \
              -t ghcr.io/mariusiordan/silverbank-backend:latest \
              ghcr.io/mariusiordan/silverbank-backend:{{ app_tag }}

            echo "Promoted {{ app_tag }} to :latest — AWS DR ready"

      rescue:
        # Only triggered if the monitoring shell script exits with code 1
        # i.e., 3 consecutive health check failures

        - name: Auto-rollback to previous environment
          # Runs switch-backend.sh with the PREVIOUS (now stable) environment
          # This reverts nginx upstream config instantly
          command: "/opt/switch-backend.sh {{ previous_env }}"

        - name: Confirm rollback
          debug:
            msg: "Rolled back to {{ previous_env }} — :latest NOT updated"

        - name: Fail the pipeline
          # Marks the GitHub Actions job as failed
          # The team is notified, :latest remains the previous stable version
          # AWS DR will continue running the previous stable image
          fail:
            msg: "Deployment failed — rolled back to {{ previous_env }}"


# ============================================================
# COMPONENT 5 — GITHUB ACTIONS PIPELINE
# ============================================================
#
# File: .github/workflows/deploy.yml  (in SilverBank-App repo)
#
# Each Ansible playbook is called as a SEPARATE GitHub Actions job.
# This gives full visibility — every step is clearly labelled
# and can be inspected independently if something fails.
#
# Job flow:
#
#   promote-image
#   (retag :staging → :prod-{date}-sha-{sha}, no rebuild)
#       │
#       ▼
#   Manual Approval ⏳
#   (release manager reviews in GitHub Environments)
#       │
#       ▼
#   Detect Active Environment
#   (SSH to edge → cat /opt/current-env → output active + idle)
#       │
#       ▼
#   Deploy to Idle Environment
#   (ansible-playbook deploy-idle.yml -e idle_env=blue/green)
#       │
#       ▼
#   Smoke Tests
#   (ansible-playbook smoke-tests.yml -e idle_env=blue/green)
#       │
#       ▼
#   Switch Traffic + Monitor + Rollback
#   (switch-traffic.yml → rollback.yml)
#       │
#       ▼
#   Update AWS DR (if active)
#   (detect edge IP from Terraform S3 state → pull :latest → redeploy)
#
#
# Why promote-image instead of rebuild?
# The image was already BUILT and TESTED in the staging pipeline.
# Rebuilding from the same commit would produce an identical image.
# Promoting (retagging) guarantees we deploy EXACTLY what was tested.
#
# Why detect-environment as a separate job?
# The active/idle state is read at deploy time, not hardcoded.
# This ensures the pipeline always deploys to the correct idle VM,
# regardless of what happened in previous runs.
#
# Why use job outputs to pass active/idle env between jobs?
# GitHub Actions jobs run on separate runners.
# outputs: is the correct mechanism to share data between jobs.
# The detect-environment job sets:
#   active_env: blue (or green)
#   idle_env:   green (or blue)
# Subsequent jobs read these via: ${{ needs.detect-environment.outputs.idle_env }}


# ============================================================
# COMPLETE DEPLOYMENT FLOW — STEP BY STEP
# ============================================================
#
# This is what happens when a developer merges a PR to main:
#
# T+0:00  Push to main triggers deploy.yml
#
# T+0:01  promote-image job starts
#         - Generates tag: v1.0-prod-2026-03-22-sha-abc1234
#         - Retags :staging image with production tag (no rebuild)
#         - Logs source and target image names
#
# T+0:30  Manual Approval gate appears in GitHub
#         - Release manager reviews the PR, checks staging results
#         - Clicks "Approve" in GitHub Environments
#
# T+0:31  detect-environment job starts (self-hosted runner)
#         - SSH to 192.168.7.50: cat /opt/current-env → "green"
#         - Sets: active_env=green, idle_env=blue
#
# T+0:32  deploy-to-idle job starts
#         - Targets prod-vm1-BLUE (192.168.7.101)
#         - Stops existing containers
#         - Prunes unused Docker images
#         - Pulls new images: silverbank-frontend:v1.0-prod-..., silverbank-backend:v1.0-prod-...
#         - Starts new containers
#         - Waits for port 4000 (backend) and port 3000 (frontend)
#
# T+1:30  smoke-tests job starts
#         - Runs FROM edge-nginx
#         - curl http://10.10.20.11:4000/api/health (BLUE direct, bypass nginx)
#         - Response: {"status":"ok","database":"connected","environment":"blue"}
#         - Smoke test passed — no user impact during this entire phase
#
# T+1:45  switch-traffic job starts
#         - Runs /opt/switch-backend.sh blue on edge-nginx
#         - Rewrites /etc/nginx/conf.d/upstream.conf
#         - nginx -t validates config
#         - systemctl reload nginx — graceful reload, zero downtime
#         - Writes "blue" to /opt/current-env
#         - GREEN remains running as instant fallback
#
# T+1:46  switch-monitor-rollback job starts
#         - Monitors http://localhost/api/health every 30 seconds
#         - For 10 minutes (600 seconds = 20 checks)
#
#         If checks pass for 10 minutes:
#           T+11:46  Promotes v1.0-prod-2026-03-22-sha-abc1234 → :latest
#                    AWS DR will pull this on next deployment
#           T+11:47  Pipeline succeeds ✅
#
#         If 3 consecutive checks fail:
#           T+X:XX   Runs /opt/switch-backend.sh green (rollback)
#                    nginx points back to GREEN immediately
#                    :latest NOT updated — remains previous stable version
#                    Pipeline fails ❌ — team notified
#
# T+11:48  aws-update job starts
#          - Checks if AWS DR is active: curl http://{edge_ip}/api/health
#          - If active: reads IPs from Terraform S3 state
#                       generates inventory-aws.ini dynamically
#                       ansible-playbook deploy-production.yml -e app_tag=latest
#                       health check on AWS DR
#          - If not active: skips silently


# ============================================================
# ROLLBACK SCENARIOS
# ============================================================
#
# Scenario 1: Smoke tests fail
#   → Pipeline stops at smoke-tests job
#   → No traffic switch occurs
#   → Users on GREEN (active) are completely unaffected
#   → Fix the issue and redeploy
#
# Scenario 2: Health checks fail after traffic switch
#   → rollback.yml detects 3 consecutive failures
#   → Automatically runs /opt/switch-backend.sh green
#   → Traffic reverts to GREEN in milliseconds
#   → Pipeline fails, team is notified
#   → :latest NOT updated — AWS DR keeps previous stable version
#
# Scenario 3: Manual rollback (any time)
#   → SSH to edge-nginx
#   → sudo /opt/switch-backend.sh green
#   → Done — takes ~2 seconds
#
# ============================================================
# RECOVERY TIMES (RTO)
# ============================================================
#
#   Auto-rollback (health check failure)  → ~1-3 minutes
#   Manual rollback (switch-backend.sh)   → ~5 seconds
#   Blue VM completely down               → switch-backend.sh green → ~5 seconds
#   Green VM completely down              → switch-backend.sh blue  → ~5 seconds
#   Edge nginx down                       → start VM from Proxmox UI → ~2 minutes
#   Full Proxmox failure                  → activate AWS DR → ~15 minutes