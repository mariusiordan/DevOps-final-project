# SilverBank AWS — Commands & Troubleshooting

An operator's reference for the AWS platform: the commands used day to day, and every
failure encountered while building it — what the error text looks like, what it actually
means, and how to recognise the same class of problem next time.

The troubleshooting entries are written so you can search for the error string. If
something breaks, `Ctrl+F` the message.

---

## Contents

- [Daily workflow](#daily-workflow)
- [Terraform](#terraform)
- [Ansible over SSM](#ansible-over-ssm)
- [AWS CLI](#aws-cli)
- [Docker on the hosts](#docker-on-the-hosts)
- [Blue/Green operations](#bluegreen-operations)
- [Database backup and restore](#database-backup-and-restore)
- [Git workflow](#git-workflow)
- [Pipeline operations](#pipeline-operations)
- [Troubleshooting](#troubleshooting)
- [Shell patterns worth knowing](#shell-patterns-worth-knowing)

---

## Daily workflow

The infrastructure is destroyed between sessions to control cost. A session looks like this:

```bash
# ── Start ────────────────────────────────────────────────────
cd aws-silverbank/terraform

curl https://checkip.amazonaws.com          # has your address changed?
grep your_home_ip terraform.tfvars          # update with /32 if so

terraform apply                             # ~10 minutes

cd ../ansible
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
# regenerate the SSM inventory (see below) — instance IDs are new
ansible all -i inventory-ssm.ini -m ping    # expect 5 × pong
ansible-playbook playbooks/site.yml -i inventory-ssm.ini

# ── End ──────────────────────────────────────────────────────
ansible db -i inventory-ssm.ini -m shell -a "/opt/backup-db.sh"
cd ../terraform && terraform destroy
```

> **Never skip the backup.** `terraform destroy` deletes the EBS volume that holds the
> database. The S3 backup is the only way back.

---

## Terraform

```bash
cd aws-silverbank/terraform

terraform init                  # first run, or after adding a provider
terraform validate              # syntax check, no AWS calls, instant
terraform plan                  # preview without changing anything
terraform apply                 # create or update
terraform destroy               # remove everything

terraform output                          # all outputs
terraform output -raw edge_elastic_ip     # one value, no quotes
terraform state list                      # everything Terraform manages
terraform state list | grep ssm           # filter
```

### Reading a plan

The symbol in front of each resource is the whole message:

| Symbol | Meaning | When to worry |
|---|---|---|
| `+` | create | Fine |
| `~` | update in place | Fine — the resource survives |
| `-` | destroy | Check what it is |
| `-/+` | **destroy and recreate** | **Stop.** On an instance this wipes it. |

Attaching an IAM instance profile to a running instance is `~`. If you ever see `-/+`
on an `aws_instance` when you only meant to change a role, stop and work out why.

### Useful patterns

```bash
# Confirm a string appears exactly once before running sed against it
grep -c "vpc_security_group_ids = \[aws_security_group.app.id\]" main.tf

# Which instances have an instance profile attached?
grep -n "iam_instance_profile" main.tf     # expect 5 lines
```

---

## Ansible over SSM

### The macOS prerequisite

```bash
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
```

Required before every Ansible command on macOS. Without it Ansible crashes with
`A worker was found in a dead state` and a "Python quit unexpectedly" dialog. Not needed
on Linux, which is why the CI runners do not set it.

Add it to `~/.zshrc` to stop thinking about it.

### Regenerate the inventory

Instance IDs change on every `terraform apply`. This is the single most common cause of
"it worked yesterday".

```bash
cd aws-silverbank/ansible

get_id() {
  aws ec2 describe-instances --region eu-west-2 \
    --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text
}

cat > inventory-ssm.ini << EOF
[edge]
edge-nginx ansible_aws_ssm_instance_id=$(get_id edge-nginx)

[prod]
prod-vm1-BLUE ansible_aws_ssm_instance_id=$(get_id prod-vm1-BLUE)
prod-vm2-GREEN ansible_aws_ssm_instance_id=$(get_id prod-vm2-GREEN)

[db]
db-postgresql ansible_aws_ssm_instance_id=$(get_id db-postgresql)

[monitoring]
monitoring-staging ansible_aws_ssm_instance_id=$(get_id monitoring-staging)

[all:vars]
ansible_connection=community.aws.aws_ssm
ansible_aws_ssm_region=eu-west-2
ansible_aws_ssm_bucket_name=silverbank-ssm-transfer-mariusiordan
ansible_python_interpreter=/usr/bin/python3
ansible_remote_tmp=/tmp/.ansible-tmp
ansible_aws_ssm_document_name=AWS-StartNonInteractiveCommand
ansible_become=true
EOF
```

Note the heredoc uses `<< EOF`, **not** `<< 'EOF'` — the quotes would stop `$(get_id ...)`
from being evaluated and you would write the literal text into the file.

### What each inventory setting does

| Setting | Why it is there |
|---|---|
| `ansible_connection=community.aws.aws_ssm` | Use SSM instead of SSH. The switch that makes all of this work. |
| `ansible_aws_ssm_instance_id` | SSM addresses hosts by instance ID, not IP |
| `ansible_aws_ssm_bucket_name` | The plugin stages files through S3 |
| `ansible_remote_tmp=/tmp/.ansible-tmp` | The SSM session cannot write to `/home/ubuntu` |
| `ansible_aws_ssm_document_name` | Non-interactive session — more reliable for automation |
| `ansible_become=true` | Run as root; `ssm-user` has no Docker access |

### Everyday commands

```bash
ansible all -i inventory-ssm.ini --list-hosts    # no connection, just parse
ansible all -i inventory-ssm.ini -m ping         # real connectivity test

# Run a command on a group
ansible prod -i inventory-ssm.ini -m shell -a "docker ps"
ansible prod:db -i inventory-ssm.ini -m shell -a "df -h /"   # ':' means "or"

# One host only
ansible -i inventory-ssm.ini prod-vm2-GREEN -m shell -a "uptime"

# Copy a file to a host
ansible monitoring -i inventory-ssm.ini -m copy \
  -a "src=./script.sh dest=/tmp/script.sh mode=0755"

# Playbooks
ansible-playbook playbooks/site.yml -i inventory-ssm.ini
ansible-playbook playbooks/deploy-production.yml -i inventory-ssm.ini --limit prod-vm2-GREEN
ansible-playbook playbooks/deploy-staging.yml -i inventory-ssm.ini
ansible-playbook playbooks/deploy-monitoring.yml -i inventory-ssm.ini

# Dry run and verbose
ansible-playbook playbooks/site.yml -i inventory-ssm.ini --check
ansible-playbook playbooks/site.yml -i inventory-ssm.ini -vvv
```

### Vault

```bash
ansible-vault view   group_vars/all/vault.yml
ansible-vault edit   group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml
```

`ansible.cfg` points at `~/.vault-password`, which is why every CI job that runs any
Ansible command must write that file first — even a command that needs no secrets.

---

## AWS CLI

### SSM

```bash
# Which instances are reachable?
aws ssm describe-instance-information --region eu-west-2 \
  --query 'InstanceInformationList[].[InstanceId,PingStatus]' --output table

# Count them — quick to read, quick to communicate
aws ssm describe-instance-information --region eu-west-2 \
  --query 'InstanceInformationList[].InstanceId' --output text | wc -w

# Run a command without Ansible (asynchronous: send, then fetch the result)
CMD=$(aws ssm send-command --region eu-west-2 \
  --instance-ids i-0abc123 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["hostname && whoami"]' \
  --query 'Command.CommandId' --output text)

aws ssm get-command-invocation --region eu-west-2 \
  --command-id "$CMD" --instance-id i-0abc123 \
  --query 'StandardOutputContent' --output text

# Interactive shell on a private instance
aws ssm start-session --region eu-west-2 --target i-0abc123

# Port-forward a private service to localhost
aws ssm start-session --region eu-west-2 --target i-0abc123 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3001"],"localPortNumber":["3001"]}'
```

Port forwarding is how you reach Grafana (`3001`), Prometheus (`9090`) and Loki (`3100`)
without opening a single port.

### EC2

```bash
# Instance IDs by tag
aws ec2 describe-instances --region eu-west-2 \
  --filters "Name=tag:Name,Values=edge-nginx" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text

# All of them, name and ID
aws ec2 describe-instances --region eu-west-2 \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId]' \
  --output text
```

`Reservations[0].Instances[0]` returns a plain string. `Reservations[].Instances[]`
returns a list — use the first form when assigning to a variable.

### S3

```bash
aws s3 ls s3://silverbank-tfstate-mariusiordan/db-backups/
aws s3 ls s3://silverbank-ssm-transfer-mariusiordan/
aws s3 cp s3://silverbank-tfstate-mariusiordan/db-backups/backup_xxx.sql .
```

### Identity

```bash
aws sts get-caller-identity     # which credentials am I actually using?
```

Useful when a permission error makes no sense — you may be authenticated as someone else.

---

## Docker on the hosts

```bash
ansible prod -i inventory-ssm.ini -m shell -a "docker ps"
ansible prod -i inventory-ssm.ini -m shell -a "docker logs --tail 50 silverbank-backend"
ansible prod -i inventory-ssm.ini -m shell -a "cd /opt/app && docker compose ps"

# Reclaim disk space (conservative: stopped containers, dangling images)
ansible prod:db -i inventory-ssm.ini -m shell \
  -a "docker container prune -f; docker image prune -f; df -h / | tail -1"
```

> `docker system prune -a` also removes images not used by a **running** container.
> On a host where you have just stopped the stack, that includes images you are about to
> need. Prefer the two narrower commands.

Compose scopes commands by project, and the project name defaults to the directory name.
A `docker compose down` run in `/opt/staging` cannot touch containers started from
`/opt/monitoring`.

---

## Blue/Green operations

```bash
# Which colour is serving traffic? The uncommented line wins.
ansible edge -i inventory-ssm.ini -m shell \
  -a "grep -E '^\s*server' /etc/nginx/conf.d/upstream.conf"

# Switch
ansible edge -i inventory-ssm.ini -m shell -a "/opt/switch-backend.sh green"
ansible edge -i inventory-ssm.ini -m shell -a "/opt/switch-backend.sh blue"

# Health through the edge
ansible edge -i inventory-ssm.ini -m shell -a "curl -s http://localhost/api/health"

# From your machine
curl -s http://$(cd ../terraform && terraform output -raw edge_elastic_ip)/api/health \
  | python3 -m json.tool
```

The health payload reports `environment` and `image_tag`, so you can always tie what
users are seeing back to a specific commit.

### The detection logic

```bash
grep -E '^\s*server.*:3000' /etc/nginx/conf.d/upstream.conf | grep -ioE 'blue|green'
```

`^\s*server` matches a line that *starts* with `server`, optionally indented. A commented
line starts with `#`, so it never matches — which is the entire mechanism.

---

## Database backup and restore

```bash
# Back up (always before destroy, and automatically before every production deploy)
ansible db -i inventory-ssm.ini -m shell -a "/opt/backup-db.sh"

# List backups
aws s3 ls s3://silverbank-tfstate-mariusiordan/db-backups/

# Restore
ansible db -i inventory-ssm.ini -m shell -a "/opt/restore-db.sh <backup-file>"
```

The backup script reads the database credentials from the running container
(`docker exec postgres printenv POSTGRES_USER`) rather than hardcoding them, so it stays
correct whatever Ansible and Vault configured. Backups are named with a timestamp and
the deployed image tag, and expire after 30 days via an S3 lifecycle rule.

---

## Git workflow

Three long-lived branches: `development` → `staging` → `main`.

```bash
# Work
git switch development
# ... changes ...
git add -A
git commit -m "feat(scope): what changed"
git push

# Promote to staging (opens CD — Staging Deployment on merge)
# PR: development → staging

# Release (opens CD — Production Deployment on merge)
# PR: staging → main
```

`main` is protected: no direct pushes, PR required, all CI checks must pass.

### Commands that come up

```bash
git branch --show-current            # where am I?
git branch -a                        # local and remote
git status                           # what is uncommitted?
git log --oneline -5
git log origin/main --oneline -1     # what does the remote have?

cd "$(git rev-parse --show-toplevel)"   # jump to the repository root

git mv old.yml new.yml               # rename, tracked in one step
git rm -r folder/                    # delete and stage in one step
git add -A                           # stage everything, wherever you are
```

`git mv` and `git rm` are worth the habit: plain `mv`/`rm` leave Git to infer what
happened, and `git mv` in particular records a rename so history follows the file.

### Resolving a merge conflict

```
<<<<<<< HEAD
version on the branch you are on
=======
version from the branch you are merging
>>>>>>> other-branch
```

Delete the markers, keep the version you want, then:

```bash
git add <file>
git commit
```

Not every conflict is a real disagreement. Two forms of the same YAML —
`branches: [main, staging]` versus a block list — conflict textually but mean the same
thing. Read both before deciding.

---

## Pipeline operations

### Running a workflow manually

Actions → the workflow → **Run workflow** → **pick the branch**.

The branch selector defaults to `main`. If your fix is on a feature branch and you do not
change it, you are testing the old code — a mistake that is easy to make twice.

### What each pipeline needs

| Pipeline | Trigger | Requires |
|---|---|---|
| CI | PR → `staging` / `main` | nothing external |
| CD Staging | push → `staging` | infrastructure running |
| CD Production | push → `main` | infrastructure running + approval |

### Secrets

Only one remains in the application repository:

| Secret | Purpose |
|---|---|
| `VAULT_PASSWORD` | Decrypts `group_vars/all/vault.yml` (database and GHCR credentials) |

`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` were removed when OIDC replaced them.

### Confirming OIDC is in use

Look at the `env` block of any step in the job log:

```
AWS_ACCESS_KEY_ID: ***
AWS_SECRET_ACCESS_KEY: ***
AWS_SESSION_TOKEN: ***        ← temporary credentials
```

`AWS_SESSION_TOKEN` is only present with federated or assumed-role credentials. A static
IAM user key has no session token.

---

## Troubleshooting

### `TargetNotConnected: i-0abc123 is not connected`

**Where:** any Ansible command over SSM.

**Cause:** almost always a stale inventory. The infrastructure was destroyed and
recreated, so every instance ID changed. Occasionally the SSM agent has not registered yet.

**Fix:**

```bash
# Is that ID even alive?
aws ssm describe-instance-information --region eu-west-2 \
  --query 'InstanceInformationList[].InstanceId' --output text

grep <name> inventory-ssm.ini
```

If the ID is missing from the list, regenerate the inventory. If the list is short right
after an apply, wait — registration takes two to five minutes.

**Recognising it:** an instance ID in the error that does not appear in the live list.
This is why the pipelines rebuild the inventory on every run.

---

### `The vault password file /home/runner/.vault-password was not found`

**Where:** any CI job running an Ansible command.

**Cause:** `ansible.cfg` declares `vault_password_file = ~/.vault-password`, and Ansible
tries to read it at **startup** — regardless of whether the task needs a secret. A job
that only copies a file still fails.

**Fix:** every job that invokes Ansible needs the vault step:

```yaml
- name: Provide Ansible Vault password
  run: |
    echo "${{ secrets.VAULT_PASSWORD }}" > $HOME/.vault-password
    chmod 600 $HOME/.vault-password
```

**Recognising it:** the error names a path you did not set. That means a config file set
it — look in `ansible.cfg`.

---

### `permission denied while trying to connect to the docker API`

**Where:** Ansible tasks that run Docker, over SSM.

**Cause:** the task carries `become_user: "{{ docker_user }}"`. Over SSH as `ubuntu` that
was fine — `ubuntu` is in the `docker` group. An SSM session starts as `ssm-user`, and
stepping down to `ubuntu` from there loses socket access.

**Fix:** remove the line and let the task run as root (inherited from `become: true`).

```bash
sed -i '' '/become_user: "{{ docker_user }}"/d' roles/<role>/tasks/main.yml
```

Beyond fixing the error, this makes the playbook portable: the same file now works over
SSH and over SSM, because it no longer assumes which user the connection lands as.

**Recognising it:** `become_user` on a Docker task is a red flag whenever the connection
method changes.

---

### `mkdir: cannot create directory '/home/ubuntu': Permission denied`

**Where:** the first Ansible run over SSM.

**Cause:** Ansible stages temporary files in the connecting user's home directory. Over
SSM that user is `ssm-user`, which has no home at `/home/ubuntu`.

**Fix:** in the inventory:

```ini
ansible_remote_tmp=/tmp/.ansible-tmp
```

`/tmp` is writable by everyone, so the assumption disappears. The error text suggests
this fix itself — worth reading errors to the end.

---

### `A worker was found in a dead state` (plus "Python quit unexpectedly")

**Where:** Ansible on macOS.

**Cause:** a long-standing interaction between macOS process forking and the libraries
boto3 loads.

**Fix:**

```bash
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
```

Not a code problem — the same playbook runs cleanly on the Linux CI runners.

---

### `Syntax error in template: unexpected '.'`

**Where:** an ad-hoc command containing `{{ }}`.

**Cause:** Ansible treats `{{ ... }}` as its own template syntax and tries to evaluate it.
`docker ps --format '{{.Names}}'` is Go template syntax, and the two collide.

**Fix:** avoid the braces, or escape them:

```bash
# instead of --format '{{.Names}}'
ansible prod -i inventory-ssm.ini -m shell -a "docker ps"
```

**Recognising it:** an Ansible error about templating in a command you thought was plain
shell means something in that command looks like Jinja2.

---

### `go-yaml load error ... did not find expected ',' or ']'`

**Where:** `docker compose` on a host, after Ansible rendered a template.

**Cause:** the generated YAML is malformed. In this project a stray backslash had crept
into a template during a copy-paste:

```yaml
test: ["CMD", "curl", "-f", "http://localhost:4000/api/health"\]
                                                              ^^ breaks the array
```

**Fix:** read the **rendered** file on the host, not just the template. The error gives
you a line and column:

```bash
ansible monitoring -i inventory-ssm.ini -m shell \
  -a "sed -n '30,40p' /opt/staging/docker-compose.yml"
```

**Recognising it:** `L36.C13` is a coordinate. Go and look at it — the fault is usually
a single character.

---

### `'db_user' is undefined` / `'monitoring_ip' is undefined`

**Where:** an Ansible role, usually the first time it runs in CI.

**Two different causes:**

1. **Wrong group.** Variables in `group_vars/prod.yml` are visible only to hosts in the
   `prod` group. A role running against `monitoring` cannot see them.
2. **The file is not in Git.** `group_vars/all/main.yml` and `group_vars/prod.yml` are
   generated by Terraform (they hold current IPs) and are `.gitignore`d. They exist on
   your machine and never reach the runner.

**Fix:** put the variables where the running group can see them **and** where Git can
carry them — for staging, `group_vars/monitoring.yml`. Or remove the dependency
altogether, which is what happened with `monitoring_ip`: over SSM there was no need for
an IP at all.

```bash
git ls-files aws-silverbank/ansible/group_vars/all/    # what is actually tracked?
grep -n "group_vars" .gitignore
```

**Recognising it:** a variable that exists locally but is undefined in CI is almost
always in an ignored file.

---

### `403 Forbidden when calling the HeadBucket operation`

**Where:** Ansible over SSM, after switching to OIDC.

**Cause:** the SSM plugin calls `HeadBucket` to resolve the bucket's region. That is a
bucket-level call and carries no key prefix — so an IAM policy that scopes `s3:ListBucket`
with a `s3:prefix` condition denies it.

**Fix:** grant `s3:ListBucket` and `s3:GetBucketLocation` on the bucket without a prefix
condition.

**Recognising it:** a `403` on an operation whose name starts with `Head`, `Get...Bucket`
or `List` is usually a bucket-level call being blocked by a prefix condition.

---

### `AccessDenied: s3:DeleteObject on .../i-0abc123//tmp/.ansible-tmp/...`

**Where:** Ansible over SSM, under a least-privilege role.

**Cause:** read the path. The plugin writes to `<bucket>/<instance-id>/...`, not under
the prefix configured by `ansible_aws_ssm_bucket_prefix`. **That setting is ignored.**
A permissive IAM user had been hiding the fact all along.

**Fix:** a dedicated bucket for SSM transfers, so bucket-wide access is harmless. Do not
widen access on a bucket that holds Terraform state or database backups.

**Recognising it:** compare the path in the error with the path you expected. The
difference *is* the diagnosis.

---

### `remote: error: GH013: Repository rule violations found`

**Where:** `git push` to `main`.

**Cause:** branch protection is doing its job. Direct pushes are not allowed.

**Fix:** open a pull request. If you had already merged locally:

```bash
git reset --hard origin/main    # discard the local merge
# then PR the branch instead
```

**Recognising it:** this is not a bug. It is the rule you configured, working.

---

### `! [rejected] main -> main (non-fast-forward)`

**Cause:** the remote has commits you do not.

**Fix:**

```bash
git pull --no-rebase origin main
git push
```

---

### `fatal: Need to specify how to reconcile divergent branches`

**Cause:** both local and remote have moved independently. Git will not guess.

**Fix:**

```bash
git pull --no-rebase origin <branch>     # merge (safe: does not rewrite history)
git config pull.rebase false             # set it as the default for this repo
```

---

### `There is no tracking information for the current branch`

**Cause:** the local branch is not linked to a remote one.

**Fix:**

```bash
git push -u origin <branch>     # -u links them for next time
```

---

### `zsh: no matches found: --include=*.ts`

**Cause:** zsh expands `*` before the command sees it, and fails when nothing matches.
Bash silently passes the pattern through.

**Fix:** quote it.

```bash
grep -rn "router\." backend/src --include="*.ts"
```

---

### `zsh: command not found: warning:` (and a cascade of similar lines)

**Cause:** terminal output was pasted back into the terminal and each line was
interpreted as a command. Harmless noise.

**Fix:** `clear`, then run one command at a time.

---

### `ModuleNotFoundError: No module named 'yaml'`

**Cause:** a missing Python library, not a fault in the file you were checking.

**Fix:** `pip3 install pyyaml --break-system-packages`, or validate the YAML another way.

**Recognising it:** `ModuleNotFoundError` is always about the tool, never about the input.

---

### `Cannot connect to the Docker daemon at unix:///...`

**Cause:** Docker Desktop is not running.

**Fix:** start it and retry.

---

### `Error response from daemon: unauthorized` on `docker pull`

**Cause:** the GHCR package is private and you are not logged in.

**Fix:**

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <username> --password-stdin
```

The playbooks do this on each host using the token from Vault.

---

### GHCR returns 403 on the very first image push

**Cause:** the package does not exist yet, and Actions cannot create it in some
configurations.

**Fix (one time):** push the image manually from your machine, then in the package
settings link it to the repository and grant the repository the **Write** role. Automation
works from then on.

---

### The pipeline runs code you have already fixed

**The single most common time-waster in this project. It happened twice.**

**Two independent causes:**

1. **Fixed locally, not pushed.** Workflows run what is in the repository, not what is on
   your laptop.
2. **Fixed on the wrong branch.** Two sub-cases:
   - Workflow files: `workflow_dispatch` uses the branch chosen in the **Run workflow**
     dropdown, which defaults to `main`.
   - Ansible playbooks: the pipeline checks out the infrastructure repository's **default
     branch**. A fix sitting on a feature branch is invisible until it is merged to `main`.

**How to check:** read the job log. It prints the command it is running. If that text does
not match your local file, the runner has a different version.

```
Run echo "***" > /tmp/vault-pass        ← the old path
```

While the local file said `$HOME/.vault-password`. That one line was the whole diagnosis.

---

### `.github/workflow/` instead of `.github/workflows/`

**Symptom:** a workflow exists but never appears in the Actions tab.

**Cause:** GitHub reads only `.github/workflows/` — plural. A directory named `workflow`
is ignored entirely, with no warning.

**Fix:**

```bash
cp .github/workflow/x.yml .github/workflows/x.yml
rm -rf .github/workflow
```

---

### `fatal: pathspec '...' did not match any files`, with a doubled path

```
could not open directory 'aws-silverbank/ansible/aws-silverbank/ansible/roles/...'
                          ^^^^^^^^^^^^^^^^^^^^^^ doubled
```

**Cause:** you passed a repository-root path while standing in a subdirectory. Git paths
are relative to where you are.

**Fix:** use a relative path, or `git add -A`, or jump to the root first:

```bash
cd "$(git rev-parse --show-toplevel)"
```

---

### `--tags <name>` runs nothing

**Symptom:** `ok=2 changed=0` and the role you wanted never appears.

**Cause:** the roles have no tags defined, so the filter matches nothing.

**Fix:** run without `--tags`, or use a dedicated playbook that includes only the role you
want. The second is better over SSM anyway — `site.yml` includes the `common` role, whose
`meta: reset_connection` task is SSH-specific and breaks the SSM connection.

---

### `git stash` saved nothing

**Cause:** plain `git stash` does not include untracked files.

**Fix:** `git stash -u`, or commit first.

---

### Stuck in Vim after `git commit` or `git merge`

```
:wq     write and quit  (accept the message)
:q!     quit without saving (abort)
```

---

### The site does not open in a browser but `curl` works

**Cause:** the browser silently upgrades to HTTPS. There is no TLS on the edge instance.

**Fix:** type the scheme explicitly — `http://<ip>` — or use a private window to bypass
any cached HSTS state.

---

### Wrong repository

`SilverBank-App` (the Proxmox project) and `SilverBank-AWS` (this one) have similar names
and similar files. Half an hour disappeared into looking for the wrong pipelines in the
wrong clone.

```bash
pwd
git config --get remote.origin.url
```

When nothing matches your expectations, check where you are before checking anything else.

---

## Shell patterns worth knowing

The building blocks that appear throughout the playbooks and pipelines.

### Chaining

```bash
cmd1 && cmd2      # run cmd2 only if cmd1 succeeded (exit code 0)
cmd1 || cmd2      # run cmd2 only if cmd1 failed
cmd1 ; cmd2       # run both regardless
cmd1 | cmd2       # send cmd1's output into cmd2
```

`&&` and `||` test the **exit code**, not the output. That is why
`curl -sf url && echo ok` is a health check: `-f` makes curl exit non-zero on an HTTP error.

Useful for feedback:

```bash
terraform validate && echo "✅ config is valid"
grep -q "pattern" file || echo "⚠️  not found"
```

### Command substitution

```bash
EDGE=$(aws ec2 describe-instances ... --output text)
echo "Edge is $EDGE"
```

`$( ... )` runs the command and substitutes its output.

### Arithmetic

```bash
ELAPSED=$((ELAPSED + INTERVAL))
```

### Heredocs — and the one detail that matters

```bash
cat > file.txt << 'EOF'      # quoted: literal. $VAR stays as text.
$HOME is not expanded
EOF

cat > file.txt << EOF        # unquoted: expanded. $VAR becomes its value.
Instance: $EDGE
EOF
```

Getting this backwards writes `$EDGE` into your inventory instead of `i-0abc123`.
Check the result:

```bash
grep instance_id inventory-ssm.ini    # should show i-..., not $EDGE
```

### Functions

```bash
get_id() {
  aws ec2 describe-instances --region eu-west-2 \
    --filters "Name=tag:Name,Values=$1" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text
}

EDGE=$(get_id edge-nginx)
BLUE=$(get_id prod-vm1-BLUE)
```

`$1` is the first argument. Write the long command once, call it five times.

### Loops with a counter

```bash
ELAPSED=0
while [ $ELAPSED -lt $DURATION ]; do
  if curl -sf http://localhost/api/health > /dev/null; then
    echo "  ✅ [${ELAPSED}s/${DURATION}s] healthy"
  else
    echo "  ❌ failed"
    break
  fi
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done
```

Numeric comparisons: `-lt` `-gt` `-le` `-ge` `-eq` `-ne`.

### Testing an HTTP endpoint

```bash
CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/api/health)
[ "$CODE" = "200" ] && echo "OK" || echo "got $CODE"
```

`-s` silent · `-o /dev/null` discard the body · `-w "%{http_code}"` print only the status.

### Cookies

```bash
curl -c jar.txt -X POST .../login -d '{...}'    # -c saves cookies
curl -b jar.txt -X DELETE .../delete            # -b sends them
```

The API authenticates with an httpOnly cookie, so the integration tests need both.

### sed on macOS

```bash
sed -i '' 's/old/new/' file        # macOS needs the empty backup argument
sed -i    's/old/new/' file        # Linux does not
```

Always confirm the target is unique first:

```bash
grep -c "text to replace" file     # 1 means it is safe
```

### Discarding output

```bash
command > /dev/null          # discard stdout
command 2> /dev/null         # discard stderr
command > /dev/null 2>&1     # discard both — keep only the exit code
```

---

## Quick reference

| I want to… | Command |
|---|---|
| Bring everything up | `terraform apply` then `ansible-playbook playbooks/site.yml -i inventory-ssm.ini` |
| Check connectivity | `ansible all -i inventory-ssm.ini -m ping` |
| See which instances are reachable | `aws ssm describe-instance-information --region eu-west-2 --output table` |
| Find the public address | `terraform output -raw edge_elastic_ip` |
| See which colour is live | `ansible edge -i inventory-ssm.ini -m shell -a "grep -E '^\s*server' /etc/nginx/conf.d/upstream.conf"` |
| Switch traffic | `ansible edge -i inventory-ssm.ini -m shell -a "/opt/switch-backend.sh green"` |
| Open Grafana | `aws ssm start-session --document-name AWS-StartPortForwardingSession ...` |
| Back up the database | `ansible db -i inventory-ssm.ini -m shell -a "/opt/backup-db.sh"` |
| Free disk space | `ansible prod:db -i inventory-ssm.ini -m shell -a "docker container prune -f; docker image prune -f"` |
| Tear everything down | back up first, then `terraform destroy` |