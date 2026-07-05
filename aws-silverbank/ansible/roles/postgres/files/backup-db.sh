#!/bin/bash
# backup-db.sh
# Dumps the PostgreSQL database and uploads it to S3
# Uses the IAM role attached to this VM - no credentials needed
#
# Usage: sudo /opt/backup-db.sh

set -euo pipefail   # exit on error, undefined var, or failed pipe

# ── Config ──────────────────────────────────────────────────
# Read DB credentials from the running container so they always
# match whatever Ansible/vault configured - no hardcoding
DB_USER=$(docker exec postgres printenv POSTGRES_USER)
DB_NAME=$(docker exec postgres printenv POSTGRES_DB)

S3_BUCKET="silverbank-tfstate-mariusiordan"
S3_PREFIX="db-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="silverbank_${TIMESTAMP}.sql.gz"
LOCAL_PATH="/tmp/${BACKUP_FILE}"

echo "[$(date)] Starting backup of DB '${DB_NAME}' as user '${DB_USER}'..."

# ── Step 1: Dump the database ───────────────────────────────
# Dump to an uncompressed temp file FIRST so we can check pg_dump
# actually succeeded before we compress and upload.
# (Piping pg_dump | gzip hides pg_dump failures - we avoid that.)
RAW_DUMP="/tmp/silverbank_${TIMESTAMP}.sql"
docker exec postgres pg_dump -U "$DB_USER" --data-only --disable-triggers --exclude-table=_prisma_migrations "$DB_NAME" > "$RAW_DUMP"

# Safety check: a real dump is never tiny. Fail if it looks empty.
DUMP_SIZE=$(stat -c%s "$RAW_DUMP")
if [ "$DUMP_SIZE" -lt 100 ]; then
    echo "[$(date)] ERROR: dump is only ${DUMP_SIZE} bytes - backup aborted"
    rm -f "$RAW_DUMP"
    exit 1
fi

# Compress it
gzip -c "$RAW_DUMP" > "$LOCAL_PATH"
rm -f "$RAW_DUMP"

echo "[$(date)] Dump created: ${LOCAL_PATH} (${DUMP_SIZE} bytes uncompressed)"

# ── Step 2: Upload timestamped copy to S3 ───────────────────
aws s3 cp "$LOCAL_PATH" "s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_FILE}"
echo "[$(date)] Uploaded ${BACKUP_FILE}"

# ── Step 3: Upload as "latest" for easy restore ─────────────
aws s3 cp "$LOCAL_PATH" "s3://${S3_BUCKET}/${S3_PREFIX}/silverbank_latest.sql.gz"
echo "[$(date)] Updated latest pointer"

# ── Step 4: Clean up ────────────────────────────────────────
rm -f "$LOCAL_PATH"
echo "[$(date)] Backup complete!"
