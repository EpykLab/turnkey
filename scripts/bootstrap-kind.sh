#!/usr/bin/env bash
# Create a kind cluster (optional config for ingress NodePort → localhost:8080) and run Pulumi against
# turnkey:cluster.provider=existing with kubeconfig stored as a stack secret.
#
# Prerequisites: kind, kubectl, pulumi, Go (for pulumi language host), docker.
# One-time: pulumi stack init kind (or set STACK=... to an existing stack name).
#
# Usage:
#   ./scripts/bootstrap-kind.sh
#   STACK=kind KIND_NAME=turnkey ./scripts/bootstrap-kind.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK="${STACK:-kind}"
KIND_NAME="${KIND_NAME:-turnkey}"
PULUMI_DIR="${ROOT}/pulumi"
KIND_CONFIG="${ROOT}/deploy/kind/kind-config.yaml"

if ! command -v kind >/dev/null 2>&1; then
	echo "ERROR: kind is not installed (https://kind.sigs.k8s.io/docs/user/quick-start/#installation)." >&2
	exit 1
fi

if ! kind get clusters 2>/dev/null | grep -qx "${KIND_NAME}"; then
	echo "==> Creating kind cluster: ${KIND_NAME}"
	kind create cluster --name "${KIND_NAME}" --config "${KIND_CONFIG}"
else
	echo "==> Kind cluster already exists: ${KIND_NAME}"
fi

cd "${PULUMI_DIR}"

echo "==> Warming Go build (first compile can take a while)"
go build -o /tmp/turnkey-pulumi-langhost .

echo "==> Selecting Pulumi stack: ${STACK}"
pulumi stack select "${STACK}" 2>/dev/null || pulumi stack init "${STACK}"

echo "==> Applying kind-oriented Pulumi config (non-secret keys)"
pulumi config set turnkey:cluster.provider existing
pulumi config set turnkey:cluster.name "${KIND_NAME}-kind"
pulumi config set turnkey:cluster.env dev
pulumi config set turnkey:argocd.repoUrl "${TURNKEY_ARGO_REPO_URL:-https://github.com/EpykLab/turnkey}"
pulumi config set turnkey:argocd.targetRevision "${TURNKEY_ARGO_REVISION:-master}"
pulumi config set turnkey:argocd.path bootstrap

echo "==> Setting kubeconfig secret from kind"
pulumi config set --secret turnkey:cluster.kubeconfig "$(kind get kubeconfig --name "${KIND_NAME}")"

echo "==> pulumi up --yes --skip-preview"
if command -v stdbuf >/dev/null 2>&1; then
	stdbuf -oL -eL pulumi up --yes --skip-preview
else
	pulumi up --yes --skip-preview
fi

echo ""
echo "Next steps:"
echo "  1. Commit and push chart/values.kind.yaml, bootstrap/platform-application.kind.yaml, and related changes."
echo "  2. Point the turnkey-platform Application at values.kind.yaml (see docs/runbooks/kind-local.md)."
echo "  3. For ingress smoke on the host: http://127.0.0.1:8080 (maps to NodePort 30080 when synced)."
echo ""
