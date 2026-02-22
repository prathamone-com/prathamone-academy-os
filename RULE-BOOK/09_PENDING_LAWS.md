# RULE-BOOK: 09_PENDING_LAWS.md — VULNERABILITY GAP REPORT & PROPOSED DRAFT LAWS
**Classification:** PENDING RATIFICATION (Audit Output v1.0 — Generated 2026-02-22)**
**Produced by:** Chief Kernel Guardian & Architectural Auditor (3-Phase Audit)
**Architect:** Jawahar R Mallah — PrathamOne Academy OS

> [!WARNING]
> The following gaps represent HIGH-RISK architectural vectors not currently codified
> as Locked Laws. Each section identifies the vulnerability, provides formal analysis,
> and proposes a Draft Law in the absolute language of the PrathamOne Academy OS doctrine.
> These PENDING laws must be reviewed by the Sovereign Architect, ratified, and migrated
> to the appropriate Module Rule-Book before being considered LOCKED.

---

## GAP #1 — THE "RIGHT TO ERASURE" CONFLICT (DPDP Act Compliance)

### Vulnerability Analysis

**Affected Laws:** `L9-LAW-5` (Forensic Audit Spine — Immutability)
**Regulatory Driver:** India's Digital Personal Data Protection Act (DPDP Act, 2023), Article 12-13, Right to Erasure. Also applicable: GDPR Article 17, Kenya DPA, and analogous frameworks.

**The Conflict:** The Audit Spine (`audit_event_log`) is an append-only, hash-chained ledger. This is mandatory for courtroom-grade evidence. However, a Data Principal (student/guardian) has a legally enforceable right to request deletion of their Personally Identifiable Information (PII). A naive erasure of audit records would break the SHA-256 hash chain, constituting a tampering event. A naive refusal to erase would constitute a regulatory violation.

**Consequence of Gap:** Without a codified protocol, any DPDP erasure request creates an irresolvable conflict between `L9-LAW-5` and regulatory law, potentially resulting in enforcement action, fines, or injunctions against all tenants on the platform.

### Proposed Draft Laws

---
**PENDING LAW 09-1.1 (The Anonymization Mandate):**
Upon receiving a verified Right-to-Erasure request, the system **must** execute a Cryptographic Anonymization Protocol (CAP). The protocol **must** replace all PII values within the subject's `entity_value` records with a cryptographically derived, irreversible tombstone token (format: `ERASED-{SHA256(tenant_id + subject_id + erasure_timestamp)}`). The underlying EAV record structure (entity, attribute, timestamps, audit linkages) **must** be preserved intact.

**PENDING LAW 09-1.2 (The Audit Spine Preservation Rule):**
The hash chain in `audit_event_log` **must never** be reconstructed or re-sealed following an erasure event. The audit record for the anonymization action itself (action_type: `GDPR_ERASURE_EVENT`) **must** be appended to the chain as the next valid block, referencing the prior hash. The `previous_hash` linkage is thereby preserved; the erasure event becomes an immutable forensic fact within the chain.

**PENDING LAW 09-1.3 (The Erasure Request Lifecycle):**
Every Right-to-Erasure request **must** itself be a first-class workflow entity, traversing states: `RECEIVED` → `VERIFIED` → `LEGAL_HOLD_CHECK` → `IN_PROGRESS` → `COMPLETED`. No erasure may execute unless the workflow reaches `COMPLETED` state, ensuring Policy Engine and legal-hold checks pass first. A student under a live legal dispute (legal hold flag = TRUE) **cannot** have erasure processed until the hold is lifted.

**PENDING LAW 09-1.4 (Segregated PII Vault):**
All PII fields (name, date_of_birth, contact, guardian data) **must** be designated with `pii_class = 'DIRECT'` in `attribute_master`. The CAP is the **only permitted execution path** for altering these fields post-creation. Any UPDATE to a `pii_class='DIRECT'` field outside of a CAP-workflow context **must** be rejected by the kernel as a CRITICAL security policy violation and logged immediately.

---

## GAP #2 — EMERGENCY BREAK-GLASS PROCEDURE

### Vulnerability Analysis

**Affected Laws:** `L9-LAW-5` (Immutability), `L0-LAW-9` (No Bypass Law)
**Trigger Event:** Hardware failure, disk corruption, or catastrophic data loss that physically destroys the integrity of the last N audit records, creating an unrecoverable hash chain break that is not caused by human tampering.

**The Conflict:** The system has no codified protocol for this event. The "no manual override" law (`L0-LAW-9`) forbids human intervention on the audit spine. But a corrupted spine is also a violation of `L9-LAW-5`. Without a Break-Glass Protocol, an Incident Response team has no lawful path to recovery, potentially leading to unauthorized ad-hoc actions that cause greater damage.

