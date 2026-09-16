#!/usr/bin/env bash
set -euo pipefail
: "${ES_URL:?}" "${ES_USER:?}" "${ES_PASSWORD:?}" "${ES_CA:?}" "${EXPECTED_CLUSTER_UUID:?}"
NS=elasticsearch-lab-002
CURL=(curl --connect-timeout 5 --max-time 140 --fail --silent --show-error --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD")

start_port_forward() {
  local pod="$1"
  if [ -f /tmp/es-pf.pid ]; then
    kill "$(cat /tmp/es-pf.pid)" 2>/dev/null || true
    wait "$(cat /tmp/es-pf.pid)" 2>/dev/null || true
  fi
  kubectl -n "$NS" port-forward "pod/$pod" 9200:9200 > /tmp/es-pf.log 2>&1 &
  echo $! > /tmp/es-pf.pid

  for _ in $(seq 1 30); do
    if kill -0 "$(cat /tmp/es-pf.pid)" 2>/dev/null && "${CURL[@]}" "$ES_URL/" >/dev/null 2>&1; then
      echo "PASS: API tunnel active through $pod"
      return 0
    fi
    sleep 2
  done
  echo "FAIL: API tunnel did not become healthy through $pod"
  cat /tmp/es-pf.log || true
  exit 1
}

precheck() {
  local nodes_json identity h count
  nodes_json="$("${CURL[@]}" "$ES_URL/_cat/nodes?format=json")" || { echo 'FAIL: Elasticsearch API unavailable during node-count precheck'; exit 1; }
  [ "$(jq 'length' <<<"$nodes_json")" -eq 3 ] || { echo 'FAIL: node count'; exit 1; }

  identity="$("${CURL[@]}" "$ES_URL/")" || { echo 'FAIL: Elasticsearch API unavailable during cluster-identity precheck'; exit 1; }
  [ "$(jq -r '.cluster_uuid' <<<"$identity")" = "$EXPECTED_CLUSTER_UUID" ] || { echo 'FAIL: cluster UUID mismatch; STOP and preserve evidence'; exit 1; }

  h="$("${CURL[@]}" "$ES_URL/_cluster/health/installation-validation-v1?wait_for_status=green&timeout=120s")" || { echo 'FAIL: health API unavailable'; exit 1; }
  [ "$(jq -r '.status' <<<"$h")" = green ] && [ "$(jq -r '.unassigned_shards' <<<"$h")" -eq 0 ] || { echo 'FAIL: pre-restart health'; exit 1; }

  count="$("${CURL[@]}" "$ES_URL/installation-validation-v1/_count")" || { echo 'FAIL: count API unavailable'; exit 1; }
  [ "$(jq -r '.count' <<<"$count")" -eq 4 ] || { echo 'FAIL: pre-restart data'; exit 1; }
}

for pod in elasticsearch-2 elasticsearch-1 elasticsearch-0; do
  precheck

  # The workflow initially pins the API tunnel to elasticsearch-0. Before
  # restarting that pod, hand the control path to a surviving node so the
  # validation harness does not fail merely because its port-forward target
  # was intentionally deleted.
  if [ "$pod" = elasticsearch-0 ]; then
    start_port_forward elasticsearch-1
    precheck
  fi

  old_uid="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.metadata.uid}')"
  pvc="data-$pod"
  pvc_uid="$(kubectl -n "$NS" get pvc "$pvc" -o jsonpath='{.metadata.uid}')"
  pv="$(kubectl -n "$NS" get pvc "$pvc" -o jsonpath='{.spec.volumeName}')"
  kubectl -n "$NS" delete pod "$pod" --wait=true --timeout=150s
  # A named wait can fail with NotFound between deletion and recreation.
  for i in $(seq 1 60); do
    new_uid="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
    [ -n "$new_uid" ] && [ "$new_uid" != "$old_uid" ] && break
    [ "$i" -lt 60 ] || { echo 'FAIL: replacement pod not created'; exit 1; }
    sleep 2
  done
  kubectl -n "$NS" wait --for=condition=Ready "pod/$pod" --timeout=300s
  new_uid="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.metadata.uid}')"
  [ "$new_uid" != "$old_uid" ] || { echo 'FAIL: pod UID did not change'; exit 1; }
  [ "$(kubectl -n "$NS" get pvc "$pvc" -o jsonpath='{.metadata.uid}')" = "$pvc_uid" ] || { echo 'FAIL: PVC UID changed'; exit 1; }
  [ "$(kubectl -n "$NS" get pvc "$pvc" -o jsonpath='{.spec.volumeName}')" = "$pv" ] || { echo 'FAIL: PV changed'; exit 1; }
  runtime_config="$(kubectl -n "$NS" exec "$pod" -c elasticsearch -- cat /usr/share/elasticsearch/config/elasticsearch.yml)"
  if [ -z "$runtime_config" ] || grep -q 'cluster.initial_master_nodes' <<<"$runtime_config"; then
    echo 'FAIL: invalid runtime config'; exit 1
  fi
  # TCP readiness precedes discovery; retry the full precheck in a subshell
  # so its explicit failures remain failures inside the conditional.
  for i in $(seq 1 60); do
    if (precheck); then break; fi
    [ "$i" -lt 60 ] || { echo 'FAIL: node did not rejoin'; exit 1; }
    sleep 2
  done
  echo "PASS: $pod restart/rejoin with persistent storage and same cluster UUID"
done
