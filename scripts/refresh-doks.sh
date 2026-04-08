#!/usr/bin/env bash
# Refresh Pulumi state for a DOKS stack — reconciles state with live DigitalOcean resources.
# Use this when the stack is out of sync with reality (e.g. manual changes, partial deploy, drift).
#
# Prerequisites: `doctl auth init` (or export DIGITALOCEAN_TOKEN); pulumi logged in (pulumi whoami).
#
# Usage: ./scripts/refresh-doks.sh
#        STACK=dev ./scripts/refresh-doks.sh
#        SKIP_BUILD=1 ./scripts/refresh-doks.sh   # skip the Go warm-up build
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

echo "==> pulumi refresh --yes --skip-preview"
if command -v stdbuf >/dev/null 2>&1; then
	stdbuf -oL -eL pulumi refresh --yes --skip-preview
else
	pulumi refresh --yes --skip-preview
fi

echo "==> Refresh complete. Current stack outputs:"
pulumi stack output 2>/dev/null || true
