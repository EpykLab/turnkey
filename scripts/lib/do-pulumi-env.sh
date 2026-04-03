# Source from other scripts: `source "$(dirname "$0")/../lib/do-pulumi-env.sh"` (adjust path).
# Sets PULUMI_HOME and DIGITALOCEAN_TOKEN for unattended Pulumi + DO provider use.
#
# Pulumi's DigitalOcean provider reads DIGITALOCEAN_TOKEN from the environment; it does not use
# doctl's config by itself. If the token is not already exported, we take it the same way doctl
# does: prefer `doctl auth token` (your logged-in context), then fall back to parsing the config.
: "${PULUMI_HOME:=${HOME}/.pulumi}"
export PULUMI_HOME

if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]] && command -v doctl >/dev/null 2>&1; then
	# Same token doctl uses for API calls (see `doctl auth token --help`).
	_t="$(doctl auth token 2>/dev/null || true)"
	_t="${_t//$'\r'/}"
	_t="${_t//$'\n'/}"
	if [[ -n "${_t}" ]]; then
		DIGITALOCEAN_TOKEN="${_t}"
		export DIGITALOCEAN_TOKEN
	fi
	unset _t
fi

if [[ -z "${DIGITALOCEAN_TOKEN:-}" && -f "${HOME}/.config/doctl/config.yaml" ]]; then
	DIGITALOCEAN_TOKEN="$(awk '/^access-token:/{print $2}' "${HOME}/.config/doctl/config.yaml")"
	export DIGITALOCEAN_TOKEN
fi
