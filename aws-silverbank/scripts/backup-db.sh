#!/bin/bash
# Backup PostgreSQL din Docker container
# Rulează cu cron: 0 2 * * * /opt/scripts/backup-db.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/backups"
CONTAINER_NAME="postgres"
DB_NAME="${DB_NAME:-appdb}"
DB_USER="${DB_USER:-appuser}"

mkdir -p $BACKUP_DIR

echo "[$DATE] Starting backup..."

docker exec $CONTAINER_NAME pg_dump -U $DB_USER $DB_NAME > $BACKUP_DIR/backup_$DATE.sql

if [ $? -eq 0 ]; then
  echo "[$DATE] Backup successful: backup_$DATE.sql"
  ls -t $BACKUP_DIR/backup_*.sql | tail -n +8 | xargs rm -f
else
  echo "[$DATE] Backup FAILED!"
  exit 1
fi
