#!/usr/bin/env bash
set -euo pipefail
NS="${NAMESPACE:-elasticsearch-lab-002}"
kubectl get pvc -n "$NS" -o wide 2>/dev/null || true
kubectl get pv -o wide 2>/dev/null || true
kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=180s
kubectl get pv -o wide 2>/dev/null || true
