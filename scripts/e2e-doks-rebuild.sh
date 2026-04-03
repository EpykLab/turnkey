#!/usr/bin/env bash
# Non-interactive destroy + reprovision of a DOKS-backed Turnkey stack with post-up health gates.
# Usage: STACK=dev ./scripts/e2e-doks-rebuild.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK="${STACK:-dev}"
PULUMI_DIR="${ROOT}/pulumi"

cd "${PULUMI_DIR}"

echo "==> Selecting Pulumi stack: ${STACK}"
pulumi stack select "${STACK}"

echo "==> pulumi destroy --yes"
pulumi destroy --yes

echo "==> pulumi up --yes"
pulumi up --yes

KUBECONFIG_RAW="$(pulumi stack output kubeconfig --show-secrets -j 2>/dev/null | jq -r '.' 2>/dev/null || true)"
if [[ -z "${KUBECONFIG_RAW}" || "${KUBECONFIG_RAW}" == "null" ]]; then
  echo "WARN: kubeconfig stack output missing; skip kubectl waits."
  exit 0
fi

TMP_KUBECONFIG="$(mktemp)"
trap 'rm -f "${TMP_KUBECONFIG}"' EXIT
printf '%s' "${KUBECONFIG_RAW}" >"${TMP_KUBECONFIG}"
export KUBECONFIG="${TMP_KUBECONFIG}"

echo "==> Waiting for core platform namespaces"
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=300s
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=600s

echo "==> e2e rebuild complete for stack ${STACK}"
