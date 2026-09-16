#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-elasticsearch-lab-002}"
umask 077
# Only remove a private directory created by this process, never a caller's OUT.
OUT="$(mktemp -d)"
trap 'rm -rf -- "$OUT"' EXIT

openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -subj '/CN=Elasticsearch Lab 002 CA' \
  -keyout "$OUT/ca.key" -out "$OUT/ca.crt"

cat >"$OUT/http.ext" <<EOF
subjectAltName=DNS:localhost,IP:127.0.0.1,DNS:elasticsearch,DNS:elasticsearch.${NAMESPACE},DNS:elasticsearch.${NAMESPACE}.svc
extendedKeyUsage=serverAuth
EOF
openssl req -newkey rsa:2048 -nodes -subj '/CN=elasticsearch' -keyout "$OUT/http.key" -out "$OUT/http.csr"
openssl x509 -req -sha256 -days 1 -in "$OUT/http.csr" -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" -CAcreateserial -extfile "$OUT/http.ext" -out "$OUT/http.crt"

for ordinal in 0 1 2; do
  node="elasticsearch-${ordinal}"
  cat >"$OUT/${node}.ext" <<EOF
subjectAltName=DNS:${node},DNS:${node}.elasticsearch-headless,DNS:${node}.elasticsearch-headless.${NAMESPACE}.svc,DNS:${node}.elasticsearch-headless.${NAMESPACE}.svc.cluster.local
extendedKeyUsage=serverAuth,clientAuth
EOF
  openssl req -newkey rsa:2048 -nodes -subj "/CN=${node}" -keyout "$OUT/${node}.key" -out "$OUT/${node}.csr"
  openssl x509 -req -sha256 -days 1 -in "$OUT/${node}.csr" -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" -CAcreateserial -extfile "$OUT/${node}.ext" -out "$OUT/${node}.crt"
done

kubectl -n "$NAMESPACE" create secret generic elasticsearch-ca \
  --from-file=ca.crt="$OUT/ca.crt" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic elasticsearch-http-tls \
  --from-file=tls.crt="$OUT/http.crt" --from-file=tls.key="$OUT/http.key" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic elasticsearch-transport-tls \
  --from-file=elasticsearch-0.crt="$OUT/elasticsearch-0.crt" --from-file=elasticsearch-0.key="$OUT/elasticsearch-0.key" \
  --from-file=elasticsearch-1.crt="$OUT/elasticsearch-1.crt" --from-file=elasticsearch-1.key="$OUT/elasticsearch-1.key" \
  --from-file=elasticsearch-2.crt="$OUT/elasticsearch-2.crt" --from-file=elasticsearch-2.key="$OUT/elasticsearch-2.key" \
  --dry-run=client -o yaml | kubectl apply -f -

mkdir -p artifacts
cp "$OUT/ca.crt" artifacts/http-ca.crt
openssl x509 -in "$OUT/http.crt" -noout -subject -issuer -serial -dates -fingerprint -sha256 > artifacts/http-certificate-metadata.txt
: > artifacts/transport-certificate-metadata.txt
for ordinal in 0 1 2; do
  openssl x509 -in "$OUT/elasticsearch-${ordinal}.crt" -noout -subject -issuer -serial -dates -fingerprint -sha256 >> artifacts/transport-certificate-metadata.txt
done
