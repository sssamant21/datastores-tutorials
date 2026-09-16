#!/usr/bin/env bash
set -euo pipefail

NS="${NAMESPACE:-elasticsearch-lab-002}"
INDEX="installation-validation-v1"
ES_URL="${ES_URL:-https://localhost:9200}"
ES_USER="${ES_USER:-elastic}"
: "${ES_PASSWORD:?ES_PASSWORD is required}"
: "${ES_CA:?ES_CA is required}"

OUT="${SCENARIO_EVIDENCE:-validation-output}"
mkdir -p "$OUT" /tmp/scenario-002
api() { curl --silent --show-error --fail --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$@"; }

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
[ -n "$EXPECTED_UUID" ] && [ "$EXPECTED_UUID" != "_na_" ]
for p in elasticsearch-0 elasticsearch-1 elasticsearch-2; do
  kubectl exec -n "$NS" "$p" -- sh -c '! grep -q "cluster.initial_master_nodes" /usr/share/elasticsearch/config/elasticsearch.yml'
done

jq -r '.items[] | [.metadata.name,.metadata.uid,.spec.volumeName] | @tsv' "$OUT/07-baseline-pvcs.json" | sort > /tmp/scenario-002/pvc-before.tsv
ORIGINAL_ALLOCATION="$(api "$ES_URL/_cluster/settings?flat_settings=true" | jq -r '.persistent["cluster.routing.allocation.enable"] // "__ABSENT__"')"
printf '%s\n' "$ORIGINAL_ALLOCATION" > "$OUT/original-allocation-state.txt"

kubectl -n "$NS" get secret elasticsearch-transport-tls -o jsonpath='{.data.elasticsearch-2\.crt}' | base64 -d > /tmp/scenario-002/elasticsearch-2.crt
kubectl -n "$NS" get secret elasticsearch-transport-tls -o jsonpath='{.data.elasticsearch-2\.key}' | base64 -d > /tmp/scenario-002/elasticsearch-2.key

# 2. Contributing fault: replicas requiring a new allocation are blocked.
api -X PUT -H 'Content-Type: application/json' "$ES_URL/_cluster/settings" \
  -d '{"persistent":{"cluster.routing.allocation.enable":"primaries"}}' > "$OUT/09-allocation-restriction.json"

# 3. Root fault: replace only node-2 transport identity with a certificate from an untrusted lab CA.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -sha256 \
  -subj '/CN=Scenario-002-Untrusted-CA' \
  -keyout /tmp/scenario-002/bad-ca.key -out /tmp/scenario-002/bad-ca.crt >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj '/CN=elasticsearch-2-invalid' \
  -keyout /tmp/scenario-002/bad-node.key -out /tmp/scenario-002/bad-node.csr >/dev/null 2>&1
cat >/tmp/scenario-002/bad-node.ext <<'EOF'
subjectAltName=DNS:invalid-node-2.invalid
extendedKeyUsage=serverAuth,clientAuth
EOF
openssl x509 -req -days 1 -sha256 -in /tmp/scenario-002/bad-node.csr \
  -CA /tmp/scenario-002/bad-ca.crt -CAkey /tmp/scenario-002/bad-ca.key -CAcreateserial \
  -extfile /tmp/scenario-002/bad-node.ext -out /tmp/scenario-002/bad-node.crt >/dev/null 2>&1

BAD_CRT="$(base64 -w0 /tmp/scenario-002/bad-node.crt)"
BAD_KEY="$(base64 -w0 /tmp/scenario-002/bad-node.key)"
kubectl -n "$NS" patch secret elasticsearch-transport-tls --type merge \
  -p "{\"data\":{\"elasticsearch-2.crt\":\"$BAD_CRT\",\"elasticsearch-2.key\":\"$BAD_KEY\"}}"
kubectl delete pod elasticsearch-2 -n "$NS" --wait=true

for i in $(seq 1 90); do
  nodes="$(api "$ES_URL/_cluster/health" | jq -r '.number_of_nodes' || echo 0)"
  status="$(api "$ES_URL/_cluster/health/$INDEX" | jq -r '.status' || echo unknown)"
  if [ "$nodes" -eq 2 ] && [ "$status" = yellow ]; then break; fi
  sleep 5
  [ "$i" -lt 90 ] || { echo 'FAIL: deterministic 2-node/YELLOW state not observed'; exit 1; }
done

# Require concrete transport TLS failure evidence. Generic feature/configuration
# strings containing words such as "certificate" must never satisfy this gate.
TLS_EVIDENCE=0
TLS_FAILURE_RE='SSLHandshakeException|javax\.net\.ssl\.SSLException|failed to establish trust with server|failed to establish trust with client|certificate_unknown|bad_certificate|unknown_ca|unable to find valid certification path|PKIX path|CertPathValidatorException|certificate verify failed|No subject alternative DNS name matching|No subject alternative names matching|x509.*(unknown|invalid|verify|verification|trust)|handshake.*(failed|failure|exception)|SSL.*handshake.*(failed|failure|exception)'
for i in $(seq 1 90); do
  kubectl -n "$NS" logs elasticsearch-2 --tail=400 > "$OUT/12-elasticsearch-2-current.log" 2>&1 || true
  kubectl -n "$NS" logs elasticsearch-2 --previous --tail=400 > "$OUT/13-elasticsearch-2-previous.log" 2>&1 || true
  cat "$OUT/12-elasticsearch-2-current.log" "$OUT/13-elasticsearch-2-previous.log" > /tmp/scenario-002/node2-all.log
  if grep -Eiq "$TLS_FAILURE_RE" /tmp/scenario-002/node2-all.log; then
    TLS_EVIDENCE=1
    grep -Ei "$TLS_FAILURE_RE" /tmp/scenario-002/node2-all.log > "$OUT/transport-tls-failure-evidence.txt" || true
    break
  fi
  sleep 5
  [ "$i" -lt 90 ] || break
done
[ "$TLS_EVIDENCE" -eq 1 ] || { echo 'FAIL: node-2 did not emit concrete transport TLS handshake/trust/certificate-validation failure evidence within timeout'; exit 1; }

kubectl -n "$NS" get pods -o wide > "$OUT/10-failure-pods.txt"
kubectl -n "$NS" describe pod elasticsearch-2 > "$OUT/11-elasticsearch-2-describe.txt" 2>&1 || true
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
jq -e '.allocate_explanation and ([.node_allocation_decisions[]?.deciders[]? | select(.decision=="NO")] | length > 0)' "$OUT/20-allocation-explain.json" >/dev/null

# 4. Repair only TLS and prove node rejoin is not full recovery.
GOOD_CRT="$(base64 -w0 /tmp/scenario-002/elasticsearch-2.crt)"
GOOD_KEY="$(base64 -w0 /tmp/scenario-002/elasticsearch-2.key)"
kubectl -n "$NS" patch secret elasticsearch-transport-tls --type merge \
  -p "{\"data\":{\"elasticsearch-2.crt\":\"$GOOD_CRT\",\"elasticsearch-2.key\":\"$GOOD_KEY\"}}"
kubectl delete pod elasticsearch-2 -n "$NS" --wait=true
kubectl wait --for=condition=Ready pod/elasticsearch-2 -n "$NS" --timeout=600s

for i in $(seq 1 60); do
  nodes="$(api "$ES_URL/_cluster/health" | jq -r '.number_of_nodes')"
  [ "$nodes" -eq 3 ] && break
  sleep 5
done
api "$ES_URL/" > "$OUT/21-post-tls-repair-identity.json"
api "$ES_URL/_cluster/health/$INDEX?pretty" > "$OUT/22-post-rejoin-pre-allocation-restore-health.json"
[ "$(jq -r '.cluster_uuid' "$OUT/21-post-tls-repair-identity.json")" = "$EXPECTED_UUID" ]
jq -e '.number_of_nodes==3 and .status=="yellow" and .unassigned_shards>0' "$OUT/22-post-rejoin-pre-allocation-restore-health.json" >/dev/null

# 5. Restore exact prior allocation state.
if [ "$ORIGINAL_ALLOCATION" = "__ABSENT__" ]; then
  RESTORE_JSON='{"persistent":{"cluster.routing.allocation.enable":null}}'
else
  RESTORE_JSON="$(jq -nc --arg v "$ORIGINAL_ALLOCATION" '{persistent:{"cluster.routing.allocation.enable":$v}}')"
fi
api -X PUT -H 'Content-Type: application/json' "$ES_URL/_cluster/settings" -d "$RESTORE_JSON" > "$OUT/23-allocation-restored.json"
api "$ES_URL/_cat/recovery/$INDEX?format=json" > "$OUT/24-recovery.json"
api "$ES_URL/_cluster/health/$INDEX?wait_for_status=green&wait_for_no_relocating_shards=true&timeout=180s&pretty" > "$OUT/25-final-health.json"
api "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true&pretty" > "$OUT/26-final-cluster-settings.json"
api "$ES_URL/$INDEX/_count?pretty" > "$OUT/27-final-index-count.json"
kubectl -n "$NS" get pvc -o json > "$OUT/28-final-pvcs.json"
kubectl get pv -o json > "$OUT/29-final-pvs.json"

jq -e '.status=="green" and .number_of_nodes==3 and .unassigned_shards==0' "$OUT/25-final-health.json" >/dev/null
[ "$(jq -r '.count' "$OUT/27-final-index-count.json")" -eq 4 ]
[ "$(api "$ES_URL/" | jq -r '.cluster_uuid')" = "$EXPECTED_UUID" ]
jq -r '.items[] | [.metadata.name,.metadata.uid,.spec.volumeName] | @tsv' "$OUT/28-final-pvcs.json" | sort > /tmp/scenario-002/pvc-after.tsv
diff -u /tmp/scenario-002/pvc-before.tsv /tmp/scenario-002/pvc-after.tsv > "$OUT/30-pvc-continuity.diff" || { cat "$OUT/30-pvc-continuity.diff"; exit 1; }
for p in elasticsearch-0 elasticsearch-1 elasticsearch-2; do
  kubectl exec -n "$NS" "$p" -- sh -c '! grep -q "cluster.initial_master_nodes" /usr/share/elasticsearch/config/elasticsearch.yml'
done

FINAL_EXPLICIT="$(api "$ES_URL/_cluster/settings?flat_settings=true" | jq -r '.persistent["cluster.routing.allocation.enable"] // "__ABSENT__"')"
[ "$FINAL_EXPLICIT" = "$ORIGINAL_ALLOCATION" ] || { echo "FAIL: allocation state not restored: original=$ORIGINAL_ALLOCATION final=$FINAL_EXPLICIT"; exit 1; }

BAD_AUTH="$(curl --silent --output "$OUT/31-negative-auth.json" --write-out '%{http_code}' --cacert "$ES_CA" -u "$ES_USER:deliberately-wrong-password" "$ES_URL/" || true)"
[ "$BAD_AUTH" = 401 ]

rm -rf /tmp/scenario-002
printf 'SCENARIO 002 IMPLEMENTATION VALIDATION PASS\n' | tee "$OUT/32-validation-result.txt"
