# PrathamOne Academy OS
## Institutional Admin Governance Orientation Guide
### Point 15 — 15-Point Pilot Onboarding Technical Checklist

**Audience:** School Principal, Administrative Head, IT Coordinator  
**Delivery Format:** 3-hour facilitated session (in-person or video call)  
**Mandatory Completion:** Required before any institution staff receive login credentials.  
**Facilitator:** PrathamOne Platform Operations representative  

---

## Why This Session Is Non-Negotiable

PrathamOne Academy OS is not a conventional school management software. It is a **Sovereign Academic Runtime Platform (SARP)** — a system where every decision, every data entry, and every process transition is governed by explicit laws rather than human discretion.

This means:
- The system does exactly what the policies say, not what you expect intuitively
- Manual overrides are **architecturally impossible**, not merely restricted
- Every action is permanently recorded in a tamper-proof audit chain

Misunderstanding any of the above **will cause staff frustration, erroneous escalations, and loss of trust** in the platform. This orientation eliminates that risk before it begins.

---

## Module 1: The 12 Governing Laws (30 minutes)

Every operation in PrathamOne is governed by 12 inviolable laws. Admins must understand which ones they encounter daily.

| Law | What It Means to Your Staff |
|-----|-----------------------------|
| **LAW 1** | Every "thing" in the system (student, teacher, course, batch) exists as a registered entity. You cannot invent ad-hoc fields or categories. |
| **LAW 2** | There are no custom columns. Every student attribute (date of birth, category, scores) is a named field in the system's attribute registry. |
| **LAW 3** | **No status can be changed manually.** Every state change is a workflow event. An admission cannot jump from DRAFT to ENROLLED — it must traverse SUBMITTED → VERIFIED → REVIEWED → OFFERED → ENROLLED. |
| **LAW 4** | Policies evaluate BEFORE any state change. If a policy blocks an action (e.g., age eligibility fails), the workflow will not advance regardless of who requests it. This is not a bug. |
| **LAW 5** | System defaults are configured settings, not code. Fee deadlines, seat limits, passing thresholds — all set in the system by your Platform Operations team. |
| **LAW 6** | All your institution's data is scoped exclusively to your tenant. No other institution can see your data, and you cannot see theirs. |
| **LAW 7** | Your identity and institution context are injected at the server level. The frontend never controls data boundaries. |
| **LAW 8** | Every action ever taken is permanently recorded. Records **cannot be deleted, modified, or hidden.** This is the system's most important guarantee for regulators. |
| **LAW 9** | Reports are computed from data at query time. They reflect reality as it exists, not as it was saved to a report table. |
| **LAW 10** | No grades, ranks, or pass/fail results are ever "stored." They are derived on-demand from raw data. This ensures assessment integrity. |
| **LAW 11** | Adding a new academic process means adding configuration rows, not new tables or modules. The platform expands via data, not code changes. |
| **LAW 12** | The kernel (the core engine) is sealed. All academic features are configuration. This protects your institution from undocumented platform changes. |

---

## Module 2: How Workflows Actually Work (45 minutes)

### The Core Concept: State Machines, Not Status Dropdowns

In most school software, a staff member opens a student record and changes "Status" from a dropdown. In PrathamOne, **this is not possible**. Status is the output of a workflow, not an input.

**Example: Admission Process**

```
DRAFT → SUBMITTED → DOCUMENT_VERIFIED → ENTRANCE_SCHEDULED
      → ENTRANCE_COMPLETED → SELECTION_REVIEW → OFFER_ISSUED
      → FEE_PAID → ENROLLED
```

Each arrow is a **transition event** that can only be triggered by the correct role at the correct time.

### What Staff Experience

| Scenario | What Happens | Why |
|----------|-------------|-----|
| Admission officer tries to skip DOCUMENT_VERIFIED and move directly to OFFER_ISSUED | **System blocks it** with a LAW 3 violation | That transition edge does not exist in the workflow graph |
| Principal tries to approve an application where the entrance score is below the minimum threshold | **System blocks it** with a policy denial | The ENTRANCE_SCORE_MINIMUM policy evaluated BEFORE the transition and returned `deny` |
| Staff member tries to DELETE a rejected application | **System blocks it permanently** | LAW 8: all records are soft-deleted (flagged, not removed); the audit record remains forever |
| Student is marked ENROLLED and fee is then found to be miscalculated | **A correction event is raised** — not an edit | A FEE_ADJUSTMENT_ISSUED event is appended to the audit chain; the original is never changed |

### How to Handle Escalations

When a legitimate business need conflicts with a workflow guard:
1. Do **not** attempt to work around the system (no direct database changes)
2. Raise an **Escalation Request** to your Platform Operations contact
3. The Platform Operations team evaluates whether a Policy adjustment is needed
4. If approved, the policy `rule_definition` is updated via the Admin Sovereign Console
5. The change is logged, version-tracked, and takes effect on the next evaluation cycle

---

## Module 3: The Audit Trail — Your Strongest Asset (30 minutes)

