# RULE-BOOK: 08_SOVEREIGN_RULE_MATRIX.md — THE SOVEREIGN RULE MATRIX
**Classification:** LOCKED (Audit Output v1.0 — Generated 2026-02-22)**
**Produced by:** Chief Kernel Guardian & Architectural Auditor (3-Phase Audit)
**Architect:** Jawahar R Mallah — PrathamOne Academy OS

> [!IMPORTANT]
> This document is a comprehensive, machine-verifiable catalog of all Locked Laws
> across every layer of the Sovereign Academic Runtime Platform (SARP).
> It is a primary compliance artifact. No law may be silently removed.
> Additions require a formal Amendment with version bump.

---

## LAYER MAP — THE SARP ARCHITECTURE

| Layer | Name | Primary Kernel | Status |
|-------|------|----------------|--------|
| L-0 | Infrastructure & Auth | Auth Gateway | LOCKED |
| L-1 | Tenant Isolation | RLS + Session Context | LOCKED |
| L-2 | EAV Metadata Kernel | `entity_master` / `attribute_master` | LOCKED |
| L-3 | Policy Engine | `policy_master` | LOCKED |
| L-4 | Workflow Engine | `workflow_transitions` | LOCKED |
| L-5 | Admissions Module | Student Lifecycle State Machine | LOCKED |
| L-6 | Exams & Grading Module | Score Component Derivation | LOCKED |
| L-7 | Financial Ledger | `FINANCE_LEDGER` (append-only) | LOCKED |
| L-8 | Library & Asset Module | License + Session Manager | LOCKED |
| L-9 | Forensic Audit Spine | `audit_event_log` (hash-chained) | LOCKED |
| L-10 | Reporting Engine | Declarative `report_master` | LOCKED |
| L-11 | AI Governance Layer | `ai_model_registry` / Sandboxed | LOCKED |
| L-12 | UI Projection Layer | Metadata-Driven Frontend | LOCKED |

---

## PART I — CORE CONSTITUTION LAWS (KMC v1.0)

*Source: `00_CORE_CONSTITUTION.md`*

| Law ID | Law Name | Enforcement Point | Verification Criterion |
|--------|----------|-------------------|------------------------|
| **L2-LAW-1** | Metadata Supremacy | L-2 EAV Kernel | Zero physical feature-columns exist. All fields in `attribute_master`. |
| **L1-LAW-2** | Tenant Sovereignty & Isolation | L-0/L-1 | `tenant_id` never in client request. Derived from JWT → DB session RLS only. |
| **L4-LAW-3** | Workflow & State Integrity | L-4 Workflow Engine | No `if (status==...)` logic in Python/JS. All transitions via `workflow_transitions`. |
| **L3-LAW-4** | Policy & Decision Precedence | L-3 Policy Engine | All eligibility rules in `policy_master`. Policies evaluate before transition commits. |
| **L9-LAW-5** | Forensic Audit Spine (Immutability) | L-9 Audit Spine | `audit_event_log` is INSERT-only. No UPDATE/DELETE. SHA-256 hash chain per tenant. |
| **L7-LAW-6** | Financial Integrity (Additive Principle) | L-7 Financial Ledger | No financial amount overwritten. Derived balances only. Additive adjustments. |
| **L12-LAW-7** | UI Projection Doctrine | L-12 UI Layer | Zero decision logic in frontend. UI renders metadata outputs exclusively. |
| **L11-LAW-8** | AI Advisor Status | L-11 AI Governance | AI is advisory only. No direct DB mutations. Human-in-the-loop required. |
| **L0-LAW-9** | KMC Compliance (No Bypass) | L-0 to L-12 (All) | No module bypasses Audit, Policy, Workflow, or Tenant Isolation kernel. |

---

## PART II — DOMAIN MODULE LAWS

### Module 01: Admissions (L-5)
*Source: `01_ADMISSIONS_RULES.md`*

| Law ID | Statement | Enforcement Point |
|--------|-----------|-------------------|
| **LAW 1.1** | No student is "active" without `STUDENT_APPLICATION` reaching `FINAL_ADMISSION` state. | L-4 Workflow Engine + RLS |
| **LAW 1.2** | Every student must link to a `BATCH` node at admission. No batchless students. | L-2 EAV + NOT NULL constraint |
| **LAW 1.3** | Student profile fields are EAV-only. No schema changes for custom fields. | L-2 `attribute_master` |
| **LAW 1.4** | Guardian consent (file node link) is mandatory for all students under age 18. | L-3 Policy Engine + L-9 Audit |

