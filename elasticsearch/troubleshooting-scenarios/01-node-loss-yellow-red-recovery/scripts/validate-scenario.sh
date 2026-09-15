#!/usr/bin/env bash
set -euo pipefail

: "${ES_URL:?ES_URL is required}"
: "${ES_USER:?ES_USER is required}"
: "${ES_PASSWORD:?ES_PASSWORD is required}"
: "${ES_CA:?ES_CA is required}"

OUT="${OUT:-validation-output}"
mkdir -p "$OUT"
AUTH=(-u "$ES_USER:$ES_PASSWORD" --cacert "$ES_CA")
api() { curl --fail --silent --show-error "${AUTH[@]}" "$@"; }

wait_health() {
  local expected="$1" nodes="$2" unassigned="$3"
  local h status n u
  for _ in $(seq 1 120); do
    h=$(api "$ES_URL/_cluster/health") || { sleep 2; continue; }
    read -r status n u < <(python3 -c 'import json,sys; h=json.load(sys.stdin); print(h["status"],h["number_of_nodes"],h["unassigned_shards"])' <<<"$h")
    if [[ "$status" == "$expected" && "$n" -eq "$nodes" && "$u" -eq "$unassigned" ]]; then
      printf '%s\n' "$h"
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for status=$expected nodes=$nodes unassigned=$unassigned" >&2
  api "$ES_URL/_cluster/health?pretty" >&2 || true
  return 1
}

baseline=$(wait_health green 3 0)
printf '%s\n' "$baseline" | tee "$OUT/01-baseline-health.json"

api -X DELETE "$ES_URL/scenario01" >/dev/null 2>&1 || true
api -X PUT "$ES_URL/scenario01" -H 'Content-Type: application/json' -d '{
  "settings": {"number_of_shards":3,"number_of_replicas":0},
  "mappings": {"properties":{"event_date":{"type":"date"},"status":{"type":"keyword"}}}
}' | tee "$OUT/02-create-index.json"

started=0
for _ in $(seq 1 30); do
  started=$(api "$ES_URL/_cat/shards/scenario01?format=json&h=prirep,state,node" | python3 -c 'import json,sys; x=json.load(sys.stdin); print(sum(1 for s in x if s["prirep"]=="p" and s["state"]=="STARTED"))')
  [[ "$started" -eq 3 ]] && break
  sleep 1
done
[[ "$started" -eq 3 ]]

api -X PUT "$ES_URL/scenario01/_settings" -H 'Content-Type: application/json' -d '{"index":{"number_of_replicas":1}}' | tee "$OUT/03-enable-replicas.json"
scenario_status=""
for _ in $(seq 1 60); do
  h=$(api "$ES_URL/_cluster/health/scenario01")
  scenario_status=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$h")
  [[ "$scenario_status" == green ]] && break
  sleep 1
done
[[ "$scenario_status" == green ]]
api "$ES_URL/_cat/shards/scenario01?format=json&h=index,shard,prirep,state,node" | tee "$OUT/04-green-shards.json"

# TRAINING ONLY. This deliberately strict threshold deterministically exercises
# the disk allocation decider without filling CI disks. It is not a production
# recommendation and must be removed before validation completes.
api -X PUT "$ES_URL/_cluster/settings" -H 'Content-Type: application/json' -d '{"transient":{"cluster.routing.allocation.disk.watermark.low":"1%"}}' | tee "$OUT/05-set-training-watermark.json"
api "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true" | tee "$OUT/06-cluster-settings.json"
grep -q 'cluster.routing.allocation.disk.watermark.low' "$OUT/06-cluster-settings.json"

# The workflow pins ES_URL to elasticsearch-0. Scale the StatefulSet from 3 to 2
# so ordinal 2 stays absent while the independent observation path remains up.
# This gives a sustained two-node incident window rather than racing StatefulSet
# pod recreation.
echo elasticsearch-2 | tee "$OUT/07-target-node.txt"
kubectl scale statefulset/elasticsearch -n elasticsearch-lab --replicas=2
kubectl wait --for=delete pod/elasticsearch-2 -n elasticsearch-lab --timeout=5m

