# MusicBrainz/Lidarr Configuration

Configuration-as-code for the local MusicBrainz mirror and Lidarr Metadata Server (LMD) stack.

## Current Status (2025-12-27)

**WORKING** - The stack is operational:
- Lidarr search returns artist images for fresh queries
- Local Solr search is fast (10-30ms vs 5-10s from official API)
- Pi-hole DNS redirects `api.lidarr.audio` to local LMD
- HTTPS endpoint: `https://musicbrainz.digmyjam.com/api/v0.4`

**Known Issues:**
- Some cached searches may show empty images from before the fix - these will refresh over time
- Replication cron needs to be reconfigured after container restarts

## Architecture

```
Lidarr (music.digmyjam.com)
    |
    | api.lidarr.audio (Pi-hole CNAME -> drteeth)
    v
drteeth (10.21.1.10)                    piggy (10.21.1.9)
+---------------------------+           +---------------------------+
| Docker Containers:        |           | TrueNAS:                  |
|   - lmd (port 5001)       |           |   - PostgreSQL            |
|   - search (Solr 8983)    |           |     - musicbrainz_db      |
|   - musicbrainz (5000)    |---------->|     - lm_cache_db         |
|   - redis (6379)          |           |   - NFS Volumes           |
|   - mq (RabbitMQ)         |           |     - solrdata            |
|   - indexer               |           |     - solrdump            |
+---------------------------+           +---------------------------+
```

## Key Fixes Applied

### 1. Fanart.tv URL Bug (provider.py patch)

LMD's `FanartTvProvider.build_url()` was adding a trailing slash before query params:
```
BROKEN: https://webservice.fanart.tv/v3/music/mbid/?api_key=KEY
FIXED:  https://webservice.fanart.tv/v3/music/mbid?api_key=KEY
```
**Solution:** Mount patched `provider.py` as read-only volume. See `patches/README.md`.

### 2. Traefik Path Stripping

Lidarr expects LMD at `/api/v0.4/endpoint`, but LMD serves at root `/endpoint`.
Traefik middleware strips the `/api/v0.4` prefix.

### 3. Pi-hole DNS Redirect

Instead of calling the rate-limited official `api.lidarr.audio`, Pi-hole CNAMEs it to `drteeth.digmyjam.com`.
This allows Lidarr to use our local LMD with fast Solr search.

### 4. HTTP Route for Internal Traffic

Lidarr connects via HTTP internally (no TLS needed for local network).
Added HTTP entrypoint for `api.lidarr.audio`.

## Services

| Service | Description | Port |
|---------|-------------|------|
| LMD | Lidarr Metadata Server API | 5001 |
| Solr | MusicBrainz search index | 8983 (internal) |
| RabbitMQ | Message queue for indexing | 5672 (internal) |
| Redis | Caching layer | 6379 (internal) |
| MusicBrainz | Web interface | 5000 |

## Quick Start

1. Clone this repository
2. Copy `.env.example` to `.env` and configure your values
3. Deploy to target host:
   ```bash
   ./scripts/deploy.sh drteeth
   ```

## Configuration Files

### Compose Overrides (`compose/`)

| File | Description |
|------|-------------|
| `lmd-settings.yml` | LMD API keys, database config, provider.py patch mount |
| `traefik-settings.yml` | Reverse proxy with path stripping and api.lidarr.audio route |
| `nfs-volumes.yml` | NFS volume mounts for Solr data |
| `postgres-settings.yml` | Database credentials |
| `memory-settings.yml` | RAM allocation for Postgres/Solr |
| `external-db-settings.yml` | External PostgreSQL host (piggy) |

### Patches (`patches/`)

| File | Description |
|------|-------------|
| `provider.py` | Fixes fanart.tv URL trailing slash bug |

### Environment Variables

See `.env.example` for all required variables. Key secrets:
- Spotify API credentials
- Fanart.tv API key
- Last.fm API key
- MusicBrainz replication token

## Testing

### Test LMD Search with Images
```bash
# Direct LMD test
curl -s "http://drteeth:5001/search?type=artist&query=madonna" | jq '.[0].images'

# Via Traefik
curl -sk "https://musicbrainz.digmyjam.com/api/v0.4/search?type=artist&query=madonna" | jq '.[0].images'

# Via spoofed domain (as Lidarr sees it)
curl -s "http://api.lidarr.audio/api/v0.4/search?type=artist&query=madonna" | jq '.[0].images'
```

### Test Lidarr API
```bash
APIKEY=$(ssh drteeth 'grep -oP "<ApiKey>\\K[^<]+" /home/lidarr/config.xml')
curl -s "http://drteeth:8686/api/v1/search?term=taylor%20swift" \
  -H "X-Api-Key: $APIKEY" | jq '.[0].artist.images | length'
```

## Health Check

Run the health check script on the target host:
```bash
/opt/docker/musicbrainz-docker/scripts/health-check.sh
```

Checks performed:
- 6 containers running
- Solr 15/15 collections
- LMD API responding
- PostgreSQL connectivity
- Replication status
- Network connectivity

## Maintenance

### Cleanup Excess Solr Replicas

After loading backup archives, Solr may create multiple replicas. Run:
```bash
/opt/docker/musicbrainz-docker/scripts/cleanup-solr-replicas.sh
```

### Rebuild Solr Index
```bash
cd /opt/docker/musicbrainz-docker
docker compose run --rm indexer python -m sir reindex
```

### Manual Replication
```bash
docker exec musicbrainz-docker-musicbrainz-1 /replication.sh
```

### View Logs
```bash
docker compose logs -f lmd
docker compose logs -f search
```

## Lidarr Configuration

In Lidarr Settings > Metadata:
- **Metadata Source:** `https://musicbrainz.digmyjam.com/api/v0.4`

Lidarr will use this directly. The Pi-hole redirect for `api.lidarr.audio` is a fallback.

## Secrets Management

**NEVER commit the `.env` file.** Store secrets in:
- Jenkins credentials store
- HashiCorp Vault
- Environment-specific `.env` files on target hosts

## Jenkins Integration

This repository includes a Jenkinsfile for CI/CD:
- Validates configuration on push
- Deploys to staging/production on merge
- Runs health checks after deployment
