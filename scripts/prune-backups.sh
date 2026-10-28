#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/medops/backups}"
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

if (( KEEP_COUNT == 0 )); then
    echo "Retention disabled."
    exit 0
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "ERROR: Backup directory does not exist."
    exit 1
fi

mapfile -t BACKUP_FILES < <(
    find "$BACKUP_DIR" -maxdepth 1 -type f \
        -name 'medops-*.dump' -printf '%f\n' |
        LC_ALL=C sort
)

TOTAL="${#BACKUP_FILES[@]}"
REMOVE_COUNT=$(( TOTAL - KEEP_COUNT ))

if (( REMOVE_COUNT <= 0 )); then
    echo "Retention: no backups to remove."
    exit 0
fi

echo "Retention: keeping $KEEP_COUNT of $TOTAL archives."

for (( i=0; i<REMOVE_COUNT; i++ )); do
    OLD_FILE="$BACKUP_DIR/${BACKUP_FILES[$i]}"

    if [[ "$DRY_RUN" == "1" ]]; then
        echo "DRY RUN: would remove $OLD_FILE"
    else
        rm -- "$OLD_FILE"
        echo "Removed: $OLD_FILE"
    fi
done
