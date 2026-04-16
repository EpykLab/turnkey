# Deploying Apps from stllr-infra

Turnkey can deploy applications from your infrastructure repository (`stllr-infra`), supporting both Kargo-managed promotions and standard ArgoCD applications.

## Overview

The `helloPlaceholder` feature in Turnkey allows you to configure ArgoCD Applications that pull from `stllr-infra` (or any external repo). You can mix:

- **Kargo-managed apps**: Applications that participate in Kargo promotion stages (e.g., your main app with preview → staging → prod stages)
- **Standard ArgoCD apps**: Applications that ArgoCD manages directly without Kargo promotion (e.g., cluster configuration, monitoring rules)

## Configuration

### Basic Setup

Enable apps from stllr-infra in your stack config:

```yaml
# stacks/dev.yaml (or your stack config)
config:
  helloPlaceholder.enabled: "true"
  helloPlaceholder.repoURL: "https://github.com/EpykLab/stllr-infra"
  helloPlaceholder.targetRevision: "main"
```

Or set via Pulumi:

```bash
pulumi config set turnkey:helloPlaceholder.enabled true
pulumi config set turnkey:helloPlaceholder.repoURL https://github.com/EpykLab/stllr-infra
pulumi config set turnkey:helloPlaceholder.targetRevision main
```

### App Configuration

Configure your apps in `chart/values.yaml` under `helloPlaceholder.apps`:

```yaml
helloPlaceholder:
  enabled: true
  repoURL: "https://github.com/EpykLab/stllr-infra"
  targetRevision: "main"
  apps:
    # Kargo-managed: Main application with promotion stages
    - name: stllr-web-preview
      path: charts/stllr-web/overlays/preview
      namespace: stllr-preview
      kargoAuthorizedStage: "stllr:preview"  # Enables Kargo management
      syncWave: "55"
      
    - name: stllr-web-staging
      path: charts/stllr-web/overlays/staging
      namespace: stllr-staging
      kargoAuthorizedStage: "stllr:staging"
      syncWave: "55"
      
    - name: stllr-web-prod
      path: charts/stllr-web/overlays/prod
      namespace: stllr-prod
      kargoAuthorizedStage: "stllr:prod"
      syncWave: "55"
    
    # Standard ArgoCD: Cluster configuration (no Kargo stage)
    - name: cluster-config
      path: charts/cluster-config/base
      namespace: kube-system
      syncWave: "56"  # Deploy after main app
      
    - name: monitoring-rules
      path: charts/monitoring/rules
      namespace: observability
      syncWave: "57"
      
    - name: custom-resources
      path: charts/crds
      namespace: ""
      syncWave: "1"  # Deploy early (CRDs first)
      project: platform
```

### Field Reference

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | ArgoCD Application name (must be unique) |
| `path` | Yes | Path within the repo to the manifests/chart |
| `namespace` | Yes | Target namespace (`""` for cluster-scoped) |
| `kargoAuthorizedStage` | No | Kargo stage name (e.g., `stllr:preview`). Omit for standard ArgoCD management |
| `syncWave` | No | ArgoCD sync wave (default: `55`). Lower numbers deploy first |
| `project` | No | ArgoCD project (default: `default`) |
| `helmValueFiles` | No | Extra Helm value files (paths relative to `path` / chart dir) for Helm charts |
| `helmValues` | No | Inline Helm `valuesObject` (see template) |

## Key Differences

### Kargo-Managed Apps

```yaml
- name: stllr-web-preview
  path: charts/stllr-web/overlays/preview
  namespace: stllr-preview
  kargoAuthorizedStage: "stllr:preview"  # ← Has stage = Kargo manages
```

- **ArgoCD syncs** the initial deployment
- **Kargo controls** updates via promotion stages
- Application resources include: `kargo.akuity.io/authorized-stage` annotation
- Kargo can modify the ArgoCD Application's target revision

### Standard ArgoCD Apps

```yaml
- name: cluster-config
  path: charts/cluster-config/base
  namespace: kube-system
  # No kargoAuthorizedStage = ArgoCD manages fully
```

- **ArgoCD manages** all aspects of the application
- **No Kargo involvement** - ArgoCD watches the Git repo directly
- Updates happen automatically when you push to the tracked branch

## Sync Wave Guidelines

Order your deployments using `syncWave`:

| Wave | Use Case |
|------|----------|
| 1-10 | CRDs, cluster-level config, namespaces |
| 45-50 | Platform-dependent apps (after controllers ready) |
| 55 | Main application stages (Kargo-managed) |
| 56-60 | Supporting infrastructure (monitoring, config) |
| 100 | Status page (last) |

## Private Repo Access

If `stllr-infra` is private, ArgoCD needs credentials:

```bash
# Create repository secret for ArgoCD
kubectl apply -n argocd -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: stllr-infra-repo
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  url: https://github.com/EpykLab/stllr-infra
  username: git
  password: <github-token>
EOF
```

## Examples by Use Case

### Example 1: Main Application with Kargo

Your main app deployed across three stages with Kargo promotion:

```yaml
helloPlaceholder:
  enabled: true
  repoURL: "https://github.com/EpykLab/stllr-infra"
  targetRevision: "main"
  apps:
    - name: app-preview
      path: apps/stllr/overlays/preview
      namespace: preview
      kargoAuthorizedStage: "stllr:preview"
    - name: app-staging
      path: apps/stllr/overlays/staging
      namespace: staging
      kargoAuthorizedStage: "stllr:staging"
    - name: app-prod
      path: apps/stllr/overlays/prod
      namespace: prod
      kargoAuthorizedStage: "stllr:prod"
```

