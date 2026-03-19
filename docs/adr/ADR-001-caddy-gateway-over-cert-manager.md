# ADR-001: Caddy Gateway over cert-manager

- Status: Accepted
- Date: 2026-03-19

## Decision

Turnkey uses Caddy Gateway as the Gateway API implementation and does not include cert-manager.

## Rationale

- Reduces bootstrap complexity and avoids cert-manager webhook ordering issues.
- Aligns with Gateway API as the standard ingress surface.
- Keeps certificate lifecycle in a single gateway control plane.

## Tradeoffs

- Caddy Gateway ecosystem maturity is lower than older ingress options.
- Fallback path is to switch Gateway implementation while preserving Gateway API resources.
