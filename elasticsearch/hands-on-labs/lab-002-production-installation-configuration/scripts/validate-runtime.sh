#!/usr/bin/env bash
set -euo pipefail
: "${ES_URL:?}" "${ES_USER:?}" "${ES_PASSWORD:?}" "${ES_CA:?}"
CURL=(curl --fail --silent --show-error --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD")
root="$("${CURL[@]}" "$ES_URL/")"
[ "$(jq -r '.version.number' <<<"$root")" = 9.5.3 ] || { echo 'FAIL: ES version'; exit 1; }
[ "$("${CURL[@]}" "$ES_URL/_cat/nodes?format=json" | jq 'length')" -eq 3 ] || exit 1
fd="$("${CURL[@]}" "$ES_URL/_nodes/stats/process?filter_path=nodes.*.name,nodes.*.process.max_file_descriptors")"
[ "$(jq '[.nodes[] | select(.process.max_file_descriptors < 65535)] | length' <<<"$fd")" -eq 0 ] || { echo 'FAIL: file descriptors'; exit 1; }
settings="$("${CURL[@]}" "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true")"
[ "$(jq '.transient | length' <<<"$settings")" -eq 0 ] || { echo 'FAIL: unexpected transient settings'; exit 1; }
"${CURL[@]}" "$ES_URL/_nodes?filter_path=nodes.*.name,nodes.*.roles,nodes.*.transport.publish_address,nodes.*.http.publish_address" > evidence/nodes-runtime.json
"${CURL[@]}" "$ES_URL/_nodes/jvm?filter_path=nodes.*.name,nodes.*.jvm.version,nodes.*.jvm.mem.heap_init_in_bytes,nodes.*.jvm.mem.heap_max_in_bytes,nodes.*.jvm.using_compressed_ordinary_object_pointers" > evidence/jvm.json
printf '%s\n' "$fd" > evidence/process-stats.json
printf '%s\n' "$settings" > evidence/cluster-settings.json
echo 'PASS: runtime audit'