### What Is It?

Every action in PrathamOne — every login, data entry, workflow transition, policy evaluation, and fee transaction — is appended to an **immutable, cryptographically chained audit log**. Each entry includes:
- **Who** did it (actor UUID and role)
- **What** happened (event type and payload)
- **When** it happened (timestamp)
- **A SHA-256 hash** linking it to every entry before and after it

### Why Regulators Love This

If a regulator, auditor, or legal counsel asks:
> *"Show me every action taken on this student's application from submission to enrollment."*

You run a single query. Every transition, every document verification, every committee decision — displayed in chronological order with cryptographic proof that nothing was altered.

### How to Read an Audit Replay (Live Demo)

```sql
-- Replace <record_id> with the student application UUID
SET app.tenant_id = '<your_tenant_id>';
SELECT
    tenant_sequence_number      AS "Seq#",
    event_type                  AS "Action",
    event_data->>'from_state'   AS "From",
    event_data->>'to_state'     AS "To",
    logged_at                   AS "When"
FROM audit_event_log
WHERE record_id = '<record_id>'
ORDER BY tenant_sequence_number;
```

> **Key message for admins:** If a staff member ever claims they "accidentally" changed something — the audit chain shows exactly what happened, when, and under which login. There is no ambiguity.

---

## Module 4: What Admins Can and Cannot Do (30 minutes)

### ✅ What Your Admin Console Lets You Do
- View and configure system settings (fee amounts, seat caps, academic year)
- Activate or deactivate workflow states for seasonal processes
- Run reports (all declarative — no raw SQL)
- Onboard new staff and assign roles
- View the audit replay for any student record
- Configure policy thresholds (within approved bounds)

### 🚫 What Is Architecturally Impossible (Not Just Restricted)
| Action | Why It Cannot Happen |
|--------|---------------------|
| Delete an audit log entry | LAW 8: INSERT-ONLY. The database trigger raises an exception. |
| Edit a student's date of birth after submission | All edits produce a versioned `ENTITY_RECORD_UPDATED` event — the old value is preserved forever in `entity_attribute_value_history` |
| Change an admission's state to ENROLLED directly | LAW 3: The transition edge does not exist in the graph |
| Change your institution's data region | LAW 09-6.1 (GAP-6): `data_residency_region` is immutable from creation |
| Add a custom column to a student table | LAW 2: All variable fields go through the attribute registry |
| Run arbitrary SQL queries | No direct DB access is granted; all data access is via API or the Admin Sovereign Console |

---

## Module 5: Emergency & Escalation Protocols (20 minutes)

### When to Escalate to Platform Operations
- A legitimate workflow transition is blocked and you believe the business case is valid
- A policy is producing unexpected results across multiple records
- A staff member reports that data "looks wrong" or is missing from a report
- A suspicious activity alert appears in the security dashboard

### What Escalation Is NOT
- Not a path to bypassing laws
- Not a request to directly edit database records
- Not a workaround for a policy you find inconvenient

### The Break-Glass Protocol (Extreme Scenarios Only)
In the event of a catastrophic system error affecting the audit hash chain (e.g., data centre failover affecting audit integrity), PrathamOne's Break-Glass Protocol requires a **3-of-3 quorum of Sovereign Admins** to authorise any recovery action. Your institution cannot initiate this — it is handled exclusively by PrathamOne's Kernel Engineering team.

---

## Module 6: Quick Reference Card (Distribute to All Staff)

> Print and post at each workstation.

```
┌─────────────────────────────────────────────────────┐
│       PRATHAMONE ACADEMY OS — STAFF QUICK REFERENCE  │
├─────────────────────────────────────────────────────┤
│ ✓ DO: Use the Admin Console for all data operations  │
│ ✓ DO: Follow the workflow — each step exists for a  │
│       reason (policy or audit requirement)           │
│ ✓ DO: Escalate to Platform Ops if a workflow blocks │
│       a legitimate action                            │
│ ✓ DO: Use audit replay to investigate disputes      │
├─────────────────────────────────────────────────────┤
│ ✗ DON'T: Ask for direct database access             │
│ ✗ DON'T: Try to skip workflow steps — it won't work │
│ ✗ DON'T: Assume a "missing" record was deleted —   │
│          it is soft-deleted and fully auditable      │
│ ✗ DON'T: Share login credentials — every action is │
│          attributed to the actor UUID               │
└─────────────────────────────────────────────────────┘
```

---

## Completion Checklist (Facilitator Signs Off)

- [ ] Principal/Admin Head confirmed they understand LAW 3 (no manual status changes)
- [ ] Admin Head demonstrated a live audit replay query
- [ ] IT Coordinator confirmed no direct DB access will be requested
- [ ] All staff received the Quick Reference Card
- [ ] Escalation contact (Platform Operations) details distributed
- [ ] Training completion logged in the institution's onboarding record

**Facilitator signature:** ___________________________  
**Date of training:** ___________________________  
**Institution name:** ___________________________  
**Pilot Tenant ID:** ___________________________  
