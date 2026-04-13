# Deploying a New Stellarbridge Stack

This guide covers standing up a full Stellarbridge production stack from zero: a new Kubernetes cluster via turnkey, the platform components (Argo CD, Kargo, cert-manager, ESO, etc.), the Stellarbridge application layer (dashboard app, API, chain-of-custody reporting, Vector), and the first tenant.

> **Using turnkey in your own organisation?** Do not fork — use it as a GitHub template. See [Using turnkey as a Template](#using-turnkey-as-a-template) below.

---

## Architecture Overview

Two repos work together:

| Repo | Role |
|---|---|
| `EpykLab/turnkey` (this repo) | Kubernetes cluster provisioning (Pulumi) + platform chart (Argo CD, Kargo, cert-manager, Kyverno, ingress, ESO, observability) |
| `EpykLab/stllr-infra` | Stellarbridge application manifests, Kargo promotion pipeline, tenant definitions |

Turnkey bootstraps the cluster and installs the platform. Once Argo CD is healthy, you configure it to pull the application stack from `stllr-infra`. Tenants are pure GitOps: add a directory under `stllr-infra/tenants/` and the `stllr-tenants` ApplicationSet does the rest.

---

## Using turnkey as a Template

Turnkey is designed to be adopted via GitHub's **"Use this template"** feature, not forked. This gives you a clean, independent repo (no upstream link, private from creation) that you own and customise freely.

### 1. Create your repo from the template

On GitHub, click **"Use this template" → "Create a new repository"**. Choose a name, set visibility to **Private**, and create it.

### 2. Set your repo URL

Every stack config in `stacks/` and `pulumi/Pulumi.*.yaml` has a single line to change:

```yaml
argocd.repoUrl: https://github.com/your-org/your-repo
```

This value controls everything: where Argo CD pulls from, which source repo the `platform` AppProject trusts, and what gets referenced in change-control annotations. It is the only URL you need to update.

### 3. Customise your stacks

Edit the stack configs under `stacks/` for your environments (cluster size, region, feature flags, etc.). The rest of the platform picks up from there.

### 4. Bootstrap

Follow the normal bootstrap procedure below.

---

## Prerequisites

### Required tools

- `golang` (for Pulumi Go program compilation)
- `kubectl`
- `pulumi` (logged in: `pulumi login`)
- `task` (Taskfile runner)
- `helm` (for manual chart inspection)

### Secrets backend

- `op` CLI authenticated (`op signin`) — 1Password is the secrets backend for this stack

### Cloud CLI (depending on cluster provider)

- `doctl` authenticated (`doctl auth init`) — for DOKS
- `az` CLI — for AKS

---

## Phase 1: Provision the Cluster

### 1.1 Configure the stack

Select or create a stack config in `stacks/`. The production stack (`stacks/prod.yaml`) targets an existing AKS cluster; the dev stack (`stacks/dev.yaml`) provisions a new DOKS cluster.

Key values to confirm before deploying:

```yaml
# stacks/prod.yaml
config:
  cluster.provider: aks
  cluster.provisionMode: existing      # "managed" to provision a new DOKS cluster
  cluster.name: turnkey-prod
  cluster.region: usgovvirginia
  cluster.nodeCount: "5"
  cluster.nodeSize: Standard_D4s_v5
  argocd.repoUrl: https://github.com/EpykLab/turnkey   # ← must be your repo URL
  argocd.targetRevision: master
  argocd.path: bootstrap
```

For a new DOKS cluster:

```yaml
# stacks/dev.yaml
config:
  cluster.provider: doks
  cluster.provisionMode: managed
  cluster.name: turnkey-dev
  cluster.region: nyc1
  cluster.version: 1.35.1-do.2
  cluster.nodeCount: "1"
  cluster.nodeSize: s-4vcpu-8gb
```

### 1.2 Deploy the cluster

**Option A — automated (recommended):**

```bash
task pulumi:stack:init
task deploy
```

**Option B — manual:**

```bash
# 1. Provision infrastructure
cd pulumi
pulumi stack select dev          # or prod
pulumi up --yes

# 2. Save kubeconfig
task save-kubecfg

# 3. Bootstrap Argo CD
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=300s
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=600s
```

The automated script waits up to 45 minutes for all platform Applications to reach `Synced/Healthy`. Expected timeline: ~15–20 minutes.

### 1.3 Validate platform health

```bash
# All platform applications should be Synced and Healthy
kubectl get applications.argoproj.io -n argocd

# Check the status page is responding (returns 200)
task status

# Core component checks
kubectl cluster-info
kubectl get pods -n argocd
kubectl get pods -n cert-manager
kubectl get pods -n kyverno
kubectl get pods -n kargo
kubectl get pods -n ingress-nginx
```

Expected: 10 applications, all `Synced/Healthy`.

---

## Phase 2: Post-Bootstrap Platform Configuration

These steps are required before any Stellarbridge application or tenant can run.

### 2.1 Configure the secrets backend (External Secrets Operator + 1Password)

The `stllr-tenant` chart relies on a `ClusterSecretStore` named `onepassword`. This is deployed by the platform chart when ESO is enabled. On DOKS, ESO CRDs must be pre-installed to avoid a 262 KB annotation size limit:

```bash
# Pre-install ESO CRDs
# Use create (not apply) to avoid the 262 KB annotation size limit that apply triggers
kubectl create -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml
kubectl wait --for=condition=Established crd/clustersecretstores.external-secrets.io --timeout=120s
```

#### Step 1: Seed the 1Password Connect server credentials

The platform chart automatically deploys a 1Password Connect server into the cluster when `onePassword.enabled` is true. Before enabling it in values, seed the Connect server credentials secret:

```bash
task secrets:1password-connect-creds
```

This prompts you for the path to (or contents of) your `1password-credentials.json` file. Download it from **1Password.com → Integrations → Connect → your server → Save Credentials File**, then paste the path or contents when prompted.

#### Step 2: Enable ESO with 1Password in your chart values

Commit and push — Argo CD will sync and deploy the Connect server and ESO automatically:

```yaml
# chart/values.yaml (or your environment overlay)
externalSecrets:
  enabled: true
  onePassword:
    enabled: true
    vaultName: "<your-1password-vault-name>"
```

> `connectHost` is no longer required — it is derived automatically from the in-cluster Connect service.

#### Step 3: Seed the ESO access token

```bash
task secrets:eso-1password
```

This prompts you to either generate a token via `op connect token create` or paste an existing one, then writes it into `external-secrets/onepassword-connect-token`.

Verify the ClusterSecretStore is ready after Argo CD syncs:

```bash
kubectl get clustersecretstore onepassword
# STATUS should be: Valid
```

### 2.2 Give Argo CD access to stllr-infra

`stllr-infra` is a private repo. Run from either the `turnkey` or `stllr-infra` repo:

```bash
task secrets:argocd-repo
```

This opens GitHub in your browser with the `repo` (read-only) scope pre-selected. Create the token, copy it, and paste it into the terminal prompt. The task writes the credential directly into the `argocd` namespace.

Verify:

```bash
# Check the repo appears as Connected in the Argo CD UI: Settings → Repositories
# For a CLI check, inspect the secret directly — the exec approach below does NOT work
# for private repos because bare git doesn't use Argo CD's credential store.
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository
```

### 2.3 Configure Kargo credentials

Kargo needs two secrets in the `stllr` namespace. Run these from either repo:

**Git credentials** (push access to commit promoted image tags back to stllr-infra):

```bash
task secrets:kargo-git
```

Opens GitHub with the `repo` (read + write) scope pre-selected. Writes `stllr-infra-git` into the `stllr` namespace with the required Kargo label.

**Image registry credentials** (read ghcr.io to discover new tags):

```bash
task secrets:kargo-ghcr
```

Opens GitHub with `read:packages` pre-selected. Writes `ghcr-credentials` into the `stllr` namespace with the required Kargo label.

**Copy image pull credentials to tenant namespaces:**

The `ghcr-credentials` secret is created in the `stllr` namespace for Kargo, but pods in tenant namespaces also need it to pull private images. Copy it to each tenant namespace after the namespace is created by ArgoCD:

```bash
for ns in tenant-hello-preview tenant-hello-demo tenant-hello-prod; do
  kubectl get secret ghcr-credentials -n stllr -o json \
    | python3 -c "import json,sys; s=json.load(sys.stdin); s['metadata']={'name':s['metadata']['name'],'namespace':'$ns'}; print(json.dumps(s))" \
    | kubectl apply -f - 2>/dev/null || true
done
```

> **Note:** Tenant workload deployments are disabled by default in tenant values files (e.g. `tenants/hello-demo/values.yaml`) until Kargo promotes real images. Once Kargo runs image promotion and updates the image tags, re-enable the workloads in the tenant values.

---

## Phase 3: Deploy the Stellarbridge Application Stack

With the platform healthy and credentials in place, wire turnkey to pull the application stack from `stllr-infra`.

### 3.0 Application secrets for Kargo stages (full `stllr-tenant` stack only)

Phase 2.3 configures **Kargo** (git push + ghcr poll). That is **not** the same as **application runtime secrets** (database, Auth0, Redis, etc.).

| Concern | What it unlocks | Where it lives |
|---|---|---|
| Kargo git + ghcr secrets | Warehouse discovers tags; stages can commit image bumps to `stllr-infra` | Kubernetes Secrets in namespace `stllr`, labeled for Kargo |
| App secrets (ESO) | Pods start with env vars; avoids CrashLoop on missing DB/Auth0/etc. | One vault item **per Kubernetes namespace**, name `stllr-<namespace>` |

**When this applies:** The default **hello-placeholder** overlays are nginx-only; they do **not** need `tenant-secrets` or ESO. As soon as you point preview/demo Applications at the **`charts/stllr-tenant`** chart—typically via `environments/preview` and `environments/demo` in `stllr-infra`—you must provision app secrets **before** those workloads can run.

**Naming (same convention for Azure Key Vault or 1Password):** the `ExternalSecret` in `stllr-tenant` requests remote key `stllr-<k8s-namespace>`. Examples:

| Kubernetes namespace | Vault item / AKV secret name |
|---|---|
| `stllr-preview` | `stllr-stllr-preview` |
| `stllr-demo` | `stllr-stllr-demo` |
| `tenant-hello-preview` | `stllr-tenant-hello-preview` |

If you use different `namespace:` values under `helloPlaceholder.apps` in your chart overlay, use those namespaces in the `stllr-<namespace>` name.

**ClusterSecretStore:** If you use 1Password with ESO, ensure each environment values file sets `externalSecret.secretStoreRef.name: onepassword` (the chart default is `azure-keyvault`). Without the correct store name, ESO never syncs even if the vault item exists.

**Create or update the JSON blob** (interactive scaffold + push to 1Password or AKV) from a checkout of **`stllr-infra`**—once **per** stage namespace, e.g.:

```bash
cd /path/to/stllr-infra
task secrets:tenant
# When prompted for namespace, enter: stllr-preview  (then repeat for stllr-demo)
```

Use `task secrets:push` if you already have a JSON file.

**Verify in the cluster** (from this repo):

```bash
task secrets:stllr-stages-verify
# If your preview/demo namespaces differ (e.g. template forks):
STAGE_NS="tenant-hello-preview tenant-hello-demo" task secrets:stllr-stages-verify
```

You should see `ExternalSecret` `Ready` and a populated `tenant-secrets` Secret in each namespace. If the namespace does not exist yet, Argo CD has not synced—run the check again after the namespace appears.

### 3.1 Enable stllr-infra apps in the turnkey chart

Edit `chart/values.yaml` (or your environment overlay) to enable the `helloPlaceholder` block. This tells the platform chart to create Argo CD Applications pointing at `stllr-infra`:

```yaml
helloPlaceholder:
  enabled: true
  repoURL: "https://github.com/EpykLab/stllr-infra"
  targetRevision: "master"
  apps:
    # Kargo-managed: preview environment (auto-promoted by Kargo)
    - name: stllr-preview
      path: deploy/hello-placeholder/overlays/preview
      namespace: stllr-preview
      kargoAuthorizedStage: "stllr:preview"
      syncWave: "55"

    # Kargo-managed: demo environment (manual promotion gate)
    - name: stllr-demo
      path: deploy/hello-placeholder/overlays/demo
      namespace: stllr-demo
      kargoAuthorizedStage: "stllr:demo"
      syncWave: "55"

    # Tenant ApplicationSet: creates one Argo CD Application per directory under tenants/
    - name: stllr-tenants
      path: argocd
      namespace: argocd
      syncWave: "60"
      project: default

    # Kargo project, warehouse, and stages
    - name: stllr-kargo
      path: kargo
      namespace: stllr
      syncWave: "52"
      project: default
```

Commit and push. Argo CD will sync the new Applications within ~3 minutes.

### 3.2 Verify Kargo is watching for images

```bash
# Kargo warehouse should show Healthy after credentials are applied
kubectl get warehouse stllr-images -n stllr

# Check for any discovered freight (may be empty on a fresh cluster)
kubectl get freight -n stllr
```

### 3.3 Verify preview and demo environments

```bash
kubectl get application stllr-preview -n argocd
kubectl get application stllr-demo -n argocd
kubectl get pods -n stllr-preview
kubectl get pods -n stllr-demo
```

With **hello-placeholder** paths (as in the snippet above), preview and demo run the nginx placeholder until you cut over. After you switch to **`charts/stllr-tenant`** (e.g. `environments/preview` / `environments/demo`), the full stack runs: `stellarbridge-app`, `stellarbridge-api`, `coc-reporting-web`, `coc-reporting-worker`, and `vector`. Image tags start as placeholders and update on Kargo promotion; **app secrets** for that layout are covered in [§3.0](#30-application-secrets-for-kargo-stages-full-stllr-tenant-stack-only).

> **Preview** auto-promotes when CI pushes a new semver tag (`>=0.1.0`) to any watched image.
> **Demo** requires a manual approval in the Kargo UI.

---

## Phase 4: Onboard a New Tenant

Each customer gets its own namespace, its own secrets, and its own copy of the stllr-tenant chart. Adding a tenant is a pure GitOps operation against `stllr-infra`.

### 4.1 Create the tenant directory

In your local checkout of `stllr-infra`:

```
tenants/
  <tenant-slug>/
    values.yaml
```

The slug becomes the namespace: `tenant-<slug>`. Keep it lowercase, alphanumeric, hyphens only.

### 4.2 Write the tenant values file

Start from `tenants/hello-demo/values.yaml` and update for the new tenant. Set image tags to the current prod-approved versions from `stages/prod-approved.yaml`:

```yaml
tenant:
  namespace: tenant-<slug>

stellarbridgeApp:
  replicas: 1
  image:
    tag: <version from stages/prod-approved.yaml>

stellarbridgeApi:
  replicas: 1
  image:
    tag: <version>

cocReporting:
  web:
    replicas: 1
    image:
      tag: <version>
  worker:
    replicas: 1
    image:
      tag: <version>

vector:
  replicas: 1
  image:
    tag: <version>
  tenantId: <slug>   # used as the tenant label in Elasticsearch / Vector
```

Do not put secrets in this file.

### 4.3 Create the tenant secrets

Run the interactive secrets scaffold from within the `stllr-infra` directory:

```bash
task secrets:tenant
```

This walks you through every required key, opens an editor, and pushes the completed JSON to 1Password (choose option 3). The item is stored in 1Password as `stllr-<namespace>` (e.g. `stllr-tenant-acme-corp`) and ESO syncs it into the `tenant-secrets` Kubernetes Secret in the tenant namespace.

If you need to push an existing secrets file later:

```bash
task secrets:push
```

### 4.4 Open a pull request

```bash
git checkout -b onboard/<slug>
git add tenants/<slug>/values.yaml
git commit -m "feat: onboard tenant <slug>"
git push origin onboard/<slug>
# Open PR → review → merge
```

### 4.5 Verify the tenant came up

After merge the `stllr-tenants` ApplicationSet detects the new directory within ~3 minutes:

```bash
# Application should appear and reach Synced/Healthy
kubectl get application tenant-<slug> -n argocd

# Namespace and pods
kubectl get pods -n tenant-<slug>

# ESO should have synced the secrets from the vault
kubectl get externalsecret tenant-secrets -n tenant-<slug>
kubectl get secret tenant-secrets -n tenant-<slug>
```

If ESO hasn't synced yet (default refresh is 1 hour), force it:

```bash
kubectl annotate externalsecret tenant-secrets \
  -n tenant-<slug> \
  force-sync=$(date +%s) --overwrite
```

### 4.6 Assign the tenant to a rollout cohort

Add the tenant to `tenants/_cohorts.yaml` in the appropriate cohort for staggered production rollouts:

```yaml
cohorts:
  cohort-1:
    tenants:
      - hello-demo
      - <slug>   # ← add here
```

---

## Validation Checklist

### Platform

- [ ] All Argo CD applications `Synced/Healthy`: `kubectl get applications -n argocd`
- [ ] `ClusterSecretStore onepassword` status `Valid`
- [ ] Argo CD can reach `stllr-infra`: repo visible in Argo CD UI Settings → Repositories
- [ ] Kargo Warehouse `stllr-images` is `Healthy`
- [ ] Kargo git secret `stllr-infra-git` and image secret `ghcr-credentials` exist in `stllr` namespace

### Application Stack

- [ ] `stllr-preview` Application `Synced/Healthy`
- [ ] `stllr-demo` Application `Synced/Healthy`
- [ ] `stllr-tenants` ApplicationSet generating Applications
- [ ] All pods in `stllr-preview` and `stllr-demo` are `Running`
- [ ] If preview/demo use `stllr-tenant`: vault items `stllr-<namespace>` exist; `task secrets:stllr-stages-verify` shows `ExternalSecret` Ready and `tenant-secrets` present (see [§3.0](#30-application-secrets-for-kargo-stages-full-stllr-tenant-stack-only))

### Per-Tenant

- [ ] `tenant-<slug>` Application `Synced/Healthy`
- [ ] All pods `Running` in `tenant-<slug>`
- [ ] `ExternalSecret tenant-secrets` status `SecretSynced`
- [ ] Vector shipping logs (check Elasticsearch / Grafana)

---

## Accessing Platform UIs

### Argo CD

```bash
task access:argo
# https://localhost:8989
# Username: admin
# Password:
task secrets:argocd
```

### Kargo

```bash
task access:kargo
# https://localhost:8888
# Username: admin
# Password: turnkey-dev-admin
```

---

## Promoting a Release to Production

See `stllr-infra/docs/promotion-model.md` and `stllr-infra/docs/staggered-rollout.md` for the full procedure. In summary:

1. CI pushes a semver tag → Kargo auto-promotes to `preview`
2. Verify preview is healthy → manually approve in Kargo UI to promote to `demo`
3. Soak demo for ≥24h (patch) / ≥48h (minor)
4. Update `stages/prod-approved.yaml` with the approved versions, open a PR
5. Open cohort PRs to update image tags in `tenants/<slug>/values.yaml` — one cohort at a time
6. Argo CD syncs each tenant automatically on merge

---

## Troubleshooting

### External Secrets CRD too large

```
metadata.annotations: Too long: may not be more than 262144 bytes
```

Pre-install the CRDs manually before enabling ESO in the chart — see [Phase 2.1](#21-configure-the-secrets-backend-external-secrets-operator--azure-key-vault).

### `turnkey-external-secrets` shows `Unknown` with ComparisonError

```
error building typed value from live resource: .status.terminatingReplicas: field not declared in schema
```

This is a known ArgoCD issue with large ESO CRDs that declare status sub-resources outside their OpenAPI schema. The chart includes `ignoreDifferences` for CRD status fields and `ServerSideApply=true` to handle this automatically. If the app shows `Unknown` after first sync, trigger a hard refresh:

```bash
kubectl annotate application turnkey-external-secrets -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

### 1Password Connect server fails to start (`illegal base64 data`)

```
failed to credentialsDataFromBase64, illegal base64 data at input byte 0
```

The Connect server expects the credentials file mounted from the `op-credentials` secret to be **base64-encoded JSON**, not raw JSON. The `task secrets:1password-connect-creds` task handles this encoding automatically. If you seeded the secret manually or with an older version of the task, re-run:

```bash
task secrets:1password-connect-creds
```

To fix an existing secret without re-running the task:

```bash
RAW_JSON=$(kubectl get secret op-credentials -n onepassword-connect \
  -o jsonpath='{.data.1password-credentials\.json}' | base64 -d)
B64=$(printf '%s' "$RAW_JSON" | base64 -w 0)
kubectl create secret generic op-credentials -n onepassword-connect \
  --from-literal=1password-credentials.json="$B64" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/onepassword-connect -n onepassword-connect
```

### `default` ServiceAccount missing in platform namespace

If a platform component namespace (e.g. `onepassword-connect`) was created before the Kyverno FedRAMP AC-2 policy excluded it, the Kubernetes service account controller may have been blocked from auto-creating the `default` SA. Symptoms: pods stuck in `FailedCreate` with `serviceaccount "default" not found`.

```bash
kubectl create serviceaccount default -n <namespace>
kubectl rollout restart deployment/<name> -n <namespace>
```

This is a one-time bootstrap issue. The platform namespace exclusion list in `policies/fedramp-ac2-account-management.yaml` prevents recurrence on new clusters.

### Kyverno `PolicyViolation` warnings in ArgoCD

Events like `policy fedramp-ac2-audit-account-changes/audit-serviceaccount-changes fail` appear on ServiceAccounts and RoleBindings. These are **audit-only** (`validationFailureAction: Audit`) — they generate compliance trail events but do not block anything. They are intentional: the FedRAMP AC-2 controls require logging all account lifecycle events.

### ApplicationSet `exclude` field type error

```
spec.generators[0].git.directories[0].exclude: Invalid value: "string": must be of type boolean
```

The ArgoCD ApplicationSet git generator `exclude` field is a boolean, not a path string. The correct syntax is a separate directory entry:

```yaml
directories:
  - path: tenants/*
  - path: tenants/_defaults
    exclude: true   # ← boolean, on its own entry
```

### Argo CD can't access stllr-infra

```bash
# Check repo secret exists
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository
```

> **Note:** `kubectl exec ... git ls-remote` does not work for private repos — bare git in the
> container shell has no access to Argo CD's internal credential store. The authoritative check
> is the Argo CD UI: **Settings → Repositories** should show the repo as **Connected**.

### ESO not syncing tenant secrets

```bash
# Check ExternalSecret status
kubectl describe externalsecret tenant-secrets -n tenant-<slug>

# Verify ClusterSecretStore is valid
kubectl describe clustersecretstore onepassword

# Verify the item exists in 1Password with the right name
op item get stllr-tenant-<slug> --vault <vault-name>

# Force sync
kubectl annotate externalsecret tenant-secrets \
  -n tenant-<slug> force-sync=$(date +%s) --overwrite
```

### Kargo not discovering new images

```bash
# Check Warehouse status and events
kubectl describe warehouse stllr-images -n stllr

# Verify ghcr-credentials secret has the kargo label
kubectl get secret ghcr-credentials -n stllr --show-labels
```

### Kargo Project shows OutOfSync (`spec.promotionPolicies` drift)

The `spec.promotionPolicies` field in the Kargo `Project` CRD is deprecated. Auto-promotion is now configured at the Stage level via `spec.requestedFreight.sources.direct: true`. If your `project.yaml` still contains `promotionPolicies`, remove it — the field is ignored by the controller but causes an ArgoCD diff:

```yaml
# kargo/project.yaml — correct form
spec: {}
```

### Doppler `DopplerSecret` blocking platform health check

If Doppler is enabled in values but no API key is configured, the `DopplerSecret` resource never becomes healthy and `turnkey-platform` sync will stall waiting for it. If you are using 1Password as your secrets backend, disable Doppler:

```yaml
# chart/values.doks.yaml (or your environment overlay)
doppler:
  enabled: false
```

Commit, push, and re-sync `turnkey-platform`.

### Namespace stuck terminating on destroy

```bash
source scripts/lib/argocd-destroy-cleanup.sh
argocd_destroy_cleanup
```

---

## See Also

- `docs/runbooks/bootstrap.md` — general bootstrap reference
- `docs/runbooks/doks-deployment.md` — DOKS-specific deployment
- `docs/runbooks/stllr-infra-apps.md` — configuring apps from stllr-infra
- `docs/runbooks/cert-manager-cloudflare-dns01.md` — TLS certificates
- `stllr-infra/docs/tenant-onboarding.md` — tenant onboarding deep-dive
- `stllr-infra/docs/secrets.md` — secrets model and AKV naming
- `stllr-infra/docs/promotion-model.md` — Kargo promotion pipeline
- `stllr-infra/docs/staggered-rollout.md` — cohort rollout procedure
