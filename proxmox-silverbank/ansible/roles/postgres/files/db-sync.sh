#!/bin/bash
# Sync database from primary (db-postgresql) to replica (db-replica)
# Run with cron: */30 * * * * /opt/scripts/db-sync.sh
# This gives max 30 minutes of data loss if primary fails

PRIMARY_HOST="10.10.20.20"
REPLICA_HOST="10.10.20.21"
DB_NAME="${DB_NAME:-appdb}"
DB_USER="${DB_USER:-appuser}"
BACKUP_FILE="/tmp/db-sync-$(date +%Y%m%d_%H%M%S).sql"

DB_USER="${DB_USER:-appuser}"
BACKUP_FILE="/tmp/db-sync-$(date +%Y%m%d_%H%M%S).sql"

# Wait for primary DB to be ready before starting sync
echo "[$(date)] Checking primary DB connection..."
for i in $(seq 1 5); do
  if docker exec postgres pg_isready -U $DB_USER > /dev/null 2>&1; then
    echo "[$(date)] ✅ Primary DB is ready"
    break
  fi
  echo "[$(date)] Waiting for DB... attempt $i/5"
  sleep 5
  if [ $i -eq 5 ]; then
    echo "[$(date)] ❌ Primary DB not ready after 25 seconds"
    exit 1
  fi
done

echo "[$(date)] Starting DB sync from primary to replica..."

# Step 1 - dump from primary
docker exec postgres pg_dump -U $DB_USER $DB_NAME > $BACKUP_FILE

if [ $? -ne 0 ]; then
  echo "[$(date)] ❌ pg_dump failed!"
  exit 1
fi

echo "[$(date)] ✅ Dump successful: $BACKUP_FILE"

# Step 2 - copy dump to replica via scp
scp -o StrictHostKeyChecking=no $BACKUP_FILE devop@$REPLICA_HOST:/tmp/db-sync.sql

if [ $? -ne 0 ]; then
  echo "[$(date)] ❌ SCP to replica failed!"
  rm -f $BACKUP_FILE
  exit 1
fi

echo "[$(date)] ✅ Copied to replica"

# Step 3 - restore on replica
ssh -o StrictHostKeyChecking=no devop@$REPLICA_HOST \
  "docker exec -i postgres psql -U $DB_USER $DB_NAME < /tmp/db-sync.sql"

if [ $? -eq 0 ]; then
  echo "[$(date)] ✅ Sync complete!"
else
  echo "[$(date)] ❌ Restore on replica failed!"
  exit 1
fi

# Cleanup temp files
rm -f $BACKUP_FILE
ssh -o StrictHostKeyChecking=no devop@$REPLICA_HOST "rm -f /tmp/db-sync.sql"
