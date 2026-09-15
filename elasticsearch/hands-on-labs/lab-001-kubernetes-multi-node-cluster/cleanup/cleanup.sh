#!/usr/bin/env bash
set -euo pipefail
NS=${NS:-elasticsearch-lab}
echo 'PVC/PV state before cleanup:'
kubectl get pvc -n "$NS" || true
kubectl get pv || true
kubectl delete namespace "$NS" --wait=true
echo 'PV state after namespace deletion:'
kubectl get pv || true
echo 'Verify the underlying storage provider and reclaim policy before declaring storage cleanup complete.'