### Example 2: Cluster State Only (No Kargo)

Deploy cluster configuration without Kargo:

```yaml
helloPlaceholder:
  enabled: true
  repoURL: "https://github.com/EpykLab/stllr-infra"
  targetRevision: "main"
  apps:
    - name: network-policies
      path: policies/network
      namespace: ""
      syncWave: "5"
    - name: rbac-config
      path: rbac/base
      namespace: ""
      syncWave: "6"
    - name: limit-ranges
      path: quotas/limits
      namespace: default
      syncWave: "7"
```

### Example 3: Mixed Kargo and Non-Kargo

Combine both approaches:

```yaml
helloPlaceholder:
  enabled: true
  repoURL: "https://github.com/EpykLab/stllr-infra"
  targetRevision: "main"
  apps:
    # Kargo-managed: Main app
    - name: stllr-api-preview
      path: charts/api/preview
      namespace: api-preview
      kargoAuthorizedStage: "stllr:preview"
      syncWave: "55"
    - name: stllr-api-prod
      path: charts/api/prod
      namespace: api-prod
      kargoAuthorizedStage: "stllr:prod"
      syncWave: "55"
    
    # Standard ArgoCD: Supporting infrastructure
    - name: ingress-config
      path: ingress/rules
      namespace: ingress-nginx
      syncWave: "56"
    - name: cert-issuers
      path: certs/issuers
      namespace: cert-manager
      syncWave: "57"
    - name: pdb-policies
      path: policies/pdb
      namespace: ""
      syncWave: "58"
```

### Example 4: Stellarbridge `stllr-tenant` (Helm + Kargo)

Preview and staging deploy the **`stllr-tenant`** Helm chart from `stllr-infra` with
per-environment value files. Use `helmValueFiles` (paths **relative to the
chart directory**). Keep Application names **`stllr-preview`** and
**`stllr-staging`** so Kargo `argocd-update` in `stllr-infra` matches.

```yaml
helloPlaceholder:
  enabled: true
  repoURL: "https://github.com/EpykLab/stllr-infra"
  targetRevision: "master"
  apps:
    - name: stllr-preview
      path: charts/stllr-tenant
      namespace: stllr-preview
      project: tenant
      kargoAuthorizedStage: "stllr:preview"
      syncWave: "55"
      helmValueFiles:
        - ../../environments/preview/values.yaml
    - name: stllr-staging
      path: charts/stllr-tenant
      namespace: stllr-staging
      project: tenant
      kargoAuthorizedStage: "stllr:staging"
      syncWave: "55"
      helmValueFiles:
        - ../../environments/staging/values.yaml
```

Those value files enable **`ingress`** (host-based routing to app, API, and
CoC web on `*.stellarbridge.app`), **cert-manager** TLS, and DNS on the shared
ingress-nginx LoadBalancer IP. Credentials stay in ESO-backed `tenant-secrets`;
non-secrets and computed **`STLLR_DOMAIN`** come from Helm ConfigMaps (`configEnv`
in values). See `stllr-infra` `README.md`, `docs/promotion-model.md`, and
`docs/secrets.md`.

## Verification

After deployment, verify your apps:

```bash
# List all ArgoCD applications
kubectl get applications.argoproj.io -n argocd

# Check Kargo-managed apps have the annotation
kubectl get application app-preview -n argocd -o jsonpath='{.metadata.annotations}' | grep kargo

# View standard ArgoCD apps (no Kargo annotation)
kubectl get application cluster-config -n argocd -o jsonpath='{.metadata.annotations}'

# Check Kargo stages
kubectl get stages -n kargo
```

## Troubleshooting

### Kargo not managing app

1. Verify the annotation exists:
   ```bash
   kubectl get application <name> -n argocd -o jsonpath='{.metadata.annotations.kargo\.akuity\.io/authorized-stage}'
   ```

2. Check Kargo has a matching Stage:
   ```bash
   kubectl get stages -n kargo <stage-name> -o yaml
   ```

### ArgoCD can't access stllr-infra

1. Check repo is configured:
   ```bash
   kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository
   ```

2. Test connectivity from ArgoCD:
   ```bash
   kubectl exec -n argocd deployment/argocd-repo-server -- git ls-remote https://github.com/EpykLab/stllr-infra
   ```

### Apps not appearing

1. Verify `helloPlaceholder.enabled: true` in config
2. Check template rendered correctly:
   ```bash
   helm template chart/ --values chart/values.yaml --values stacks/dev.yaml | grep -A5 "stllr-"
   ```

## Best Practices

1. **Separate concerns**: Use Kargo for apps needing promotion (main app), standard ArgoCD for cluster config
2. **Sync wave ordering**: Deploy CRDs first (low wave), apps in middle, config last
3. **Namespace strategy**: Group related resources by namespace
4. **Path structure**: Mirror stllr-infra layout for clarity:
   ```
   stllr-infra/
   ├── apps/
   │   └── stllr/
   │       └── overlays/
   │           ├── preview/
   │           ├── staging/
   │           └── prod/
   ├── charts/
   │   ├── cluster-config/
   │   └── monitoring/
   └── policies/
   ```
5. **Track revisions**: Pin `targetRevision` to branches/tags; use `main` for dev, `v1.x` for prod

## See Also

- `docs/runbooks/kind-local.md` - Local testing with Kargo
- `docs/runbooks/additional-applications.md` - Deploying via Pulumi config
- Kargo docs: https://kargo.akuity.io/
- ArgoCD Application docs: https://argo-cd.readthedocs.io/
