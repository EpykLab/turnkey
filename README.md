# turnkey

Turnkey is the platform baseline for provisioning and bootstrapping Kubernetes clusters with Pulumi and Argo CD.

## Repository layout

- `pulumi/`: infrastructure entrypoint and Argo CD bootstrap.
- `bootstrap/`: Argo CD app-of-apps manifests (root app target path).
- `chart/`: platform baseline Helm chart (Argo CD managed).
- `stacks/`: environment-level Pulumi configuration.
- `docs/`: ADRs, runbooks, and compliance mapping.
- `scripts/`: deployment and utility scripts.

## Bootstrap flow

1. `pulumi up` provisions provider infrastructure (AKS or DOKS) and obtains kubeconfig.
2. Pulumi creates `argocd` namespace and installs Argo CD.
3. Pulumi applies root Argo CD Application.
4. Root app syncs `bootstrap/`, which declares the platform app.
5. Platform app syncs the Helm chart from `chart/`.

`bootstrap/platform-application.yaml` currently uses Helm `valueFiles` `values.yaml` + `values.doks.yaml` for DigitalOcean. For AKS, point `valueFiles` at `values.aks.yaml` instead (or add a second Application per environment).

## Quick start (DigitalOcean Kubernetes)

Prerequisites: `doctl auth init`, `pulumi login`, `DIGITALOCEAN_TOKEN` env var set (or use `doctl auth token`).

### Automated Deployment (Recommended)

The `deploy-doks.sh` script handles the full deployment including health checks:

```bash
# Set your DigitalOcean token
export DIGITALOCEAN_TOKEN=$(doctl auth token)

# Run the deployment
./scripts/deploy-doks.sh
```

This will:
1. Provision the DOKS cluster with Pulumi
2. Install ArgoCD
3. Bootstrap all platform applications
4. Wait for all applications to be Synced and Healthy

### Manual Deployment

If you prefer manual steps:

```bash
cd pulumi
pulumi stack select dev
pulumi up

# Get kubeconfig
pulumi stack output kubeconfig --show-secrets > ~/.kube/turnkey-config
export KUBECONFIG=~/.kube/turnkey-config

# Wait for applications to sync (see bootstrap runbook)
```

## Full DOKS rebuild (automated E2E)

Requires `pulumi` logged in, `DIGITALOCEAN_TOKEN`, `kubectl`, and `doctl` (optional but recommended for clean destroys). After `pulumi up`, kubeconfig is available as a stack output:

`pulumi stack output kubeconfig --show-secrets > kubeconfig`

Non-interactive destroy + reprovision + health gates (runs `pulumi refresh` first; pre-destroy clears Argo `Application` finalizers so the `argocd` namespace can delete after Helm uninstall keeps CRDs; never deletes DOKS before Pulumi uninstalls Helm):

```bash
./scripts/e2e-doks-rebuild.sh
```

## Status page (smoke URL)

When `statusPage.enabled` is true (default), Argo syncs app **`turnkey-status-page`** last (wave 100) from `deploy/status-page/`: nginx on **8080** behind a **LoadBalancer** on **port 80**. After DigitalOcean assigns an IP or hostname, open `http://<lb>/` to confirm the cluster is up.

**Example:** `http://206.189.252.251` (actual IP will vary)

Note: a cloud LoadBalancer may incur cost on DO; disable via `statusPage.enabled: false` in your values overlay if you do not want it.

## Platform Applications

The following applications are deployed and managed by ArgoCD:

| Application | Purpose | Status |
|-------------|---------|--------|
| cert-manager | TLS certificate management | Enabled |
| ingress-nginx | Ingress controller (webhooks disabled) | Enabled |
| kargo | GitOps promotion management | Enabled |
| kyverno | Policy enforcement | Enabled |
| kyverno-policies | Baseline security policies | Enabled |
| tekton-pipeline | CI/CD pipelines | Enabled |
| tekton-triggers | Webhook-triggered pipelines | Enabled |
| doppler | Secrets synchronization | Enabled (requires token) |
| external-secrets | External secrets operator | **Disabled** (see notes) |
| status-page | Public health endpoint | Enabled |

### External Secrets - Disabled

External Secrets is currently **disabled by default** in `values.doks.yaml` because the CRDs exceed Kubernetes annotation size limits (262144 bytes). Even with `ServerSideApply=true`, the `ClusterSecretStore` and `SecretStore` CRDs fail to install.

To enable External Secrets in the future:
1. Wait for upstream fix to reduce CRD size, OR
2. Install CRDs manually outside of ArgoCD, OR
3. Use a custom values file with `installCRDs: false` and pre-install CRDs

### Ingress Nginx - Admission Webhooks Disabled

Ingress Nginx admission webhooks are disabled in `values.doks.yaml` to avoid Helm hook synchronization issues that can cause ArgoCD to get stuck on the first deployment.

```yaml
ingressNginx:
  enabled: true
  helmValues:
    controller:
      admissionWebhooks:
        enabled: false
```

## Access Information

### ArgoCD Web UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open: `https://localhost:8080`

**Default credentials:**
- Username: `admin`
- Password: Get with `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`

### Kargo

Kargo is deployed with a default admin account:

**Access:**
```bash
kubectl port-forward svc/kargo-api -n kargo 8443:443
```

Then open: `https://localhost:8443`

**Credentials:**
- Username: `admin`
- Password: `turnkey-dev-admin`

⚠️ **Warning:** This is a development-only password. Rotate via SealedSecret or ExternalSecret for production.

## Extending the Platform

### Additional Applications

You can deploy custom Helm charts or Kubernetes manifests from external repositories alongside the platform baseline. Configure via Pulumi:

```bash
pulumi config set turnkey:additionalApps '[
  {
    "name": "home-pipelines",
    "repoURL": "https://github.com/yourorg/home-repo",
    "chart": "home",
    "targetRevision": "main",
    "namespace": "home",
    "isHelm": true,
    "valueFiles": ["values.yaml"]
  }
]'
```

**Use cases:**
- Deploy your Tekton pipelines from a separate repo
- Seed Kargo stages and promotions at build time
- Include custom monitoring dashboards
- Deploy team-specific applications

See `docs/runbooks/additional-applications.md` for complete configuration options.

## Documentation

- `docs/runbooks/bootstrap.md` - Full bootstrap procedure
- `docs/runbooks/drift-recovery.md` - Recover from configuration drift
- `docs/runbooks/cert-manager-cloudflare-dns01.md` - TLS certificate setup
- `docs/adr/` - Architecture Decision Records
