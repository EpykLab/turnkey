# Source from other scripts: `source "$(dirname "$0")/../lib/do-pulumi-env.sh"` (adjust path).
# Sets PULUMI_HOME and DIGITALOCEAN_TOKEN for unattended Pulumi + DO provider use.
: "${PULUMI_HOME:=${HOME}/.pulumi}"
export PULUMI_HOME

if [[ -z "${DIGITALOCEAN_TOKEN:-}" && -f "${HOME}/.config/doctl/config.yaml" ]]; then
	DIGITALOCEAN_TOKEN="$(awk '/^access-token:/{print $2}' "${HOME}/.config/doctl/config.yaml")"
	export DIGITALOCEAN_TOKEN
fi
