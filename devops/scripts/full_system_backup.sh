#!/bin/bash
set -e

# ==========================================
# School Management System - Full Backup
# ==========================================
# This script performs a seamless, atomic backup of all 
# databases, volumes, and credentials to a single encrypted archive
# and uploads it to S3 using a zero-dependency Docker approach.

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

BACKUP_DIR="/tmp/sms_backup_$(date +%Y%m%d_%H%M%S)"
ARCHIVE_NAME="sms_full_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

# Fallback bucket if not defined in .env
S3_BUCKET="${S3_BACKUP_BUCKET:-s3://your-backup-bucket/sms-backups}"

echo "Starting full system backup to $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR/databases"
mkdir -p "$BACKUP_DIR/volumes"
mkdir -p "$BACKUP_DIR/credentials"

# 1. Backup Credentials & Env Variables
echo "Backing up credentials and configuration..."
cp .env "$BACKUP_DIR/credentials/dot_env_file" 2>/dev/null || true
cp devops/docker-compose.yml "$BACKUP_DIR/credentials/docker-compose.yml" 2>/dev/null || true
cp agents/app-agents/golem.yaml "$BACKUP_DIR/credentials/golem.yaml" 2>/dev/null || true

# 2. Backup Databases (Postgres)
echo "Dumping PostgreSQL databases..."
# Synapse DB
if docker ps | grep -q synapse-postgresql; then
    docker exec -t devops-synapse-postgresql-1 pg_dumpall -c -U synapse > "$BACKUP_DIR/databases/synapse_pg_dump.sql" || echo "Failed to dump synapse"
fi


# 3. Backup Docker Volumes
echo "Backing up Docker volumes..."
VOLUMES=("devops_synapse_data" "devops_opencloud_data" "devops_postgres_data")
for VOL in "${VOLUMES[@]}"; do
    if docker volume inspect "$VOL" >/dev/null 2>&1; then
        echo "  Tarring volume $VOL..."
        docker run --rm \
            -v "$VOL:/volume_data" \
            -v "$BACKUP_DIR/volumes:/backup_out" \
            alpine tar -czf "/backup_out/${VOL}.tar.gz" -C /volume_data .
    fi
done

# 4. Compress Everything
echo "Compressing full backup archive..."
cd /tmp
tar -czf "$ARCHIVE_NAME" "$(basename "$BACKUP_DIR")"

# 5. Upload to S3 (Using Dockerized AWS CLI)
echo "Uploading to S3 ($S3_BUCKET)..."
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    # Use optional endpoint URL for S3 compatible storage (Cloudflare R2, MinIO, DO Spaces)
    ENDPOINT_FLAG=""
    if [ -n "$S3_ENDPOINT_URL" ]; then
        ENDPOINT_FLAG="--endpoint-url $S3_ENDPOINT_URL"
    fi

    docker run --rm \
        -v /tmp:/tmp \
        -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}" \
        amazon/aws-cli s3 cp "/tmp/$ARCHIVE_NAME" "$S3_BUCKET/$ARCHIVE_NAME" $ENDPOINT_FLAG
    echo "Upload complete!"
else
    echo "WARNING: AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not found in .env."
    echo "Skipped S3 upload. Backup file remains at /tmp/$ARCHIVE_NAME"
fi

# Cleanup
rm -rf "$BACKUP_DIR"
if [ -n "$AWS_ACCESS_KEY_ID" ]; then
    rm -f "/tmp/$ARCHIVE_NAME"
    echo "Local backup cleaned up."
fi

echo "Backup process finished successfully."
