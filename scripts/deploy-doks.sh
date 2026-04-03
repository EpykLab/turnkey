#!/usr/bin/env bash
# One-shot: provision DOKS + Argo bootstrap + wait for core sync gates (no prompts).
# Run from your machine (not from a restricted CI sandbox): needs outbound access to api.digitalocean.com.
#
# Prerequisites: `doctl auth init` (or export DIGITALOCEAN_TOKEN); pulumi logged in (pulumi whoami).
# doctl is used for API checks and to supply the token Pulumi needs (via doctl auth token).
# Optional: DOKS_K8S_VERSION=1.35.1-do.1 pulumi config is applied before up.
#
# Usage: ./scripts/deploy-doks.sh
#        STACK=dev ./scripts/deploy-doks.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/do-pulumi-env.sh"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/pulumi-network.sh"

STACK="${STACK:-dev}"
PULUMI_DIR="${ROOT}/pulumi"

if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]]; then
	echo "ERROR: No DigitalOcean token: run \`doctl auth init\` or export DIGITALOCEAN_TOKEN." >&2
	exit 1
fi

echo "==> Verifying DigitalOcean API"
if command -v doctl >/dev/null 2>&1 && doctl account get >/dev/null 2>&1; then
	: # doctl works (no IDE proxy in the way)
elif command -v curl >/dev/null 2>&1; then
	# doctl often breaks when Cursor injects HTTPS_PROXY; curl + NO_PROXY does not.
	code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" https://api.digitalocean.com/v2/account)"
	if [[ "${code}" != "200" ]]; then
		echo "ERROR: DigitalOcean API returned HTTP ${code} (token or network)." >&2
		exit 1
	fi
	echo "    (OK via HTTPS; doctl was skipped or failed — check IDE proxy settings)"
else
	echo "ERROR: need working \`doctl account get\` or \`curl\` to verify the token." >&2
	exit 1
fi

cd "${PULUMI_DIR}"

echo "==> Warming Go build (first compile can take minutes with no Pulumi output)"
go build -o /tmp/turnkey-pulumi-langhost .

echo "==> Selecting Pulumi stack: ${STACK}"
pulumi stack select "${STACK}"

# Keep Pulumi stack version aligned with stacks/<stack>.yaml (Pulumi.*.yaml is often gitignored).
STACK_FILE="${ROOT}/stacks/${STACK}.yaml"
if [[ -n "${DOKS_K8S_VERSION:-}" ]]; then
	echo "==> Setting turnkey:cluster.version=${DOKS_K8S_VERSION} (from env)"
	pulumi config set turnkey:cluster.version "${DOKS_K8S_VERSION}"
elif [[ -f "${STACK_FILE}" ]]; then
	VER="$(awk '/^[[:space:]]*cluster.version:/{print $2}' "${STACK_FILE}" | head -1)"
	if [[ -n "${VER}" ]]; then
		echo "==> Setting turnkey:cluster.version=${VER} (from ${STACK_FILE})"
		pulumi config set turnkey:cluster.version "${VER}"
	fi
fi

echo "==> pulumi up --yes --skip-preview"
if command -v stdbuf >/dev/null 2>&1; then
	stdbuf -oL -eL pulumi up --yes --skip-preview
else
	pulumi up --yes --skip-preview
fi

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
