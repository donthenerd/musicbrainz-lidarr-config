#!/bin/bash
# MusicBrainz/Lidarr Stack Health Check
# Run: /opt/docker/musicbrainz-docker/scripts/health-check.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

pass() { echo -e "${GREEN}✓${NC} $1"; ((PASSED++)); }
fail() { echo -e "${RED}✗${NC} $1"; ((FAILED++)); }
warn() { echo -e "${YELLOW}!${NC} $1"; ((WARNINGS++)); }

echo "========================================"
echo "MusicBrainz/Lidarr Stack Health Check"
echo "========================================"
echo ""

# 1. Container checks
echo "--- Containers ---"
for container in musicbrainz-docker-search-1 musicbrainz-docker-lmd-1 musicbrainz-docker-mq-1 musicbrainz-docker-redis-1 musicbrainz-docker-musicbrainz-1 musicbrainz-docker-indexer-1; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        pass "$container running"
    else
        fail "$container NOT running"
    fi
done
echo ""

# 2. Solr checks
echo "--- Solr Search ---"
SOLR_RESP=$(docker exec musicbrainz-docker-search-1 curl -sf "http://localhost:8983/solr/admin/collections?action=LIST" 2>/dev/null)
if [ -n "$SOLR_RESP" ]; then
    COLLECTIONS=$(echo "$SOLR_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('collections',[])))" 2>/dev/null || echo "0")
    if [ "$COLLECTIONS" -eq 15 ]; then
        pass "Solr: $COLLECTIONS/15 collections"
    else
        fail "Solr: Only $COLLECTIONS/15 collections"
    fi
else
    fail "Solr admin API not responding"
fi

# Use a specific query since *:* may not work with this Solr config
ARTIST_RESP=$(docker exec musicbrainz-docker-search-1 curl -sf "http://localhost:8983/solr/artist/select?q=name:a*&rows=0" 2>/dev/null)
if [ -n "$ARTIST_RESP" ]; then
    ARTIST_COUNT=$(echo "$ARTIST_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['response']['numFound'])" 2>/dev/null || echo "0")
    if [ "$ARTIST_COUNT" -gt 0 ]; then
        pass "Solr artist index: $ARTIST_COUNT+ documents"
    else
        fail "Solr artist index empty"
    fi
else
    fail "Solr artist collection not responding"
fi
echo ""

# 3. LMD API checks
echo "--- LMD API ---"
LMD_RESP=$(curl -sf "http://localhost:5001/" 2>/dev/null)
if [ -n "$LMD_RESP" ]; then
    LMD_VERSION=$(echo "$LMD_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','unknown'))" 2>/dev/null)
    pass "LMD responding: v$LMD_VERSION"
else
    fail "LMD not responding"
fi

# Test artist lookup (Nirvana)
ARTIST_RESP=$(curl -sf "http://localhost:5001/artist/5b11f4ce-a62d-471e-81fc-a69a8278c7da" 2>/dev/null)
if [ -n "$ARTIST_RESP" ]; then
    if echo "$ARTIST_RESP" | grep -q '"error"'; then
        fail "LMD artist lookup returned error"
    else
        pass "LMD artist lookup working"
    fi
else
    fail "LMD artist lookup failed"
fi

# Test search (use shorter timeout, search can be slow)
SEARCH_RESP=$(curl -sf --max-time 30 "http://localhost:5001/search?type=artist&query=beatles" 2>/dev/null)
if [ -n "$SEARCH_RESP" ]; then
    SEARCH_COUNT=$(echo "$SEARCH_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    if [ "$SEARCH_COUNT" -gt 0 ]; then
        pass "LMD search working ($SEARCH_COUNT results)"
    else
        warn "LMD search returned empty"
    fi
else
    warn "LMD search timed out or failed"
fi
echo ""

# 4. Database checks
echo "--- PostgreSQL (piggy) ---"
DB_TEST=$(docker exec musicbrainz-docker-lmd-1 python3 -c "
import asyncio, asyncpg
async def test():
    try:
        conn = await asyncpg.connect(host='10.21.1.9', port=5432, user='abc', password='abc', database='musicbrainz_db')
        count = await conn.fetchval('SELECT COUNT(*) FROM artist')
        await conn.close()
        print(count)
    except Exception as e:
        print('ERROR')
asyncio.run(test())
" 2>/dev/null)
if [[ "$DB_TEST" =~ ^[0-9]+$ ]]; then
    pass "PostgreSQL musicbrainz_db: $DB_TEST artists"
else
    fail "PostgreSQL musicbrainz_db connection failed"
fi

CACHE_TEST=$(docker exec musicbrainz-docker-lmd-1 python3 -c "
import asyncio, asyncpg
async def test():
    try:
        conn = await asyncpg.connect(host='10.21.1.9', port=5432, user='abc', password='abc', database='lm_cache_db')
        await conn.close()
        print('OK')
    except:
        print('ERROR')
asyncio.run(test())
" 2>/dev/null)
if [ "$CACHE_TEST" = "OK" ]; then
    pass "PostgreSQL lm_cache_db accessible"
else
    fail "PostgreSQL lm_cache_db connection failed"
fi
echo ""

# 5. Replication checks
echo "--- Replication ---"
if [ -f /opt/docker/musicbrainz-docker/local/secrets/metabrainz_access_token ]; then
    pass "Replication token file exists"
else
    fail "Replication token file missing"
fi

CRON_CHECK=$(docker exec musicbrainz-docker-musicbrainz-1 crontab -l 2>/dev/null | grep -c replication.sh || echo "0")
if [ "$CRON_CHECK" -gt 0 ]; then
    pass "Replication cron configured"
else
    warn "Replication cron not configured"
fi

CRON_PID=$(docker exec musicbrainz-docker-musicbrainz-1 pgrep cron 2>/dev/null || echo "")
if [ -n "$CRON_PID" ]; then
    pass "Cron daemon running (PID $CRON_PID)"
else
    fail "Cron daemon not running"
fi
echo ""

# 6. Network connectivity
echo "--- Network ---"
if ping -c1 -W2 10.21.1.9 >/dev/null 2>&1; then
    pass "piggy (10.21.1.9) reachable"
else
    fail "piggy (10.21.1.9) unreachable"
fi
echo ""

# Summary
echo "========================================"
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$WARNINGS warnings${NC}"
echo "========================================"

exit $FAILED
