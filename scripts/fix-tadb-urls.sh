#!/bin/bash
# Fix broken TheAudioDB image URLs in Lidarr database
#
# Problem: TADB migrated their CDN from theaudiodb.com to r2.theaudiodb.com
# Lidarr's old /v1/tadb/ proxy path returns 404, but /cache/ path works
#
# This script converts:
#   https://images.lidarr.audio/v1/tadb/artist/TYPE/FILE
# To:
#   https://images.lidarr.audio/cache/https://r2.theaudiodb.com/images/media/artist/TYPE/FILE

set -e

LIDARR_HOST="${1:-drteeth}"
LIDARR_DB="/home/lidarr/lidarr.db"

echo "Fixing TADB URLs on $LIDARR_HOST..."

# Check for broken URLs first
BROKEN_COUNT=$(ssh "$LIDARR_HOST" "python3 -c \"
import sqlite3
conn = sqlite3.connect('$LIDARR_DB')
cur = conn.cursor()
cur.execute(\\\"SELECT COUNT(*) FROM ArtistMetadata WHERE Images LIKE '%/v1/tadb/%'\\\")
print(cur.fetchone()[0])
conn.close()
\"")

if [ "$BROKEN_COUNT" -eq 0 ]; then
    echo "No broken TADB URLs found. Nothing to fix."
    exit 0
fi

echo "Found $BROKEN_COUNT artists with broken /v1/tadb/ URLs"

# Stop Lidarr, fix URLs, restart
ssh "$LIDARR_HOST" "docker stop lidarr && python3 << 'PYEOF'
import sqlite3
import re

conn = sqlite3.connect(\"$LIDARR_DB\")
cur = conn.cursor()

cur.execute(\"SELECT Id, Name, Images FROM ArtistMetadata WHERE Images LIKE '%/v1/tadb/%'\")
rows = cur.fetchall()

pattern = r\"(https?://(?:images|imagecache)\.lidarr\.audio)/v1/tadb/artist/(\w+)/([^\\\"]+)\"
replacement = r\"https://images.lidarr.audio/cache/https://r2.theaudiodb.com/images/media/artist/\2/\3\"

fixed = 0
for row in rows:
    artist_id, name, images = row
    if images:
        new_images = re.sub(pattern, replacement, images)
        if new_images != images:
            cur.execute(\"UPDATE ArtistMetadata SET Images = ? WHERE Id = ?\", (new_images, artist_id))
            fixed += 1

conn.commit()
print(f\"Fixed {fixed} artists\")
conn.close()
PYEOF
docker start lidarr"

echo "Done! Lidarr restarted with fixed URLs."
echo "Run a metadata refresh in Lidarr to download the images."
