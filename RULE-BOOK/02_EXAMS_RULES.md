# RULE-BOOK/02: EXAMS RULES

## Domain: Marks & Grading Derivation

**LAW 2.1:** **No marks, ranks, or grades are ever stored as facts.** They must be views derived at runtime from the raw `EXAM_SCORE_COMPONENT` records.
**LAW 2.2:** Results cannot be published to the student portal unless the exam workflow is in the **`EVALUATION_LOCKED`** state.
**LAW 2.3:** Moderators can only adjust scores via **`SCORE_ADJUSTMENT`** records. Overwriting the original score component is a LAW 8 violation.
**LAW 2.4:** Exam schedules must be immutable. Changes to exam dates require a new `EXAM_SESSION` record with a cross-reference to the cancelled one.

---
© 2026 PrathamOne Academy OS.
