# Local cluster with kind

Use this flow to iterate on Turnkey without DigitalOcean: install optional components (Tekton, Kargo, Kyverno, kube-bench, Chaos Mesh), debug Argo sync order, and document gaps before moving to a DOKS dev cluster.

## Prerequisites

- Docker, `kind`, `kubectl`, `pulumi` (logged in), Go 1.23+ (Pulumi Go program)
- Enough RAM for a single-node cluster running ingress-nginx, cert-manager, Kyverno, Tekton, and Kargo (8 GiB Docker allocation is a practical minimum)

## Bootstrap

```bash
./scripts/bootstrap-kind.sh
```

The script creates `kind` cluster `turnkey` (override with `KIND_NAME`), applies `deploy/kind/kind-config.yaml` so **NodePort 30080** maps to **http://127.0.0.1:18080** on the host (avoids colliding with other tools on 8080), selects Pulumi stack `kind` (or creates it), sets `turnkey:cluster.provider` to `existing`, and stores `kind get kubeconfig` as `turnkey:cluster.kubeconfig` (secret).

Override Git coordinates when you are testing a fork or branch:

```bash
export TURNKEY_ARGO_REPO_URL=https://github.com/yourorg/turnkey
export TURNKEY_ARGO_REVISION=your-branch
./scripts/bootstrap-kind.sh
```

## Kind Helm overlay (`values.kind.yaml`)

The Argo CD Application **`turnkey-platform`** is created by **Pulumi** (`pulumi/bootstrap/platform_application.go`), not from Git, so GitOps selfHeal does not revert your overlay.

Set on the Pulumi stack (the bootstrap script does this automatically):

```bash
cd pulumi && pulumi stack select kind
pulumi config set turnkey:platform.valueFiles '["values.yaml","values.kind.yaml"]'
pulumi up --yes
```

Default DOKS / dev stacks omit `platform.valueFiles` and use `values.yaml` + `values.doks.yaml`.

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

## Hello placeholder (Argo → stllr-infra charts)

Turnkey can deploy applications directly from your infrastructure repository (`stllr-infra`). You can configure **Kargo-managed apps** (with promotion stages) alongside **standard ArgoCD apps** (for cluster state) via the `helloPlaceholder` feature.

**Key capabilities:**
- Deploy charts from `stllr-infra` instead of mirroring in turnkey
- Mix Kargo-managed apps (main application stages) with standard ArgoCD apps (cluster config)
- Configure via Helm values in your stack file

**Kargo** `Warehouse` / stages point at **`stllr-infra`** for Freight; configure Git credentials on the Kargo `Project` when that repo is private. Apps with `kargoAuthorizedStage` are managed by Kargo, apps without are standard ArgoCD.

Quick setup:
1. Push **`stllr-infra`** first so the paths exist on the tracked revision.
2. Configure `helloPlaceholder` in your stack config to point at stllr-infra charts.
3. If the infra repo is private, add an Argo repository `Secret` for `https://github.com/EpykLab/stllr-infra` (see above).

See **`docs/runbooks/stllr-infra-apps.md`** for complete configuration examples and field reference.

Verify:

```bash
kubectl get applications.argoproj.io -n argocd | grep stllr-
kubectl get pods -n tenant-hello-preview
kubectl port-forward -n tenant-hello-preview svc/hello-placeholder 28080:80
curl -sSf http://127.0.0.1:28080/ | head
```

Swap to `charts/stllr-tenant` later by changing `helloPlaceholder.apps` paths or replacing with Helm-based `additionalApps` entries.

## Optional: sync `stllr-ci` (Kargo stages + Tekton pipelines)

Turnkey already installs **controllers** from this repo (`deploy/tekton-*`). Day-2 **resource definitions** (your `Pipeline`s, `Stage`s, `Warehouse`) can live in **`EpykLab/stllr-ci`** and be applied by extra Argo `Application`s via Pulumi `turnkey:additionalApps` (applied at bootstrap; default sync wave `50`, override per app).

Kargo only (smaller slice; edit `stage-*.yaml` placeholders for real `stllr-infra` + Argo app names first):

```bash
cd pulumi && pulumi stack select kind
pulumi config set turnkey:additionalApps '[
  {
    "name": "stllr-ci-kargo",
    "repoURL": "https://github.com/EpykLab/stllr-ci",
    "targetRevision": "master",
    "path": "kargo",
    "namespace": "stllr",
    "isHelm": false,
    "syncWave": "45"
  }
]'
cd .. && ./scripts/bootstrap-kind.sh
```

Add Tekton manifests (Kustomize in `stllr-ci/tekton/` pulls a remote Catalog `Task`; repo-server must reach GitHub):

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "stllr-ci-kargo",
    "repoURL": "https://github.com/EpykLab/stllr-ci",
    "targetRevision": "master",
    "path": "kargo",
    "namespace": "stllr",
    "isHelm": false,
    "syncWave": "45"
  },
  {
    "name": "stllr-ci-tekton",
    "repoURL": "https://github.com/EpykLab/stllr-ci",
    "targetRevision": "master",
    "path": "tekton",
    "namespace": "tekton-pipelines",
    "isHelm": false,
    "syncWave": "44"
  }
]'
```

If `stllr-ci` is private, use the same Git credential `Secret` pattern scoped to `https://github.com/EpykLab` (or the exact repo URL). After changing `additionalApps`, run **`pulumi up`** so Argo receives the new `Application` CRs.

## Mapping to migration success criteria

| Criterion | kind iteration |
|-----------|------------------|
| Deploy Turnkey without intervention | `./scripts/bootstrap-kind.sh` + pushed Git revision + correct platform value files |
| Seed Tekton / Kargo (and related) defs | Controllers from Turnkey `deploy/`; definitions from **`stllr-ci`** via `additionalApps` (see above) |
| Move release through stages / gated promotions | Requires Kargo + Git wiring to `stllr-infra`; validate CRDs and UI on kind; full gating on DOKS |
| Preview apps + seeded data + Playwright | Needs tenant chart and data jobs; placeholder app acceptable on kind per team plan |
| Tenant via Argo with seed values | Exercise with hello-world chart in `stllr-infra` if the real app secrets block boot |
| Kargo per-tenant deploy | Same as promotion model; validate freight/stages when infra repo is connected |
| kube-bench | CronJob deployed via `turnkey-kube-bench` Application; interpret on DOKS for production-like CIS |
| Chaos engineering | Optional `chaosMesh.enabled`; verify install and RBAC on kind first |

## Troubleshooting

- **Status page**: Disabled in `values.kind.yaml` by default (LoadBalancer never becomes healthy on plain kind). Enable after MetalLB or switch the Service to NodePort in a forked manifest.
- **Sync timeouts**: Reduce footprint (`tekton.enabled: false`, `kargo.enabled: false`, `kubeBench.enabled: false`) while debugging.
- **`pulumi up` fails on kubeconfig**: Re-run `pulumi config set --secret turnkey:cluster.kubeconfig "$(kind get kubeconfig --name "$KIND_NAME")"` after recreating the cluster.

## See also

- `bootstrap.md` — DOKS-oriented bootstrap (production-like)
- `additional-applications.md` — extra Argo `Application` entries via Pulumi `additionalApps`