---

### Module 02: Exams & Grading (L-6)
*Source: `02_EXAMS_RULES.md`*

| Law ID | Statement | Enforcement Point |
|--------|-----------|-------------------|
| **LAW 2.1** | Marks, ranks, and grades are NEVER stored as facts. They are runtime-derived views from `EXAM_SCORE_COMPONENT`. | L-6 / L-10 Reporting Engine |
| **LAW 2.2** | Results cannot be published unless exam workflow is in `EVALUATION_LOCKED` state. | L-4 Workflow Engine |
| **LAW 2.3** | Score adjustments only via `SCORE_ADJUSTMENT` records. Overwriting original score = LAW 8 violation. | L-9 Audit + L-7 Additive Principle |
| **LAW 2.4** | Exam schedules are immutable. Changes require a new `EXAM_SESSION` cross-referencing the cancelled one. | L-4 / L-9 Audit |

---

### Module 03: Fees & Finance (L-7)
*Source: `03_FEES_FINANCE_RULES.md`*

| Law ID | Statement | Enforcement Point |
|--------|-----------|-------------------|
| **LAW 3.1** | Financial truth is additive. No financial amount is ever overwritten. | L-7 `FINANCE_LEDGER` (append-only) |
| **LAW 3.2** | Balances NEVER stored as mutable columns. Derived at runtime from ledger. | L-10 Reporting Engine |
| **LAW 3.3** | Refunds and waivers require separate auditable adjustment records linked to original transaction. | L-9 Audit + L-7 |
| **LAW 3.4** | GST/statutory taxes calculated at invoice generation and stored as immutable rows. No retrospective adjustments. | L-7 / L-9 Audit |

---

### Module 04: Library & Asset Management (L-8)
*Source: `04_LIBRARY_RULES.md`*

| Law ID | Statement | Enforcement Point |
|--------|-----------|-------------------|
| **LAW L1** | Digital assets must include `digital_asset_url` and `license_limit` in `attribute_master`. | L-2 EAV Kernel |
| **LAW L2** | No "Available" flag stored. Availability = runtime derivation (`active_sessions < license_limit`). | L-10 Reporting Engine |
| **LAW L3** | Library dashboard components are metadata-driven. No hardcoded Library pages. | L-12 UI Projection |
| **LAW L4** | Role-based filtering is mandatory. Students see only grade-relevant materials. | L-3 Policy + L-12 UI |
| **LAW L5** | Direct file access is forbidden. All digital sessions trigger a `LIBRARY_DIGITAL_ACCESS` record. | L-9 Audit |
| **LAW L6** | Every "Open" click increments the per-tenant hash-chained audit log. | L-9 Audit (hash chain) |
| **LAW L7** | AI library recommendations are ADVISORY only. | L-11 AI Governance |
| **LAW L8** | AI cannot bypass license limits or subject-access policies. | L-3 Policy + L-11 AI |

---

### Module 05: StudyBuddy AI (L-11)
*Source: `05_STUDYBUDDY_AI_RULES.md`*

| Law ID | Statement | Enforcement Point |
|--------|-----------|-------------------|
| **LAW SB-1** | AI must be registered in `ai_model_registry` (`model_type='LOCAL'`) and `ai_capability_master` (`scope=ASSISTIVE`). | L-11 AI Governance |
| **LAW SB-2** | STUDENT role granted `INTERACT` level only. Forbidden from `DECISION_SUPPORT`. | L-3 Policy + L-11 |
| **LAW SB-3** | AI strictly forbidden from DB mutations (marks, attendance). Human execution required. | L-11 + L-9 Audit |
| **LAW SB-4** | If `local_only_mode=TRUE` in `ai_tenant_settings`, all cloud AI calls are blocked at kernel layer. | L-0 Auth Gateway |
| **LAW SB-5** | Tenant academic data must never train/fine-tune models for other institutions. | L-1 Tenant Isolation |
| **LAW SB-6** | AI interface forbidden from passing `tenant_id`. Resolved via signed JWT. | L-0 / L-1 |
| **LAW SB-7** | Every AI interaction generates a record in `ai_execution_log`. | L-9 Audit |
| **LAW SB-8** | `input_hash` and `output_hash` captured. Linked to per-tenant hash chain. | L-9 Audit (hash chain) |
| **LAW SB-9** | `model_version` and `confidence_score` logged for every academic response. | L-11 AI Governance |
| **LAW SB-10** | Responses below `confidence_threshold` flagged as uncertain or blocked. | L-11 AI Governance |
| **LAW SB-11** | AI in isolated container. Zero direct DML privileges on primary database. | L-0 Network Isolation |
| **LAW SB-12** | Student AI preferences must never override institutional policies or grading thresholds. | L-3 Policy Engine |

