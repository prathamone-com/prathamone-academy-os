# RULE-BOOK/03: FEES & FINANCE RULES

## Domain: Irreversible Ledger & GST Laws

**LAW 3.1:** Financial truth is **additive**. No financial amount is ever overwritten. 
**LAW 3.2:** **Balances must NEVER be stored as mutable columns.** They must be derived at runtime from the append-only ledger (`FINANCE_LEDGER`).
**LAW 3.3:** Refunds and waivers require separate, auditable adjustment records linked to the original transaction.
**LAW 3.4:** GST and other statutory taxes must be calculated at the point of invoice generation and stored as immutable rows. No retrospective tax adjustments.

---
© 2026 PrathamOne Academy OS.
