#!/usr/bin/env bash
set -euo pipefail
: "${ES_URL:?}" "${ES_USER:?}" "${ES_PASSWORD:?}" "${ES_CA:?}"
CURL=(curl --fail --silent --show-error --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD")

"${CURL[@]}" -X PUT "$ES_URL/installation-validation-v1" -H 'Content-Type: application/json' -d '{"settings":{"number_of_shards":3,"number_of_replicas":1},"mappings":{"properties":{"patient_id":{"type":"keyword"},"facility":{"type":"keyword"},"event_time":{"type":"date"},"description":{"type":"text"}}}}' >/dev/null
bulk="$("${CURL[@]}" -X POST "$ES_URL/_bulk?refresh=true" -H 'Content-Type: application/x-ndjson' --data-binary @data/validation.ndjson)"
[ "$(jq -r '.errors' <<<"$bulk")" = false ] || { echo 'FAIL: bulk errors'; exit 1; }
[ "$("${CURL[@]}" "$ES_URL/installation-validation-v1/_count" | jq -r '.count')" -eq 4 ] || { echo 'FAIL: count'; exit 1; }
settings="$("${CURL[@]}" "$ES_URL/installation-validation-v1/_settings?flat_settings=true")"
[ "$(jq -r '.[].settings["index.number_of_shards"]' <<<"$settings")" = 3 ] || exit 1
[ "$(jq -r '.[].settings["index.number_of_replicas"]' <<<"$settings")" = 1 ] || exit 1
mapping="$("${CURL[@]}" "$ES_URL/installation-validation-v1/_mapping")"
for pair in patient_id:keyword facility:keyword event_time:date description:text; do
  field="${pair%%:*}"; type="${pair##*:}"
  [ "$(jq -r --arg f "$field" '.[].mappings.properties[$f].type' <<<"$mapping")" = "$type" ] || exit 1
done
health="$("${CURL[@]}" "$ES_URL/_cluster/health/installation-validation-v1?wait_for_status=green&timeout=120s")"
[ "$(jq -r '.status' <<<"$health")" = green ] || exit 1
[ "$(jq -r '.unassigned_shards' <<<"$health")" -eq 0 ] || exit 1
shards="$("${CURL[@]}" "$ES_URL/_cat/shards/installation-validation-v1?format=json")"
[ "$(jq '[.[]|select(.prirep=="p" and .state=="STARTED")]|length' <<<"$shards")" -eq 3 ] || exit 1
[ "$(jq '[.[]|select(.prirep=="r" and .state=="STARTED")]|length' <<<"$shards")" -eq 3 ] || exit 1
echo 'PASS: deterministic index validation'
