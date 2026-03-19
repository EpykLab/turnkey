# Turnkey Platform Compliance Control Mapping

This document maps platform controls implemented by Turnkey to SOC 2, HIPAA, and FedRAMP control families.

## Mappings

- Cilium NetworkPolicy -> SOC 2 CC6.6, HIPAA 164.312(e)(1), FedRAMP SC.
- Cilium mTLS -> SOC 2 CC6.7, HIPAA 164.312(e)(2)(i), FedRAMP SC-8.
- Kyverno pod security/image policy -> SOC 2 CC6.1/CC7.1, HIPAA 164.312(a)(1), FedRAMP AC/SI.
- Doppler secret management -> SOC 2 CC6.1, HIPAA 164.312(a)(2)(iv), FedRAMP IA.
- OTel + Elastic audit trail -> SOC 2 CC7.2, HIPAA 164.312(b), FedRAMP AU.
- Caddy Gateway TLS -> SOC 2 CC6.7, HIPAA 164.312(e)(2)(i), FedRAMP SC-8.
- Argo CD GitOps change flow -> SOC 2 CC8.1, HIPAA 164.308(a)(5), FedRAMP CM.

## Inheritance Notes

AKS in Azure Government provides inherited controls at the cloud layer. Turnkey control inheritance boundaries are tracked separately in FedRAMP boundary documentation.
