# PrathamOne Academy OS
## Second Pilot & 1→10 Institution Acceleration Strategy
### 90-Day Expansion Plan Without Eroding Kernel Doctrine

**Status:** To be activated after Pilot 1 Integrity Certificate is signed.  
**Owner:** Platform Operations Lead + Sovereign Architect  
**Constraint:** Every new institution MUST complete the 15-Point Onboarding Checklist.  
**Non-negotiable:** Kernel laws (LAW 1–12) and the 22 GAP laws are LOCKED. No institution customisation may bypass them.

---

## The Prime Directive for Expansion

> **A faster onboarding that bypasses any of the 15 points is not faster — it is a liability.**  
> One audit chain failure at institution #3 will destroy trust at institutions #1, #2, and every future one.

The goal of this strategy is to **reduce the time-per-institution from 5 days → 1 day** by automating the repeatable parts of the checklist while keeping human sign-off on the irreducible parts (governance training, residency region, shard allocation).

---

## Days 1–30: Automating the Repeatable Checklist Steps

### What Can Be Automated (Safe to Templatise)

| Onboarding Point | Current Time | Automation Target | Method |
|-----------------|-------------|------------------|--------|
| Point 1 — Production Env Audit | 2 hours | 5 minutes | Run `21_phase_a_onboarding_readiness.sql` as part of CI/CD pipeline gate |
| Point 4 — Academic Structure | 3 hours | 20 minutes | Parameterised seed template per board type (CBSE / ICSE / IB / State) |
| Point 5 — Role Mapping | 2 hours | 10 minutes | Pre-built role→workflow mapping templates per institution tier |
| Point 6 — Workflow Activation | 1 hour | 5 minutes | Feature-flag toggle in ASC; no SQL needed |
| Point 7 — Policy Config | 2 hours | 15 minutes | Policy presets: `CBSE_DEFAULT`, `IB_DEFAULT`, `STATE_BOARD_DEFAULT` |
| Point 8 — System Settings | 1 hour | 5 minutes | Settings template JSON per tier, applied via ASC bulk import |
| Point 12 — Hash-Chain Validation | 30 min | 2 minutes | `22_phase_c_governance_drills.sql` runs as automated post-provisioning test |

**Target: Points 1, 4, 5, 6, 7, 8, 12 automated → 3 days saved per institution.**

### What Must Remain Manual (Human Judgement Required)

| Point | Why It Cannot Be Automated |
|-------|---------------------------|
| Point 3 — Tenant Provisioning (residency region) | GAP-6: `data_residency_region` is immutable. A human must set the correct region. One wrong automation = permanent incorrect residency. |
| Point 2 — Shard Allocation | Blast Radius Score requires human review of anticipated usage patterns. No algorithm can accurately predict institutional traffic at onboarding time. |
| Point 11 — Tenant Isolation Drill | A human must read and certify the 0-row result. Automated pass/fail is insufficient for regulatory purposes. |
| Point 13 — Financial Integrity | Test payment requires a human to verify the additive principle was upheld in the live environment. |
| Point 15 — Governance Training | Cannot be automated. This is a human-to-human knowledge transfer. |

### Deliverables for Days 1–30

- [ ] **Onboarding Automation Scripts** — parameterised versions of Points 1, 4–8, 12
- [ ] **Board-Specific Policy Presets** — `CBSE_DEFAULT.json`, `ICSE_DEFAULT.json`, `IB_DEFAULT.json`
- [ ] **ASC Bulk Settings Import** — single JSON payload per institution tier
- [ ] **Automated Drill Runner** — CI/CD step that runs Phase A + Phase C drills and emails results

---

## Days 31–60: Shard Federation & Multi-Tenant Architecture

### The Mega-Tenant Problem

As institutions grow in user count, a single shared shard will approach capacity. The GAP-4 circuit breaker fires at 40% shard utilisation (`fn_check_circuit_breaker()`). With 10 institutions on one shard, a single large institution can throttle all others.

### Solution: Two-Tier Shard Architecture

```
Tier 1 Shards (Shared)          Tier 2 Shards (Dedicated)
──────────────────────          ─────────────────────────
• Institutions < 500 users      • Institutions > 500 users
• Quota: 1,000 API calls/min    • Quota: 10,000 API calls/min
• Cost: shared infrastructure   • Cost: dedicated infrastructure
• Max 5 tenants per shard       • 1 tenant per shard
• Blast Radius Score: < 4.0    • Blast Radius Score: < 7.0
```

### Shard Naming Convention

```
shard-{REGION}-{TIER}-{SEQUENCE}
Examples:
  shard-IN-MUM-shared-01   (shared, Mumbai, sequence 1)
  shard-IN-MUM-shared-02   (shared, Mumbai, sequence 2)
  shard-IN-MUM-dedicated-01 (dedicated, large institution)
  shard-IN-DEL-shared-01   (Delhi region, shared)
```

### Institution Banding

