#!/usr/bin/env bash
set -euo pipefail

NS=${NS:-elasticsearch-lab}
ES_URL=${ES_URL:-https://localhost:9200}
ES_USER=${ES_USER:-elastic}
: "${ES_PASSWORD:?Set ES_PASSWORD}"
: "${ES_CA:?Set ES_CA to the CA certificate path}"

es() { curl --fail --silent --show-error --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$@"; }
mkdir -p validation-output

echo '== Kubernetes =='
kubectl get sts,pods,pvc -n "$NS" | tee validation-output/kubernetes-baseline.txt
kubectl wait --for=condition=Ready pod -l app=elasticsearch -n "$NS" --timeout=10m

ready=$(kubectl get pods -l app=elasticsearch -n "$NS" --field-selector=status.phase=Running --no-headers | wc -l | tr -d ' ')
test "$ready" -eq 3
restart_sum=$(kubectl get pods -l app=elasticsearch -n "$NS" -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{s+=$1} END {print s+0}')
test "$restart_sum" -eq 0

echo '== Elasticsearch membership =='
es "$ES_URL/_cluster/health?wait_for_nodes=3&timeout=120s&pretty" | tee validation-output/cluster-health-baseline.json
nodes=$(es "$ES_URL/_cluster/health" | python3 -c 'import json,sys; print(json.load(sys.stdin)["number_of_nodes"])')
test "$nodes" -eq 3
version=$(es "$ES_URL/" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"]["number"])')
test "$version" = '9.5.3'

echo '== Create index =='
es -X PUT "$ES_URL/patients-v1" -H 'Content-Type: application/json' --data-binary @configs/patients-v1.json >/dev/null

echo '== Verify settings and mapping =='
es "$ES_URL/patients-v1/_settings" > validation-output/index-settings.json
es "$ES_URL/patients-v1/_mapping" > validation-output/index-mapping.json
python3 - <<'PY'
import json
s=json.load(open('validation-output/index-settings.json'))['patients-v1']['settings']['index']
assert int(s['number_of_shards']) == 3, s
assert int(s['number_of_replicas']) == 1, s
m=json.load(open('validation-output/index-mapping.json'))['patients-v1']['mappings']
assert isinstance(m.get('properties'), dict) and m['properties'], m
PY

echo '== Bulk load =='
es -X POST "$ES_URL/_bulk?refresh=true" -H 'Content-Type: application/x-ndjson' --data-binary @data/patients.ndjson > validation-output/bulk.json
python3 - <<'PY'
import json
result=json.load(open('validation-output/bulk.json'))
assert result['errors'] is False, result
PY

echo '== Count and search =='
count=$(es "$ES_URL/patients-v1/_count" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])')
test "$count" -eq 4
es "$ES_URL/patients-v1/_search?size=10" > validation-output/search-baseline.json
hits=$(python3 -c 'import json; print(json.load(open("validation-output/search-baseline.json"))["hits"]["total"]["value"])')
test "$hits" -eq 4

echo '== Shards =='
es "$ES_URL/_cat/shards/patients-v1?format=json&h=index,shard,prirep,state,node" > validation-output/shards-baseline.json
python3 - <<'PY'
import json
x=json.load(open('validation-output/shards-baseline.json'))
p=[s for s in x if s['prirep']=='p']
r=[s for s in x if s['prirep']=='r']
assert len(p)==3, x
assert len(r)==3, x
PY

health=$(es "$ES_URL/_cluster/health/patients-v1?wait_for_status=green&timeout=180s" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
test "$health" = green

echo 'BASELINE VALIDATION PASS'
