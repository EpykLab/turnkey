#!/usr/bin/env bash
# Destroy managed DOKS + Pulumi Kubernetes state, reprovision from scratch, wait until
# Argo CD and Kyverno are Synced/Healthy with no manual kubectl steps.
set -euo pipefail

if ! command -v pulumi >/dev/null 2>&1 && [[ -x "${HOME}/.pulumi/bin/pulumi" ]]; then
  PATH="${HOME}/.pulumi/bin:${PATH}"
  export PATH
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/argocd-destroy-cleanup.sh disable=SC1091
source "${REPO_ROOT}/scripts/lib/argocd-destroy-cleanup.sh"
cd "${REPO_ROOT}/pulumi"

: "${PULUMI_STACK:=dev}"

pulumi stack select "${PULUMI_STACK}"

export PULUMI_K8S_DELETE_UNREACHABLE="${PULUMI_K8S_DELETE_UNREACHABLE:-true}"

echo ">>> pulumi refresh (reconcile state if the cluster was deleted out-of-band)"
pulumi refresh --yes --skip-preview

CLUSTER_NAME="$(pulumi config get cluster.name 2>/dev/null || true)"
PROVIDER="$(pulumi config get cluster.provider 2>/dev/null || true)"

# IMPORTANT: do not delete the DOKS cluster before Pulumi finishes uninstalling Helm/Argo or destroy will fail.
# If a prior run left the stack wedged (cluster gone but state remains), set RECOVER_ORPHAN_DOKS=1.
if [[ "${RECOVER_ORPHAN_DOKS:-}" == "1" ]] && [[ "${PROVIDER}" == "doks" ]] && command -v doctl >/dev/null 2>&1 && [[ -n "${DIGITALOCEAN_TOKEN:-}" && -n "${CLUSTER_NAME}" ]]; then
  echo ">>> RECOVER_ORPHAN_DOKS: deleting stray DOKS cluster ${CLUSTER_NAME} (if any)"
  doctl kubernetes cluster delete "${CLUSTER_NAME}" --force --dangerous 2>/dev/null || true
  sleep 15
  echo ">>> RECOVER_ORPHAN_DOKS: reconciling Pulumi state with cloud"
  pulumi refresh --yes --skip-preview || true
fi

echo ">>> Pre-destroy: clear Argo CD finalizers (Helm keeps CRDs; child Applications block ns delete)"
TMP_PRE=$(mktemp)
if pulumi stack output kubeconfig --show-secrets --stack "${PULUMI_STACK}" >"${TMP_PRE}" 2>/dev/null; then
  export KUBECONFIG="${TMP_PRE}"
  if kubectl get --raw=/readyz &>/dev/null; then
    argocd_destroy_cleanup || true
  fi
  unset KUBECONFIG
fi
rm -f "${TMP_PRE}"

echo ">>> pulumi destroy"
if ! pulumi destroy --yes --skip-preview; then
  echo ">>> Destroy failed; cleanup + refresh + one retry"
  TMP_RETRY=$(mktemp)
  if pulumi stack output kubeconfig --show-secrets --stack "${PULUMI_STACK}" >"${TMP_RETRY}" 2>/dev/null; then
    export KUBECONFIG="${TMP_RETRY}"
    argocd_destroy_cleanup || true
    unset KUBECONFIG
  fi
  rm -f "${TMP_RETRY}"
  pulumi refresh --yes --skip-preview || true
  pulumi destroy --yes --skip-preview
fi

echo ">>> pulumi up"
pulumi up --yes --skip-preview

TMPKCFG="$(mktemp)"
cleanup() { rm -f "${TMPKCFG}"; }
trap cleanup EXIT

pulumi stack output kubeconfig --show-secrets --stack "${PULUMI_STACK}" >"${TMPKCFG}"
export KUBECONFIG="${TMPKCFG}"

echo ">>> Waiting for API server"
api_ok=false
for _ in $(seq 1 120); do
  if kubectl get --raw=/readyz &>/dev/null; then
    api_ok=true
    break
  fi
  sleep 5
done
if ! ${api_ok}; then
  echo "Timed out waiting for Kubernetes API /readyz" >&2
  exit 1
fi

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
