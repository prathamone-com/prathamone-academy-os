# PRATHAMONE ACADEMY OS — CORE CONSTITUTION (KMC v1.0)

## These Global Rules are derived from the Kernel-to-Module Contract (KMC v1.0).

### 1. The Metadata Supremacy Law (EAV Model)
*   **No physical tables or columns** may be created for specific features or modules.
*   All data structures must be defined as **entities** in `entity_master` and **attributes** in `attribute_master`.
*   **Rule:** If something is not defined in the metadata kernel, it does not exist in the system.

### 2. Tenant Sovereignty & Isolation Law
*   **Implicit Context:** The system must never accept `tenant_id` from a client request or frontend.
*   **Security Boundary:** Tenant context must be **implicitly derived** from signed auth tokens and injected at the database session level (Row-Level Security).
*   **No Cross-Tenant Joins:** Manual joining or querying across tenants is strictly forbidden to prevent data leakage.

### 3. Workflow & State Integrity Law
*   **Zero Hardcoding:** No `if (status == ...)` or hardcoded state names are allowed in application code (Python/JS).
*   **Engine Enforced:** All state movements must be managed through `workflow_transitions`.
*   **Truth is State:** The UI must query the kernel for allowed actions rather than inferring them from local logic.

### 4. Policy & Decision Precedence Law
*   **Policies Decide "IF":** No business logic or eligibility rules (e.g., age checks, pass thresholds) may be embedded in the code.
*   **Deterministic Evaluation:** All conditional rules must be stored in `policy_master` and evaluated by the kernel before any workflow transition occurs.
*   **Precedence:** Policies **must** evaluate and pass before a workflow transition is committed.

### 5. The Forensic Audit Spine Law
*   **Immutable Ledger:** Every data mutation (Create, Update, Transition) **must** trigger a hash-chained audit event.
*   **Append-Only:** The `audit_event_log` is strictly insert-only; no `UPDATE` or `DELETE` operations are permitted.
*   **Tamper-Resistant:** Each audit entry must be linked to a **per-tenant cryptographic hash chain** to ensure courtroom-grade evidence.

### 6. Financial Integrity Law (The Additive Principle)
*   **No Overwrites:** Financial amounts must **never be overwritten**.
*   **Additive Transactions:** All corrections handled through **additive adjustment entries** (waivers, scholarships) to maintain a complete audit trail.
*   **Derived Balances:** Outstanding amounts calculated at runtime, never stored as a mutable "balance" column.

### 7. UI Projection Doctrine
*   **Metadata Projection:** The frontend is a **projection of metadata**, not a repository of logic.
*   **Zero Decision Logic:** The UI simply renders what the kernel metadata permits; it never evaluates permissions or eligibility locally.

### 8. AI Advisor Status Law
*   **Advisory Only:** AI is an **advisor, not an authority**.
*   **No Direct Mutation:** AI is strictly **prohibited from committing database mutations directly**.
*   **Human-in-the-Loop:** Recommended actions (e.g., grading) must be confirmed by a human authority before saving.

### 9. Kernel-to-Module Contract (KMC) Compliance
*   **No Bypassing:** No module or plugin is permitted to bypass kernel services (Audit, Policy, Workflow, or Tenant Isolation).
*   **Architectural Breach:** Any attempt to create independent business tables or hardcode role checks must be rejected as an **architectural breach**.

---

**Founder & Technical Architect:**
**Jawahar R Mallah**
[https://aiTDL.com](https://aiTDL.com) | [pratham1.com](https://pratham1.com)

© 2026 PrathamOne Academy OS. All rights reserved.