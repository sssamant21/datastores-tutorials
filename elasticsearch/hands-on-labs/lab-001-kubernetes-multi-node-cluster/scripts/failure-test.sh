#!/usr/bin/env bash
set -euo pipefail

NS=${NS:-elasticsearch-lab}
ES_URL=${ES_URL:-https://localhost:9200}
ES_USER=${ES_USER:-elastic}
: "${ES_PASSWORD:?Set ES_PASSWORD}"
: "${ES_CA:?Set ES_CA}"
es() { curl --fail --silent --show-error --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$@"; }

mkdir -p validation-output
es "$ES_URL/_cat/shards/patients-v1?format=json&h=index,shard,prirep,state,node" > validation-output/shards-before.json

TARGET=$(python3 - <<'PY'
import json
x=json.load(open('validation-output/shards-before.json'))
for s in x:
    if s['prirep']=='p' and s['state']=='STARTED':
        print(s['node']); break
PY
)
: "${TARGET:?Could not find a primary-owning node}"
echo "Failure target: $TARGET"

(
  for _ in $(seq 1 120); do
    date -u +%FT%TZ
    es "$ES_URL/_cluster/health/patients-v1" || true
    sleep 2
  done
) > validation-output/health-during-failure.log &
WATCH_PID=$!

kubectl delete pod "$TARGET" -n "$NS"
kubectl wait --for=condition=Ready "pod/$TARGET" -n "$NS" --timeout=10m

es "$ES_URL/_cluster/health?wait_for_nodes=3&wait_for_status=green&timeout=300s&pretty" > validation-output/final-health.json
kill "$WATCH_PID" 2>/dev/null || true
wait "$WATCH_PID" 2>/dev/null || true

es "$ES_URL/_cat/shards/patients-v1?format=json&h=index,shard,prirep,state,node" > validation-output/shards-after.json
python3 - <<'PY'
import json
h=json.load(open('validation-output/final-health.json'))
assert h['status']=='green', h
assert h['number_of_nodes']==3, h
assert h['unassigned_shards']==0, h
PY

echo 'FAILURE/RECOVERY VALIDATION PASS'
