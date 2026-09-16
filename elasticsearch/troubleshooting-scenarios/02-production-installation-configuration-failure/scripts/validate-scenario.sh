#!/usr/bin/env bash
set +x
set -euo pipefail
umask 077

NS="${NAMESPACE:-elasticsearch-lab-002}"
INDEX="installation-validation-v1"
ES_URL="${ES_URL:-https://localhost:9200}"
ES_USER="${ES_USER:-elastic}"
: "${ES_PASSWORD:?ES_PASSWORD is required}"
: "${ES_CA:?ES_CA is required}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT="${SCENARIO_EVIDENCE:-validation-output}"
# Refuse stale evidence, including a previous PASS marker. Never delete caller data.
mkdir -p "$OUT"
[ -z "$(find "$OUT" -mindepth 1 -print -quit)" ] || { echo 'FAIL: evidence directory must be empty'; exit 1; }
TMP="$(mktemp -d)"
api() { curl --connect-timeout 5 --max-time 200 --retry 3 --retry-delay 2 --retry-connrefused --retry-max-time 45 --silent --show-error --fail --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$@"; }
kubectl() { command kubectl --request-timeout=30s "$@"; }
retry() {
  local deadline=$((SECONDS + $1)); shift
  until "$@"; do
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 3
  done
}
ALLOCATION_DIRTY=0
TLS_DIRTY=0
LOCK_HELD=0
restore_tls() {
  kubectl -n "$NS" patch secret elasticsearch-transport-tls --type merge --patch-file "$TMP/good-patch.json" >/dev/null
}
cleanup() {
  local rc=$? failed=0
  trap - EXIT
  set +e
  if [ "$TLS_DIRTY" -eq 1 ]; then
    retry 60 restore_tls && kubectl -n "$NS" delete pod elasticsearch-2 --wait=true --timeout=150s || failed=1
  fi
  if [ "$ALLOCATION_DIRTY" -eq 1 ]; then
    retry 60 api -X PUT -H 'Content-Type: application/json' "$ES_URL/_cluster/settings" --data-binary @"$TMP/restore-allocation.json" >"$TMP/cleanup-allocation.json" || failed=1
  fi
  if [ "$TLS_DIRTY" -eq 1 ] || [ "$ALLOCATION_DIRTY" -eq 1 ]; then
    api "$ES_URL/_cluster/health?wait_for_nodes=3&wait_for_status=green&timeout=180s" > "$OUT/rollback-health.json" &&
      jq -e '.timed_out==false and .number_of_nodes==3 and .status=="green" and .unassigned_shards==0' "$OUT/rollback-health.json" >/dev/null || failed=1
  fi
  if [ "$LOCK_HELD" -eq 1 ]; then
    kubectl -n "$NS" delete configmap scenario-002-validation-lock --wait=true --timeout=30s >/dev/null || failed=1
  fi
  rm -rf -- "$TMP"
  if [ "$rc" -ne 0 ] || [ "$failed" -ne 0 ]; then
    rm -f -- "$OUT/32-validation-result.txt"
    printf 'FAIL: validation exit=%s; rollback failure=%s\n' "$rc" "$failed" >&2
    exit 1
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
kubectl -n "$NS" create configmap scenario-002-validation-lock --from-literal=purpose=scenario-002-validation >/dev/null
LOCK_HELD=1
bootstrap_evidence() {
  local phase=$1 p
  kubectl -n "$NS" get configmap elasticsearch-config -o json | jq -er '.data["elasticsearch.yml"]' > "$OUT/$phase-configmap.yml"
  for p in elasticsearch-0 elasticsearch-1 elasticsearch-2; do
    kubectl -n "$NS" exec "$p" -c elasticsearch -- cat /usr/share/elasticsearch/config/elasticsearch.yml > "$OUT/$phase-$p-config.yml"
  done
  python3 "$SCRIPT_DIR/verify-evidence.py" bootstrap "$OUT" "$phase"
}
snapshot_extra() {
  local phase=$1
  api "$ES_URL/_cluster/health?pretty" > "$OUT/$phase-cluster-health.json"
  api "$ES_URL/$INDEX/_search?size=10&track_total_hits=true&pretty" > "$OUT/$phase-documents.json"
  api "$ES_URL/$INDEX/_settings?flat_settings=true&pretty" > "$OUT/$phase-index-settings.json"
  api "$ES_URL/$INDEX/_mapping?pretty" > "$OUT/$phase-mapping.json"
  api "$ES_URL/_cat/nodes?format=json" > "$OUT/$phase-nodes.json"
  api "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true&pretty" > "$OUT/$phase-settings.json"
  api "$ES_URL/" > "$OUT/$phase-identity.json"
}
new_pod() {
  local old_uid=$1 new_uid
  new_uid="$(kubectl -n "$NS" get pod elasticsearch-2 -o jsonpath='{.metadata.uid}')" || return 1
  [ -n "$new_uid" ] && [ "$new_uid" != "$old_uid" ]
}
loaded_certificate() {
  local expected=$1 phase=$2
  kubectl -n "$NS" exec elasticsearch-2 -c elasticsearch -- cat /usr/share/elasticsearch/config/certs/transport/tls.crt > "$TMP/loaded.crt" || return 1
  cmp -s "$expected" "$TMP/loaded.crt" || return 1
  openssl x509 -in "$TMP/loaded.crt" -noout -subject -issuer -serial -fingerprint -sha256 > "$OUT/$phase-loaded-certificate.txt" || return 1
  kubectl -n "$NS" get pod elasticsearch-2 -o json | jq '{metadata:{name:.metadata.name,uid:.metadata.uid,creationTimestamp:.metadata.creationTimestamp},status:{podIP:.status.podIP,containerStatuses:.status.containerStatuses}}' > "$OUT/$phase-pod.json"
}
health_matches() {
  local nodes=$1 status=$2
  api --max-time 15 "$ES_URL/_cluster/health/$INDEX" > "$TMP/health.json" || return 1
  jq -e --argjson nodes "$nodes" --arg status "$status" '.number_of_nodes==$nodes and .status==$status and .active_primary_shards==3 and .unassigned_shards>0' "$TMP/health.json" >/dev/null
}

# 1. Healthy baseline and identity/storage evidence.
api "$ES_URL/" > "$OUT/01-baseline-cluster-identity.json"
EXPECTED_UUID="$(jq -r '.cluster_uuid' "$OUT/01-baseline-cluster-identity.json")"
api "$ES_URL/_cat/nodes?format=json" > "$OUT/02-baseline-nodes.json"
api "$ES_URL/_cluster/health/$INDEX?pretty" > "$OUT/03-baseline-health.json"
api "$ES_URL/_cat/shards/$INDEX?format=json&h=index,shard,prirep,state,node,unassigned.reason" > "$OUT/04-baseline-shards.json"
api "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true&pretty" > "$OUT/05-baseline-cluster-settings.json"
kubectl -n "$NS" get pods -o wide > "$OUT/06-baseline-pods.txt"
kubectl -n "$NS" get pvc -o json > "$OUT/07-baseline-pvcs.json"
kubectl get pv -o json > "$OUT/08-baseline-pvs.json"

jq -e '.status=="green" and .number_of_nodes==3 and .unassigned_shards==0' "$OUT/03-baseline-health.json" >/dev/null
[ "$(api "$ES_URL/$INDEX/_count" | jq -r '.count')" -eq 4 ]
jq -e '.cluster_uuid | type=="string" and length>0 and .!="_na_"' "$OUT/01-baseline-cluster-identity.json" >/dev/null
snapshot_extra baseline
bootstrap_evidence baseline


jq -r '.items[] | [.metadata.name,.metadata.uid,.spec.volumeName] | @tsv' "$OUT/07-baseline-pvcs.json" | sort > "$TMP/pvc-before.tsv"
# Save both scopes; transient overrides persistent. Only an effective "all"
# baseline can both restore exactly and finish GREEN without changing the scenario.
api "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true" > "$OUT/original-allocation-state.json"
jq -e '(.transient["cluster.routing.allocation.enable"] // .persistent["cluster.routing.allocation.enable"] // .defaults["cluster.routing.allocation.enable"]) == "all"' "$OUT/original-allocation-state.json" >/dev/null
jq '{persistent:{"cluster.routing.allocation.enable":.persistent["cluster.routing.allocation.enable"]},transient:{"cluster.routing.allocation.enable":.transient["cluster.routing.allocation.enable"]}}' "$OUT/original-allocation-state.json" > "$TMP/restore-allocation.json"
kubectl -n "$NS" get secret elasticsearch-transport-tls -o json > "$TMP/transport-secret.json"
jq '{data:{"elasticsearch-2.crt":.data["elasticsearch-2.crt"],"elasticsearch-2.key":.data["elasticsearch-2.key"]}}' "$TMP/transport-secret.json" > "$TMP/good-patch.json"
jq -er '.data["elasticsearch-2.crt"]' "$TMP/transport-secret.json" | base64 -d > "$TMP/elasticsearch-2.crt"
openssl x509 -in "$TMP/elasticsearch-2.crt" -noout -subject -issuer -serial -fingerprint -sha256 > "$OUT/baseline-certificate.txt"
python3 "$SCRIPT_DIR/verify-evidence.py" baseline "$OUT"

# 2. Contributing fault: replicas requiring a new allocation are blocked.
ALLOCATION_DIRTY=1
api -X PUT -H 'Content-Type: application/json' "$ES_URL/_cluster/settings" \
  -d '{"persistent":{"cluster.routing.allocation.enable":"primaries"},"transient":{"cluster.routing.allocation.enable":null}}' > "$OUT/09-allocation-restriction.json"

# 3. Root fault: replace only node-2 transport identity with a certificate from an untrusted lab CA.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -sha256 \
  -subj '/CN=Scenario-002-Untrusted-CA' \
  -keyout "$TMP/bad-ca.key" -out "$TMP/bad-ca.crt" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj '/CN=elasticsearch-2-invalid' \
  -keyout "$TMP/bad-node.key" -out "$TMP/bad-node.csr" >/dev/null 2>&1
cat >"$TMP/bad-node.ext" <<'EOF'
subjectAltName=DNS:invalid-node-2.invalid
extendedKeyUsage=serverAuth,clientAuth
EOF
openssl x509 -req -days 1 -sha256 -in "$TMP/bad-node.csr" \
  -CA "$TMP/bad-ca.crt" -CAkey "$TMP/bad-ca.key" -CAcreateserial \
  -extfile "$TMP/bad-node.ext" -out "$TMP/bad-node.crt" >/dev/null 2>&1

jq -n --rawfile crt "$TMP/bad-node.crt" --rawfile key "$TMP/bad-node.key" '{data:{"elasticsearch-2.crt":($crt|@base64),"elasticsearch-2.key":($key|@base64)}}' > "$TMP/bad-patch.json"
openssl x509 -in "$TMP/bad-node.crt" -noout -subject -issuer -serial -fingerprint -sha256 > "$OUT/injected-certificate.txt"
old_uid="$(kubectl -n "$NS" get pod elasticsearch-2 -o jsonpath='{.metadata.uid}')"
printf '%s\n' "$old_uid" > "$OUT/baseline-node2-uid.txt"
TLS_DIRTY=1
kubectl -n "$NS" patch secret elasticsearch-transport-tls --type merge --patch-file "$TMP/bad-patch.json" >/dev/null
kubectl delete pod elasticsearch-2 -n "$NS" --wait=true --timeout=150s
retry 120 new_pod "$old_uid"
retry 300 loaded_certificate "$TMP/bad-node.crt" failure
retry 450 health_matches 2 yellow

# Require concrete transport TLS failure evidence. Generic feature/configuration
# strings containing words such as "certificate" must never satisfy this gate.
# Only fresh logs from the injected pod and peers are eligible. The verifier
# requires transport context plus a concrete TLS error in the same log record.
TLS_SINCE="$(jq -r '.metadata.creationTimestamp' "$OUT/failure-pod.json")"
collect_tls() {
  local p
  for p in elasticsearch-0 elasticsearch-1 elasticsearch-2; do
    kubectl -n "$NS" logs "$p" -c elasticsearch --since-time="$TLS_SINCE" --timestamps > "$OUT/$p-transport.log" 2>"$TMP/log-error" || return 1
  done
  python3 "$SCRIPT_DIR/verify-evidence.py" tls "$OUT"
}
retry 450 collect_tls

kubectl -n "$NS" get pods -o wide > "$OUT/10-failure-pods.txt"
kubectl -n "$NS" get pod elasticsearch-2 -o json | jq '{metadata:{name:.metadata.name,uid:.metadata.uid},containers:[.spec.containers[]|{name,image,resources}],status:.status}' > "$OUT/11-elasticsearch-2-diagnostics.json"
api "$ES_URL/" > "$OUT/14-failure-cluster-identity.json"
api "$ES_URL/_cat/nodes?format=json" > "$OUT/15-failure-nodes.json"
api "$ES_URL/_cluster/health/$INDEX?pretty" > "$OUT/16-failure-health.json"
api "$ES_URL/_cat/shards/$INDEX?format=json&h=index,shard,prirep,state,node,unassigned.reason" > "$OUT/17-failure-shards.json"
api "$ES_URL/$INDEX/_settings?flat_settings=true&include_defaults=true&pretty" > "$OUT/18-index-settings.json"
api "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true&pretty" > "$OUT/19-cluster-settings.json"

jq -e '.number_of_nodes==2 and .status=="yellow" and .unassigned_shards>0' "$OUT/16-failure-health.json" >/dev/null
jq -e '[.[] | select(.prirep=="r" and .state=="UNASSIGNED")] | length > 0' "$OUT/17-failure-shards.json" >/dev/null
SHARD="$(jq -r '[.[] | select(.prirep=="r" and .state=="UNASSIGNED")][0].shard' "$OUT/17-failure-shards.json")"
api -X POST -H 'Content-Type: application/json' "$ES_URL/_cluster/allocation/explain?pretty" \
  -d "{\"index\":\"$INDEX\",\"shard\":$SHARD,\"primary\":false}" > "$OUT/20-allocation-explain.json"
snapshot_extra failure
bootstrap_evidence failure
python3 "$SCRIPT_DIR/verify-evidence.py" failure "$OUT"

# 4. Repair only TLS and prove node rejoin is not full recovery.
old_uid="$(kubectl -n "$NS" get pod elasticsearch-2 -o jsonpath='{.metadata.uid}')"
restore_tls
kubectl delete pod elasticsearch-2 -n "$NS" --wait=true --timeout=150s
retry 120 new_pod "$old_uid"
retry 300 loaded_certificate "$TMP/elasticsearch-2.crt" repaired
retry 300 health_matches 3 yellow
TLS_DIRTY=0
snapshot_extra rejoined
bootstrap_evidence rejoined
api "$ES_URL/_cat/shards/$INDEX?format=json&h=index,shard,prirep,state,node,unassigned.reason" > "$OUT/rejoined-shards.json"
api -X POST -H 'Content-Type: application/json' "$ES_URL/_cluster/allocation/explain?pretty" \
  -d "{\"index\":\"$INDEX\",\"shard\":$SHARD,\"primary\":false}" > "$OUT/rejoined-allocation-explain.json"
api "$ES_URL/" > "$OUT/21-post-tls-repair-identity.json"
api "$ES_URL/_cluster/health/$INDEX?pretty" > "$OUT/22-post-rejoin-pre-allocation-restore-health.json"
[ "$(jq -r '.cluster_uuid' "$OUT/21-post-tls-repair-identity.json")" = "$EXPECTED_UUID" ]
jq -e '.number_of_nodes==3 and .status=="yellow" and .unassigned_shards>0' "$OUT/22-post-rejoin-pre-allocation-restore-health.json" >/dev/null

# 5. Restore exact prior allocation state.
python3 "$SCRIPT_DIR/verify-evidence.py" rejoined "$OUT"
api -X PUT -H 'Content-Type: application/json' "$ES_URL/_cluster/settings" --data-binary @"$TMP/restore-allocation.json" > "$OUT/23-allocation-restored.json"
api "$ES_URL/_cat/recovery/$INDEX?format=json" > "$OUT/24-recovery.json"
api "$ES_URL/_cluster/health?wait_for_status=green&wait_for_no_relocating_shards=true&wait_for_no_initializing_shards=true&timeout=180s&pretty" > "$OUT/25-final-health.json"
api "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true&pretty" > "$OUT/26-final-cluster-settings.json"
api "$ES_URL/$INDEX/_count?pretty" > "$OUT/27-final-index-count.json"
kubectl -n "$NS" get pvc -o json > "$OUT/28-final-pvcs.json"
kubectl get pv -o json > "$OUT/29-final-pvs.json"

jq -e '.status=="green" and .number_of_nodes==3 and .unassigned_shards==0' "$OUT/25-final-health.json" >/dev/null
[ "$(jq -r '.count' "$OUT/27-final-index-count.json")" -eq 4 ]
[ "$(api "$ES_URL/" | jq -r '.cluster_uuid')" = "$EXPECTED_UUID" ]
jq -r '.items[] | [.metadata.name,.metadata.uid,.spec.volumeName] | @tsv' "$OUT/28-final-pvcs.json" | sort > "$TMP/pvc-after.tsv"
diff -u "$TMP/pvc-before.tsv" "$TMP/pvc-after.tsv" > "$OUT/30-pvc-continuity.diff" || { cat "$OUT/30-pvc-continuity.diff"; exit 1; }
bootstrap_evidence final

snapshot_extra final
api "$ES_URL/_cat/shards/$INDEX?format=json&h=index,shard,prirep,state,node,unassigned.reason" > "$OUT/final-shards.json"
api "$ES_URL/_nodes/stats/process?pretty" > "$OUT/final-process.json"

BAD_AUTH="$(curl --connect-timeout 5 --max-time 30 --silent --show-error --output "$OUT/31-negative-auth.json" --write-out '%{http_code}' --cacert "$ES_CA" -u "$ES_USER:deliberately-wrong-password" "$ES_URL/" || true)"
printf '%s\n' "$BAD_AUTH" > "$OUT/negative-auth-status.txt"
[ "$BAD_AUTH" = 401 ]

python3 "$SCRIPT_DIR/verify-evidence.py" all "$OUT"
ALLOCATION_DIRTY=0
python3 "$SCRIPT_DIR/verify-evidence.py" sanitize "$OUT"
printf 'SCENARIO 002 IMPLEMENTATION VALIDATION PASS\n' | tee "$OUT/32-validation-result.txt"
