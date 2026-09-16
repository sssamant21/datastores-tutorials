#!/usr/bin/env bash
set -euo pipefail
kubectl apply -f manifests/06-configmap-runtime.yaml
runtime_config="$(kubectl get configmap elasticsearch-config -n elasticsearch-lab-002 -o jsonpath='{.data.elasticsearch\.yml}')"
if [ -z "$runtime_config" ] || grep -q 'cluster.initial_master_nodes' <<<"$runtime_config"; then
  echo 'FAIL: bootstrap setting remains in runtime ConfigMap'
  exit 1
fi
echo 'PASS: runtime ConfigMap excludes cluster.initial_master_nodes'
