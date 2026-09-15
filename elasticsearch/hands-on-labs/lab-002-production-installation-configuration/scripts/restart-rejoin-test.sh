#!/usr/bin/env bash
set -euo pipefail
: "${ES_URL:?}" "${ES_USER:?}" "${ES_PASSWORD:?}" "${ES_CA:?}" "${EXPECTED_CLUSTER_UUID:?}"
NS=elasticsearch-lab-002
CURL=(curl --fail --silent --show-error --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD")

precheck() {
  [ "$("${CURL[@]}" "$ES_URL/_cat/nodes?format=json" | jq 'length')" -eq 3 ] || { echo 'FAIL: node count'; exit 1; }
  [ "$("${CURL[@]}" "$ES_URL/" | jq -r '.cluster_uuid')" = "$EXPECTED_CLUSTER_UUID" ] || { echo 'FAIL: cluster UUID mismatch; STOP and preserve evidence'; exit 1; }
  h="$("${CURL[@]}" "$ES_URL/_cluster/health/installation-validation-v1?wait_for_status=green&timeout=120s")"
  [ "$(jq -r '.status' <<<"$h")" = green ] && [ "$(jq -r '.unassigned_shards' <<<"$h")" -eq 0 ] || { echo 'FAIL: pre-restart health'; exit 1; }
  [ "$("${CURL[@]}" "$ES_URL/installation-validation-v1/_count" | jq -r '.count')" -eq 4 ] || { echo 'FAIL: pre-restart data'; exit 1; }
}

for pod in elasticsearch-2 elasticsearch-1 elasticsearch-0; do
  precheck
  old_uid="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.metadata.uid}')"
  pvc="data-$pod"
  pvc_uid="$(kubectl -n "$NS" get pvc "$pvc" -o jsonpath='{.metadata.uid}')"
  pv="$(kubectl -n "$NS" get pvc "$pvc" -o jsonpath='{.spec.volumeName}')"
  kubectl -n "$NS" delete pod "$pod" --wait=true
  kubectl -n "$NS" wait --for=condition=Ready "pod/$pod" --timeout=300s
  new_uid="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.metadata.uid}')"
  [ "$new_uid" != "$old_uid" ] || { echo 'FAIL: pod UID did not change'; exit 1; }
  [ "$(kubectl -n "$NS" get pvc "$pvc" -o jsonpath='{.metadata.uid}')" = "$pvc_uid" ] || { echo 'FAIL: PVC UID changed'; exit 1; }
  [ "$(kubectl -n "$NS" get pvc "$pvc" -o jsonpath='{.spec.volumeName}')" = "$pv" ] || { echo 'FAIL: PV changed'; exit 1; }
  if kubectl -n "$NS" exec "$pod" -- grep -q '^cluster.initial_master_nodes:' /usr/share/elasticsearch/config/elasticsearch.yml; then
    echo 'FAIL: bootstrap setting present after runtime restart'; exit 1
  fi
  precheck
  echo "PASS: $pod restart/rejoin with persistent storage and same cluster UUID"
done
