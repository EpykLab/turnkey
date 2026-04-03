# Source after do-pulumi-env.sh when running Pulumi from IDEs (e.g. Cursor) that inject HTTP(S)_PROXY.
# Those proxies often return 403 for api.digitalocean.com and stall Pulumi Service / plugin downloads.
#
# Add hosts here if preview/up still hangs in a locked-down environment.
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy GIT_HTTP_PROXY GIT_HTTPS_PROXY

export NO_PROXY="api.digitalocean.com,app.pulumi.com,api.pulumi.com,github.com,codeload.github.com,raw.githubusercontent.com,proxy.golang.org,sum.golang.org,storage.googleapis.com,registry.npmjs.org,127.0.0.1,localhost,::1"
export no_proxy="${NO_PROXY}"

# Fewer background calls on each run.
export PULUMI_SKIP_UPDATE_CHECK="${PULUMI_SKIP_UPDATE_CHECK:-true}"
