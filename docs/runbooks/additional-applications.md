# Additional Applications Configuration

Turnkey supports deploying additional Helm charts, Kubernetes manifests, or Kustomize configurations from external repositories via ArgoCD. This allows you to seed custom resources at build time alongside the platform baseline.

## Overview

You can configure additional ArgoCD Applications via Pulumi config. These applications are deployed after the root application but before the status page (sync wave 50 by default).

**Two main use cases:**
1. **Deploy additional Helm charts** (new applications)
2. **Deploy resource definitions** into existing platform namespaces (Tekton Pipelines, Kargo Stages, etc.)

## Quick Examples

### Stellarbridge: `stllr-ci` (Kargo + Tekton)

See `docs/runbooks/kind-local.md` for full context. Minimal pattern: two Git-directory applications (Kustomize), `syncWave` `44`–`45` so they apply after controllers (Turnkey platform wave `30`/`40`).

### Deploy Tekton Pipelines into Existing Namespace

Deploy your Pipeline and Task definitions into the already-running Tekton:

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "my-tekton-pipelines",
    "repoURL": "https://github.com/yourorg/pipeline-definitions",
    "targetRevision": "main",
    "path": "tekton",
    "namespace": "tekton-pipelines",
    "isHelm": false,
    "syncWave": "45"
  }
]'
```

Your repo structure:
```
pipeline-definitions/
└── tekton/
    ├── pipeline.yaml
    ├── tasks/
    │   ├── build-task.yaml
    │   └── test-task.yaml
    └── pipelineruns/
        └── example-run.yaml
```

### Deploy Kargo Stages into Existing Namespace

Deploy your Kargo Stage, Warehouse, and Promotion definitions:

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "kargo-stages",
    "repoURL": "https://github.com/yourorg/kargo-config",
    "targetRevision": "main",
    "path": "stages",
    "namespace": "kargo",
    "isHelm": false,
    "syncWave": "45"
  }
]'
```

Your repo structure:
```
kargo-config/
└── stages/
    ├── warehouse.yaml
    ├── staging-stage.yaml
    ├── production-stage.yaml
    └── promotion-policies.yaml
```

### Deploy Additional Helm Chart

Deploy a completely separate application via Helm:

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "custom-app",
    "repoURL": "https://charts.example.com",
    "chart": "myapp",
    "targetRevision": "2.1.0",
    "namespace": "custom",
    "isHelm": true,
    "valueFiles": ["values.yaml"]
  }
]'
```

## Configuration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Application name (must be unique in ArgoCD) |
| `repoURL` | string | Yes | Git repository URL or OCI registry |
| `chart` | string | For Helm | Chart name (only when `isHelm: true`) |
| `path` | string | For Git | Path within repo to manifests (when `isHelm: false`) |
| `targetRevision` | string | Yes | Git branch/tag or chart version |
| `namespace` | string | Yes | Target namespace (can be existing like `tekton-pipelines`, `kargo`, or new) |
| `isHelm` | bool | Yes | `true` for Helm chart, `false` for plain manifests/Kustomize |
| `valueFiles` | []string | No | Helm value files to use |
| `helmValues` | object | No | Inline Helm values (key-value pairs) |
| `syncWave` | string | No | ArgoCD sync wave (default: "50") |
| `project` | string | No | ArgoCD project (default: "default") |

## Use Cases

### Use Case 1: Tekton Pipelines

**Problem:** You want to define your CI/CD pipelines in a separate repo, but deploy them automatically when the cluster is provisioned.

**Solution:** 
- Tekton is already installed by Turnkey (in `tekton-pipelines` namespace)
- Define your Pipeline and Task YAMLs in your repo
- Configure Turnkey to deploy them into the existing namespace

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "company-pipelines",
    "repoURL": "https://github.com/yourorg/cicd-pipelines",
    "targetRevision": "main",
    "path": "pipelines",
    "namespace": "tekton-pipelines",
    "isHelm": false,
    "syncWave": "45"
  }
]'
```

### Use Case 2: Kargo Stages and Promotions

**Problem:** You have Kargo installed, but need to define your promotion stages.

**Solution:**
- Kargo is already installed by Turnkey (in `kargo` namespace)
- Define Stage, Warehouse, and Promotion resources in your config repo
- Turnkey deploys them into the existing Kargo namespace

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "production-kargo",
    "repoURL": "https://github.com/yourorg/kargo-production",
    "targetRevision": "v1.0.0",
    "path": ".",
    "namespace": "kargo",
    "isHelm": false,
    "syncWave": "45"
  }
]'
```

### Use Case 3: Kustomize Overlays

**Problem:** You use Kustomize to manage environment-specific configurations.

**Solution:**
```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "prod-overlays",
    "repoURL": "https://github.com/yourorg/kustomize-config",
    "targetRevision": "main",
    "path": "overlays/production",
    "namespace": "production",
    "isHelm": false,
    "syncWave": "55"
  }
]'
```

### Use Case 4: OCI Registry Chart with Custom Values

**Problem:** You want to deploy from GitHub Container Registry with custom values.

**Solution:**
```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "internal-dashboard",
    "repoURL": "ghcr.io/yourorg/charts",
    "chart": "dashboard",
    "targetRevision": "1.5.0",
    "namespace": "dashboard",
    "isHelm": true,
    "helmValues": {
      "ingress": {
        "enabled": true,
        "host": "dashboard.example.com"
      },
      "replicas": 3
    }
  }
]'
```

### Use Case 5: Multiple Resources

Deploy multiple configurations at once:

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "tekton-pipelines",
    "repoURL": "https://github.com/yourorg/pipelines",
    "targetRevision": "main",
    "path": "tekton",
    "namespace": "tekton-pipelines",
    "isHelm": false,
    "syncWave": "45"
  },
  {
    "name": "kargo-stages",
    "repoURL": "https://github.com/yourorg/kargo-config",
    "targetRevision": "v1.0.0",
    "path": "stages",
    "namespace": "kargo",
    "isHelm": false,
    "syncWave": "45"
  },
  {
    "name": "monitoring-rules",
    "repoURL": "https://github.com/yourorg/monitoring",
    "targetRevision": "main",
    "path": "rules",
    "namespace": "observability",
    "isHelm": false,
    "syncWave": "60"
  }
]'
```

