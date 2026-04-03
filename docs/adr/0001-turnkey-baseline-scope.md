# ADR 0001: Turnkey baseline scope

## Status

Accepted

## Context

Turnkey provisions a Kubernetes cluster baseline and bootstraps GitOps (Argo CD). Application workloads (e.g. Stellerbridge tenant Helm charts) live in a separate infrastructure repository and are out of scope for this repo’s baseline chart.

## Decision

Turnkey owns:

- Cluster provisioning entrypoints (Pulumi) for supported providers.
- Argo CD install and root Application wiring.
- Platform support components delivered as Argo-managed child Applications inside the `turnkey-platform` Helm chart (for example ingress-nginx, cert-manager, Kyverno, optional External Secrets Operator).

Turnkey does **not** own Stellerbridge application charts or tenant namespaces beyond generic platform namespaces required by those components.

## Consequences

- Clear separation between “cluster shell” and “product deployables.”
- Platform upgrades can ship without coupling to application release cadence, as long as shared contracts (ingress classes, secrets operators) remain stable.