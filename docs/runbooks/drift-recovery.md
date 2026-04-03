# Drift Recovery Runbook

## Objective

Recover desired state after unauthorized or accidental cluster-side changes.

## Procedure

1. Inspect Argo CD applications for OutOfSync resources.
   ```bash
   kubectl get applications.argoproj.io -n argocd -o wide
   ```
2. Confirm source manifest correctness in git.
3. Trigger app sync with prune and self-heal enabled.
   ```bash
   # Via kubectl
   kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}'
   
   # Or via ArgoCD CLI (if installed)
   argocd app sync <app-name> --prune
   ```
4. Verify drifted resources converge.
5. Record root cause and corrective action.

## Common Drift Scenarios

### External Secrets Disabled

If External Secrets was disabled due to CRD issues, applications will show as missing. This is expected behavior - the deployment intentionally excludes External Secrets to avoid CRD size limit errors.

### Ingress Nginx Webhook Issues

Ingress Nginx admission webhooks are disabled by default. If manually enabled and causing issues, revert to:
```yaml
controller:
  admissionWebhooks:
    enabled: false
```

### Doppler Secrets Out of Sync

Doppler requires a valid service token. If secrets aren't syncing:
1. Check token secret exists: `kubectl get secret doppler-service-token -n doppler-operator-system`
2. Verify token validity at Doppler dashboard
3. Restart operator: `kubectl rollout restart deployment -n doppler-operator-system`

## Escalation

If repeated drift occurs, enforce stricter RBAC and admission controls before re-syncing. Consider enabling Kyverno policies to prevent unauthorized changes.

## See Also

- `bootstrap.md` - Full bootstrap procedure
- `doks-deployment.md` - DOKS-specific deployment issues
