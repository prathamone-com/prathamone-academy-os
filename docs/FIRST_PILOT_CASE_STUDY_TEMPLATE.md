# PrathamOne Academy OS
## First Pilot Case Study — Live Documentation Template

> **Instructions:** Fill this document IN PARALLEL with executing the 15-Point Onboarding Checklist.  
> Every section has a "Record Here" block. Do not complete onboarding without completing this document.  
> A pilot without documentation is just an experience. A documented pilot is institutional proof.

---

## Cover Page

| Field | Value |
|-------|-------|
| **Institution Name** | _(fill during Point 3)_ |
| **Pilot Tenant ID** | _(fill during Point 3)_ |
| **Data Residency Region** | _(fill during Point 3)_ |
| **Pilot Start Date** | _(fill on Day 1)_ |
| **Pilot End Date** | _(fill on completion)_ |
| **Platform Version** | PrathamOne Academy OS v1.0 |
| **Laws in Force** | 59 Locked Laws + 22 Pending Laws (GAP-1 through GAP-6) |
| **Pilot Lead (Institution)** | _(name + role)_ |
| **Pilot Lead (PrathamOne)** | _(name + role)_ |

---

## Section 1: Pre-Activation Baseline (Phase A)

### 1.1 Production Environment Audit Results (Point 1)

> **Record Here:** Copy output from `db/21_phase_a_onboarding_readiness.sql` Point 1.

| Check | Result | Notes |
|-------|--------|-------|
| RLS enforced on all tenant tables | ✓ PASS / ✗ FAIL | # tables verified: ___ |
| Hash-chain trigger ACTIVE | ✓ PASS / ✗ FAIL | Trigger name confirmed: ___ |
| INSERT-ONLY guards ACTIVE | ✓ PASS / ✗ FAIL | Tables verified: ___ |
| pgcrypto extension installed | ✓ PASS / ✗ FAIL | — |
| SSL/TLS enabled | ✓ PASS / ✗ FAIL | ssl setting: ___ |

**Phase A Point 1 Overall Result:** ✓ PASS / ✗ FAIL  
**Signed off by (Platform Ops):** ___________________________

---

### 1.2 Shard Allocation Results (Point 2)

> **Record Here:** Copy output from `db/21_phase_a_onboarding_readiness.sql` Point 2.

| Metric | Value |
|--------|-------|
| Shard ID allocated | _(e.g. shard-IN-MUM-pilot-01)_ |
| Blast Radius Score | _(must be < 7.0)_ |
| API Quota (calls/min) | _(e.g. 1,000)_ |
| Write Quota (writes/min) | _(e.g. 100)_ |
| Contracted Tier | _(STARTER / PRO / ENTERPRISE)_ |
| Mega-tenant imbalance detected? | YES / NO |

**Phase A Point 2 Overall Result:** ✓ PASS / ✗ FAIL  

---

### 1.3 Tenant Provisioning Guard Results (Point 3)

> **Record Here:** Copy output from `db/21_phase_a_onboarding_readiness.sql` Point 3.

| Check | Result |
|-------|--------|
| data_residency_region set at creation | ✓ / ✗ |
| Region value and format valid | ✓ / ✗ — Value: ___ |
| Immutability trigger blocked UPDATE | ✓ / ✗ |
| TENANT_CREATED event in audit log | ✓ / ✗ |

**Phase A Point 3 Overall Result:** ✓ PASS / ✗ FAIL  

---

## Section 2: Governance Drill Results (Phase C)

### 2.1 Tenant Isolation Drill (Drill 11)

> Record the exact row counts from the cross-tenant read attempt.

| Query | Result |
|-------|--------|
| entity_records rows visible under attacker tenant_id | ___ (expected: 0) |
| audit_event_log rows visible under attacker tenant_id | ___ (expected: 0) |
| RLS enforcement verdict | **HERMETICALLY SEALED** / **BREACH DETECTED** |

**Drill 11 Result:** ✓ PASS / ✗ CRITICAL BREACH  
**Zero cross-tenant data leaks confirmed:** YES / NO  

> If breach detected: **DO NOT PROCEED.** Halt onboarding and escalate immediately.

---

### 2.2 Hash-Chain Validation (Drill 12)

> This is your most important proof-of-integrity data point.

| Metric | Value |
|--------|-------|
| Total audit events scanned | ___ |
| Events with INTACT hash | ___ |
| Events with TAMPERED hash | ___ (expected: 0) |
| Genesis blocks (previous_hash IS NULL) | ___ (expected: 1) |
| Validation timestamp | ___ |

**Drill 12 Result:** ✓ 100% INTACT / ✗ TAMPERING DETECTED  

> **For regulators:** This table proves that as of the above timestamp, every audit record in the system is cryptographically verified and unmodified.

---

### 2.3 Financial Integrity Drill (Drill 13)

