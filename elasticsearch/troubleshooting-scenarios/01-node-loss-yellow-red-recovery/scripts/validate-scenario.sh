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

# Baseline: Lab 01 must be healthy before injecting the scenario.
baseline=$(wait_health green 3 0)
printf '%s\n' "$baseline" | tee "$OUT/01-baseline-health.json"

# Create a dedicated synthetic scenario index. Three primaries ensure every node
# can host one primary when allocation is balanced; zero replicas make placement
# deterministic enough to identify a node to remove, then replicas are enabled.
api -X DELETE "$ES_URL/scenario01" >/dev/null 2>&1 || true
api -X PUT "$ES_URL/scenario01" -H 'Content-Type: application/json' -d '{
  "settings": {"number_of_shards":3,"number_of_replicas":0},
  "mappings": {"properties":{"event_date":{"type":"date"},"status":{"type":"keyword"}}}
}' | tee "$OUT/02-create-index.json"

for i in $(seq 1 30); do
  started=$(api "$ES_URL/_cat/shards/scenario01?format=json&h=prirep,state,node" | python3 -c 'import json,sys; x=json.load(sys.stdin); print(sum(1 for s in x if s["prirep"]=="p" and s["state"]=="STARTED"))')
  [[ "$started" -eq 3 ]] && break
  sleep 1
done
[[ "$started" -eq 3 ]]

api -X PUT "$ES_URL/scenario01/_settings" -H 'Content-Type: application/json' -d '{"index":{"number_of_replicas":1}}' | tee "$OUT/03-enable-replicas.json"
for _ in $(seq 1 60); do
  h=$(api "$ES_URL/_cluster/health/scenario01")
  [[ "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$h")" == green ]] && break
  sleep 1
done
[[ "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$h")" == green ]]
api "$ES_URL/_cat/shards/scenario01?format=json&h=index,shard,prirep,state,node" | tee "$OUT/04-green-shards.json"

# Deliberately strict TRAINING-ONLY low watermark. Both surviving nodes are
# expected to be above 1% used, so a missing replica cannot be newly allocated.
api -X PUT "$ES_URL/_cluster/settings" -H 'Content-Type: application/json' -d '{"transient":{"cluster.routing.allocation.disk.watermark.low":"1%"}}' | tee "$OUT/05-set-training-watermark.json"
api "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true" | tee "$OUT/06-cluster-settings.json"
grep -q 'cluster.routing.allocation.disk.watermark.low' "$OUT/06-cluster-settings.json"

# Select a node hosting a scenario primary. Deleting its pod exercises real
# replica promotion. The strict low watermark prevents restoration of at least
# one lost replica while only two nodes are present.
target_node=$(api "$ES_URL/_cat/shards/scenario01?format=json&h=prirep,state,node" | python3 -c 'import json,sys; x=json.load(sys.stdin); print(next(s["node"] for s in x if s["prirep"]=="p" and s["state"]=="STARTED"))')
echo "$target_node" | tee "$OUT/07-target-node.txt"
kubectl delete pod "$target_node" -n elasticsearch-lab --wait=false

# Wait until ES observes two nodes and a degraded scenario index.
for _ in $(seq 1 120); do
  h=$(api "$ES_URL/_cluster/health/scenario01") || { sleep 2; continue; }
  read -r status nodes prim unassigned < <(python3 -c 'import json,sys; h=json.load(sys.stdin); print(h["status"],h["number_of_nodes"],h["unassigned_primary_shards"],h["unassigned_shards"])' <<<"$h")
  if [[ "$status" == yellow && "$nodes" -eq 2 && "$prim" -eq 0 && "$unassigned" -ge 1 ]]; then break; fi
  sleep 2
done
[[ "$status" == yellow && "$nodes" -eq 2 && "$prim" -eq 0 && "$unassigned" -ge 1 ]]
printf '%s\n' "$h" | tee "$OUT/08-yellow-health.json"
api "$ES_URL/_cat/shards/scenario01?format=json&h=index,shard,prirep,state,node,unassigned.reason" | tee "$OUT/09-yellow-shards.json"

# Ask ES to explain one unassigned replica and require the disk-threshold
# decider to be part of the evidence.
read -r shard < <(python3 -c 'import json,sys; x=json.load(open(sys.argv[1])); print(next(s["shard"] for s in x if s["prirep"]=="r" and s["state"]=="UNASSIGNED"))' "$OUT/09-yellow-shards.json")
api -X POST "$ES_URL/_cluster/allocation/explain?include_disk_info=true" -H 'Content-Type: application/json' -d "{\"index\":\"scenario01\",\"shard\":$shard,\"primary\":false}" | tee "$OUT/10-allocation-explain.json"
python3 - "$OUT/10-allocation-explain.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert x.get("current_state")=="unassigned", x
text=json.dumps(x)
assert "disk_threshold" in text, x
assert '"decision": "NO"' in text or '"decision":"NO"' in text, x
PY

# Capture safe observational backpressure/JVM diagnostics. We intentionally do
# not create an uncontrolled OOM or rejection storm in CI.
api "$ES_URL/_cat/thread_pool/search?format=json&h=node_name,name,active,queue,rejected,completed" | tee "$OUT/11-search-thread-pool.json"
api "$ES_URL/_nodes/stats?filter_path=nodes.*.name,nodes.*.jvm.mem.pools.old" | tee "$OUT/12-jvm-old-gen.json"

# Wait for Kubernetes to recreate the deleted pod. With the strict watermark,
# it may rejoin quickly; the important failure-state evidence was captured above.
kubectl wait --for=condition=Ready "pod/$target_node" -n elasticsearch-lab --timeout=10m

# Remove the training-only setting and require full recovery.
api -X PUT "$ES_URL/_cluster/settings" -H 'Content-Type: application/json' -d '{"transient":{"cluster.routing.allocation.disk.watermark.low":null}}' | tee "$OUT/13-clear-training-watermark.json"
final=$(wait_health green 3 0)
printf '%s\n' "$final" | tee "$OUT/14-final-health.json"
api "$ES_URL/_cat/shards/scenario01?format=json&h=index,shard,prirep,state,node" | tee "$OUT/15-final-shards.json"

python3 - "$OUT/15-final-shards.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert len(x)==6, x
assert all(s["state"]=="STARTED" for s in x), x
assert sum(s["prirep"]=="p" for s in x)==3, x
assert sum(s["prirep"]=="r" for s in x)==3, x
PY

echo 'SCENARIO 01 IMPLEMENTATION VALIDATION PASS'
