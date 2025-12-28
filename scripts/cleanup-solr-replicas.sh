#!/bin/bash
# Cleanup excess Solr replicas after loading backups
# The metabrainz load-backup-archives script doesn't set replicationFactor=1
# which causes Solr to create 8 replicas per collection on a single node
# This wastes resources and causes timeouts
#
# Run this AFTER loading backups: ./cleanup-solr-replicas.sh

set -e

SOLR_CONTAINER="${SOLR_CONTAINER:-musicbrainz-docker-search-1}"
SOLR_URL="http://localhost:8983/solr"

echo "Checking Solr replica counts..."

# Get cluster status
CLUSTER_STATUS=$(docker exec "$SOLR_CONTAINER" curl -sf "$SOLR_URL/admin/collections?action=CLUSTERSTATUS")

# Parse and delete extras using Python
python3 << PYEOF
import json
import subprocess
import sys

data = json.loads('''$CLUSTER_STATUS''')
colls = data["cluster"]["collections"]
deleted = 0

for coll_name in sorted(colls.keys()):
    shards = colls[coll_name].get("shards", {})
    for shard_name, shard in shards.items():
        replicas = shard.get("replicas", {})
        if len(replicas) <= 1:
            continue

        for rep_name, rep in replicas.items():
            if rep.get("leader") != "true":
                print(f"Deleting {coll_name}/{shard_name}/{rep_name}...", end=" ", flush=True)
                cmd = f"docker exec $SOLR_CONTAINER curl -sf '$SOLR_URL/admin/collections?action=DELETEREPLICA&collection={coll_name}&shard={shard_name}&replica={rep_name}'"
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                if '"status":0' in result.stdout:
                    print("OK")
                    deleted += 1
                else:
                    print("FAILED")

if deleted == 0:
    print("All collections already have 1 replica per shard - no cleanup needed")
else:
    print(f"Deleted {deleted} excess replicas")
PYEOF

echo "Done!"