**Consequence of Gap:** A single disk failure in a high-tenant-density shard could permanently compromise the forensic integrity of hundreds of institutions' records, with no defined recovery path.

### Proposed Draft Laws

---
**PENDING LAW 09-2.1 (The Break-Glass Declaration):**
A "Chain Break Event" (CBE) may only be officially declared by a quorum of **three** Sovereign-level administrators acting simultaneously, with each action cryptographically signed by their respective Hardware Security Module (HSM) keys. A declaration by fewer than three signatories **must** be rejected by the kernel.

**PENDING LAW 09-2.2 (The Re-Seal Protocol):**
Following a ratified CBE declaration, the kernel **must** initiate automated re-sealing from the last known **verified, off-site WORM-backed checkpoint** (see GAP #5). The re-sealing process inserts a mandatory `CHAIN_BREAK_RECOVERY` sentinel block signed by all three quorum keys. This sentinel becomes an immutable forensic record of the event, time of failure, and recovery point. No data is fabricated; only the chain linkage is re-established from the verified checkpoint forward.

**PENDING LAW 09-2.3 (The CBE Notification Law):**
Upon completion of any CBE recovery, the system **must** automatically notify all tenant administrators on the affected shard via a signed, kernel-generated notification within 72 hours. The notification **must** specify: the corrupted time range, the last valid checkpoint timestamp, and the recovery sentinel block hash.

**PENDING LAW 09-2.4 (Quarterly Drip-Test Mandate):**
Every tenant shard's audit hash chain **must** undergo an automated integrity verification ("drip-test") on a quarterly schedule. The test result **must** be appended as a `CHAIN_INTEGRITY_VERIFIED` audit event. Any shard that fails three consecutive quarterly verifications **must** be automatically elevated to a CRITICAL security alert, triggering a mandatory CBE risk assessment.

---

## GAP #3 — PLUGIN MEMORY & BLAST RADIUS CONTROL

### Vulnerability Analysis

**Affected Laws:** `L0-LAW-9` (KMC Compliance — No Bypass), `LAW SB-11` (Sandboxed Execution)
**The Gap:** While the Plugin Framework mandates sandbox execution and prohibits direct DML, there are NO quantitative resource limits defined. A poorly written or malicious third-party plugin can exhaust CPU, RAM, or API quotas within the sandbox, creating a Denial-of-Service event for the entire shard (the "blast radius" problem). A runaway plugin could also act as a side-channel for data exfiltration through excessive API calls.

**Consequence of Gap:** An institution integrating a malicious or buggy plugin could bring down services for hundreds of co-tenants on the same shard, violating the Tenant Sovereignty Law (`L1-LAW-2`) through a resource starvation attack.

### Proposed Draft Laws

---
**PENDING LAW 09-3.1 (Plugin Execution Time Limit):**
No single plugin invocation may execute for longer than **5,000 milliseconds (5 seconds)**. Violation results in automatic `SIGKILL` of the plugin process, automatic status escalation to `SUSPENDED`, and a `HIGH` severity entry in `audit_event_log` (action_type: `PLUGIN_TIMEOUT_KILL`). The invoking tenant is notified immediately.

**PENDING LAW 09-3.2 (Plugin Memory Ceiling):**
No plugin container may consume more than **256 megabytes of RAM** during any single invocation. Exceeding this threshold results in immediate `SIGKILL`, `SUSPENDED` status, and a `HIGH` severity audit event (action_type: `PLUGIN_MEMORY_EXCEEDED`).

**PENDING LAW 09-3.3 (Plugin API Rate Limits):**
A plugin is permitted a maximum of **100 outbound API calls per minute** to the PrathamOne kernel. Exceeding this rate triggers automatic throttling for 60 seconds, followed by suspension if the rate is exceeded in three consecutive minutes. Every throttle event generates a `MEDIUM` severity audit entry.

**PENDING LAW 09-3.4 (Plugin Tenant Egress Isolation):**
A plugin's sandbox network interface **must** be bound exclusively to the invoking tenant's VLAN. Any attempt to make network calls outside of explicitly whitelisted kernel API endpoints is an instant `CRITICAL` severity kernel security event, resulting in permanent plugin revocation for that tenant and a mandatory review by the Sovereign Architect. No cross-tenant network path may exist within any plugin sandbox.

**PENDING LAW 09-3.5 (Plugin Blast Radius Score):**
Prior to activation for any tenant, every plugin must receive a "Blast Radius Score" (BRS) from the kernel's static analysis engine. Plugins with a BRS exceeding **7/10** must receive explicit Sovereign Architect approval before tenant-level activation is permitted.

---

## GAP #4 — API GATEWAY & SELECTIVE RATE LIMITING

### Vulnerability Analysis

**Affected Laws:** `L1-LAW-2` (Tenant Isolation), `L0-LAW-9` (KMC Compliance)
**The Gap:** The system lacks defined, codified throttling rules for the API Gateway at the tenant and shard level. A mega-tenant with 50,000 concurrently active students, or a runaway automated script on any tenant, can generate API request volumes that degrade service for all co-tenants on the same shard — a "noisy neighbor" DDoS.

**Consequence of Gap:** The absence of codified API quotas means the current system has no contractual or architectural basis for throttling a misbehaving tenant without taking the entire shard offline — which itself violates the Tenant Sovereignty Law.

### Proposed Draft Laws

---
**PENDING LAW 09-4.1 (Per-Tenant API Quota):**
Each tenant shard allocation **must** define a maximum sustained API throughput limit (default: **1,000 requests per minute**). Tenants exceeding this limit receive HTTP 429 responses with a `Retry-After` header. The limit **must** be configurable within the tenant's service agreement metadata, stored in `tenant_shard_config`.

**PENDING LAW 09-4.2 (Shard-Level Circuit Breaker):**
The Shard Router **must** implement a circuit breaker. If any single tenant consumes more than **40% of a shared shard's total API capacity** for more than 60 consecutive seconds, the Shard Router **must** automatically impose an emergency per-tenant cap at **20% of shard capacity**, and generate a `CRITICAL` audit event. The affected tenant's primary contact **must** be notified automatically.

**PENDING LAW 09-4.3 (DDoS Sentinel):**
The API Gateway **must** implement an anomaly detection sentinel that identifies request patterns consistent with a DDoS (e.g., rate exceeds 5x the tenant's 30-day rolling average within a 5-minute window). Detection triggers automatic geographic CAPTCHA challenge for the anomalous subnet, followed by full subnet block if the anomaly persists beyond 120 seconds.

**PENDING LAW 09-4.4 (Endpoint Vulnerability Classification):**
All kernel API endpoints **must** be classified as `TIER-1` (read-only, high-volume allowed) or `TIER-2` (write/mutating, strict quota enforced). TIER-2 endpoints **must** enforce a separate, lower quota of no more than **100 writes per minute per tenant** by default, regardless of the overall API quota.

---

## GAP #5 — DATA ARCHIVAL & COLD STORAGE TRANSITION

### Vulnerability Analysis

**Affected Laws:** `L9-LAW-5` (Immutability), `L7-LAW-6` (Financial Integrity)
**The Gap:** The system anticipates over 1 billion audit events. No rules define when, how, and under what conditions historical data is moved from the hot OLTP PostgreSQL shard to cold WORM (Write Once Read Many) archive storage. Without this, the primary database will degrade in performance over time, and the audit spine has no protection against long-term storage failure.

**Consequence of Gap:** Failure to define archival rules will eventually result in database performance degradation, storage cost explosion, and — critically — loss of the ability to perform a forensic hash-chain replay for audit records older than the hot storage retention window.

### Proposed Draft Laws

---
**PENDING LAW 09-5.1 (Hot Storage Retention Window):**
Audit events, EAV entity values, and financial ledger records older than **36 calendar months** from their `created_at` timestamp **must** be migrated automatically to the Cold WORM Archive tier. The migration **must** be transactional: the record is written to cold storage and verified by hash before deletion from the hot tier.

**PENDING LAW 09-5.2 (Cold Archive Integrity Seal):**
Each batch of records migrated to cold storage **must** be sealed with a Batch Archive Manifest (BAM). The BAM is a single, signed JSON document containing: tenant_id, date range covered, record count, the SHA-256 hash of every record in the batch in order, and the hash of the BAM itself. The BAM **must** be stored both in cold storage and appended as a `COLD_ARCHIVE_SEALED` event to the primary hot audit chain.

**PENDING LAW 09-5.3 (Forensic Replay Guarantee):**
The kernel **must** provide a `forensic_replay()` function capable of reconstituting the complete, verified hash chain for any tenant for any date range, across both the hot archive and cold WORM tiers. This function **must** complete execution within **30 minutes** for any 12-month date range query. Any failure to replay constitutes a CRITICAL system integrity breach event.

**PENDING LAW 09-5.4 (WORM Immutability Enforcement):**
Cold archive storage **must** be provisioned with WORM object-lock semantics (S3 Object Lock Compliance Mode or equivalent). The minimum object lock retention period is **7 years** for financial ledger data and **10 years** for academic record events, conforming to the Indian Records management standards (NKN guidelines and UGC regulations).

**PENDING LAW 09-5.5 (Archival Event Audit):**
Every cold storage migration event (BAM creation) **must** itself be logged in the hot-tier `audit_event_log` with action_type `COLD_ARCHIVE_SEALED`. This ensures there is always a hot-tier audit trail of all archival events, even if the cold storage becomes temporarily inaccessible.

---

## GAP #6 — CROSS-REGION DATA RESIDENCY

### Vulnerability Analysis

**Affected Laws:** `L1-LAW-2` (Tenant Sovereignty & Isolation), `L0-LAW-9` (KMC Compliance)
**Regulatory Driver:** India's DPDP Act (Section 16 — Restricted Transfers); EU GDPR Chapter V; various state-level data localization mandates.
**The Gap:** As the platform scales globally, there are no hard, DB-level constraints preventing a tenant's data from being replicated to—or even temporarily cached in—an unauthorized geographic region. Currently, data residency is potentially managed only at the infrastructure layer (cloud tags/labels), which is insufficient for compliance.

**Consequence of Gap:** If a tenant's data residency is `INDIA` and a replication event pushes data to a Singapore AWS region, the tenant (and PrathamOne) may face regulatory violation. Without kernel-level enforcement, this is a silent, undetectable breach.

### Proposed Draft Laws

---
**PENDING LAW 09-6.1 (Mandatory Residency Tag):**
Every tenant record **must** carry a `data_residency_region` field in `tenant_master` (e.g., `IN-MUM`, `EU-IRL`, `US-VA`). This field is immutable after initial provisioning. Any attempt to modify `data_residency_region` **must** require a full data migration workflow with multi-party signatures and a corresponding Legal Transfer Instrument (LTI) document linked as a file node.

**PENDING LAW 09-6.2 (Replication Boundary Enforcement):**
The database replication configuration **must** enforce that tenant data is only streamed to replica nodes within the same `data_residency_region`. This **must** be implemented as a PostgreSQL Row-Level Security policy on the publication/subscription tables, not merely as an infrastructure tag. Any replication configuration change that would cross a residency boundary **must** be rejected by the kernel with a `CRITICAL` audit event.

**PENDING LAW 09-6.3 (The Unauthorized Transfer Detection Law):**
An automated residency sentinel **must** run every 24 hours and verify that no tenant data has been written to a data store tagged with a region code not matching the tenant's `data_residency_region`. Detection of a violation **must** immediately trigger: (1) quarantine of the foreign data, (2) a `CRITICAL` breach audit event, and (3) mandatory notification to the tenant's Data Protection Officer (DPO) contact within 1 hour.

**PENDING LAW 09-6.4 (Cold Archive Residency Lock):**
The cold archival process (see PENDING LAW 09-5.1) **must** verify and assert the target WORM storage bucket's region code against the tenant's `data_residency_region` before any write operation. A mismatch **must** abort the archival job and generate a `HIGH` severity audit event. Data **must never** be written to a cold store in a non-compliant region, even temporarily.

---

## RATIFICATION CHECKLIST

| Gap # | Proposed Laws | Risk Level | Status | Required Action |
|-------|---------------|------------|--------|-----------------|
| GAP-1 (DPDP Erasure) | 09-1.1 to 09-1.4 | 🔴 CRITICAL | PENDING | Ratify → Migrate to Module Rule-Book |
| GAP-2 (Break-Glass) | 09-2.1 to 09-2.4 | 🔴 CRITICAL | PENDING | Ratify → Migrate to `00_CORE_CONSTITUTION.md` Annex |
| GAP-3 (Plugin Blast Radius) | 09-3.1 to 09-3.5 | 🟠 HIGH | PENDING | Ratify → New `10_PLUGIN_FRAMEWORK_RULES.md` |
| GAP-4 (API Rate Limiting) | 09-4.1 to 09-4.4 | 🟠 HIGH | PENDING | Ratify → New `11_API_GATEWAY_RULES.md` |
| GAP-5 (Cold Storage Archival) | 09-5.1 to 09-5.5 | 🟡 MEDIUM | PENDING | Ratify → New `12_ARCHIVAL_RULES.md` |
| GAP-6 (Cross-Region Residency) | 09-6.1 to 09-6.4 | 🔴 CRITICAL | PENDING | Ratify → `00_CORE_CONSTITUTION.md` Amendment |

---

## ARCHITECT'S RATIFICATION SECTION

```
Sovereign Architect Sign-off Required for CRITICAL and HIGH items.

Reviewed by: _______________________
Date: _______________________
Signature (HSM / Wet): _______________________
```

---

*© 2026 PrathamOne Academy OS. All rights reserved.*
*Founder & Technical Architect: Jawahar R Mallah — [aiTDL.com](https://aiTDL.com)*