## Sync Waves

Sync waves control the order of deployment:

| Wave | Components |
|------|------------|
| 0-40 | Platform infrastructure (Ingress, Cert Manager, Kyverno, Doppler, Tekton, Kargo) |
| 45-55 | **Your additional applications** (recommended for pipeline/stage definitions) |
| 100 | Status Page |

**Recommendation:**
- Use wave **45** for Tekton Pipelines (deploys after Tekton controller is ready)
- Use wave **45** for Kargo Stages (deploys after Kargo is ready)
- Use wave **50** (default) for independent applications
- Use wave **55+** if your apps depend on platform services being fully ready

## Configuration Methods

### Via Pulumi CLI

```bash
# Set as JSON
pulumi config set turnkey:additionalApps '[{"name":"myapp","repoURL":"...","targetRevision":"main","namespace":"myns","isHelm":false}]'

# Set from file
pulumi config set turnkey:additionalApps "$(cat apps.json)"
```

### Via Stack Config File

Edit `Pulumi.<stack>.yaml`:

```yaml
config:
  turnkey:additionalApps: |
    [
      {
        "name": "my-pipelines",
        "repoURL": "https://github.com/org/pipelines",
        "targetRevision": "main",
        "path": "tekton",
        "namespace": "tekton-pipelines",
        "isHelm": false,
        "syncWave": "45"
      }
    ]
```

### Via Environment Variable (CI/CD)

```bash
export PULUMI_CONFIG_turnkey:additionalApps='[{"name":"ci-pipelines","repoURL":"...","isHelm":false}]'
pulumi up
```

## Validation

After deployment, verify additional applications:

```bash
# List all ArgoCD applications
kubectl get applications.argoproj.io -n argocd

# Check specific app status
kubectl get application my-pipelines -n argocd

# View app events and status
kubectl describe application my-pipelines -n argocd

# Verify resources were created in target namespace
kubectl get pipelines -n tekton-pipelines
kubectl get stages -n kargo
```

## Troubleshooting

### Application not appearing

Check Pulumi config:
```bash
pulumi config get turnkey:additionalApps
```

### Resources not created in target namespace

1. Check the ArgoCD Application is syncing:
   ```bash
   kubectl get application <name> -n argocd -o jsonpath='{.status.sync.status}'
   ```

2. Verify the path in your repo contains valid YAML:
   ```bash
   kubectl get application <name> -n argocd -o jsonpath='{.status.operationState.message}'
   ```

3. Check ArgoCD has access to the repository (for private repos)

### Tekton Pipelines not executing

1. Verify Tekton is healthy: `kubectl get pods -n tekton-pipelines`
2. Check Pipeline definitions: `kubectl get pipelines -n tekton-pipelines`
3. Review Tekton controller logs: `kubectl logs -n tekton-pipelines deployment/tekton-pipelines-controller`

### Kargo Stages not appearing

1. Verify Kargo is healthy: `kubectl get pods -n kargo`
2. Check Stage resources: `kubectl get stages -n kargo`
3. Review Kargo controller logs: `kubectl logs -n kargo deployment/kargo-controller`

## Best Practices

### For Tekton Pipelines

- Organize by domain: `pipelines/build.yaml`, `pipelines/deploy.yaml`
- Keep tasks reusable in `tasks/` subdirectory
- Use PipelineRuns sparingly (they auto-trigger on apply)
- Set `syncWave: "45"` to ensure Tekton controller is ready

### For Kargo Configuration

- Separate stages by environment: `staging/`, `production/`
- Include PromotionPolicies for automated promotions
- Reference existing Warehouses (or define them)
- Set `syncWave: "45"` to ensure Kargo controller is ready

### For Helm Charts

- Pin chart versions (don't use `latest`)
- Use value files for environment-specific config
- Set appropriate sync wave based on dependencies

## Security Considerations

- **Private repositories**: ArgoCD needs credentials. Add via ArgoCD UI or create a repository secret.
- **Sensitive values**: Don't put secrets in `helmValues`. Use Sealed Secrets or External Secrets.
- **Namespace isolation**: Deploying into existing namespaces (tekton-pipelines, kargo) means those resources run with platform-level permissions. Ensure your definitions are trusted.

## See Also

- `bootstrap.md` - Platform bootstrap process
- `doks-deployment.md` - DOKS-specific deployment
- `stllr-infra-apps.md` - Deploying from stllr-infra with Kargo and standard ArgoCD
- ArgoCD Application docs: https://argo-cd.readthedocs.io/en/stable/core_concepts/
- Tekton docs: https://tekton.dev/docs/
- Kargo docs: https://kargo.akuity.io/
