# Bootstrap Runbook

## Objective

Provision a new Turnkey cluster from zero to Argo-managed steady state.

## Procedure

1. Configure stack file in `stacks/<env>.yaml`.
2. Set Pulumi config secrets as required.
3. Run `pulumi up` from `pulumi/`.
4. Verify Argo CD pods in namespace `argocd`.
5. Verify root application is `Synced` and `Healthy`.
6. Verify platform ApplicationSet generated applications are healthy.

## Validation

- Cluster API reachable
- Argo CD running
- Kyverno webhook available
- Doppler synced secret in target namespace
- OTel collector DaemonSet scheduled on all nodes