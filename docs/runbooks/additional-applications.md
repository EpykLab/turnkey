# Additional Applications Configuration

Turnkey supports deploying additional Helm charts or Kubernetes manifests from external repositories via ArgoCD. This allows you to seed custom applications at build time alongside the platform baseline.

## Overview

You can configure additional ArgoCD Applications via Pulumi config. These applications are deployed after the root application but before the status page (sync wave 50 by default).

## Configuration

Add applications to your Pulumi stack configuration using the `turnkey:additionalApps` key:

```bash
# Set as a JSON array
pulumi config set turnkey:additionalApps '[
  {
    "name": "home-pipelines",
    "repoURL": "https://github.com/yourorg/home-repo",
    "chart": "home",
    "targetRevision": "main",
    "namespace": "home-pipelines",
    "isHelm": true,
    "valueFiles": ["values.yaml"],
    "syncWave": "45"
  }
]'
```

Or edit `Pulumi.<stack>.yaml` directly:

```yaml
config:
  turnkey:additionalApps: |
    [
      {
        "name": "home-pipelines",
        "repoURL": "https://github.com/yourorg/home-repo",
        "chart": "home",
        "targetRevision": "main",
        "namespace": "home-pipelines",
        "isHelm": true,
        "valueFiles": ["values.yaml", "values.prod.yaml"],
        "syncWave": "45"
      },
      {
        "name": "kargo-config",
        "repoURL": "https://github.com/yourorg/kargo-config",
        "path": "apps",
        "targetRevision": "v1.2.0",
        "namespace": "kargo",
        "isHelm": false,
        "syncWave": "45"
      }
    ]
```

## Configuration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Application name (must be unique) |
| `repoURL` | string | Yes | Git repository URL or OCI registry |
| `chart` | string | For Helm | Chart name (when `isHelm: true`) |
| `path` | string | For Git | Path within repo (when `isHelm: false`) |
| `targetRevision` | string | Yes | Git branch/tag or chart version |
| `namespace` | string | Yes | Target namespace for deployment |
| `isHelm` | bool | Yes | `true` for Helm chart, `false` for plain manifests |
| `valueFiles` | []string | No | Helm value files to apply |
| `helmValues` | object | No | Inline Helm values (key-value pairs) |
| `syncWave` | string | No | ArgoCD sync wave (default: "50") |
| `project` | string | No | ArgoCD project (default: "default") |

## Examples

### Example 1: Home Pipelines (Helm Chart)

Deploy your custom pipelines chart from a separate repo:

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "home-pipelines",
    "repoURL": "https://github.com/yourorg/pipelines-repo",
    "chart": "home-pipelines",
    "targetRevision": "1.0.0",
    "namespace": "home",
    "isHelm": true,
    "valueFiles": ["values.yaml", "values.doks.yaml"],
    "syncWave": "45"
  }
]'
```

### Example 2: Kargo Configuration (Git Directory)

Deploy Kargo stages and promotions from a config repo:

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "kargo-config",
    "repoURL": "https://github.com/yourorg/kargo-config",
    "path": "stages",
    "targetRevision": "main",
    "namespace": "kargo",
    "isHelm": false,
    "syncWave": "45"
  }
]'
```

### Example 3: OCI Registry Chart

Deploy from an OCI registry (e.g., GitHub Container Registry):

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "custom-app",
    "repoURL": "ghcr.io/yourorg/charts",
    "chart": "myapp",
    "targetRevision": "2.1.0",
    "namespace": "custom",
    "isHelm": true,
    "helmValues": {
      "replicas": 3,
      "service": {
        "type": "LoadBalancer"
      }
    }
  }
]'
```

### Example 4: Multiple Applications

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "home-pipelines",
    "repoURL": "https://github.com/yourorg/home-repo",
    "chart": "home",
    "targetRevision": "main",
    "namespace": "home",
    "isHelm": true,
    "valueFiles": ["values.yaml"],
    "syncWave": "45"
  },
  {
    "name": "kargo-config",
    "repoURL": "https://github.com/yourorg/kargo-config",
    "path": "apps",
    "targetRevision": "v1.0.0",
    "namespace": "kargo",
    "isHelm": false,
    "syncWave": "45"
  },
  {
    "name": "monitoring-dashboards",
    "repoURL": "https://github.com/yourorg/grafana-dashboards",
    "path": "dashboards",
    "targetRevision": "main",
    "namespace": "observability",
    "isHelm": false,
    "syncWave": "60"
  }
]'
```

## Sync Waves

Sync waves control the order of deployment:

- **Wave 0-40**: Platform infrastructure (Cilium, Ingress, Cert Manager, Kyverno, Doppler, Tekton)
- **Wave 45-55**: **Additional applications** (recommended for your custom apps)
- **Wave 100**: Status Page

Use earlier waves (e.g., "45") if your apps depend on platform components. Use later waves (e.g., "60") if platform components depend on your apps.

## Validation

After deployment, verify additional applications:

```bash
# List all applications
kubectl get applications.argoproj.io -n argocd

# Check specific app status
kubectl get application home-pipelines -n argocd

# View app details
kubectl describe application home-pipelines -n argocd
```

## Troubleshooting

### Application not appearing

Check Pulumi config is set correctly:
```bash
pulumi config get turnkey:additionalApps
```

### Application stuck in "Missing"

1. Verify repository URL is accessible from the cluster
2. Check ArgoCD repository credentials (if private repo)
3. Review ArgoCD logs: `kubectl logs -n argocd deployment/argocd-server`

### Sync conflicts

If your apps conflict with platform apps:
1. Adjust sync wave to deploy before/after platform components
2. Add explicit dependencies in your Helm values
3. Use ArgoCD sync hooks for ordering within your app

## Security Considerations

- **Private repositories**: ArgoCD will need credentials. Configure via ArgoCD UI or add a repository secret.
- **OCI registries**: Ensure ArgoCD has permission to pull from the registry.
- **Values with secrets**: Use Sealed Secrets or External Secrets for sensitive values, not inline helmValues.

## See Also

- `bootstrap.md` - Platform bootstrap process
- `doks-deployment.md` - DOKS-specific deployment
- ArgoCD documentation: https://argo-cd.readthedocs.io/
