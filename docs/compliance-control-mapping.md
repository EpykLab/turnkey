# Compliance control mapping (Turnkey baseline)

This document ties Turnkey platform controls to the security posture described in the Stellerbridge Kubernetes migration plan. It is a living index: fill in control IDs and evidence locations as the program matures.

## Baseline enforcement (in repo today)

| Theme | Implementation | Notes |
| --- | --- | --- |
| Admission policies | Kyverno (`chart` → `turnkey-kyverno*`, `policies/baseline.yaml`) | Privileged containers denied; probes and resource requests/limits enforced for workloads outside platform namespaces. |
| Ingress | ingress-nginx (Argo-managed child app) | Aligns with the nginx ingress decision; not the Stellerbridge tenant chart. |
| TLS issuance | cert-manager (Argo-managed child app) | Install only in this phase; ClusterIssuers (e.g. Cloudflare DNS-01) are operator-managed after CRDs are healthy. |
| Secret sync to cluster | External Secrets Operator (optional, `externalSecrets.enabled`) | Disabled by default until Azure Key Vault / other backend is configured. |
| CIS-style node/control-plane checks | kube-bench CronJob (`deploy/kube-bench`, `kubeBench.enabled`) | Use managed-cluster baselines for honest posture; kind results differ from DOKS/AKS. Namespace `turnkey-compliance` is excluded from baseline Pod/CronJob policies that conflict with hostPath/hostPID scans; document waived or accepted findings per environment. |

## FedRAMP / CMMC follow-ups

- Map each Kyverno policy and platform choice to explicit control families (AC, AU, CM, SC, etc.).
- Record evidence: repo paths, Argo Application names, and change-management process.
- Track gaps called out in the migration journal (e.g. AKS managed provisioning, minimum production node sizing).

## References

- Repository: `EpykLab/turnkey` (Pulumi bootstrap + platform Helm chart).
- Architecture source: internal journal “Moving to K8s” (Stellerbridge).
