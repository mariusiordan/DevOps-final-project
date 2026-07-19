# SilverBank — DevOps Infrastructure

Two implementations of a CI/CD platform for the SilverBank three-tier banking
application (Next.js · Express/Prisma · PostgreSQL), built with Terraform, Ansible,
Docker, and GitHub Actions.

The second builds on the first: same application, same core ideas, rebuilt on AWS with
the parts that would not survive a security review replaced.

> 📖 Each project folder contains its own detailed documentation — open the folder to read it.

## Projects

### 🏠 [`proxmox-silverbank/`](./proxmox-silverbank/)

The original homelab implementation on Proxmox — 5 VMs, Blue/Green deployment behind
nginx, three GitHub Actions pipelines driven by a self-hosted runner, Prometheus and
Grafana monitoring, and AWS as a disaster-recovery target.

**This is the accredited final project**, submitted for a DevOps programme at
Școala Informală de IT. The folder includes the full written report.

### ☁️ [`aws-silverbank/`](./aws-silverbank/)

The AWS evolution — the same application on a 5-instance EC2 environment, with the
deployment and security model rebuilt from scratch:

- **No inbound SSH.** Deployments reach private instances through AWS Systems Manager.
- **No long-lived credentials.** GitHub Actions authenticates via OIDC; credentials
  expire in an hour and are restricted to specific branches.
- **Isolated staging.** A complete three-tier stack with its own database, validated by
  integration tests against the live API before anything is promoted.
- **Build once, deploy many.** The image that reaches production is byte-for-byte the one
  that passed the staging tests — promotion is a retag, never a rebuild.
- **Guarded releases.** Manual approval, an automatic database backup, Blue/Green
  traffic switching, health monitoring, and automatic rollback.

📄 [Documentation](./aws-silverbank/README.md) ·
🔧 [Commands & troubleshooting](./aws-silverbank/COMMANDS-AWS.md)

## Tech stack

Terraform · Ansible · Docker · GitHub Actions · GHCR · nginx · PostgreSQL ·
Prometheus · Grafana · Loki · AWS (EC2, VPC, IAM, S3, SSM)

## Application repositories

The infrastructure lives here; the application code and workflow definitions live
alongside each implementation:

| Implementation | Application repository |
|---|---|
| Proxmox | [SilverBank-App](https://github.com/mariusiordan/SilverBank-App) |
| AWS | [SilverBank-AWS](https://github.com/mariusiordan/SilverBank-AWS) |
