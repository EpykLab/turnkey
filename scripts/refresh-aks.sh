#!/usr/bin/env bash
# Refresh Pulumi state for an AKS stack — reconciles state with live Azure resources.
# Use this when the stack is out of sync with reality (e.g. manual changes, partial deploy, drift).
#
# Prerequisites: `az login` (or export ARM_* vars); pulumi logged in (pulumi whoami).
#
# Usage: ./scripts/refresh-aks.sh
#        STACK=staging ./scripts/refresh-aks.sh
#        SKIP_BUILD=1 ./scripts/refresh-aks.sh   # skip the Go warm-up build
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

echo "==> pulumi refresh --yes --skip-preview"
if command -v stdbuf >/dev/null 2>&1; then
	stdbuf -oL -eL pulumi refresh --yes --skip-preview
else
	pulumi refresh --yes --skip-preview
fi

echo "==> Refresh complete. Current stack outputs:"
pulumi stack output 2>/dev/null || true
