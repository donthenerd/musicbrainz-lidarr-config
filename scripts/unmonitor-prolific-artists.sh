#!/bin/bash
# Unmonitor artists with more than N albums (default: 50)
# This prevents Lidarr from searching for hundreds of albums you don't want
#
# Usage: ./unmonitor-prolific-artists.sh [threshold]
# Example: ./unmonitor-prolific-artists.sh 100

set -e

THRESHOLD=${1:-50}
LIDARR_URL="${LIDARR_URL:-http://localhost:8686}"
APIKEY="${LIDARR_APIKEY:-$(grep -oP '<ApiKey>\K[^<]+' /home/lidarr/config.xml 2>/dev/null || echo '')}"

if [ -z "$APIKEY" ]; then
    echo "Error: LIDARR_APIKEY not set and couldn't read from config"
    exit 1
fi

echo "Unmonitoring artists with more than $THRESHOLD albums..."
echo ""

# Get all monitored artists with album count > threshold
artists=$(curl -s "$LIDARR_URL/api/v1/artist" -H "X-Api-Key: $APIKEY" | \
    jq -r ".[] | select(.statistics.albumCount > $THRESHOLD and .monitored == true) | [.id, .artistName, .statistics.albumCount] | @tsv")

if [ -z "$artists" ]; then
    echo "No monitored artists found with more than $THRESHOLD albums."
    exit 0
fi

count=0
while IFS=$'\t' read -r id name albums; do
    # Get full artist object
    artist=$(curl -s "$LIDARR_URL/api/v1/artist/$id" -H "X-Api-Key: $APIKEY")

    # Set monitored to false
    updated=$(echo "$artist" | jq ".monitored = false")

    # PUT back
    result=$(curl -s -X PUT "$LIDARR_URL/api/v1/artist/$id" \
        -H "X-Api-Key: $APIKEY" \
        -H "Content-Type: application/json" \
        -d "$updated" | jq -r ".monitored")

    echo "Unmonitored: $name ($albums albums)"
    ((count++))
done <<< "$artists"

echo ""
echo "Done! Unmonitored $count artists."
