# Runbook: cert-manager with Cloudflare DNS-01 (wildcard-friendly)

Turnkey installs cert-manager as a child Argo CD Application. After cert-manager CRDs and the controller are healthy, create credentials and a `ClusterIssuer` in the cluster (not committed to git).

## Prerequisites

- Cloudflare API token with DNS edit permission for the zone.
- cert-manager running (`cert-manager` namespace).

## Steps

1. Create a secret in `cert-manager` with the API token:
  ```bash
   kubectl -n cert-manager create secret generic cloudflare-api-token \
     --from-literal=api-token="YOUR_TOKEN"
  ```
2. Apply a `ClusterIssuer` referencing that secret (adjust email and solver config as needed). Example skeleton:
  ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-cloudflare
   spec:
     acme:
       email: platform@example.com
       server: https://acme-v02.api.letsencrypt.org/directory
       privateKeySecretRef:
         name: letsencrypt-cloudflare-account-key
       solvers:
         - dns01:
             cloudflare:
               apiTokenSecretRef:
                 name: cloudflare-api-token
                 key: api-token
  ```
3. Create `Certificate` or ingress/gateway resources that reference the issuer.
4. Confirm certificate status:
  ```bash
   kubectl get certificate -A
   kubectl describe clusterissuer letsencrypt-cloudflare
  ```

## Notes

- Use Let’s Encrypt staging while testing to avoid rate limits.
- Root-cause any historical cert-manager renewal issues before production cutover (see migration journal).

