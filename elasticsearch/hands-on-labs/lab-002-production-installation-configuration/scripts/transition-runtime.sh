#!/usr/bin/env bash
set -euo pipefail
kubectl apply -f manifests/06-configmap-runtime.yaml
if kubectl get configmap elasticsearch-config -n elasticsearch-lab-002 -o jsonpath='{.data.elasticsearch\.yml}' | grep -q '^cluster.initial_master_nodes:'; then
  echo 'FAIL: bootstrap setting remains in runtime ConfigMap'
  exit 1
fi
echo 'PASS: runtime ConfigMap excludes cluster.initial_master_nodes'