status=""; nodes=0; prim=99; unassigned=0; h='{}'
for _ in $(seq 1 120); do
  h=$(api "$ES_URL/_cluster/health/scenario01") || { sleep 2; continue; }
  read -r status nodes prim unassigned < <(python3 -c 'import json,sys; h=json.load(sys.stdin); print(h["status"],h["number_of_nodes"],h["unassigned_primary_shards"],h["unassigned_shards"])' <<<"$h")
  if [[ "$status" == yellow && "$nodes" -eq 2 && "$prim" -eq 0 && "$unassigned" -ge 1 ]]; then break; fi
  sleep 2
done
[[ "$status" == yellow && "$nodes" -eq 2 && "$prim" -eq 0 && "$unassigned" -ge 1 ]]
printf '%s\n' "$h" | tee "$OUT/08-yellow-health.json"
api "$ES_URL/_cat/shards/scenario01?format=json&h=index,shard,prirep,state,node,unassigned.reason" | tee "$OUT/09-yellow-shards.json"

shard=$(python3 -c 'import json,sys; x=json.load(open(sys.argv[1])); print(next(s["shard"] for s in x if s["prirep"]=="r" and s["state"]=="UNASSIGNED"))' "$OUT/09-yellow-shards.json")
api -X POST "$ES_URL/_cluster/allocation/explain?include_disk_info=true" -H 'Content-Type: application/json' -d "{\"index\":\"scenario01\",\"shard\":$shard,\"primary\":false}" | tee "$OUT/10-allocation-explain.json"
python3 - "$OUT/10-allocation-explain.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert x.get("current_state")=="unassigned", x
no_disk=False
for node in x.get("node_allocation_decisions", []):
    for d in node.get("deciders", []):
        if d.get("decider")=="disk_threshold" and d.get("decision")=="NO":
            no_disk=True
assert no_disk, x
PY

api "$ES_URL/_cat/thread_pool/search?format=json&h=node_name,name,active,queue,rejected,completed" | tee "$OUT/11-search-thread-pool.json"
api "$ES_URL/_nodes/stats?filter_path=nodes.*.name,nodes.*.jvm.mem.pools.old" | tee "$OUT/12-jvm-old-gen.json"

# Availability check while redundancy is degraded: primaries must remain
# searchable. The scenario index is empty by design, so success and shard status
# matter here rather than hit count.
api -X POST "$ES_URL/scenario01/_search" -H 'Content-Type: application/json' -d '{"size":10,"track_total_hits":false,"query":{"match_all":{}}}' | tee "$OUT/13-yellow-search.json"
python3 - "$OUT/13-yellow-search.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert x.get("timed_out") is False, x
assert x.get("_shards",{}).get("failed")==0, x
PY

# Restore capacity first, then remove the artificial allocation blocker.
kubectl scale statefulset/elasticsearch -n elasticsearch-lab --replicas=3
kubectl wait --for=condition=Ready pod/elasticsearch-2 -n elasticsearch-lab --timeout=10m
api -X PUT "$ES_URL/_cluster/settings" -H 'Content-Type: application/json' -d '{"transient":{"cluster.routing.allocation.disk.watermark.low":null}}' | tee "$OUT/14-clear-training-watermark.json"
final=$(wait_health green 3 0)
printf '%s\n' "$final" | tee "$OUT/15-final-health.json"
api "$ES_URL/_cat/shards/scenario01?format=json&h=index,shard,prirep,state,node" | tee "$OUT/16-final-shards.json"

python3 - "$OUT/16-final-shards.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert len(x)==6, x
assert all(s["state"]=="STARTED" for s in x), x
assert sum(s["prirep"]=="p" for s in x)==3, x
assert sum(s["prirep"]=="r" for s in x)==3, x
PY

echo 'SCENARIO 01 IMPLEMENTATION VALIDATION PASS'
