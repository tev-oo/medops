#!/usr/bin/env bash
set -Eeuo pipefail

# MedOps PostgreSQL backup script

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="$BACKUP_DIR/medops-$TIMESTAMP.dump"

cd "$PROJECT_DIR"

umask 077
mkdir -p "$BACKUP_DIR"

# Check database container availability
if ! docker compose exec -T db \
    pg_isready -U medops -d medops >/dev/null; then
    echo "ERROR: PostgreSQL is unavailable."
    exit 1
fi

# Prevent overwriting an existing backup
if [[ -e "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup already exists."
    exit 1
fi

TEMP_FILE="$(mktemp "$BACKUP_DIR/.medops-XXXXXXXX.dump")"

cleanup() {
    rm -f "$TEMP_FILE"
}
trap cleanup EXIT

echo "Starting MedOps backup..."

docker compose exec -T db \
    pg_dump -U medops -d medops -Fc \
    > "$TEMP_FILE"

# Verify the archive is readable
docker compose exec -T db \
    pg_restore --list \
    < "$TEMP_FILE" > /dev/null

if [[ ! -s "$TEMP_FILE" ]]; then
    echo "ERROR: Backup file is empty."
    exit 1
fi

mv "$TEMP_FILE" "$BACKUP_FILE"

echo "Backup created successfully."
echo "File: $BACKUP_FILE"
du -h "$BACKUP_FILE"
