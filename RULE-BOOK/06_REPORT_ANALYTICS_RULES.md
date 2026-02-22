# RULE-BOOK/06: REPORT & ANALYTICS RULES

## Domain: Declarative Extraction & Visualization

**LAW 6.1:** **If a report requires a custom SQL join written by a developer, the architecture has failed.** 
**LAW 6.2:** Reports must be purely **declarative metadata** stored in `report_master`.
**LAW 6.3:** Data extraction for reports must respect **Temporal Isolation**. Reports cannot query "future" records (logged_at > now()).
**LAW 6.4:** No raw PII (Personally Identifiable Information) in reports unless the user role possesses the `FORENSIC_PII_VIEWER` permission.

---
© 2026 PrathamOne Academy OS.
