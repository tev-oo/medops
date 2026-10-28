#!/usr/bin/env bash
set -Eeuo pipefail

# MedOps PostgreSQL backup script

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="$BACKUP_DIR/medops-$TIMESTAMP.dump"

# Validate retention settings before starting a backup
KEEP_COUNT="${BACKUP_KEEP_COUNT:-0}"
DRY_RUN="${BACKUP_PRUNE_DRY_RUN:-1}"

if ! [[ "$KEEP_COUNT" =~ ^(0|[1-9][0-9]*)$ ]]; then
    echo "ERROR: Invalid BACKUP_KEEP_COUNT"
    exit 1
fi

if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
    echo "ERROR: Invalid BACKUP_PRUNE_DRY_RUN"
    exit 1
fi

cd "$PROJECT_DIR"
umask 077
mkdir -p -m 700 "$BACKUP_DIR"

# Check database availability
if ! docker compose exec -T db sh -c \
    'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    > /dev/null; then
    echo "ERROR: PostgreSQL is unavailable."
    exit 1
fi

# Prevent overwriting an existing archive
if [[ -e "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup already exists."
    exit 1
fi

TEMP_FILE="$(mktemp "$BACKUP_DIR/.medops-XXXXXXXX.dump")"

cleanup() {
    rm -f -- "$TEMP_FILE"
}
trap cleanup EXIT

echo "Starting MedOps backup..."

docker compose exec -T db sh -c \
    'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
    > "$TEMP_FILE"

# Verify PostgreSQL archive readability
docker compose exec -T db \
    pg_restore --list < "$TEMP_FILE" > /dev/null

if [[ ! -s "$TEMP_FILE" ]]; then
    echo "ERROR: Backup file is empty."
    exit 1
fi

mv -- "$TEMP_FILE" "$BACKUP_FILE"

echo "Backup created successfully."
echo "File: $BACKUP_FILE"
du -h "$BACKUP_FILE"

# Prune only after successful backup creation and validation.
if (( KEEP_COUNT > 0 )); then
    BACKUP_DIR="$BACKUP_DIR" \
    BACKUP_KEEP_COUNT="$KEEP_COUNT" \
    BACKUP_PRUNE_DRY_RUN="$DRY_RUN" \
    bash "$PROJECT_DIR/scripts/prune-backups.sh"
fi
