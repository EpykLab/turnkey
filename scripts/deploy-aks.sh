#!/usr/bin/env bash
# One-shot: provision AKS + Argo bootstrap + wait for core sync gates (no prompts).
# Run from your machine: needs outbound access to management.azure.com.
#
# Prerequisites: `az login` (or export ARM_CLIENT_ID/ARM_CLIENT_SECRET/ARM_TENANT_ID/ARM_SUBSCRIPTION_ID);
#                pulumi logged in (pulumi whoami).
#
# Usage: ./scripts/deploy-aks.sh
#        STACK=staging ./scripts/deploy-aks.sh
#        AKS_K8S_VERSION=1.30.0 ./scripts/deploy-aks.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/azure-pulumi-env.sh"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/pulumi-network.sh"

STACK="${STACK:-staging}"
PULUMI_DIR="${ROOT}/pulumi"

if [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]]; then
	echo "ERROR: No Azure subscription: run \`az login\` or export ARM_SUBSCRIPTION_ID." >&2
	exit 1
fi

echo "==> Verifying Azure credentials"
if command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; then
	echo "    (OK via az CLI)"
elif command -v curl >/dev/null 2>&1; then
	# Fall back to a lightweight ARM token check when az is broken or proxied.
	code="$(curl -sS -o /dev/null -w '%{http_code}' \
		-H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv 2>/dev/null || echo invalid)" \
		"https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}?api-version=2020-01-01")"
	if [[ "${code}" != "200" ]]; then
		echo "ERROR: Azure management API returned HTTP ${code} (credentials or network)." >&2
		exit 1
	fi
	echo "    (OK via HTTPS; az was skipped or failed — check IDE proxy settings)"
else
	echo "ERROR: need working \`az account show\` or \`curl\` to verify credentials." >&2
	exit 1
fi

cd "${PULUMI_DIR}"

if [[ -z "${PULUMI_CONFIG_PASSPHRASE:-}" && -z "${PULUMI_CONFIG_PASSPHRASE_FILE:-}" ]]; then
	read -r -s -p "Enter your Pulumi config passphrase: " PULUMI_CONFIG_PASSPHRASE
	echo ""
	export PULUMI_CONFIG_PASSPHRASE
fi

echo "==> Warming Go build (first compile can take minutes with no Pulumi output)"
go build -o /tmp/turnkey-pulumi-langhost .

echo "==> Selecting Pulumi stack: ${STACK}"
pulumi stack select "${STACK}"

# Apply all config from stacks/<stack>.yaml to the Pulumi stack.
STACK_FILE="${ROOT}/stacks/${STACK}.yaml"
if [[ -f "${STACK_FILE}" ]]; then
	echo "==> Applying config from ${STACK_FILE}"
	while IFS= read -r line; do
		if [[ "${line}" =~ ^[[:space:]]+([A-Za-z][A-Za-z0-9_.]+):[[:space:]]+(.+)$ ]]; then
			KEY="${BASH_REMATCH[1]}"
			VAL="${BASH_REMATCH[2]}"
			VAL="${VAL%\"}"
			VAL="${VAL#\"}"
			echo "    turnkey:${KEY}=${VAL}"
			pulumi config set "turnkey:${KEY}" "${VAL}"
		fi
	done < "${STACK_FILE}"
fi
# Allow env override for Kubernetes version after bulk apply.
if [[ -n "${AKS_K8S_VERSION:-}" ]]; then
	echo "==> Overriding turnkey:cluster.version=${AKS_K8S_VERSION} (from env)"
	pulumi config set turnkey:cluster.version "${AKS_K8S_VERSION}"
fi

echo "==> pulumi up --yes --skip-preview"
if command -v stdbuf >/dev/null 2>&1; then
	stdbuf -oL -eL pulumi up --yes --skip-preview
else
	pulumi up --yes --skip-preview
fi

KUBECONFIG_RAW="$(pulumi stack output kubeconfig --show-secrets 2>/dev/null || true)"
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

echo "==> Waiting for all Applications to be healthy (up to 45m)"
if ! command -v jq >/dev/null 2>&1; then
	echo "ERROR: jq is required for application status polling (install jq)." >&2
	exit 1
fi
deadline=$((SECONDS + 2700))
while ((SECONDS < deadline)); do
	apps_json="$(kubectl get applications.argoproj.io -n argocd -o json 2>/dev/null || echo '{"items":[]}')"
	all_apps=$(echo "${apps_json}" | jq '.items | length')
	synced_apps=$(echo "${apps_json}" | jq '[.items[] | select(.status.sync.status == "Synced")] | length')
	healthy_apps=$(echo "${apps_json}" | jq '[.items[] | select(.status.health.status == "Healthy")] | length')
	steady_degraded=$(echo "${apps_json}" | jq '[.items[] | select(.status.sync.status == "Synced" and .status.health.status == "Degraded")] | length')

	if (( SECONDS % 30 < 10 )); then
		echo "    apps: ${synced_apps}/${all_apps} synced, ${healthy_apps}/${all_apps} healthy ($(date +%H:%M:%S))"
	fi

	if [[ "${all_apps}" -gt 0 && "${synced_apps}" -eq "${all_apps}" && "${healthy_apps}" -eq "${all_apps}" ]]; then
		echo "==> All ${all_apps} applications synced and healthy!"
		kubectl get applications.argoproj.io -n argocd -o wide || true
		exit 0
	fi

	if [[ "${steady_degraded}" -gt 0 ]]; then
		echo "ERROR: ${steady_degraded} application(s) Synced but Degraded. Check: kubectl get applications.argoproj.io -n argocd -o wide" >&2
		kubectl get applications.argoproj.io -n argocd -o wide || true
		exit 1
	fi

	sleep 10
done

echo "ERROR: timeout waiting for all applications to be healthy. Current status:" >&2
kubectl get applications.argoproj.io -n argocd -o wide || true
exit 1
