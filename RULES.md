# PRATHAMONE ACADEMY OS — AGENT RULES (LOCKED)
## These laws are NON-NEGOTIABLE. Every agent task must comply.


LAW 1: No entity exists unless registered in entity_master.
LAW 2: No custom columns in entity tables. All fields go to attribute_master.
LAW 3: No if(status == ...) in code. Use workflow_transitions table.
LAW 4: Policies evaluate BEFORE workflow transitions. Policies win.
LAW 5: Policies decide IF. Workflows decide WHEN. Settings decide DEFAULT.
LAW 6: Every table MUST include tenant_id (FK). No exceptions.
LAW 7: Tenant context is implicit. Frontend NEVER passes tenant_id.
LAW 8: Audit tables are INSERT-ONLY. No UPDATE. No DELETE. Ever.
LAW 9: Reports are declarative metadata. No raw SQL in feature code.
LAW 10: No rank, grade, pass/fail stored. Always derived at runtime.
LAW 11: No new module requires a new database table.
LAW 12: The kernel is locked. Features are data. The OS is truth.


TECH STACK: PostgreSQL + FastAPI (Python) + React + Google Cloud Run
DATABASE: Always use composite primary keys (tenant_id, record_id).
SECURITY: Row-Level Security (RLS) is mandatory on all tenant tables.
AI MODEL: Use Gemini 3 Pro for architecture tasks. Claude for complex logic.
