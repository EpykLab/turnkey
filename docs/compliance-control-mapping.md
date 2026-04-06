# Compliance Control Mapping (Turnkey Baseline)

This document maps Turnkey platform controls to FedRAMP security controls (based on NIST SP 800-53). It serves as a living index for auditors and compliance teams.

## Quick Reference

| FedRAMP Control | Description | Implementation | ArgoCD App | Evidence Location |
|-----------------|-------------|----------------|------------|-------------------|
| **AC-2** | Account Management | Kyverno policies | `turnkey-kyverno-policies` | `policies/fedramp-ac2-account-management.yaml` |
| **AU-2** | Audit Events | Vector log collection | `turnkey-vector` | `deploy/vector-audit/` |
| **AU-9** | Audit Protection | S3 Object Lock | `turnkey-vector` | S3 bucket config |
| **SC-7** | Boundary Protection | NetworkPolicies | Part of platform chart | `chart/templates/controls/networkpolicies-*.yaml` |
| **SC-8** | Transmission Encryption | Istio mTLS | Part of platform chart | `chart/templates/controls/mtls-policies.yaml` |
| **SI-4** | System Monitoring | Falco runtime security | `turnkey-falco` | `deploy/falco/` |

---

## AC: Access Control

### AC-2: Account Management

**Control Description:** Manage system accounts including creation, modification, and removal.

**Implementation:**
- **Kyverno policies** (`policies/fedramp-ac2-account-management.yaml`)
- **AC-2(3):** ServiceAccount token usage tracking with annotations
- **AC-2(4):** Audit ServiceAccount changes via Kyverno PolicyReports
- **AC-2(5):** Require approval annotations for new ServiceAccounts
- **AC-2(7):** RBAC binding documentation requirements
- **AC-2(8):** Flag unused token secrets for cleanup
- **AC-2(9):** Group membership documentation
- **AC-2(10):** Shared account identification

**Evidence:**
```bash
# View AC-2 policy reports
kubectl get policyreports -n kyverno
kubectl describe clusterpolicy fedramp-ac2-require-approval-annotation
```

**ArgoCD Application:** `turnkey-kyverno-policies` (sync-wave 25)

---

## AU: Audit and Accountability

### AU-2: Audit Events

**Control Description:** Identify and log security-relevant events.

**Implementation:**
- **Vector DaemonSet** (`deploy/vector-audit/`)
- Collects Kubernetes audit logs, container logs, and host system logs
- Filters for security-relevant events:
  - Account logon/logoff events
  - Access to security objects (secrets, roles, bindings)
  - Privileged operations (pods/exec, pods/attach)
  - Security policy changes

**Configuration:**
```yaml
vector:
  enabled: true
  s3:
    enabled: true
    bucket: "fedramp-audit-logs"
    region: "us-east-1"
```

**ArgoCD Application:** `turnkey-vector` (sync-wave 30)

### AU-9: Protection of Audit Information

**Control Description:** Protect audit logs against unauthorized access, modification, and deletion.

**Implementation:**
- **S3 Object Lock** with 7-year retention (GOVERNANCE mode)
- **Vector disk buffers** prevent log loss during network issues
- **End-to-end acknowledgements** guarantee log delivery
- **Immutable storage** via S3 bucket versioning and Object Lock

**Evidence:**
```bash
# Verify S3 Object Lock configuration
aws s3api get-object-lock-configuration \
  --bucket fedramp-audit-logs
```

**Required Setup:**
1. Create S3 bucket with Object Lock enabled
2. Configure 7-year retention policy
3. Set Vector S3 credentials via External Secrets

---

## SC: System and Communications Protection

### SC-7: Boundary Protection

**Control Description:** Monitor and control communications at external boundaries.

**Implementation:**
- **Default deny NetworkPolicies** for all non-platform namespaces
- **Namespace isolation** - only explicit cross-namespace allowed
- **Ingress restrictions** - only from nginx ingress controller
- **Egress restrictions** - only to approved endpoints

**Policies:**
| Policy | Control | Description |
|--------|---------|-------------|
| `fedramp-sc7-default-deny-ingress` | SC-7 | Deny all ingress by default |
| `fedramp-sc7-default-deny-egress` | SC-7 | Deny all egress by default |
| `fedramp-sc7-allow-ingress-nginx` | SC-7(3) | Allow ingress from nginx only |
| `fedramp-sc7-allow-egress-external` | SC-7(4) | Allow egress to approved endpoints |
| `fedramp-sc7-allow-internal-communication` | SC-7(5) | Allow internal namespace traffic |

**Enable in values:**
```yaml
fedramp:
  networkPolicies:
    enabled: true
```