| Check | Result |
|-------|--------|
| Payment event written as additive audit entry | ✓ / ✗ |
| Refund event written as SEPARATE additive entry | ✓ / ✗ |
| Zero UPDATE statements on any ledger row | ✓ / ✗ |
| api_quota_ledger INSERT-ONLY guard active | ✓ / ✗ |

**Drill 13 Result:** ✓ PASS / ✗ FAIL  
**Financial Additive Principle confirmed:** YES / NO  

---

### 2.4 Exam Lifecycle & AI Advisory Bounds (Drill 14)

| Check | Result |
|-------|--------|
| LAW 10: No score/grade/rank column exists in domain tables | ✓ / ✗ |
| Exam events: SCHEDULED → ACTIVE → COMPLETED in audit chain | ✓ / ✗ |
| AI task created with advisory_only = true | ✓ / ✗ |
| AI task state = QUEUED (not autonomous execution) | ✓ / ✗ |
| Zero AI-generated scores written to any column | ✓ / ✗ |

**Drill 14 Result:** ✓ PASS / ✗ FAIL  

---

## Section 3: Institutional Configuration Summary (Phase B)

> Fill during Phase B execution (Points 4–9).

| Configuration Item | Status | Details |
|-------------------|--------|---------|
| Entity master populated (Sections, Subjects, Batches) | ✓ / ⏳ | Entity count: ___ |
| Role codes mapped to workflow transitions | ✓ / ⏳ | Roles: ___ |
| Admission workflow activated | ✓ / ⏳ | Workflow ID: ___ |
| Fee collection workflow activated | ✓ / ⏳ | Workflow ID: ___ |
| Exam lifecycle workflow activated | ✓ / ⏳ | Workflow ID: ___ |
| Age eligibility policy configured | ✓ / ⏳ | Min age: ___ |
| Entrance score minimum configured | ✓ / ⏳ | Threshold: ___ |
| Seat capacity limit configured | ✓ / ⏳ | Per class: ___ |
| System settings seeded (school name, year, board) | ✓ / ⏳ | Academic year: ___ |
| AI model registered (if applicable) | ✓ / N/A | Model code: ___ |

---

## Section 4: Data Migration Summary (Point 10)

> Only applicable if institution has legacy data to migrate.

| Metric | Value |
|--------|-------|
| Legacy records to migrate | ___ |
| Records migrated via `create_entity_record()` | ___ |
| Records migrated via direct DB INSERT | ___ **(must be 0)** |
| Migration audit events in `audit_event_log` | ___ |
| Migration hash-chain verified post-migration | ✓ INTACT / ✗ FAIL |
| Data migration completion timestamp | ___ |

---

## Section 5: Key Proof Statistics (For Board & Regulator Presentation)

> This section is the institutional proof asset. Populate from the drill results above.

```
╔════════════════════════════════════════════════════════════════╗
║       PRATHAMONE ACADEMY OS — PILOT INTEGRITY CERTIFICATE      ║
╠════════════════════════════════════════════════════════════════╣
║  Institution        : ________________________________         ║
║  Tenant ID          : ________________________________         ║
║  Pilot Period       : ________________ to ________________     ║
╠════════════════════════════════════════════════════════════════╣
║  ✓ Cross-tenant data leaks detected       : 0                  ║
║  ✓ Audit events with hash tampering       : 0                  ║
║  ✓ Financial ledger UPDATE statements     : 0                  ║
║  ✓ LAW 10 score-column violations         : 0                  ║
║  ✓ AI advisory_only enforcement           : CONFIRMED          ║
║  ✓ Total audit events verified (SHA-256)  : ___                ║
║  ✓ Audit chain genesis blocks             : 1                  ║
╠════════════════════════════════════════════════════════════════╣
║  Platform Operations Lead  : ____________________________      ║
║  Institution Admin Lead    : ____________________________      ║
║  Date of Certification     : ____________________________      ║
╚════════════════════════════════════════════════════════════════╝
```

---

## Section 6: Issues & Resolutions Log

> Document every issue encountered during the pilot, even if resolved. This becomes the risk register for future pilots.

| # | Date | Description | Root Cause | Resolution | Prevented Recurrence? |
|---|------|-------------|------------|------------|----------------------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

---

## Section 7: Institutional Admin Sign-Off (Point 15)

| Role | Name | Signature | Date |
|------|------|-----------|------|
| School Principal | | | |
| Administrative Head | | | |
| IT Coordinator | | | |

**Training completion confirmed:** YES / NO  
**Quick Reference Cards distributed:** YES / NO  
**Escalation contact details provided:** YES / NO  

---

## Appendix: Raw Drill Output

> Paste the complete terminal output from `db/21_phase_a_onboarding_readiness.sql` and `db/22_phase_c_governance_drills.sql` here. This raw output, combined with the integrity certificate above, constitutes the full institutional proof package.

```
[PASTE DRILL OUTPUT HERE]
```
