# turnkey

Turnkey is a **template repository** for provisioning and bootstrapping production-grade, FedRAMP-aligned Kubernetes clusters with Pulumi and Argo CD.

> **Using turnkey in your organisation?** Do not fork — use it as a GitHub template. See [Using turnkey as a Template](#using-turnkey-as-a-template) below.

## Using turnkey as a Template

Turnkey is designed to be adopted via GitHub's **"Use this template"** feature, not forked. This gives you a clean, independent repo (no upstream link, private from creation) that you own and customise freely.

### 1. Create your repo from the template

On GitHub, click **"Use this template" → "Create a new repository"**. Choose a name, set visibility to **Private**, and create it.

### 2. Set your repo URL

Every stack config in `stacks/` and `pulumi/Pulumi.*.yaml` has a single line to change:

```yaml
argocd.repoUrl: https://github.com/your-org/your-repo
```

This value controls everything: where ArgoCD pulls from, which source repo the `platform` AppProject trusts, and what gets referenced in change-control annotations. It is the only URL you need to update.

### 3. Customise your stacks

Edit the stack configs under `stacks/` for your environments (cluster size, region, feature flags, etc.). The rest of the platform picks up from there.

### 4. Bootstrap

Follow the normal bootstrap procedure in [docs/runbooks/bootstrap.md](docs/runbooks/bootstrap.md).

### Staying up to date with upstream

Since your repo has no upstream link, pull upstream changes manually:

```bash
git remote add upstream https://github.com/EpykLab/turnkey
git fetch upstream
git merge upstream/master
```

Review the diff carefully before merging — upstream changes may conflict with your customisations.

---

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
4. Root app syncs `bootstrap/` (marker ConfigMap only; `prune: false` on root so it does not delete the platform app).
5. Pulumi creates the `turnkey-platform` Argo Application with stack-specific Helm `valueFiles` (`turnkey:platform.valueFiles` JSON array; default `values.yaml` + `values.doks.yaml`, kind uses `values.kind.yaml`).

For AKS-only overlays, set `platform.valueFiles` to include `values.aks.yaml` (see `chart/values.aks.yaml`).

## Quick start (local kind)

For iterating on the platform chart and optional components without cloud cost, see [docs/runbooks/kind-local.md](docs/runbooks/kind-local.md) and run `./scripts/bootstrap-kind.sh` (Pulumi `cluster.provider=existing` + kind kubeconfig).

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
| status-page | Public health endpoint | Enabled (DOKS); off on plain kind |
| kube-bench | CIS-style scheduled checks | Enabled in `values.doks.yaml` / `values.kind.yaml` |
| stllr-preview / staging / prod | Hello placeholder tenants (Kustomize) | Enabled in `values.doks.yaml` / `values.kind.yaml` |

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

## FedRAMP Security Controls

Turnkey includes implementations for FedRAMP security controls (NIST SP 800-53 Rev 5):

| Control | Description | Implementation | Enable |
|---------|-------------|----------------|--------|
| **AU-2/AU-9** | Audit Events & Protection | Vector log collection → S3 Object Lock | `vector.enabled: true` |
| **AC-2** | Account Management | Kyverno policies for ServiceAccount lifecycle | Auto-enabled with Kyverno |
| **SC-7** | Boundary Protection | NetworkPolicies (default deny) | `fedramp.networkPolicies.enabled: true` |
| **SC-8** | Transmission Encryption | Linkerd mTLS (FIPS optional) | See below |
| **SI-4** | System Monitoring | Falco runtime security | `falco.enabled: true` |

### SC-8: Pod-to-Pod mTLS

Turnkey uses **Linkerd** as the pod-to-pod mTLS mechanism. FIPS mode is optional and can be enabled later when your compliance scope requires validated cryptographic modules.

**Setup (per cluster):**

```bash
# 0) Ensure Linkerd CLI is installed
task mtls:linkerd:cli:install
task mtls:linkerd:cli:check

# 1) Install Linkerd control plane
task mtls:linkerd:install

# 2) Enable sidecar injection on tenant/stage namespaces
task mtls:linkerd:inject:namespaces

# 3) Restart workloads so linkerd-proxy is injected
task mtls:linkerd:restart

# 4) Verify proxy coverage and control plane health
task mtls:linkerd:verify
```

`task mtls:linkerd:install` is idempotent (`install` first run, `upgrade` later) and
applies default sidecar/init resource settings so meshed pods satisfy namespace quotas.

Linkerd's internal CA issues short-lived certs to each proxy automatically. No external HSM or cert-manager involvement is needed for pod-to-pod mTLS.

Default DOKS values now set Linkerd/mTLS enabled with FIPS disabled, but bootstrap is still required on every new cluster.

Detailed runbook: [docs/runbooks/linkerd-mtls.md](docs/runbooks/linkerd-mtls.md)

**Why Linkerd?**
- ~1ms overhead vs Istio's ~5-10ms
- Automatic, transparent mTLS via sidecar injection
- Kyverno enforces injection is present in FedRAMP namespaces — no silent opt-out

See [docs/compliance-control-mapping.md](docs/compliance-control-mapping.md) for complete FedRAMP implementation details.

## Extending the Platform

### Trust model: platform vs tenant

Turnkey uses two ArgoCD AppProjects to separate trusted platform components from tenant workloads:

| Project | Source repos | Cluster-scoped resources | Used for |
|---------|-------------|--------------------------|----------|
| `platform` | Your turnkey repo only | Unrestricted | All turnkey infrastructure |
| `tenant` | Any repo | Blocked (`ClusterPolicy`, `ClusterRole`, `ClusterRoleBinding`, CRDs, webhooks) | Your workloads |

Additional applications added via `additionalApps` use the `tenant` project by default. This means they cannot deploy cluster-scoped security resources — which is intentional. If a workload legitimately needs a `ClusterPolicy` or `ClusterRole`, it must be added to the turnkey repo directly (PR = change control).

### Change control for security resources

Any `ClusterPolicy` in the cluster must carry a `turnkey.io/change-control` annotation referencing the PR or ticket that approved it. Kyverno enforces this — unannotated ClusterPolicies are rejected.

The workflow:
1. Open a PR to your turnkey repo describing the need
2. Add the resource with `turnkey.io/change-control: "<pr-url>"`
3. Merge after review — the PR is the change control record
4. ArgoCD syncs via the `platform` project

### Additional Applications

Deploy custom Helm charts or Kubernetes manifests from any repository alongside the platform baseline:

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

These deploy into the `tenant` AppProject. They can manage namespace-scoped resources freely but cannot create cluster-scoped security resources.

See `docs/runbooks/additional-applications.md` for complete configuration options.

## Documentation

- `docs/runbooks/bootstrap.md` - Full bootstrap procedure
- `docs/runbooks/drift-recovery.md` - Recover from configuration drift
- `docs/runbooks/cert-manager-cloudflare-dns01.md` - TLS certificate setup
- `docs/adr/` - Architecture Decision Records
