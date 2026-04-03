#!/usr/bin/env bash
# One-shot: provision DOKS + Argo bootstrap + wait for core sync gates (no prompts).
# Run from your machine (not from a restricted CI sandbox): needs outbound access to api.digitalocean.com.
#
# Prerequisites: doctl configured OR export DIGITALOCEAN_TOKEN; pulumi logged in (pulumi whoami).
# Optional: DOKS_K8S_VERSION=1.35.1-do.1 pulumi config is applied before up.
#
# Usage: ./scripts/deploy-doks.sh
#        STACK=dev ./scripts/deploy-doks.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/do-pulumi-env.sh"

STACK="${STACK:-dev}"
PULUMI_DIR="${ROOT}/pulumi"

if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]]; then
	echo "ERROR: DIGITALOCEAN_TOKEN is not set and could not be read from ~/.config/doctl/config.yaml" >&2
	exit 1
fi

if command -v doctl >/dev/null 2>&1; then
	echo "==> Verifying DigitalOcean API credentials"
	doctl account get >/dev/null
fi

cd "${PULUMI_DIR}"

echo "==> Selecting Pulumi stack: ${STACK}"
pulumi stack select "${STACK}"

if [[ -n "${DOKS_K8S_VERSION:-}" ]]; then
	echo "==> Setting turnkey:cluster.version=${DOKS_K8S_VERSION}"
	pulumi config set turnkey:cluster.version "${DOKS_K8S_VERSION}"
fi

echo "==> pulumi up --yes --skip-preview"
pulumi up --yes --skip-preview

KUBECONFIG_RAW="$(pulumi stack output kubeconfig --show-secrets -j 2>/dev/null | jq -r '.' 2>/dev/null || true)"
if [[ -z "${KUBECONFIG_RAW}" || "${KUBECONFIG_RAW}" == "null" ]]; then
	echo "WARN: kubeconfig stack output missing; skipping kubectl waits."
	exit 0
fi

TMP_KUBECONFIG="$(mktemp)"
trap 'rm -f "${TMP_KUBECONFIG}"' EXIT
printf '%s' "${KUBECONFIG_RAW}" >"${TMP_KUBECONFIG}"
export KUBECONFIG="${TMP_KUBECONFIG}"

echo "==> Waiting for Argo CD CRDs and control plane"
kubectl wait --for=condition=Established "crd/applications.argoproj.io" --timeout=300s
kubectl wait --for=condition=Available "deployment/argocd-server" -n argocd --timeout=600s

echo "==> Waiting for turnkey-platform Application (sync + health, up to 45m)"
# New clusters: many Helm child apps + Tekton/Kargo take time to become Healthy.
deadline=$((SECONDS + 2700))
while ((SECONDS < deadline)); do
	sync_h="$(kubectl get application turnkey-platform -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")"
	health_h="$(kubectl get application turnkey-platform -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")"
	echo "    turnkey-platform: sync=${sync_h:-?} health=${health_h:-?}"
	if [[ "${sync_h}" == "Synced" && ( "${health_h}" == "Healthy" || "${health_h}" == "Progressing" ) ]]; then
		echo "==> turnkey-platform is Synced with ${health_h}; printing app summary"
		kubectl get applications.argoproj.io -n argocd -o wide || true
		exit 0
	fi
	if [[ "${health_h}" == "Degraded" || "${health_h}" == "Missing" ]]; then
		echo "ERROR: turnkey-platform health is ${health_h}. Check: kubectl describe application turnkey-platform -n argocd" >&2
		kubectl get applications.argoproj.io -n argocd -o wide || true
		exit 1
	fi
	sleep 20
done

echo "ERROR: timeout waiting for turnkey-platform. Current apps:" >&2
kubectl get applications.argoproj.io -n argocd -o wide || true
exit 1
