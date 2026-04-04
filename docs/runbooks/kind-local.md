# Local cluster with kind

Use this flow to iterate on Turnkey without DigitalOcean: install optional components (Tekton, Kargo, Kyverno, kube-bench, Chaos Mesh), debug Argo sync order, and document gaps before moving to a DOKS dev cluster.

## Prerequisites

- Docker, `kind`, `kubectl`, `pulumi` (logged in), Go 1.23+ (Pulumi Go program)
- Enough RAM for a single-node cluster running ingress-nginx, cert-manager, Kyverno, Tekton, and Kargo (8 GiB Docker allocation is a practical minimum)

## Bootstrap

```bash
./scripts/bootstrap-kind.sh
```

The script creates `kind` cluster `turnkey` (override with `KIND_NAME`), applies `deploy/kind/kind-config.yaml` so **NodePort 30080** maps to **http://127.0.0.1:8080** on the host, selects Pulumi stack `kind` (or creates it), sets `turnkey:cluster.provider` to `existing`, and stores `kind get kubeconfig` as `turnkey:cluster.kubeconfig` (secret).

Override Git coordinates when you are testing a fork or branch:

```bash
export TURNKEY_ARGO_REPO_URL=https://github.com/yourorg/turnkey
export TURNKEY_ARGO_REVISION=your-branch
./scripts/bootstrap-kind.sh
```

## Point Argo at the kind Helm overlay

The default `bootstrap/platform-application.yaml` uses `values.doks.yaml`. For kind, the platform Application must use `values.kind.yaml` (see `bootstrap/platform-application.kind.yaml`).

After your changes are **pushed** to the revision Argo tracks, either:

- Merge `platform-application.kind.yaml` into the tracked branch as the canonical `platform-application.yaml`, or
- One-off apply from a machine with cluster admin:

```bash
export KUBECONFIG=... # from `pulumi stack output kubeconfig --show-secrets`
kubectl apply -f bootstrap/platform-application.kind.yaml
```

Argo reconciles the `turnkey-platform` Application in place; the next sync uses the kind value files.

## Private Git / Helm credentials

If Argo must clone a private repo (for example application charts in `stllr-infra`), create a repository `Secret` in `argocd` (do not commit tokens to Helm values). Example pattern:

```bash
kubectl -n argocd create secret generic repo-github-epyklab \
  --from-literal=type=git \
  --from-literal=url=https://github.com/EpykLab \
  --from-literal=username="${GITHUB_USERNAME}" \
  --from-literal=password="${GITHUB_PAT}"
kubectl -n argocd label secret repo-github-epyklab argocd.argoproj.io/secret-type=repository --overwrite
```

For OCI registries (for example `ghcr.io`), use `type=helm`, `name=...`, `enableOCI=true`, and registry credentials per [Argo CD repository documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories).

Rotate any personal access token that may have been copied into a local `.env` or chat log.

## Optional: Chaos Mesh

In `chart/values.kind.yaml`, set `chaosMesh.enabled: true` (or override in a private values file), commit, push, and sync. The chart version is controlled by `chaosMesh.targetRevision`. Use dashboard and CRs to run small experiments once pods are healthy; tighten `dashboard.securityMode` before any shared or production-like cluster.

## kube-bench and CIS

`deploy/kube-bench` installs a weekly `CronJob` in `turnkey-compliance` (enable with `kubeBench.enabled: true` in values). Findings on **kind** often differ from managed DOKS/AKS (paths, control plane layout, add-ons). Use Turnkey on a real dev cluster for results that match production posture.

Recommended rhythm:

1. Establish a baseline on the target distribution (kind for wiring, then DOKS dev for honest CIS signal).
2. After each major add-on (ingress, policy, CI, chaos), re-run or wait for the scheduled job and record deltas.
3. Document accepted exceptions in `docs/compliance-control-mapping.md` (or a linked evidence store) with rationale and compensating controls.

## Mapping to migration success criteria

| Criterion | kind iteration |
|-----------|------------------|
| Deploy Turnkey without intervention | `./scripts/bootstrap-kind.sh` + pushed Git revision + correct platform value files |
| Seed Tekton / Kargo (and related) defs | `values.kind.yaml` enables Tekton and Kargo; pipeline YAML lives under `deploy/` |
| Move release through stages / gated promotions | Requires Kargo + Git wiring to `stllr-infra`; validate CRDs and UI on kind; full gating on DOKS |
| Preview apps + seeded data + Playwright | Needs tenant chart and data jobs; placeholder app acceptable on kind per team plan |
| Tenant via Argo with seed values | Exercise with hello-world chart in `stllr-infra` if the real app secrets block boot |
| Kargo per-tenant deploy | Same as promotion model; validate freight/stages when infra repo is connected |
| kube-bench | CronJob deployed via `turnkey-kube-bench` Application; interpret on DOKS for production-like CIS |
| Chaos engineering | Optional `chaosMesh.enabled`; verify install and RBAC on kind first |

## Troubleshooting

- **LoadBalancer pending**: Expected on plain kind for `turnkey-status-page`. Use `kubectl port-forward -n turnkey-status svc/turnkey-status-page 8081:80` or add MetalLB.
- **Sync timeouts**: Reduce footprint (`tekton.enabled: false`, `kargo.enabled: false`, `kubeBench.enabled: false`) while debugging.
- **`pulumi up` fails on kubeconfig**: Re-run `pulumi config set --secret turnkey:cluster.kubeconfig "$(kind get kubeconfig --name "$KIND_NAME")"` after recreating the cluster.

## See also

- `bootstrap.md` — DOKS-oriented bootstrap (production-like)
- `additional-applications.md` — extra Argo `Application` entries via Pulumi `additionalApps`
