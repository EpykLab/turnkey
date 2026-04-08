#!/usr/bin/env bash
# Destroy all resources in a DOKS Pulumi stack.
# Prompts for confirmation unless FORCE=1 is set.
#
# Prerequisites: `doctl auth init` (or export DIGITALOCEAN_TOKEN); pulumi logged in (pulumi whoami).
#
# Usage: ./scripts/destroy-doks.sh
#        STACK=dev ./scripts/destroy-doks.sh
#        FORCE=1 STACK=dev ./scripts/destroy-doks.sh   # skip confirmation prompt
#        SKIP_BUILD=1 ./scripts/destroy-doks.sh        # skip the Go warm-up build
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
	: # doctl works
elif command -v curl >/dev/null 2>&1; then
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
