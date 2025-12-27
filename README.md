# MusicBrainz/Lidarr Configuration

Configuration-as-code for the local MusicBrainz mirror and Lidarr Metadata Server (LMD) stack.

## Architecture

```
drteeth (10.21.1.10)                    piggy (10.21.1.9)
+---------------------------+           +---------------------------+
| Docker Containers:        |           | TrueNAS:                  |
|   - musicbrainz-search    |           |   - PostgreSQL            |
|   - musicbrainz-mq        |           |     - musicbrainz_db      |
|   - musicbrainz-redis     |           |     - lm_cache_db         |
|   - musicbrainz-lmd       |---------->|   - NFS Volumes           |
|   - musicbrainz-indexer   |           |     - solrdata            |
|   - musicbrainz-server    |           |     - solrdump            |
+---------------------------+           +---------------------------+
```

## Services

| Service | Description | Port |
|---------|-------------|------|
| LMD | Lidarr Metadata Server API | 5001 |
| Solr | MusicBrainz search index | 8983 (internal) |
| RabbitMQ | Message queue for indexing | 5672 (internal) |
| Redis | Caching layer | 6379 (internal) |

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
| `postgres-settings.yml` | Database credentials |
| `memory-settings.yml` | RAM allocation for Postgres/Solr |
| `volume-settings.yml` | Local volume bindings |
| `external-db-settings.yml` | External PostgreSQL host |
| `nfs-volumes.yml` | NFS volume mounts |
| `traefik-settings.yml` | Reverse proxy labels |
| `lmd-settings.yml` | LMD API keys and database config |

### Environment Variables

See `.env.example` for all required variables. Key secrets:
- Spotify API credentials
- Fanart.tv API key
- Last.fm API key
- MusicBrainz replication token

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

## Replication

MusicBrainz data replication runs daily at 3 AM via cron inside the musicbrainz container.

Check replication status:
```bash
docker exec musicbrainz-docker-musicbrainz-1 crontab -l
```

## Jenkins Integration

This repository includes a Jenkinsfile for CI/CD:
- Validates configuration on push
- Deploys to staging/production on merge
- Runs health checks after deployment

## Secrets Management

**NEVER commit the `.env` file.** Store secrets in:
- Jenkins credentials store
- HashiCorp Vault
- Environment-specific `.env` files on target hosts

## Maintenance

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
