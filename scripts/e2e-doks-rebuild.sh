#!/usr/bin/env bash
# Destroy managed DOKS + Pulumi Kubernetes state, reprovision from scratch, wait until
# Argo CD and Kyverno are Synced/Healthy with no manual kubectl steps.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}/pulumi"

: "${PULUMI_STACK:=dev}"
export PULUMI_K8S_DELETE_UNREACHABLE="${PULUMI_K8S_DELETE_UNREACHABLE:-true}"

pulumi stack select "${PULUMI_STACK}"

CLUSTER_NAME="$(pulumi config get cluster.name 2>/dev/null || true)"
PROVIDER="$(pulumi config get cluster.provider 2>/dev/null || true)"

if [[ "${PROVIDER}" == "doks" ]] && command -v doctl >/dev/null 2>&1 && [[ -n "${DIGITALOCEAN_TOKEN:-}" && -n "${CLUSTER_NAME}" ]]; then
  echo ">>> Pre-delete DOKS cluster ${CLUSTER_NAME} (if present) for a clean teardown"
  doctl kubernetes cluster delete "${CLUSTER_NAME}" --force --dangerous 2>/dev/null || true
  sleep 10
fi

echo ">>> pulumi destroy"
pulumi destroy --yes --skip-preview || true

echo ">>> pulumi up"
pulumi up --yes --skip-preview

TMPKCFG="$(mktemp)"
cleanup() { rm -f "${TMPKCFG}"; }
trap cleanup EXIT

pulumi stack output kubeconfig --show-secrets --stack "${PULUMI_STACK}" >"${TMPKCFG}"
export KUBECONFIG="${TMPKCFG}"

echo ">>> Waiting for API server"
for _ in $(seq 1 120); do
  if kubectl get --raw=/readyz &>/dev/null; then
    break
  fi
  sleep 5
done

echo ">>> Waiting for Argo CD server"
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=600s

echo ">>> Waiting for Argo CD Applications (Synced + Healthy)"
DEADLINE=$((SECONDS + 2400))
apps=(turnkey-root turnkey-platform turnkey-kyverno turnkey-kyverno-policies)
all_green=false
while (( SECONDS < DEADLINE )); do
  all_green=true
  for a in "${apps[@]}"; do
    sync="$(kubectl get application "${a}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")"
    health="$(kubectl get application "${a}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")"
    if [[ "${sync}" != "Synced" || "${health}" != "Healthy" ]]; then
      all_green=false
      echo "    ${a}: sync=${sync:-?} health=${health:-?}"
      break
    fi
  done
  if ${all_green}; then
    echo ">>> All Argo applications healthy"
    break
  fi
  sleep 15
done

if ! ${all_green}; then
  echo "Timed out waiting for Argo CD applications" >&2
  kubectl get applications -n argocd -o wide || true
  exit 1
fi

echo ">>> Kyverno controller rollouts"
kubectl rollout status deployment/kyverno-admission-controller -n kyverno --timeout=600s
kubectl rollout status deployment/kyverno-background-controller -n kyverno --timeout=300s
kubectl rollout status deployment/kyverno-cleanup-controller -n kyverno --timeout=300s
kubectl rollout status deployment/kyverno-reports-controller -n kyverno --timeout=300s

echo ">>> ClusterPolicies"
kubectl get clusterpolicy

echo "E2E OK"
