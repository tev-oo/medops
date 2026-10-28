
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# MedOps: copy the newest PostgreSQL backup from Debian to Arch.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_CONFIG="$PROJECT_DIR/.vagrant/ssh-config"
SSH_HOST="default"

REMOTE_DIR="/opt/medops/backups"
LOCAL_DIR="${MEDOPS_OFFSITE_DIR:-$HOME/medops-offsite-backups}"

if [[ ! -f "$SSH_CONFIG" ]]; then
    echo "ERROR: Vagrant SSH config not found."
    exit 1
fi

mkdir -p -m 700 "$LOCAL_DIR"

# Discover the newest archive.
LATEST="$(
    ssh -F "$SSH_CONFIG" "$SSH_HOST" \
      "sudo find '$REMOTE_DIR' -maxdepth 1 -type f \
      -name 'medops-*.dump' -printf '%f\n' | LC_ALL=C sort | tail -n 1"
)"

# Only permit the expected timestamped archive names.
if [[ ! "$LATEST" =~ ^medops-[0-9]{8}T[0-9]{6}Z\.dump$ ]]; then
    echo "ERROR: No valid PostgreSQL backup found."
    exit 1
fi

REMOTE_FILE="$REMOTE_DIR/$LATEST"
LOCAL_FILE="$LOCAL_DIR/$LATEST"

echo "Latest archive: $LATEST"

# Retrieve the source checksum.
REMOTE_HASH="$(
    ssh -F "$SSH_CONFIG" "$SSH_HOST" \
      "sudo sha256sum '$REMOTE_FILE'" | awk '{print $1}'
)"

if [[ ! "$REMOTE_HASH" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "ERROR: Could not retrieve source checksum."
    exit 1
fi

# Never silently overwrite an existing backup.
if [[ -e "$LOCAL_FILE" ]]; then
    LOCAL_HASH="$(sha256sum "$LOCAL_FILE" | awk '{print $1}')"

    if [[ "$REMOTE_HASH" == "$LOCAL_HASH" ]]; then
        echo "Backup already synchronized and verified."
        exit 0
    fi

    echo "ERROR: Existing backup has a different checksum."
    exit 1
fi

# Download into a temporary file in the destination directory.
TEMP_FILE="$(mktemp "$LOCAL_DIR/.medops-sync-XXXXXXXX")"

cleanup() {
    rm -f -- "$TEMP_FILE"
}
trap cleanup EXIT

echo "Downloading archive..."

ssh -F "$SSH_CONFIG" "$SSH_HOST" \
  "sudo cat '$REMOTE_FILE'" > "$TEMP_FILE"

# Check transfer integrity before publishing the backup.
LOCAL_HASH="$(sha256sum "$TEMP_FILE" | awk '{print $1}')"

if [[ "$REMOTE_HASH" != "$LOCAL_HASH" ]]; then
    echo "ERROR: SHA-256 checksum mismatch."
    exit 1
fi

if [[ ! -s "$TEMP_FILE" ]]; then
    echo "ERROR: Downloaded archive is empty."
    exit 1
fi

# Publish without replacing an existing destination.
ln -- "$TEMP_FILE" "$LOCAL_FILE"

echo "PASS: Off-VM backup synchronized."
echo "File: $LOCAL_FILE"
echo "SHA-256: $LOCAL_HASH"

