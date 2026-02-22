# RULE-BOOK: 07_UI_METADATA_RULES.md (LOCKED)

## 1. Structural Attribute Rules (The Data Kernel)
- **LAW UI-1: The "No Custom Column" Law:** All data fields MUST be registered in `attribute_master`. Creating physical columns in entity tables is strictly forbidden (LAW 2/11).
- **LAW UI-2: Mandatory Technical Codes:** Use immutable technical codes (e.g., `guardian_name`) for internal logic. Appearance is handled by the Label Layer.
- **LAW UI-3: Strict Type Enforcement:** Kernel must reject data not conforming to defined `data_type`.
- **LAW UI-4: Validation Gating:** Constraints (`is_required`, `is_unique`) are enforced by the kernel at the metadata level.

## 2. Label Management Rules (The Display Layer)
- **LAW UI-5: Label Decoupling:** UI is forbidden from using `attribute_codes` as labels. All user-facing text must be resolved from `display_label` in `form_fields`.
- **LAW UI-6: Institutional Sovereignty:** Labels must be tenant-aware. Tenant A and Tenant B may have different labels for the same technical attribute.
- **LAW UI-7: Zero Hardcoded Strings:** Frontend must be a projection of metadata. No labels/button text hardcoded in code; must be fetched from `form_fields` or `workflow_transitions`.
- **LAW UI-8: Action Labeling:** Button text for state changes MUST be managed via `action_label` in the workflow engine.

## 3. Visibility and Rendering Rules
- **LAW UI-9: Conditional Visibility:** Rendering must be governed by `field_visibility_rules` using `condition_expr`.
- **LAW UI-10: Role-Bound Filtering:** Reporting and Form engines must exclude attributes the user's role has no permission to see.
- **LAW UI-11: Implicit Resolution:** UI must never pass `tenant_id`. Kernel resolves institutional labels via signed JWT (LAW 7).

## 4. Governance and Audit Rules
- **LAW UI-12: Centralized Modification:** Labels/Attributes only modified via **Admin Sovereign Console (ASC)**.
- **LAW UI-13: Mandatory Forensic Audit:** Every change generates an `audit_event_log` entry with BEFORE/AFTER snapshots.
- **LAW UI-14: Impact Simulation:** Admin updates require a simulation showing effects on forms and reports before commit.

---
© 2026 PrathamOne Academy OS.
