#!/bin/bash
# Backup PostgreSQL și salvare locală
# Rulează cu cron: 0 2 * * * /opt/scripts/backup-db.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/backups"
DB_NAME="silverbank"
DB_USER="silverbank"

mkdir -p $BACKUP_DIR

echo "[$DATE] Starting backup..."
pg_dump -U $DB_USER $DB_NAME > $BACKUP_DIR/backup_$DATE.sql

if [ $? -eq 0 ]; then
  echo "[$DATE] Backup successful: backup_$DATE.sql"
  # Păstrează doar ultimele 7 backup-uri
  ls -t $BACKUP_DIR/backup_*.sql | tail -n +8 | xargs rm -f
else
  echo "[$DATE] Backup FAILED!"
  exit 1
fi