### SC-8: Transmission Confidentiality

**Control Description:** Protect the confidentiality of transmitted information.

**⚠️ IMPORTANT: FIPS 140-2 Requirement**

FedRAMP requires **FIPS 140-2 validated cryptographic modules**. The following are **NOT acceptable**:
- ❌ WireGuard (uses ChaCha20-Poly1305, not FIPS validated)
- ❌ AES-CBC without authentication
- ❌ MD5, SHA-1, RC4, DES, 3DES
- ❌ RSA keys < 2048 bits
- ❌ Non-FIPS curves (Curve25519, etc.)

**RECOMMENDED: Linkerd with FIPS Build**

We recommend **Linkerd** for turnkey's FedRAMP implementation:

| Factor | Linkerd | Istio |
|--------|---------|-------|
| **Resource Usage** | Low (Rust proxy, ~1ms overhead) | High (Envoy, ~5-10ms overhead) |
| **Operational Complexity** | Simple | Complex |
| **mTLS Focus** | Purpose-built ✅ | Many features ⚠️ |
| **FedRAMP Audit** | Easy to document ✅ | Harder to audit ⚠️ |
| **Certificate Mgmt** | Automatic ✅ | Automatic ✅ |
| **FIPS 140-2** | BoringSSL-FIPS ✅ | BoringCrypto ✅ |

**Linkerd is the better choice because:**
1. **Simpler to operate** - Fewer components, easier to secure and audit
2. **Lower overhead** - Critical for resource-constrained environments
3. **Purpose-built for mTLS** - Does one thing well (SC-8 compliance)
4. **Easier FedRAMP documentation** - Smaller attack surface to assess

**Implementation:**
```yaml
# 1. Install Linkerd FIPS build first:
# linkerd install --set proxy.image.version=<fips-tag> | kubectl apply -f -

# 2. Enable in turnkey values:
linkerd:
  enabled: true
  fips:
    enabled: true

fedramp:
  mtls:
    enabled: true
```

**Alternative: Application-Level mTLS**
If you cannot use a service mesh, use cert-manager to issue FIPS-compliant certificates to each application:

```yaml
fedramp:
  appLevelMTLS:
    enabled: true
    issuerName: "fedramp-fips-ca"
```

**NOT RECOMMENDED: Istio**
We do **not** recommend Istio for turnkey unless you specifically need:
- Advanced traffic splitting (canary deployments)
- Authorization policies beyond mTLS
- WASM filters
- External authentication

Istio's complexity makes FedRAMP compliance harder to achieve and maintain.

**FIPS 140-2 Approved Cipher Suites:**
| Cipher Suite | Status |
|--------------|--------|
| ECDHE-RSA-AES256-GCM-SHA384 | ✅ Approved |
| ECDHE-RSA-AES128-GCM-SHA256 | ✅ Approved |
| ECDHE-ECDSA-AES256-GCM-SHA384 | ✅ Approved |
| ECDHE-ECDSA-AES128-GCM-SHA256 | ✅ Approved |
| ChaCha20-Poly1305 | ❌ Not FIPS |
| AES-CBC (any) | ❌ Not recommended |
| RC4, DES, 3DES | ❌ Prohibited |

**Key Requirements:**
- Minimum TLS 1.2 (TLS 1.3 allowed)
- ECDSA P-256 or P-384 keys preferred
- Certificate maximum validity: 90 days
- Automatic certificate rotation

**Enable FIPS enforcement:**
```yaml
fedramp:
  enforceFIPS:
    enabled: true  # Kyverno policy enforcement
```

---

## SI: System and Information Integrity

### SI-4: Information System Monitoring

**Control Description:** Monitor the information system to detect security incidents.

**Implementation:**
- **Falco runtime security** (`deploy/falco/`)
- **eBPF-based** syscall monitoring
- **Custom FedRAMP rules** (`deploy/falco/fedramp-si4-rules.yaml`)

**Detection Capabilities:**

| Rule | Control | Description |
|------|---------|-------------|
| `SI4_Unauthorized_Process_Launched` | SI-4(2) | Detect processes not in baseline |
| `SI4_Privilege_Escalation_Attempt` | SI-4(2) | Detect sudo/su/setuid usage |
| `SI4_Suspicious_Inbound_Connection` | SI-4(4) | Monitor suspicious inbound traffic |
| `SI4_Suspicious_Outbound_Connection` | SI-4(4) | Monitor suspicious outbound traffic |
| `SI4_Sensitive_File_Access` | SI-4(5) | Monitor access to /etc/shadow, k8s certs |
| `SI4_Kubernetes_Secret_Access` | SI-4(5) | Monitor ServiceAccount token access |
| `SI4_Container_Escape_Attempt` | SI-4(11) | Detect runc/nsenter escape attempts |
| `SI4_Crypto_Mining_Detection` | SI-4(11) | Detect xmrig/minerd processes |
| `SI4_Wireless_Interface_Created` | SI-4(14) | Detect wireless interface manipulation |
| `SI4_Modify_Sudoers` | SI-4(22) | Monitor sudoers file changes |
| `SI4_SSH_Key_Modified` | SI-4(22) | Monitor authorized_keys changes |

