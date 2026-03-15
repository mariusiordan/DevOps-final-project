#!/bin/bash
# Backup PostgreSQL from Docker container and upload to S3
# Run with cron: 0 2 * * * /opt/scripts/backup-db.sh
#
# Requirements:
#   - AWS CLI installed on the server
#   - EC2 instance needs an IAM role with S3 write permissions
#   - S3 bucket must exist: silverbank-db-backups

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/backups"
CONTAINER_NAME="postgres"
DB_NAME="${DB_NAME:-appdb}"
DB_USER="${DB_USER:-appuser}"
S3_BUCKET="s3://silverbank-db-backups"

mkdir -p $BACKUP_DIR

echo "[$DATE] Starting backup..."

# Run pg_dump inside the Docker container and save locally
docker exec $CONTAINER_NAME pg_dump -U $DB_USER $DB_NAME > $BACKUP_DIR/backup_$DATE.sql

if [ $? -eq 0 ]; then
  echo "[$DATE] Backup successful: backup_$DATE.sql"

  # Upload to S3
  echo "[$DATE] Uploading to S3..."
  aws s3 cp $BACKUP_DIR/backup_$DATE.sql $S3_BUCKET/backup_$DATE.sql

  if [ $? -eq 0 ]; then
    echo "[$DATE] ✅ Uploaded to S3: $S3_BUCKET/backup_$DATE.sql"
  else
    echo "[$DATE] ⚠️ S3 upload failed - backup kept locally"
  fi

  # Keep only last 7 local backups
  ls -t $BACKUP_DIR/backup_*.sql | tail -n +8 | xargs rm -f

else
  echo "[$DATE] ❌ Backup FAILED!"
  exit 1
fi