| Band | Criteria | Shard | Onboarding SLA |
|------|----------|-------|---------------|
| **Seed** | < 200 students | Shared | 3 days |
| **Growth** | 200–1,000 students | Shared | 3 days |
| **Scale** | 1,000–5,000 students | Dedicated | 5 days |
| **Enterprise** | > 5,000 students | Dedicated + replica | 7 days |

### Deliverables for Days 31–60

- [ ] **Shard provisioning runbook** — step-by-step for Platform Ops (no developer required)
- [ ] **Shard capacity dashboard** — live view of `api_quota_ledger` utilisation per shard
- [ ] **Auto-shard-assignment logic** in ASC — recommends shard based on projected student count
- [ ] **Shard migration playbook** — what happens when a Growth institution needs to move to Dedicated

---

## Days 61–90: Doctrine Governance at Scale

### The Core Risk: Drift

As the platform scales to 10 institutions, the risk is **doctrine drift** — well-intentioned customisations that subtly violate a LAW. Examples:
- Institution #7 asks for a direct database export "just once" → LAW 7 violated
- Institution #4's IT team asks for SQL access to "speed up a report" → LAW 9 violated
- Institution #2 requests a "status reset" on a student → LAW 3 violated, LAW 8 compromised

### Doctrine Governance Board

Establish a monthly **Doctrine Review Session** with:
- Sovereign Architect (chair)
- Platform Operations Lead
- One rotating institution representative
- Agenda: review escalation log, approve/reject customisation requests, check for LAW violations

### Doctrine Health Metrics (Automated)

Run the following monthly across all institutions:

```sql
-- Metric 1: Cross-tenant isolation health (should always be 0)
SELECT COUNT(*) FROM security_event_log
WHERE event_type = 'RLS_BREACH_ATTEMPT'
  AND logged_at > now() - interval '30 days';

-- Metric 2: Hash-chain integrity (should always be 100%)
SELECT
    tenant_id,
    COUNT(*) FILTER (WHERE recomputed_hash = current_hash) AS intact,
    COUNT(*) AS total
FROM (
    SELECT tenant_id, current_hash,
        encode(digest(
            COALESCE(previous_hash,'GENESIS')||'|'||log_id::TEXT||'|'||event_data::TEXT||'|'||logged_at::TEXT,
            'sha256'
        ), 'hex') AS recomputed_hash
    FROM audit_event_log
    WHERE logged_at > now() - interval '30 days'
) x GROUP BY tenant_id;

-- Metric 3: Residency violations (should always be 0)
SELECT COUNT(*) FROM residency_violation_log
WHERE detected_at > now() - interval '30 days';

-- Metric 4: Circuit breaker trips (indicator of shard pressure)
SELECT tenant_id, COUNT(*), MAX(detected_at)
FROM circuit_breaker_log
WHERE detected_at > now() - interval '30 days'
GROUP BY tenant_id ORDER BY COUNT(*) DESC;
```

### The 10-Institution Readiness Gate

Before onboarding institution #10, the following must be true:
1. All previous 9 institutions have signed Pilot Integrity Certificates
2. Monthly doctrine health metrics are GREEN (0 breaches, 100% chain integrity) for 3 consecutive months
3. The Shard Federation architecture is fully operational and no shard is above 60% capacity
4. At least one Governance Training refresher has been conducted per institution

---

## 90-Day Milestone Summary

| Day Range | Milestone | Success Criteria |
|-----------|-----------|-----------------|
| Day 1 | Pilot 1 Integrity Certificate signed | All 15 points passed, zero failures |
| Day 10 | Onboarding automation v1 deployed | Points 1, 4–8, 12 run in < 30 minutes |
| Day 20 | Pilot 2 live | Automated steps + manual sign-off done in < 2 days |
| Day 30 | 3 institutions onboarded | All 3 have signed Integrity Certificates |
| Day 45 | Shard Federation operational | Tier 1 + Tier 2 shards allocated correctly |
| Day 60 | 6 institutions onboarded | No shard above 50% capacity |
| Day 75 | Doctrine Review Session #1 | Zero LAW violations reported in escalation log |
| Day 90 | 10 institutions onboarded | 100% chain integrity, 0 cross-tenant leaks, 0 doctrine breaches |

---

## What Success Looks Like at Day 90

```
╔═══════════════════════════════════════════════════════════════╗
║         PRATHAMONE ACADEMY OS — 90-DAY EXPANSION REPORT       ║
╠═══════════════════════════════════════════════════════════════╣
║  Institutions onboarded          : 10                         ║
║  15-Point Checklists completed   : 10 (100%)                  ║
║  Integrity Certificates issued   : 10 (100%)                  ║
║  Cross-tenant data leaks         : 0                          ║
║  Audit chain tamper events       : 0                          ║
║  Doctrine (LAW) violations       : 0                          ║
║  Circuit breaker trips (P1)      : 0                          ║
║  Avg onboarding time (Day 90)    : < 1 day                    ║
╠═══════════════════════════════════════════════════════════════╣
║  These 10 institutions are the reference proof set.           ║
║  Each one is a case study. Each case study is a sales asset.  ║
║  The kernel doctrine has been proven at scale.                ║
╚═══════════════════════════════════════════════════════════════╝
```
