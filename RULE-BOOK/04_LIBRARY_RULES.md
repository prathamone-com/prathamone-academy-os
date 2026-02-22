# RULE-BOOK: 04_LIBRARY_RULES.md (LOCKED)

## 1. DATA INTEGRITY
- **LAW L1:** Digital assets (PDF/eBooks) must include `digital_asset_url` and `license_limit` in `attribute_master`.
- **LAW L2:** No "Available" flag stored. Availability is a runtime derivation: `active_sessions < license_limit`.

## 2. DASHBOARD & UI
- **LAW L3:** Dashboard components must be metadata-driven. No hardcoded Library pages.
- **LAW L4:** Role-based filtering is mandatory. Students see only grade-relevant materials.

## 3. ACCESS & AUDIT
- **LAW L5:** Direct file access is forbidden. All digital sessions must trigger a `LIBRARY_DIGITAL_ACCESS` record.
- **LAW L6:** Every dashboard "Open" click must increment the per-tenant hash-chained audit log.

## 4. AI ADVISORY
- **LAW L7:** AI-driven library recommendations are ADVISORY only.
- **LAW L8:** AI cannot bypass license limits or subject-access policies.

---
© 2026 PrathamOne Academy OS.
