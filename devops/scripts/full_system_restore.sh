#!/bin/bash
set -e

# ==========================================
# School Management System - Full Restore
# ==========================================
# This script restores the system from a full backup archive.
# It can restore from a local file OR directly from an S3 URL.

if [ -z "$1" ]; then
    echo "Usage: ./devops/scripts/full_system_restore.sh <path_to_backup.tar.gz OR s3://...>"
    exit 1
fi

INPUT_PATH="$1"
ARCHIVE_PATH="/tmp/sms_restore_archive.tar.gz"
RESTORE_DIR="/tmp/sms_restore_$(date +%s)"

# Load environment variables if they exist
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# 1. Fetch from S3 if input is an S3 URI
if [[ "$INPUT_PATH" == s3://* ]]; then
    echo "S3 URL detected. Downloading $INPUT_PATH from S3 using Dockerized AWS CLI..."
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "ERROR: You must define AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in .env to download from S3."
        exit 1
    fi
    
    ENDPOINT_FLAG=""
    if [ -n "$S3_ENDPOINT_URL" ]; then
        ENDPOINT_FLAG="--endpoint-url $S3_ENDPOINT_URL"
    fi

    docker run --rm \
        -v /tmp:/tmp \
        -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}" \
        amazon/aws-cli s3 cp "$INPUT_PATH" "$ARCHIVE_PATH" $ENDPOINT_FLAG
else
    echo "Local file detected. Copying $INPUT_PATH..."
    cp "$INPUT_PATH" "$ARCHIVE_PATH"
fi

echo "Extracting archive to $RESTORE_DIR..."
mkdir -p "$RESTORE_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$RESTORE_DIR" --strip-components=1

echo "1. Restoring Credentials..."
if [ -f "$RESTORE_DIR/credentials/dot_env_file" ]; then
    cp "$RESTORE_DIR/credentials/dot_env_file" .env
    echo "  .env restored."
fi
if [ -f "$RESTORE_DIR/credentials/docker-compose.yml" ]; then
    cp "$RESTORE_DIR/credentials/docker-compose.yml" devops/docker-compose.yml
    echo "  docker-compose.yml restored."
fi

echo "2. Shutting down active containers to prevent data corruption..."
docker-compose -f devops/docker-compose.yml down || true

echo "3. Restoring Docker Volumes..."
for vol_file in "$RESTORE_DIR"/volumes/*.tar.gz; do
    if [ -f "$vol_file" ]; then
        # Extract volume name from filename
        VOL=$(basename "$vol_file" .tar.gz)
        echo "  Restoring volume $VOL..."
        # Ensure volume exists
        docker volume create "$VOL" || true
        # Wipe existing data and extract backup
        docker run --rm \
            -v "$VOL:/volume_data" \
            -v "$RESTORE_DIR/volumes:/backup_in" \
            alpine sh -c "rm -rf /volume_data/* /volume_data/..?* /volume_data/.[!.]* && tar -xzf /backup_in/${VOL}.tar.gz -C /volume_data"
    fi
done

echo "4. Starting database containers..."
docker-compose -f devops/docker-compose.yml up -d synapse-postgresql
echo "Waiting 15 seconds for PostgreSQL to be ready..."
sleep 15

echo "5. Restoring PostgreSQL databases..."
if [ -f "$RESTORE_DIR/databases/synapse_pg_dump.sql" ]; then
    echo "  Restoring synapse DB..."
    cat "$RESTORE_DIR/databases/synapse_pg_dump.sql" | docker exec -i devops-synapse-postgresql-1 psql -U synapse
fi

echo "6. Starting the rest of the stack..."
docker-compose -f devops/docker-compose.yml up -d

echo "Cleaning up..."
rm -rf "$RESTORE_DIR"
rm -f "$ARCHIVE_PATH"

echo "Restore process finished successfully! Verify your deployment."
