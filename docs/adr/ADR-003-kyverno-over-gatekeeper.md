# ADR-003: Kyverno over OPA Gatekeeper

- Status: Accepted
- Date: 2026-03-19

## Decision

Turnkey uses Kyverno as admission policy engine for baseline hardening.

## Rationale

- Policy authoring in YAML aligns with Kubernetes-native workflows.
- Faster team onboarding than Rego-first policy development.
- Supports validation and mutation for practical baseline enforcement.

## Tradeoffs

- Policy complexity must be constrained to keep rules understandable.
- Some advanced policy logic may require custom admission controls later.
