# DOKS Deployment Runbook

## Overview

This runbook covers deployment to DigitalOcean Kubernetes (DOKS) using the automated deployment script.

## Prerequisites

- DigitalOcean account with API token
- `doctl` CLI installed and authenticated (`doctl auth init`)
- `pulumi` CLI installed and logged in
- `kubectl` installed
- Git repository cloned locally

## Quick Deploy

```bash
# Set DigitalOcean token
export DIGITALOCEAN_TOKEN=$(doctl auth token)

# Run automated deployment
./scripts/deploy-doks.sh
```

## What the Script Does

1. **Verifies DigitalOcean API** access (via doctl or curl)
2. **Compiles Pulumi Go program** (first time can take minutes)
3. **Provisions DOKS cluster** (5-6 minutes)
   - Cluster name: `turnkey-dev` (or per stack config)
   - Region: `nyc1` (configurable)
   - Version: `1.35.1-do.2` (from `stacks/dev.yaml`)
4. **Installs ArgoCD** via Helm
5. **Bootstraps root Application** which manages the platform
6. **Waits for all applications** to be Synced and Healthy (up to 45 minutes)

## Expected Output

```
==> Verifying DigitalOcean API
==> Warming Go build (first compile can take minutes with no Pulumi output)
==> Selecting Pulumi stack: dev
==> Setting turnkey:cluster.version=1.35.1-do.2 (from /home/dhoenisch/code/turnkey/stacks/dev.yaml)
==> pulumi up --yes --skip-preview
...
Resources:
    + 6 created
Duration: 5m46s
==> Waiting for Argo CD CRDs and control plane
==> Waiting for all Applications to be healthy (up to 45m)
[1] 2/10 apps healthy (22:15:30)
...
==> All 10 applications synced and healthy!
NAME                       SYNC STATUS   HEALTH STATUS   REVISION
...
turnkey-platform           Synced        Healthy         197a466...
```

## Configuration

### Stack Configuration

Edit `stacks/dev.yaml` to customize:

```yaml
cluster:
  name: turnkey-dev
  region: nyc1
  version: 1.35.1-do.2
  nodeCount: 1
  nodeSize: s-4vcpu-8gb
```

### Platform Values

Edit `chart/values.doks.yaml` to enable/disable components:

```yaml
# Currently enabled (aligned with kind overlay where it makes sense)
certManager:
  enabled: true

kargo:
  enabled: true

tekton:
  enabled: true

helloPlaceholder:
  enabled: true  # stllr-preview / stllr-staging / stllr-prod → deploy/hello-placeholder

kubeBench:
  enabled: true

statusPage:
  enabled: true  # LoadBalancer on DOKS (disabled on plain kind)

# Currently disabled
externalSecrets:
  enabled: false  # CRD size limits
cilium:
  enabled: false  # DOKS has its own CNI
caddyGateway:
  enabled: false  # Not in baseline
chaosMesh:
  enabled: false
```

## Post-Deployment Access

### Status Page

```bash
# Get LoadBalancer IP
kubectl get service turnkey-status-page -n turnkey-status -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# Returns: http://<ip-address>
```

### ArgoCD

```bash
# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d

# Access: https://localhost:8080
# Username: admin
```

### Kargo

```bash
# Port-forward
kubectl port-forward svc/kargo-api -n kargo 8443:443

# Access: https://localhost:8443
# Username: admin
# Password: turnkey-dev-admin
```

## Known Issues & Solutions

### Issue: External Secrets CRD Size Limit

**Symptom:** `CustomResourceDefinition.apiextensions.k8s.io "clustersecretstores.external-secrets.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes`

**Solution:** External Secrets is disabled by default in `values.doks.yaml`. To enable:
1. Pre-install CRDs manually: `kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml`
2. Set `externalSecrets.enabled: true` in values

### Issue: Ingress Nginx Admission Webhook Stuck

**Symptom:** ArgoCD stuck on `waiting for completion of hook batch/Job/ingress-nginx-admission-create`

**Solution:** Admission webhooks are disabled by default:
```yaml
ingressNginx:
  helmValues:
    controller:
      admissionWebhooks:
        enabled: false
```

### Issue: Namespace Stuck Terminating on Destroy

**Symptom:** Destroy fails with `argocd` namespace stuck in `Terminating`

**Solution:** Run cleanup script:
```bash
source scripts/lib/argocd-destroy-cleanup.sh
argocd_destroy_cleanup
```

### Issue: ArgoCD Applications Show "Missing" or "Degraded"

**Symptom:** After initial deployment, apps show unhealthy status

**Solution:** Wait 10-15 minutes. Applications deploy in waves:
- Namespaces and CRDs first
- Controllers next
- Applications with dependencies last

Check wave order in `chart/templates/*/argocd-application.yaml` annotations.

## Destroy and Rebuild

### Full Destroy

```bash
export DIGITALOCEAN_TOKEN=$(doctl auth token)
cd pulumi
pulumi destroy --yes
```

If namespace is stuck:
```bash
source ../scripts/lib/argocd-destroy-cleanup.sh
argocd_destroy_cleanup
cd ..
./scripts/deploy-doks.sh
```

### Automated Rebuild

```bash
./scripts/e2e-doks-rebuild.sh
```

This destroys and rebuilds automatically.

## Validation Checklist

- [ ] All 10 ArgoCD applications show `Synced/Healthy`
- [ ] Status page responds at LoadBalancer IP
- [ ] ArgoCD UI accessible via port-forward
- [ ] Kargo UI accessible via port-forward
- [ ] All pods running in core namespaces (argocd, cert-manager, kargo, kyverno, tekton-pipelines)

## Troubleshooting Commands

```bash
# Check all applications
kubectl get applications.argoproj.io -n argocd -o wide

# Describe a problematic app
kubectl describe application <name> -n argocd

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-server

# Check app operation status
kubectl get application <name> -n argocd -o jsonpath='{.status.operationState.message}'

# Force sync an app
kubectl patch application <name> -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}'
```

## See Also

- `bootstrap.md` - General bootstrap procedures
- `drift-recovery.md` - Recovering from drift
- `../adr/` - Architecture decisions
