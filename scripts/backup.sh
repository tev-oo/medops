#!/usr/bin/env bash
set -Eeuo pipefail

# MedOps PostgreSQL backup script

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="$BACKUP_DIR/medops-$TIMESTAMP.dump"

# Retention configuration
# BACKUP_KEEP_COUNT=0 disables retention.
# BACKUP_PRUNE_DRY_RUN=1 previews deletions without removing files.
KEEP_COUNT="${BACKUP_KEEP_COUNT:-0}"
DRY_RUN="${BACKUP_PRUNE_DRY_RUN:-1}"

if ! [[ "$KEEP_COUNT" =~ ^(0|[1-9][0-9]*)$ ]]; then
    echo "ERROR: BACKUP_KEEP_COUNT must be a non-negative integer."
    exit 1
fi

if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
    echo "ERROR: BACKUP_PRUNE_DRY_RUN must be 0 or 1."
    exit 1
fi


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

if (( KEEP_COUNT > 0 )); then
    mapfile -t BACKUP_FILES < <(
        find "$BACKUP_DIR" -maxdepth 1 -type f \
            -name 'medops-*.dump' -printf '%f\n' |
            LC_ALL=C sort
    )

    TOTAL="${#BACKUP_FILES[@]}"
    REMOVE_COUNT=$(( TOTAL - KEEP_COUNT ))

    if (( REMOVE_COUNT > 0 )); then
        echo "Retention policy: keep $KEEP_COUNT of $TOTAL archives."

        for (( i=0; i<REMOVE_COUNT; i++ )); do
            OLD_FILE="$BACKUP_DIR/${BACKUP_FILES[$i]}"

            if [[ "$DRY_RUN" == "1" ]]; then
                echo "DRY RUN: would remove $OLD_FILE"
            else
                rm -- "$OLD_FILE"
                echo "Removed old backup: $OLD_FILE"
            fi
        done
    else
        echo "Retention policy: no old backups to remove."
    fi
fi
