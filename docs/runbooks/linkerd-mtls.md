# Linkerd mTLS Bootstrap (Per Cluster)

This runbook enables pod-to-pod mTLS using Linkerd for a cluster.

## Important Scope

This is **cluster bootstrap**, not a one-time repo setting:

- You must run it for each new cluster.
- Existing clusters need this once before mTLS-protected traffic is expected.

## Prerequisites

- `kubectl` points to the target cluster
- `task` installed
- `linkerd` CLI installed
- Optional: pinned Linkerd proxy image tag

## 0) Install/check Linkerd CLI

```bash
task mtls:linkerd:cli:install
task mtls:linkerd:cli:check
```

## 1) Install Linkerd control plane

```bash
# Default proxy image version
task mtls:linkerd:install

# OR pin a specific proxy image version (recommended for controlled upgrades)
task mtls:linkerd:install LINKERD_PROXY_IMAGE_VERSION=<proxy-tag>
```

## 2) Enable sidecar injection on workload namespaces

```bash
# Default: all namespaces labeled stllr.dev/tenant=true
task mtls:linkerd:inject:namespaces

# OR explicit namespace list
task mtls:linkerd:inject:namespaces \
  MTLS_NAMESPACES="stllr-preview stllr-staging tenant-mccutdotus"
```

## 3) Restart workloads to inject proxies

```bash
task mtls:linkerd:restart

# Optional custom timeout
task mtls:linkerd:restart ROLLOUT_TIMEOUT=600s
```

## 4) Verify mTLS coverage

```bash
task mtls:linkerd:verify
```

This checks Linkerd health and reports sidecar coverage by namespace.

## One-shot flow

```bash
task mtls:linkerd:enable
```

## Going Forward

`values.doks.yaml` and `values.doks-fedramp.yaml` are set to enable Linkerd mTLS by default, but each cluster still requires this bootstrap runbook to be executed once.
