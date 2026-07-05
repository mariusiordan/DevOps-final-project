#!/bin/bash
# restore-db.sh
# Downloads the latest backup from S3 and restores it into PostgreSQL
# Uses the IAM role attached to this VM - no credentials needed
#
# Usage: sudo /opt/restore-db.sh

set -euo pipefail

# ── Config ──────────────────────────────────────────────────
DB_USER=$(docker exec postgres printenv POSTGRES_USER)
DB_NAME=$(docker exec postgres printenv POSTGRES_DB)

S3_BUCKET="silverbank-tfstate-mariusiordan"
S3_PREFIX="db-backups"
LATEST_FILE="silverbank_latest.sql.gz"
LOCAL_PATH="/tmp/${LATEST_FILE}"

echo "[$(date)] Starting restore of DB '${DB_NAME}' as user '${DB_USER}'..."

# ── Step 1: Download the latest backup from S3 ──────────────
# If no backup exists yet, this fails cleanly and stops
if ! aws s3 cp "s3://${S3_BUCKET}/${S3_PREFIX}/${LATEST_FILE}" "$LOCAL_PATH"; then
    echo "[$(date)] No backup found in S3 - nothing to restore"
    exit 0
fi

echo "[$(date)] Downloaded ${LATEST_FILE}"

# ── Step 2: Clear existing data first ───────────────────────
# TRUNCATE ... CASCADE empties all app tables in dependency order.
# This makes restore idempotent - safe to run even if data exists.
# We do NOT touch _prisma_migrations (Prisma manages the schema).
docker exec postgres psql -U "$DB_USER" "$DB_NAME" -c \
  'TRUNCATE "User", "Account", "Transaction", "CashEntry" CASCADE;'

echo "[$(date)] Cleared existing data"

# ── Step 3: Load the data from the backup ───────────────────
# gunzip -c decompresses to stdout, piped into psql inside the container
gunzip -c "$LOCAL_PATH" | docker exec -i postgres psql -U "$DB_USER" "$DB_NAME"

echo "[$(date)] Restore complete!"

# ── Step 3: Clean up ────────────────────────────────────────
rm -f "$LOCAL_PATH"
