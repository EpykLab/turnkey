# ADR-002: Doppler over self-hosted secrets management

- Status: Accepted
- Date: 2026-03-19

## Decision

Turnkey uses Doppler as the secrets source of truth and syncs into Kubernetes Secrets via operator.

## Rationale

- Lower operational burden than operating Vault at current team size.
- Supports environment promotion, access control, and audit visibility.
- Keeps application interface stable by consuming native Kubernetes Secrets.

## Tradeoffs

- Managed SaaS dependency is introduced.
- For contracts requiring on-prem key custody, replace operator path with ESO + cloud KMS.
