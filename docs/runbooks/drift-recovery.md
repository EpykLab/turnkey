# Drift Recovery Runbook

## Objective

Recover desired state after unauthorized or accidental cluster-side changes.

## Procedure

1. Inspect Argo CD applications for OutOfSync resources.
2. Confirm source manifest correctness in git.
3. Trigger app sync with prune and self-heal enabled.
4. Verify drifted resources converge.
5. Record root cause and corrective action.

## Escalation

If repeated drift occurs, enforce stricter RBAC and admission controls before re-syncing.
