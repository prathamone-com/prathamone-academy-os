# RULE-BOOK/01: ADMISSIONS RULES

## Domain: Student Lifecycle & Registration

**LAW 1.1:** No student is "active" unless their **`STUDENT_APPLICATION`** record has successfully traversed to the `FINAL_ADMISSION` state.
**LAW 1.2:** Every student must be linked to a **`BATCH`** node at the time of admission. No "batchless" students allowed in the system.
**LAW 1.3:** Student profile data is purely EAV. No core schema changes allowed for adding custom fields (e.g., Blood Group, Passport No). Register them in `attribute_master`.
**LAW 1.4:** Guardian consent is a mandatory file node link for all students under 18.

---
© 2026 PrathamOne Academy OS.
