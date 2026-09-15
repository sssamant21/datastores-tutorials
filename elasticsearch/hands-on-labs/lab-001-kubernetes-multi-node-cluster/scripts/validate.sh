#!/usr/bin/env bash
set -euo pipefail

NS=${NS:-elasticsearch-lab}
ES_URL=${ES_URL:-https://localhost:9200}
ES_USER=${ES_USER:-elastic}
: "${ES_PASSWORD:?Set ES_PASSWORD}"
: "${ES_CA:?Set ES_CA to the CA certificate path}"

es() { curl --fail --silent --show-error --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$@"; }

echo '== Kubernetes =='
kubectl get sts,pods,pvc -n "$NS"
kubectl wait --for=condition=Ready pod -l app=elasticsearch -n "$NS" --timeout=10m

ready=$(kubectl get pods -l app=elasticsearch -n "$NS" --field-selector=status.phase=Running --no-headers | wc -l | tr -d ' ')
test "$ready" -eq 3

echo '== Elasticsearch membership =='
es "$ES_URL/_cluster/health?wait_for_nodes=3&timeout=120s&pretty"
nodes=$(es "$ES_URL/_cluster/health" | python3 -c 'import json,sys; print(json.load(sys.stdin)["number_of_nodes"])')
test "$nodes" -eq 3

echo '== Create index =='
es -X PUT "$ES_URL/patients-v1" -H 'Content-Type: application/json' --data-binary @configs/patients-v1.json >/dev/null

echo '== Bulk load =='
es -X POST "$ES_URL/_bulk?refresh=true" -H 'Content-Type: application/x-ndjson' --data-binary @data/patients.ndjson >/tmp/bulk.json
python3 - <<'PY'
import json
with open('/tmp/bulk.json') as f:
    result=json.load(f)
assert result['errors'] is False, result
PY

echo '== Count =='
count=$(es "$ES_URL/patients-v1/_count" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])')
test "$count" -eq 4

echo '== Shards =='
es "$ES_URL/_cat/shards/patients-v1?v&h=index,shard,prirep,state,node"

health=$(es "$ES_URL/_cluster/health/patients-v1?wait_for_status=green&timeout=180s" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
test "$health" = green

echo 'BASELINE VALIDATION PASS'
