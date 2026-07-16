# SilverBank — DevOps Infrastructure

Two implementations of a production-grade CI/CD platform for the SilverBank
3-tier banking application (Next.js + Express/Prisma + PostgreSQL), built with
Terraform, Ansible, Docker, and GitHub Actions.

## Projects

### 🏠 [`proxmox-silverbank/`](./proxmox-silverbank/)
The original homelab implementation on Proxmox — 5 VMs, Blue/Green deployment
via nginx, self-hosted runner, Prometheus/Grafana monitoring, and AWS as a
disaster-recovery target. **This is the accredited final project.**

### ☁️ [`aws-silverbank/`](./aws-silverbank/)
A cloud-native evolution on AWS — the same application deployed to a 5-VM EC2
environment with a production-grade CI/CD pipeline: GitHub-hosted runners,
SSM-based deploys (no open SSH ports), OIDC authentication (no static keys),
and Blue/Green traffic switching.

## Tech Stack

Terraform · Ansible · Docker · GitHub Actions · GHCR · Nginx · PostgreSQL ·
Prometheus · Grafana · AWS (EC2, VPC, S3, IAM, SSM)

---

*Application repository: [SilverBank-App](https://github.com/mariusiordan/SilverBank-App)*
