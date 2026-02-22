# RULE-BOOK: 05_STUDYBUDDY_AI_RULES.md (LOCKED)

## 1. Structural Governance (Kernel Binding)
- **LAW SB-1: Registry & Capability Binding:** Explicitly register in `ai_model_registry` with `model_type = 'LOCAL'` and `ai_capability_master` with decision scope **ASSISTIVE**. (Codes: `STUDENT_STUDY_BUDDY` or `STUDENT_DOUBT_SOLVER`).
- **LAW SB-2: Role-Bound Access:** Strictly restricted via `ai_role_access`. **STUDENT** role is granted `INTERACT` level only. Forbidden from `DECISION_SUPPORT`.
- **LAW SB-3: No Direct Mutation (LAW 13):** Advisor, not an authority. Strictly forbidden from committing database mutations (e.g., marks, attendance). Suggested actions require human/kernel execution.

## 2. Sovereignty and Privacy Rules
- **LAW SB-4: "Local-Only" Enforcement:** If `local_only_mode = TRUE` in `ai_tenant_settings`, the engine must block all cloud AI API calls at the kernel layer.
- **LAW SB-5: Training Isolation:** Tenant academic data/conversations must never be used to train/fine-tune models for other institutions.
- **LAW SB-6: Implicit Tenant Context (LAW 7):** Interface forbidden from passing `tenant_id`. Context must resolve via signed user token/JWT.

## 3. Forensic and Safety Rules
- **LAW SB-7: Mandatory Forensic Logging (LAW 8):** Every interaction must generate a record in `ai_execution_log`.
- **LAW SB-8: Cryptographic Integrity:** Capture `input_hash` and `output_hash`. Linking to the per-tenant cryptographic hash chain is mandatory.
- **LAW SB-9: Model Versioning:** Log exact `model_version` and `confidence_score` for every academic response.
- **LAW SB-10: Confidence Gating:** Responses below the `confidence_threshold` must be flagged as uncertain or blocked to prevent hallucinations.

## 4. Operational Guardrails
- **LAW SB-11: Sandboxed Execution:** Run in isolated container/sandbox. Zero direct DML (INSERT/UPDATE/DELETE) privileges on the primary database.
- **LAW SB-12: Preference Boundaries:** Student preferences (`ai_user_preferences`) must never override institutional policies or grading thresholds.

---
© 2026 PrathamOne Academy OS.
