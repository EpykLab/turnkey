# turnkey

Turnkey is the platform baseline for provisioning and bootstrapping Kubernetes clusters with Pulumi and Argo CD.

## Repository layout

- `pulumi/`: infrastructure entrypoint and Argo CD bootstrap.
- `bootstrap/`: Argo CD app-of-apps manifests (root app target path).
- `chart/`: platform baseline Helm chart (Argo CD managed).
- `stacks/`: environment-level Pulumi configuration.
- `docs/`: ADRs, runbooks, and compliance mapping.

## Bootstrap flow

1. `pulumi up` provisions provider infrastructure (AKS or DOKS) and obtains kubeconfig.
2. Pulumi creates `argocd` namespace and installs Argo CD.
3. Pulumi applies root Argo CD Application.
4. Root app syncs `bootstrap/`, which declares the platform app.
5. Platform app syncs the Helm chart from `chart/`.

`bootstrap/platform-application.yaml` currently uses Helm `valueFiles` `values.yaml` + `values.doks.yaml` for DigitalOcean. For AKS, point `valueFiles` at `values.aks.yaml` instead (or add a second Application per environment).

## Quick start

```bash
cd pulumi
pulumi stack select dev
pulumi config set-all --path cluster.kubeconfig="<kubeconfig>"
pulumi up
```