---

### Module 06: Reporting & Analytics (L-10)
*Source: `06_REPORT_ANALYTICS_RULES.md`*

| Law ID | Statement | Enforcement Point |
|--------|-----------|-------------------|
| **LAW 6.1** | If a report requires a custom developer-written SQL join, the architecture has failed. | L-10 Reporting Engine |
| **LAW 6.2** | Reports are purely declarative metadata in `report_master`. | L-10 + L-2 EAV |
| **LAW 6.3** | Reports respect Temporal Isolation. Cannot query records with `logged_at > now()`. | L-10 Query Engine |
| **LAW 6.4** | No raw PII in reports unless the user role has `FORENSIC_PII_VIEWER` permission. | L-3 Policy + L-1 RLS |

---

### Module 07: UI & Metadata Projection (L-12)
*Source: `07_UI_METADATA_RULES.md`*

| Law ID | Statement | Enforcement Point |
|--------|-----------|-------------------|
| **LAW UI-1** | All data fields registered in `attribute_master`. Physical columns in entity tables forbidden. | L-2 EAV Kernel |
| **LAW UI-2** | Use immutable technical codes for internal logic. Labels handled by Label Layer. | L-12 UI Projection |
| **LAW UI-3** | Kernel must reject data not conforming to defined `data_type`. | L-2 EAV + L-3 Policy |
| **LAW UI-4** | Constraints (`is_required`, `is_unique`) enforced by kernel at metadata level. | L-2 EAV Kernel |
| **LAW UI-5** | UI forbidden from using `attribute_codes` as labels. Resolved from `display_label` in `form_fields`. | L-12 UI Projection |
| **LAW UI-6** | Labels must be tenant-aware (institutional sovereignty). | L-1 Tenant Isolation |
| **LAW UI-7** | Zero hardcoded strings in frontend. Labels fetched from `form_fields` or `workflow_transitions`. | L-12 UI Projection |
| **LAW UI-8** | Button text for state changes managed via `action_label` in workflow engine. | L-4 Workflow + L-12 |
| **LAW UI-9** | Conditional rendering governed by `field_visibility_rules` using `condition_expr`. | L-12 UI Projection |
| **LAW UI-10** | Reporting and Form engines exclude attributes the user's role cannot see. | L-3 Policy + L-10 |
| **LAW UI-11** | UI must never pass `tenant_id`. Resolved via signed JWT. | L-0 / L-1 |
| **LAW UI-12** | Labels/Attributes only modified via Admin Sovereign Console (ASC). | L-12 + L-3 Policy |
| **LAW UI-13** | Every Admin change generates an `audit_event_log` entry with BEFORE/AFTER snapshots. | L-9 Audit |
| **LAW UI-14** | Admin updates require impact simulation on forms and reports before commit. | L-12 / L-3 Policy |

---

## CONSOLIDATED LAW COUNT

| Layer | Domain | Laws Cataloged |
|-------|--------|----------------|
| L-0 to L-4 | Core Constitution (KMC v1.0) | 9 |
| L-5 | Admissions | 4 |
| L-6 | Exams & Grading | 4 |
| L-7 | Financial Ledger | 4 |
| L-8 | Library & Assets | 8 |
| L-11 | AI Governance (StudyBuddy) | 12 |
| L-10 | Reporting & Analytics | 4 |
| L-12 | UI & Metadata Projection | 14 |
| **TOTAL** | **All Domains** | **59 Laws** |

---

*© 2026 PrathamOne Academy OS. All rights reserved.*
*Founder & Technical Architect: Jawahar R Mallah — [aiTDL.com](https://aiTDL.com)*
