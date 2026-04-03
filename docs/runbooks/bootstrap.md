# Bootstrap Runbook

## Objective

Provision a new Turnkey cluster from zero to Argo-managed steady state.

## Prerequisites

- DigitalOcean account with API token
- `doctl` CLI authenticated (`doctl auth init`)
- `pulumi` CLI installed and logged in (`pulumi login`)
- `kubectl` installed
- `DIGITALOCEAN_TOKEN` environment variable set (or use `export DIGITALOCEAN_TOKEN=$(doctl auth token)`)

## Procedure

### Option 1: Automated Deployment (Recommended)

Run the deployment script which handles the entire process:

```bash
export DIGITALOCEAN_TOKEN=$(doctl auth token)
./scripts/deploy-doks.sh
```

The script will:
1. Verify DigitalOcean API access
2. Provision DOKS cluster with Pulumi (5-6 minutes)
3. Install ArgoCD
4. Apply root Application
5. Wait for all child applications to become healthy (up to 45 minutes)
6. Display final application status

### Option 2: Manual Deployment

If you need more control or want to debug issues:

```bash
# 1. Configure environment
export DIGITALOCEAN_TOKEN=$(doctl auth token)

# 2. Provision infrastructure
cd pulumi
pulumi stack select dev
pulumi up --yes

# 3. Get kubeconfig
pulumi stack output kubeconfig --show-secrets > ~/.kube/turnkey-config
export KUBECONFIG=~/.kube/turnkey-config

# 4. Wait for ArgoCD
cubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=300s
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=600s

# 5. Monitor applications until healthy
kubectl get applications.argoproj.io -n argocd -w
```

## Expected Timeline

- **Pulumi infrastructure**: 5-6 minutes (DOKS cluster creation)
- **ArgoCD installation**: 1-2 minutes
- **Applications sync**: 10-15 minutes for all apps to become healthy
- **Total time**: ~15-20 minutes for full deployment

## Validation

After deployment completes, verify:

```bash
# All applications should be Synced and Healthy
kubectl get applications.argoproj.io -n argocd

# Expected output: 10 applications, all Synced/Healthy
```

### Core Components Check

- [ ] **Cluster API reachable**: `kubectl cluster-info`
- [ ] **ArgoCD running**: Pods in `argocd` namespace are Ready
- [ ] **Kyverno webhook available**: `kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg`
- [ ] **Doppler operator running**: Pod in `doppler-operator-system` namespace
- [ ] **OTel collector scheduled**: DaemonSet in `observability` namespace
- [ ] **Status page accessible**: LoadBalancer IP responds on port 80
- [ ] **Ingress nginx ready**: Deployment in `ingress-nginx` namespace
- [ ] **Cert manager ready**: Pods in `cert-manager` namespace
- [ ] **Kargo ready**: Pods in `kargo` namespace
- [ ] **Tekton ready**: Pods in `tekton-pipelines` namespace

## Post-Deployment Configuration

### 1. Configure Doppler (Optional)

If using Doppler for secrets management:

```bash
# Replace CHANGEME with your actual Doppler service token
kubectl create secret generic doppler-service-token \
  -n doppler-operator-system \
  --from-literal=serviceToken="dp.st.xxxxxx"
```

### 2. Access ArgoCD

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open `https://localhost:8080` and login with:
- Username: `admin`
- Password: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`

### 3. Access Kargo

```bash
kubectl port-forward svc/kargo-api -n kargo 8443:443
```

Open `https://localhost:8443` and login with:
- Username: `admin`
- Password: `turnkey-dev-admin`

## Troubleshooting

### Deployment script times out

If `./scripts/deploy-doks.sh` times out waiting for applications:

```bash
# Check application status
kubectl get applications.argoproj.io -n argocd -o wide

# Describe any degraded apps
kubectl describe application <app-name> -n argocd

# Restart ArgoCD if stuck
kubectl rollout restart deployment -n argocd
```

### External Secrets disabled

External Secrets is disabled by default due to CRD size limits. This is expected and logged. The deployment will succeed without it.

### Ingress nginx stuck on hooks

If ingress-nginx gets stuck waiting for admission webhook jobs, it's a known issue with the Helm hooks. The deployment uses `Validate=false` sync option and disables admission webhooks to avoid this.

### Namespace stuck terminating

If destroy fails with namespace stuck:

```bash
source scripts/lib/argocd-destroy-cleanup.sh
argocd_destroy_cleanup
```

## Architecture Notes

### Application Deployment Order

Applications deploy in sync waves:
1. **Wave 0-5**: Namespaces, CRDs, Cilium (disabled on DOKS)
2. **Wave 10**: Ingress Nginx
3. **Wave 12**: Cert Manager
4. **Wave 13**: External Secrets (disabled)
5. **Wave 15**: Kyverno
6. **Wave 16**: Kyverno Policies
7. **Wave 20**: Doppler (if enabled)
8. **Wave 30**: Tekton
9. **Wave 40**: Kargo
10. **Wave 100**: Status Page

### Disabled Components

- **Cilium**: Disabled on DOKS (uses DOKS CNI)
- **Caddy Gateway**: Disabled in baseline
- **External Secrets**: Disabled due to CRD size limits

## See Also

- `drift-recovery.md` - Recover from configuration drift
- `cert-manager-cloudflare-dns01.md` - Set up TLS certificates
- `../adr/` - Architecture Decision Records
