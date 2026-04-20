#!/usr/bin/env bash
# Destroy all resources in an AKS Pulumi stack.
# Prompts for confirmation unless FORCE=1 is set.
#
# Prerequisites: `az login` (or export ARM_* vars); pulumi logged in (pulumi whoami).
#
# Usage: ./scripts/destroy-aks.sh
#        STACK=staging ./scripts/destroy-aks.sh
#        FORCE=1 STACK=staging ./scripts/destroy-aks.sh   # skip confirmation prompt
#        SKIP_BUILD=1 ./scripts/destroy-aks.sh            # skip the Go warm-up build
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

if [[ -z "${SKIP_BUILD:-}" ]]; then
	echo "==> Warming Go build (first compile can take minutes with no Pulumi output)"
	go build -o /tmp/turnkey-pulumi-langhost .
fi

echo "==> Selecting Pulumi stack: ${STACK}"
pulumi stack select "${STACK}"

if [[ -z "${FORCE:-}" ]]; then
	echo ""
	echo "WARNING: This will DESTROY all resources in stack '${STACK}'."
	echo "         This action is irreversible. Set FORCE=1 to skip this prompt."
	echo ""
	read -r -p "Type the stack name to confirm destruction [${STACK}]: " confirm
	if [[ "${confirm}" != "${STACK}" ]]; then
		echo "Aborted."
		exit 1
	fi
fi

echo "==> Clearing finalizers from terminating namespaces (prevents delete timeouts)"
if command -v kubectl >/dev/null 2>&1; then
	while IFS= read -r ns; do
		[[ -z "${ns}" ]] && continue
		echo "    Patching finalizers on namespace: ${ns}"
		kubectl patch namespace "${ns}" \
			-p '{"metadata":{"finalizers":[]}}' \
			--type=merge 2>/dev/null || true
	done < <(kubectl get namespaces --field-selector='status.phase=Terminating' \
		-o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
fi

echo "==> pulumi destroy --yes --skip-preview"
if command -v stdbuf >/dev/null 2>&1; then
	stdbuf -oL -eL pulumi destroy --yes --skip-preview
else
	pulumi destroy --yes --skip-preview
fi

echo "==> Stack '${STACK}' destroyed."