**Enable in values:**
```yaml
falco:
  enabled: true
  siem:
    enabled: true
    endpoint: "https://siem.gov.agency.mil/webhook"
```

**ArgoCD Application:** `turnkey-falco` (sync-wave 35)

---

## Baseline Enforcement (Existing)

| Theme | Implementation | Notes |
| --- | --- | --- |
| Admission policies | Kyverno (`chart` → `turnkey-kyverno*`, `policies/baseline.yaml`) | Privileged containers denied; probes and resource requests/limits enforced for workloads outside platform namespaces. |
| Ingress | ingress-nginx (Argo-managed child app) | Aligns with the nginx ingress decision; not the Stellerbridge tenant chart. |
| TLS issuance | cert-manager (Argo-managed child app) | Install only in this phase; ClusterIssuers (e.g. Cloudflare DNS-01) are operator-managed after CRDs are healthy. |
| Secret sync to cluster | External Secrets Operator (optional, `externalSecrets.enabled`) | Disabled by default until Azure Key Vault / other backend is configured. |
| CIS-style node/control-plane checks | kube-bench CronJob (`deploy/kube-bench`, `kubeBench.enabled`) | Use managed-cluster baselines for honest posture; kind results differ from DOKS/AKS. Kyverno excludes `CronJob`/`Job` in `turnkey-compliance` from baseline Pod-oriented rules (hostPath/hostPID scans); document waived or accepted findings per environment. |

---

## FedRAMP Deployment Example

To deploy a cluster with full FedRAMP compliance:

```yaml
# values.fedramp.yaml
global:
  environment: production
  clusterName: turnkey-fedramp-prod

# AU-2/AU-9: Audit log collection with S3 Object Lock
vector:
  enabled: true
  s3:
    enabled: true
    bucket: "gov-agency-fedramp-audit"
    region: "us-gov-west-1"
    objectLock: true
  siem:
    enabled: true
    endpoint: "https://siem.gov.agency.mil/hec"
    token: "${SPLUNK_HEC_TOKEN}"  # From External Secret

# SC-7: Boundary protection via NetworkPolicies
fedramp:
  networkPolicies:
    enabled: true
  # SC-8: FIPS 140-2 validated mTLS
  # Option 1: Linkerd (recommended)
  linkerd:
    enabled: true
    fips:
      enabled: true
  # Option 2: Istio
  # istio:
  #   enabled: true
  #   fips:
  #     enabled: true
  # Option 3: Application-level
  # appLevelMTLS:
  #   enabled: true
  #   issuerName: "fedramp-fips-ca"
  # Enforce FIPS 140-2 ciphers
  enforceFIPS:
    enabled: true

# SI-4: Runtime security monitoring
falco:
  enabled: true
  siem:
    enabled: true
    endpoint: "https://siem.gov.agency.mil/falco"

# CIS compliance scanning
kubeBench:
  enabled: true
```

Deploy with:
```bash
# First, ensure you have FIPS 140-2 validated builds:
# - Linkerd: Must install with FIPS tag
# - Istio: Must use distroless-fips image

pulumi config set turnkey:platform.valueFiles '["values.yaml","values.fedramp.yaml"]'
pulumi up
```

**FIPS 140-2 Validation Evidence:**
```bash
# For Linkerd:
linkerd check --output json | jq '.fips'

# For Istio:
kubectl exec -n istio-system deployment/istiod -- pilot-discovery request GET /debug/endpointShardz | grep -i fips

# Check cipher suites:
openssl s_client -connect <service>:443 -tls1_2 2>/dev/null | grep "Cipher"
```

---

## References

- **FedRAMP Baseline:** NIST SP 800-53 Rev 5 Moderate Impact Baseline
- **Kubernetes Security:** [OneUptime FedRAMP Guide](https://oneuptime.com/blog/post/2026-02-09-fedramp-security-controls-kubernetes/)
- **Repository:** `EpykLab/turnkey`
- **Architecture source:** internal journal "Moving to K8s" (Stellerbridge)
