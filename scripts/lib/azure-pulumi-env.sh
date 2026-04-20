# Source from other scripts: `source "$(dirname "$0")/../lib/azure-pulumi-env.sh"` (adjust path).
# Sets PULUMI_HOME and ARM_* credentials for unattended Pulumi + Azure Native provider use.
#
# Pulumi's Azure Native provider reads ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID,
# ARM_CLIENT_SECRET from the environment. If not already exported, we attempt to source
# them from the Azure CLI's current account context (requires `az login`).
: "${PULUMI_HOME:=${HOME}/.pulumi}"
export PULUMI_HOME

if command -v az >/dev/null 2>&1; then
	if [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]]; then
		_sub="$(az account show --query id -o tsv 2>/dev/null || true)"
		_sub="${_sub//$'\r'/}"
		_sub="${_sub//$'\n'/}"
		if [[ -n "${_sub}" ]]; then
			ARM_SUBSCRIPTION_ID="${_sub}"
			export ARM_SUBSCRIPTION_ID
		fi
		unset _sub
	fi

	if [[ -z "${ARM_TENANT_ID:-}" ]]; then
		_ten="$(az account show --query tenantId -o tsv 2>/dev/null || true)"
		_ten="${_ten//$'\r'/}"
		_ten="${_ten//$'\n'/}"
		if [[ -n "${_ten}" ]]; then
			ARM_TENANT_ID="${_ten}"
			export ARM_TENANT_ID
		fi
		unset _ten
	fi
fi
