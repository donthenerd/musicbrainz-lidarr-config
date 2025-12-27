#!/bin/bash
# Deploy MusicBrainz/Lidarr configuration to target host
# Usage: ./deploy.sh [host] [--dry-run]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_HOST="${1:-drteeth}"
DRY_RUN="${2:-}"

REMOTE_BASE="/opt/docker/musicbrainz-docker"

echo "Deploying MusicBrainz config to $TARGET_HOST..."

# Check for .env file
if [ ! -f "$REPO_DIR/.env" ]; then
    echo "ERROR: .env file not found. Copy .env.example to .env and configure it."
    exit 1
fi

# Source the environment
source "$REPO_DIR/.env"

# Validate required variables
REQUIRED_VARS=(
    POSTGRES_USER POSTGRES_PASSWORD POSTGRES_HOST NFS_HOST
    SPOTIFY_CLIENT_ID SPOTIFY_CLIENT_SECRET FANART_KEY LASTFM_KEY
)
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required variable $var is not set in .env"
        exit 1
    fi
done

if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "[DRY RUN] Would deploy to $TARGET_HOST"
    echo "[DRY RUN] Compose files: $REPO_DIR/compose/*.yml -> $REMOTE_BASE/local/compose/"
    echo "[DRY RUN] Scripts: $REPO_DIR/scripts/*.sh -> $REMOTE_BASE/scripts/"
    exit 0
fi

# Create remote directories if needed
ssh "$TARGET_HOST" "mkdir -p $REMOTE_BASE/local/compose $REMOTE_BASE/scripts"

# Deploy compose files
echo "Deploying compose overrides..."
for file in "$REPO_DIR"/compose/*.yml; do
    filename=$(basename "$file")
    # Substitute environment variables and copy
    envsubst < "$file" | ssh "$TARGET_HOST" "cat > $REMOTE_BASE/local/compose/$filename"
    echo "  - $filename"
done

# Deploy scripts
echo "Deploying scripts..."
scp -q "$REPO_DIR/scripts/health-check.sh" "$TARGET_HOST:$REMOTE_BASE/scripts/"
ssh "$TARGET_HOST" "chmod +x $REMOTE_BASE/scripts/*.sh"
echo "  - health-check.sh"

echo ""
echo "Deployment complete!"
echo "To apply changes, run on $TARGET_HOST:"
echo "  cd $REMOTE_BASE && docker compose up -d"
