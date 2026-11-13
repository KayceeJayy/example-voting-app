#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/helm/voting-app"
command -v helm >/dev/null || { echo 'ERROR: helm is required.' >&2; exit 1; }

echo '===== HELM LINT (OFFLINE) ====='
helm lint "$CHART" --strict

echo '===== HELM TEMPLATE (OFFLINE) ====='
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
helm template capstone-voting "$CHART" --namespace voting > "$rendered"

echo '===== MANIFEST INVENTORY ====='
# 'kind:' and 'name:' values are emitted by Helm in this known chart.
grep '^kind:' "$rendered" | sort | uniq -c
printf 'ClusterIP occurrences: '
grep -c 'type: ClusterIP' "$rendered"

if grep -Eq 'type: (NodePort|LoadBalancer)' "$rendered"; then
  echo 'ERROR: A public-facing Service appeared in the rendered manifests.' >&2
  exit 1
fi

for object in 'name: vote' 'name: result' 'name: worker' 'name: redis' 'name: db'; do
  grep -Fq "$object" "$rendered" || {
    echo "ERROR: Missing application component ($object)." >&2
    exit 1
  }
done

if [[ $(grep -c '^kind: Deployment$' "$rendered") -ne 5 ]] ||
   [[ $(grep -c '^kind: Service$' "$rendered") -ne 4 ]] ||
   [[ $(grep -c '^kind: Secret$' "$rendered") -ne 1 ]]; then
  echo 'ERROR: Unexpected chart resource count.' >&2
  exit 1
fi

echo 'PASS: Helm lint, rendering, and 5 Deployments / 4 internal Services / 1 Secret inventory.'
echo 'No AWS resources created.'
