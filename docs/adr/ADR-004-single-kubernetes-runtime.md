# ADR-004: Single Kubernetes runtime target

- Status: Accepted
- Date: 2026-03-19

## Decision

Turnkey standardizes on Kubernetes for all workloads and platform controls.

## Rationale

- Eliminates split operational patterns across multiple runtimes.
- Consolidates observability, policy, and secrets integration points.
- Aligns with FedRAMP-oriented platform direction.

## Tradeoffs

- Migration effort from legacy runtime platforms is required.
- Team workflows must converge on GitOps and Kubernetes operations.
