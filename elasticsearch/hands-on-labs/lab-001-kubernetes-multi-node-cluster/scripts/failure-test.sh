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

read -r TARGET SHARD OLD_REPLICA <<EOF
$(python3 - <<'PY'
import json
x=json.load(open('validation-output/shards-before.json'))
for p in x:
    if p['prirep']=='p' and p['state']=='STARTED':
        replicas=[r for r in x if r['shard']==p['shard'] and r['prirep']=='r' and r['state']=='STARTED']
        if replicas:
            print(p['node'], p['shard'], replicas[0]['node'])
            break
PY
)
EOF
: "${TARGET:?Could not find a primary-owning node}"
: "${SHARD:?Could not determine target shard}"
: "${OLD_REPLICA:?Could not determine replica node}"
echo "Failure target: $TARGET; shard: $SHARD; expected promotion candidate: $OLD_REPLICA"

PVC="data-$TARGET"
PVC_UID_BEFORE=$(kubectl get pvc "$PVC" -n "$NS" -o jsonpath='{.metadata.uid}')
PV_BEFORE=$(kubectl get pvc "$PVC" -n "$NS" -o jsonpath='{.spec.volumeName}')
RESTARTS_BEFORE=$(kubectl get pod "$TARGET" -n "$NS" -o jsonpath='{.status.containerStatuses[0].restartCount}')

echo 'timestamp,http_status,hits' > validation-output/search-during-failure.csv
(
  for _ in $(seq 1 120); do
    ts=$(date -u +%FT%TZ)
    body=$(mktemp)
    code=$(curl --silent --show-error --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" -o "$body" -w '%{http_code}' "$ES_URL/patients-v1/_search?size=1" || true)
    hits='NA'
    if [ "$code" = 200 ]; then
      hits=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hits"]["total"]["value"])' "$body" 2>/dev/null || echo NA)
    fi
    echo "$ts,$code,$hits"
    rm -f "$body"
    sleep 1
  done
) >> validation-output/search-during-failure.csv &
SEARCH_PID=$!

kubectl delete pod "$TARGET" -n "$NS"

PROMOTED=0
for _ in $(seq 1 120); do
  es "$ES_URL/_cat/shards/patients-v1?format=json&h=shard,prirep,state,node" > validation-output/shards-during.json || true
  if python3 - "$SHARD" "$OLD_REPLICA" <<'PY'
import json,sys
shard,node=sys.argv[1:]
try: x=json.load(open('validation-output/shards-during.json'))
except Exception: raise SystemExit(1)
raise SystemExit(0 if any(s.get('shard')==shard and s.get('prirep')=='p' and s.get('state')=='STARTED' and s.get('node')==node for s in x) else 1)
PY
  then
    PROMOTED=1
    cp validation-output/shards-during.json validation-output/replica-promotion.json
    break
  fi
  sleep 1
done
test "$PROMOTED" -eq 1

kubectl wait --for=condition=Ready "pod/$TARGET" -n "$NS" --timeout=10m
es "$ES_URL/_cluster/health?wait_for_nodes=3&wait_for_status=green&timeout=300s&pretty" > validation-output/final-health.json
kill "$SEARCH_PID" 2>/dev/null || true
wait "$SEARCH_PID" 2>/dev/null || true

PVC_UID_AFTER=$(kubectl get pvc "$PVC" -n "$NS" -o jsonpath='{.metadata.uid}')
PV_AFTER=$(kubectl get pvc "$PVC" -n "$NS" -o jsonpath='{.spec.volumeName}')
test "$PVC_UID_BEFORE" = "$PVC_UID_AFTER"
test "$PV_BEFORE" = "$PV_AFTER"

RESTARTS_AFTER=$(kubectl get pod "$TARGET" -n "$NS" -o jsonpath='{.status.containerStatuses[0].restartCount}')
test "$RESTARTS_AFTER" -eq 0

python3 - <<'PY'
import csv,json
h=json.load(open('validation-output/final-health.json'))
assert h['status']=='green', h
assert h['number_of_nodes']==3, h
assert h['unassigned_shards']==0, h
rows=list(csv.DictReader(open('validation-output/search-during-failure.csv')))
assert any(r['http_status']=='200' and r['hits']=='4' for r in rows), rows
PY

es "$ES_URL/_cat/shards/patients-v1?format=json&h=index,shard,prirep,state,node" > validation-output/shards-after.json
printf 'pvc=%s\npvc_uid_before=%s\npvc_uid_after=%s\npv_before=%s\npv_after=%s\nrestart_count_before=%s\nrestart_count_after=%s\n' \
  "$PVC" "$PVC_UID_BEFORE" "$PVC_UID_AFTER" "$PV_BEFORE" "$PV_AFTER" "$RESTARTS_BEFORE" "$RESTARTS_AFTER" > validation-output/persistence-and-probes.txt

echo 'FAILURE/RECOVERY VALIDATION PASS'
