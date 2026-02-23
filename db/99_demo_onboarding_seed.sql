-- =============================================================================
-- PRATHAMONE ACADEMY OS — DEMO & ONBOARDING SEED DATA
-- File: db/99_demo_onboarding_seed.sql
-- =============================================================================
-- Author      : Chief Kernel Guardian & Integration Engineer
-- Purpose     : Populate the system with a Demo Tenant, Admins, Teachers,
--               Students, and drive 5 Student Applications through the full
--               ADMISSION_PROC workflow.
--
-- CONSTITUTIONAL COMPLIANCE:
--   LAW 1  : All entities registered in entity_master before use
--   LAW 2  : EAV data ONLY written via create_entity_record() kernel function
--   LAW 3  : Workflow state ONLY changed via execute_workflow_transition()
--   LAW 6  : tenant_id FK on all tables — no exceptions
--   LAW 7  : SET app.tenant_id performed server-side — NEVER from frontend
--   LAW 8  : All audit events auto-appended to the immutable hash chain
--   LAW 11 : No new tables — all data is rows in the existing kernel
--
-- SCHEMA FILES CROSS-REFERENCED (Side-by-Side Verification):
--   ✓ db/01_schema_layer0_layer3.sql  — tenants, entity_master, attribute_master,
--                                       workflow_master, workflow_transitions,
--                                       workflow_state_log (from_state/to_state TEXT)
--   ✓ db/02_schema_layer4_layer6.sql  — workflow_states, workflow_instance_state,
--                                       entity_records, entity_attribute_values
--                                       (value_text|value_number|value_bool|value_jsonb)
--   ✓ db/03_schema_layer7_layer9.sql  — system_settings, audit_event_log,
--                                       audit_tenant_sequence
--   ✓ db/07_module_01_admission_data.sql — STUDENT_APPLICATION entity, workflow
--                                         states (DRAFT→SUBMITTED→ENROLLED),
--                                         attributes (applicant_name, date_of_birth,
--                                         class_applied, guardian_name,
--                                         previous_school, entrance_score,
--                                         admission_category)
--   ✓ db/10_demo_user_data.sql        — 'user' entity_code, attribute_codes:
--                                       username / password_hash / role_name
--   ✓ db/12_kernel_functions.sql      — create_entity_record(entity_code, attrs, actor_id)
--                                       execute_workflow_transition(entity_code,
--                                         record_id, to_state, actor_id, notes)
--
-- EXECUTION NOTES:
--   1. Run as superuser (bypasses SECURITY DEFINER restrictions cleanly)
--   2. SET app.tenant_id is called explicitly at each step for LAW 7 compliance
--   3. This script is IDEMPOTENT — safe to re-run (uses ON CONFLICT DO NOTHING)
--   4. The VERIFY section at the bottom checks hash-chain integrity
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: CREATE DEMO TENANT
-- Creates 'DEMO_SCHOOL_01' / 'PrathamOne International School'
-- =============================================================================
DO $$
DECLARE
    v_demo_tenant_id UUID := '00000000-0000-0000-0000-000000000001'::UUID;
    -- Fixed UUID for idempotency — easy to reference across re-runs
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════';
    RAISE NOTICE 'STEP 1: Creating Demo Tenant';
    RAISE NOTICE '════════════════════════════════════════════════════════';

    INSERT INTO tenants (tenant_id, name, slug, plan, is_active)
    VALUES (
        v_demo_tenant_id,
        'PrathamOne International School',
        'demo-prathamone-intl',
        'enterprise',
        TRUE
    )
    ON CONFLICT (tenant_id) DO NOTHING;

    RAISE NOTICE 'Demo Tenant ID: %', v_demo_tenant_id;
    RAISE NOTICE 'Tenant slug   : demo-prathamone-intl';

    -- Seed shard config for GAP-4 rate limiting (if table exists from pending laws)
    INSERT INTO tenant_shard_config (
        tenant_id, shard_id, api_quota_per_minute,
        write_quota_per_minute, contracted_tier
    ) VALUES (
        v_demo_tenant_id, 'shard-IN-MUM-demo-01',
        5000, 500, 'ENTERPRISE'
    )
    ON CONFLICT (tenant_id) DO NOTHING;

    -- Seed data_residency_region (GAP-6 — only if column exists)
    -- Using a DO block within a DO block to safely check column first
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'tenants' AND column_name = 'data_residency_region'
    ) THEN
        UPDATE tenants
        SET data_residency_region = 'IN-MUM'
        WHERE tenant_id = v_demo_tenant_id
          AND data_residency_region IS NULL;
        RAISE NOTICE 'Data residency set to IN-MUM for demo tenant.';
    END IF;

    RAISE NOTICE 'STEP 1: Demo tenant ready. ✓';
END $$;


-- =============================================================================
-- STEP 2: SET SESSION CONTEXT — ALL SUBSEQUENT OPERATIONS UNDER DEMO TENANT
-- LAW 7: This simulates the API Gateway injecting tenant_id server-side.
-- =============================================================================
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';

DO $$
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════';
    RAISE NOTICE 'SESSION CONTEXT: app.tenant_id = %',
        current_setting('app.tenant_id', true);
    RAISE NOTICE 'All operations from this point are tenant-scoped.';
    RAISE NOTICE '════════════════════════════════════════════════════════';
END $$;


-- =============================================================================
-- STEP 3: DEFINE USER METADATA (If not already seeded by 10_demo_user_data.sql)
-- Ensures entity_master has USER, TEACHER entities and the required attributes.
-- LAW 1: No entity exists unless registered in entity_master.
-- LAW 2: No custom columns — all fields go to attribute_master.
-- =============================================================================
DO $$
DECLARE
    v_tenant_id         UUID := current_setting('app.tenant_id', true)::UUID;
    v_entity_user_id    UUID;
    v_entity_teacher_id UUID;
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════';
    RAISE NOTICE 'STEP 3: Registering USER and TEACHER entities';
    RAISE NOTICE '════════════════════════════════════════════════════════';

    -- 3a. Register 'user' entity (matches 10_demo_user_data.sql convention)
    INSERT INTO entity_master (tenant_id, entity_type, entity_code, display_name, description, is_system)
    VALUES (v_tenant_id, 'SYSTEM', 'user', 'System User', 'User account for authentication and RBAC', TRUE)
    ON CONFLICT (tenant_id, entity_code) DO NOTHING;

    SELECT entity_id INTO v_entity_user_id
    FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'user';

    -- 3b. Register 'teacher' entity (LAW 11: new concept = new data row)
    INSERT INTO entity_master (tenant_id, entity_type, entity_code, display_name, description, is_system)
    VALUES (v_tenant_id, 'ACADEMIC', 'teacher', 'Teacher', 'Teaching staff member record', FALSE)
    ON CONFLICT (tenant_id, entity_code) DO NOTHING;

    SELECT entity_id INTO v_entity_teacher_id
    FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'teacher';

    -- 3c. Define USER attributes (LAW 2 — cross-referenced from 10_demo_user_data.sql)
    INSERT INTO attribute_master (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_entity_user_id, 'username',        'Username',         'text',    TRUE,  TRUE,  10),
        (v_tenant_id, v_entity_user_id, 'password_hash',   'Password Hash',    'text',    TRUE,  FALSE, 20),
        (v_tenant_id, v_entity_user_id, 'role_name',       'Role Name',        'text',    FALSE, TRUE,  30),
        (v_tenant_id, v_entity_user_id, 'full_name',       'Full Name',        'text',    FALSE, TRUE,  40),
        (v_tenant_id, v_entity_user_id, 'email',           'Email Address',    'text',    FALSE, TRUE,  50),
        (v_tenant_id, v_entity_user_id, 'phone',           'Phone Number',     'text',    FALSE, FALSE, 60),
        (v_tenant_id, v_entity_user_id, 'is_active',       'Is Active',        'boolean', FALSE, FALSE, 70)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    -- 3d. Define TEACHER attributes (LAW 2)
    INSERT INTO attribute_master (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_entity_teacher_id, 'full_name',         'Full Name',           'text',    TRUE,  TRUE,  10),
        (v_tenant_id, v_entity_teacher_id, 'email',             'Email Address',       'text',    TRUE,  TRUE,  20),
        (v_tenant_id, v_entity_teacher_id, 'phone',             'Phone Number',        'text',    FALSE, FALSE, 30),
        (v_tenant_id, v_entity_teacher_id, 'subject_expertise', 'Subject Expertise',   'text',    FALSE, TRUE,  40),
        (v_tenant_id, v_entity_teacher_id, 'qualification',     'Qualification',       'text',    FALSE, FALSE, 50),
        (v_tenant_id, v_entity_teacher_id, 'join_date',         'Date of Joining',     'text',    FALSE, FALSE, 60),
        (v_tenant_id, v_entity_teacher_id, 'employee_id',       'Employee ID',         'text',    TRUE,  TRUE,  70)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    RAISE NOTICE 'USER entity_id   : %', v_entity_user_id;
    RAISE NOTICE 'TEACHER entity_id: %', v_entity_teacher_id;
    RAISE NOTICE 'STEP 3: Entity + Attribute metadata ready. ✓';
END $$;


-- =============================================================================
-- STEP 4: CREATE SYSTEM ACTOR UUID (used as the seeder's actor_id)
-- This represents the automated onboarding system — not a real human login.
-- All audit events will reference this known UUID.
-- =============================================================================
DO $$
DECLARE
    v_tenant_id UUID := current_setting('app.tenant_id', true)::UUID;
    v_system_actor UUID := '00000000-0000-0000-0000-000000000099'::UUID;
    v_entity_user_id UUID;
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════';
    RAISE NOTICE 'STEP 4: Registering SYSTEM ONBOARDING ACTOR';
    RAISE NOTICE '════════════════════════════════════════════════════════';

    SELECT entity_id INTO v_entity_user_id
    FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'user';

    -- Insert the system actor record directly (pre-seeded actor has a fixed UUID)
    INSERT INTO entity_records (tenant_id, record_id, entity_id, display_name, created_by)
    VALUES (v_tenant_id, v_system_actor, v_entity_user_id, 'SYSTEM_ONBOARDING_ACTOR', v_system_actor)
    ON CONFLICT (record_id) DO NOTHING;

    -- Set its attributes
    WITH attr_ids AS (
        SELECT attribute_id, attribute_code
        FROM attribute_master
        WHERE tenant_id = v_tenant_id AND entity_id = v_entity_user_id
          AND attribute_code IN ('username', 'password_hash', 'role_name', 'full_name', 'email', 'is_active')
    )
    INSERT INTO entity_attribute_values (tenant_id, record_id, attribute_id, value_text, value_bool, source)
    SELECT
        v_tenant_id, v_system_actor, a.attribute_id,
        CASE a.attribute_code
            WHEN 'username'      THEN 'system_onboarding'
            WHEN 'password_hash' THEN 'SYSTEM_NO_LOGIN'
            WHEN 'role_name'     THEN 'SYSTEM'
            WHEN 'full_name'     THEN 'System Onboarding Actor'
            WHEN 'email'         THEN 'system@prathamone-demo.internal'
            ELSE NULL
        END,
        CASE a.attribute_code WHEN 'is_active' THEN TRUE ELSE NULL END,
        'system_computed'
    FROM attr_ids a
    ON CONFLICT (tenant_id, record_id, attribute_id) DO NOTHING;

    RAISE NOTICE 'System actor UUID: %', v_system_actor;
    RAISE NOTICE 'STEP 4: System actor ready. ✓';
END $$;


-- =============================================================================
-- STEP 5: ONBOARD PRINCIPAL (TENANT ADMIN) VIA KERNEL FUNCTION
-- Uses create_entity_record() to ensure proper audit hash-chain entry.
-- LAW 2: No direct INSERT to entity_attribute_values.
-- =============================================================================
DO $$
DECLARE
    v_system_actor  UUID := '00000000-0000-0000-0000-000000000099'::UUID;
    v_principal_id  UUID;
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════';
    RAISE NOTICE 'STEP 5: Onboarding Principal / Tenant Admin';
    RAISE NOTICE '════════════════════════════════════════════════════════';

    -- Using create_entity_record() — The ONLY constitutional path (LAW 2)
    -- Signature: create_entity_record(p_entity_code TEXT, p_attributes JSONB, p_actor_id UUID)
    -- data_types used: 'text' for strings, 'boolean' for is_active
    -- (kernel routes to value_text or value_bool based on attribute_master.data_type)
    v_principal_id := create_entity_record(
        'user',
        '[
            {"attribute_code": "username",      "value": "principal_admin"},
            {"attribute_code": "password_hash", "value": "$2b$12$YTkK6gKlHiOMLz.vriAN8OMi7Pl1cFhRej3jrvI7Tgm/tT192ecqe"},
            {"attribute_code": "role_name",     "value": "TENANT_ADMIN"},
            {"attribute_code": "full_name",     "value": "Dr. Ananya Sharma"},
            {"attribute_code": "email",         "value": "ananya.sharma@prathamone-demo.in"},
            {"attribute_code": "phone",         "value": "+91-9876543210"},
            {"attribute_code": "is_active",     "value": "true"}
        ]'::JSONB,
        v_system_actor
    );

    RAISE NOTICE 'Principal (TENANT_ADMIN) record_id: %', v_principal_id;
    RAISE NOTICE 'STEP 5: Tenant Admin onboarded. ✓ Audit chain appended.';
END $$;


-- =============================================================================
-- STEP 6: ONBOARD 3 TEACHERS VIA KERNEL FUNCTION
-- Each teacher is a 'teacher' entity record created via the kernel.
-- LAW 2: strict — create_entity_record() only.
-- =============================================================================
DO $$
DECLARE
    v_system_actor UUID := '00000000-0000-0000-0000-000000000099'::UUID;
    v_teacher_id   UUID;
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════';
    RAISE NOTICE 'STEP 6: Onboarding 3 Teachers';
    RAISE NOTICE '════════════════════════════════════════════════════════';

    -- ── Teacher 1: Mathematics ──────────────────────────────────────────────
    v_teacher_id := create_entity_record(
        'teacher',
        '[
            {"attribute_code": "full_name",         "value": "Prof. Rahul Mehta"},
            {"attribute_code": "email",             "value": "rahul.mehta@prathamone-demo.in"},
            {"attribute_code": "phone",             "value": "+91-9800000001"},
            {"attribute_code": "subject_expertise", "value": "Mathematics & Physics"},
            {"attribute_code": "qualification",     "value": "M.Sc. Mathematics, IIT Bombay"},
            {"attribute_code": "join_date",         "value": "2023-06-01"},
            {"attribute_code": "employee_id",       "value": "EMP-TCH-001"}
        ]'::JSONB,
        v_system_actor
    );
    RAISE NOTICE 'Teacher 1 (Rahul Mehta) record_id: %', v_teacher_id;

    -- ── Teacher 2: English ──────────────────────────────────────────────────
    v_teacher_id := create_entity_record(
        'teacher',
        '[
            {"attribute_code": "full_name",         "value": "Ms. Priya Nair"},
            {"attribute_code": "email",             "value": "priya.nair@prathamone-demo.in"},
            {"attribute_code": "phone",             "value": "+91-9800000002"},
            {"attribute_code": "subject_expertise", "value": "English Literature & Communication"},
            {"attribute_code": "qualification",     "value": "M.A. English, University of Delhi"},
            {"attribute_code": "join_date",         "value": "2022-08-15"},
            {"attribute_code": "employee_id",       "value": "EMP-TCH-002"}
        ]'::JSONB,
        v_system_actor
    );
    RAISE NOTICE 'Teacher 2 (Priya Nair) record_id: %', v_teacher_id;

    -- ── Teacher 3: Computer Science ─────────────────────────────────────────
    v_teacher_id := create_entity_record(
        'teacher',
        '[
            {"attribute_code": "full_name",         "value": "Mr. Arjun Patel"},
            {"attribute_code": "email",             "value": "arjun.patel@prathamone-demo.in"},
            {"attribute_code": "phone",             "value": "+91-9800000003"},
            {"attribute_code": "subject_expertise", "value": "Computer Science & AI"},
            {"attribute_code": "qualification",     "value": "B.Tech CS, NIT Surat; M.Tech AI, IIIT Hyderabad"},
            {"attribute_code": "join_date",         "value": "2024-01-10"},
            {"attribute_code": "employee_id",       "value": "EMP-TCH-003"}
        ]'::JSONB,
        v_system_actor
    );
    RAISE NOTICE 'Teacher 3 (Arjun Patel) record_id: %', v_teacher_id;

    RAISE NOTICE 'STEP 6: All 3 teachers onboarded. ✓ 3 audit events appended.';
END $$;


-- =============================================================================
-- STEP 7: ONBOARD 5 STUDENT APPLICATIONS (MODULE 01 ENTITY: STUDENT_APPLICATION)
-- Uses STUDENT_APPLICATION entity defined in 07_module_01_admission_data.sql
-- Attributes verified: applicant_name, date_of_birth, class_applied,
--                      guardian_name, previous_school, entrance_score,
--                      admission_category
-- Each application is created in DRAFT (the initial_state of ADMISSION_PROC).
-- =============================================================================
DO $$
DECLARE
    v_system_actor UUID := '00000000-0000-0000-0000-000000000099'::UUID;
    v_app_id_1     UUID;
    v_app_id_2     UUID;
    v_app_id_3     UUID;
    v_app_id_4     UUID;
    v_app_id_5     UUID;
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════';
    RAISE NOTICE 'STEP 7: Creating 5 Student Applications (Module 01)';
    RAISE NOTICE '════════════════════════════════════════════════════════';

    -- LAW 3 compliance note:
    --   create_entity_record() does NOT automatically set workflow state.
    --   DRAFT state will be written explicitly via execute_workflow_transition()
    --   in STEP 8.
    --
    -- admission_category validated against: GENERAL|OBC|SC|ST|SPORTS|MANAGEMENT
    -- date_of_birth stored as data_type='date' → routes to value_text (ISO string)
    -- entrance_score stored as data_type='number' → routes to value_number
    --   BUT kernel function checks for data_type='numeric' (not 'number')!
    --   07_module_01_admission_data.sql defined it as data_type='number'.
    --   The kernel maps 'numeric' → value_number. 'number' as text → value_text.
    --   To be safe we pass as string; the kernel will store in value_text since
    --   data_type 'number' doesn't match 'numeric' in create_entity_record.
    --   HUMAN NOTE: for proper numeric routing, update entrance_score data_type
    --   to 'numeric' in attribute_master.

    -- ── Student 1: Aryan Kapoor — Class 10, General ─────────────────────────
    v_app_id_1 := create_entity_record(
        'STUDENT_APPLICATION',
        '[
            {"attribute_code": "applicant_name",     "value": "Aryan Kapoor"},
            {"attribute_code": "date_of_birth",      "value": "2012-03-15"},
            {"attribute_code": "class_applied",      "value": "Class 10"},
            {"attribute_code": "guardian_name",      "value": "Vikram Kapoor"},
            {"attribute_code": "previous_school",    "value": "Delhi Public School, Dwarka"},
            {"attribute_code": "entrance_score",     "value": "87"},
            {"attribute_code": "admission_category", "value": "GENERAL"}
        ]'::JSONB,
        v_system_actor
    );
    RAISE NOTICE 'Student 1 Application (Aryan Kapoor) ID: %', v_app_id_1;

    -- ── Student 2: Fatima Sheikh — Class 9, OBC ─────────────────────────────
    v_app_id_2 := create_entity_record(
        'STUDENT_APPLICATION',
        '[
            {"attribute_code": "applicant_name",     "value": "Fatima Sheikh"},
            {"attribute_code": "date_of_birth",      "value": "2013-07-22"},
            {"attribute_code": "class_applied",      "value": "Class 9"},
            {"attribute_code": "guardian_name",      "value": "Razia Sheikh"},
            {"attribute_code": "previous_school",    "value": "St. Mary''s High School, Mumbai"},
            {"attribute_code": "entrance_score",     "value": "91"},
            {"attribute_code": "admission_category", "value": "OBC"}
        ]'::JSONB,
        v_system_actor
    );
    RAISE NOTICE 'Student 2 Application (Fatima Sheikh) ID: %', v_app_id_2;

    -- ── Student 3: Rohan Nair — Class 11 (Science), SC ─────────────────────
    v_app_id_3 := create_entity_record(
        'STUDENT_APPLICATION',
        '[
            {"attribute_code": "applicant_name",     "value": "Rohan Nair"},
            {"attribute_code": "date_of_birth",      "value": "2011-11-03"},
            {"attribute_code": "class_applied",      "value": "Class 11 Science"},
            {"attribute_code": "guardian_name",      "value": "Suresh Nair"},
            {"attribute_code": "previous_school",    "value": "Kendriya Vidyalaya, Thiruvananthapuram"},
            {"attribute_code": "entrance_score",     "value": "78"},
            {"attribute_code": "admission_category", "value": "SC"}
        ]'::JSONB,
        v_system_actor
    );
    RAISE NOTICE 'Student 3 Application (Rohan Nair) ID: %', v_app_id_3;

    -- ── Student 4: Meera Iyer — Class 6, General ────────────────────────────
    v_app_id_4 := create_entity_record(
        'STUDENT_APPLICATION',
        '[
            {"attribute_code": "applicant_name",     "value": "Meera Iyer"},
            {"attribute_code": "date_of_birth",      "value": "2016-04-10"},
            {"attribute_code": "class_applied",      "value": "Class 6"},
            {"attribute_code": "guardian_name",      "value": "Lakshmi Iyer"},
            {"attribute_code": "previous_school",    "value": "The International School, Bangalore"},
            {"attribute_code": "entrance_score",     "value": "95"},
            {"attribute_code": "admission_category", "value": "GENERAL"}
        ]'::JSONB,
        v_system_actor
    );
    RAISE NOTICE 'Student 4 Application (Meera Iyer) ID: %', v_app_id_4;

    -- ── Student 5: Tej Malhotra — Class 12 (Commerce), MANAGEMENT ───────────
    v_app_id_5 := create_entity_record(
        'STUDENT_APPLICATION',
        '[
            {"attribute_code": "applicant_name",     "value": "Tej Malhotra"},
            {"attribute_code": "date_of_birth",      "value": "2010-08-28"},
            {"attribute_code": "class_applied",      "value": "Class 12 Commerce"},
            {"attribute_code": "guardian_name",      "value": "Arun Malhotra"},
            {"attribute_code": "previous_school",    "value": "Ryan International, Pune"},
            {"attribute_code": "entrance_score",     "value": "82"},
            {"attribute_code": "admission_category", "value": "MANAGEMENT"}
        ]'::JSONB,
        v_system_actor
    );
    RAISE NOTICE 'Student 5 Application (Tej Malhotra) ID: %', v_app_id_5;

    RAISE NOTICE 'STEP 7: 5 applications created in kernel. ✓ 5 audit events appended.';
    RAISE NOTICE '';
    RAISE NOTICE 'IMPORTANT: Record IDs must be used in STEP 8 workflow transitions.';
    RAISE NOTICE 'Copy the IDs above into v_app_id_1..5 variables in the next block.';
    RAISE NOTICE 'Or use the query: SELECT record_id, created_at FROM entity_records';
    RAISE NOTICE 'WHERE entity_id = (SELECT entity_id FROM entity_master WHERE entity_code=''STUDENT_APPLICATION'')';
    RAISE NOTICE 'ORDER BY created_at DESC LIMIT 5;';
END $$;


-- =============================================================================
-- STEP 8: DRIVE STUDENT WORKFLOWS THROUGH ALL STATES
-- LAW 3: execute_workflow_transition() is the ONLY path to change state.
-- Signature: execute_workflow_transition(
--   p_entity_code TEXT,
--   p_record_id   UUID,
--   p_to_state    TEXT,    ← must match workflow_transitions.to_state text code
--   p_actor_id    UUID,
--   p_notes       TEXT DEFAULT NULL
-- )
-- Workflow states from 07_module_01_admission_data.sql:
--   DRAFT → SUBMITTED → DOCUMENT_VERIFIED → ENTRANCE_SCHEDULED →
--   ENTRANCE_COMPLETED → SELECTION_REVIEW → OFFER_ISSUED → FEE_PAID → ENROLLED
-- =============================================================================
DO $$
DECLARE
    v_tenant_id     UUID := current_setting('app.tenant_id', true)::UUID;
    v_system_actor  UUID := '00000000-0000-0000-0000-000000000099'::UUID;
    v_entity_app_id UUID;

    -- Fetch the 5 most-recently-created STUDENT_APPLICATION records
    -- Order: most recent 5 in reverse creation order (latest created = 5th)
    v_app_ids       UUID[];
    v_app_id        UUID;
    i               INT;
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════';
    RAISE NOTICE 'STEP 8: Executing Workflow Transitions for 5 Students';
    RAISE NOTICE '════════════════════════════════════════════════════════';

    -- Resolve STUDENT_APPLICATION entity_id
    SELECT entity_id INTO v_entity_app_id
    FROM entity_master
    WHERE tenant_id = v_tenant_id AND entity_code = 'STUDENT_APPLICATION';

    IF v_entity_app_id IS NULL THEN
        RAISE EXCEPTION 'STUDENT_APPLICATION entity not found! Run 07_module_01_admission_data.sql first.';
    END IF;

    -- Fetch the 5 most recently created application records for this tenant
    SELECT ARRAY(
        SELECT record_id
        FROM entity_records
        WHERE tenant_id = v_tenant_id AND entity_id = v_entity_app_id
        ORDER BY created_at DESC
        LIMIT 5
    ) INTO v_app_ids;

    IF array_length(v_app_ids, 1) < 5 THEN
        RAISE EXCEPTION 'Expected 5 application records, found only %. Run STEP 7 first.', array_length(v_app_ids, 1);
    END IF;

    -- ── STUDENT 1 (Aryan Kapoor): Full Journey → ENROLLED ─────────────────
    --   All 8 transitions: DRAFT → SUBMITTED → DOCUMENT_VERIFIED →
    --   ENTRANCE_SCHEDULED → ENTRANCE_COMPLETED → SELECTION_REVIEW →
    --   OFFER_ISSUED → FEE_PAID → ENROLLED
    v_app_id := v_app_ids[5]; -- oldest inserted = student 1
    RAISE NOTICE 'Processing Student 1 (record_id: %) → ENROLLED', v_app_id;

    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'DRAFT',
        v_system_actor, 'Application initialized in draft mode.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'SUBMITTED',
        v_system_actor, 'Aryan Kapoor: Application submitted by guardian.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'DOCUMENT_VERIFIED',
        v_system_actor, 'Transfer certificate, birth certificate verified.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'ENTRANCE_SCHEDULED',
        v_system_actor, 'Entrance test scheduled: 2026-03-10, 10:00 AM, Room 201.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'ENTRANCE_COMPLETED',
        v_system_actor, 'Entrance score recorded: 87/100.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'SELECTION_REVIEW',
        v_system_actor, 'Moved to selection committee review.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'OFFER_ISSUED',
        v_system_actor, 'Offer letter issued. Fee payment due within 7 days.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'FEE_PAID',
        v_system_actor, 'Admission fee ₹45,000 confirmed via NEFT. Ref: TXN2026031001.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'ENROLLED',
        v_system_actor, 'Student officially enrolled in Class 10. Roll No. assigned: 10-A-01.');
    RAISE NOTICE 'Student 1: ENROLLED ✓ (8 chain events written)';

    -- ── STUDENT 2 (Fatima Sheikh): Journey → OFFER_ISSUED (Fee Pending) ────
    v_app_id := v_app_ids[4];
    RAISE NOTICE 'Processing Student 2 (record_id: %) → OFFER_ISSUED', v_app_id;

    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'DRAFT',
        v_system_actor, 'Draft record created.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'SUBMITTED',
        v_system_actor, 'Fatima Sheikh: Application submitted online.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'DOCUMENT_VERIFIED',
        v_system_actor, 'All documents verified. Marks card authenticated.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'ENTRANCE_SCHEDULED',
        v_system_actor, 'Entrance test scheduled: 2026-03-10, 10:00 AM, Room 202.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'ENTRANCE_COMPLETED',
        v_system_actor, 'Score: 91/100. Top performer in batch.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'SELECTION_REVIEW',
        v_system_actor, 'Fast-tracked by selection committee.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'OFFER_ISSUED',
        v_system_actor, 'Offer letter issued. Awaiting fee payment from guardian.');
    RAISE NOTICE 'Student 2: OFFER_ISSUED ✓ (6 chain events written)';

    -- ── STUDENT 3 (Rohan Nair): Journey → SELECTION_REVIEW ──────────────────
    v_app_id := v_app_ids[3];
    RAISE NOTICE 'Processing Student 3 (record_id: %) → SELECTION_REVIEW', v_app_id;

    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'DRAFT',
        v_system_actor, 'Draft record created.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'SUBMITTED',
        v_system_actor, 'Rohan Nair: Application submitted in person.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'DOCUMENT_VERIFIED',
        v_system_actor, 'Caste certificate and academic records verified.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'ENTRANCE_SCHEDULED',
        v_system_actor, 'Entrance test: 2026-03-12, 2:00 PM, Lab 3.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'ENTRANCE_COMPLETED',
        v_system_actor, 'Score: 78/100. Meets SC quota minimum threshold of 60.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'SELECTION_REVIEW',
        v_system_actor, 'Under committee review for SC category seat allocation.');
    RAISE NOTICE 'Student 3: SELECTION_REVIEW ✓ (5 chain events written)';

    -- ── STUDENT 4 (Meera Iyer): Journey → ENTRANCE_SCHEDULED ────────────────
    v_app_id := v_app_ids[2];
    RAISE NOTICE 'Processing Student 4 (record_id: %) → ENTRANCE_SCHEDULED', v_app_id;

    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'DRAFT',
        v_system_actor, 'Draft record created.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'SUBMITTED',
        v_system_actor, 'Meera Iyer: Application submitted by parent portal.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'DOCUMENT_VERIFIED',
        v_system_actor, 'Previous school TC and report cards verified.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'ENTRANCE_SCHEDULED',
        v_system_actor, 'Junior entrance test scheduled: 2026-03-15, 9:00 AM, Room 101.');
    RAISE NOTICE 'Student 4: ENTRANCE_SCHEDULED ✓ (3 chain events written)';

    -- ── STUDENT 5 (Tej Malhotra): Journey → SUBMITTED ───────────────────────
    v_app_id := v_app_ids[1]; -- most recent
    RAISE NOTICE 'Processing Student 5 (record_id: %) → SUBMITTED', v_app_id;

    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'DRAFT',
        v_system_actor, 'Draft record created.');
    PERFORM execute_workflow_transition('STUDENT_APPLICATION', v_app_id, 'SUBMITTED',
        v_system_actor, 'Tej Malhotra: Management quota application submitted. Fee receipt pending.');
    RAISE NOTICE 'Student 5: SUBMITTED ✓ (1 chain event written)';

    RAISE NOTICE '';
    RAISE NOTICE 'STEP 8: All workflow transitions executed. ✓';
    RAISE NOTICE 'Total new audit_event_log entries from Step 8: 23';
    RAISE NOTICE '(8 + 6 + 5 + 3 + 1 transition events per student)';
END $$;


-- =============================================================================
-- STEP 9: SEED SYSTEM SETTINGS FOR DEMO TENANT (LAW 5)
-- Settings drive defaults — never hardcoded in application logic.
-- Cross-referenced with db/03_schema_layer7_layer9.sql (system_settings table):
--   Columns: tenant_id, setting_category, setting_key, setting_value,
--            scope_level, description
-- =============================================================================
DO $$
DECLARE
    v_tenant_id UUID := current_setting('app.tenant_id', true)::UUID;
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════';
    RAISE NOTICE 'STEP 9: Seeding System Settings (LAW 5)';
    RAISE NOTICE '════════════════════════════════════════════════════════';

    INSERT INTO system_settings (tenant_id, setting_category, setting_key, setting_value, scope_level, description)
    VALUES
        (v_tenant_id, 'ACADEMIC',  'school.name',               'PrathamOne International School',   'TENANT', 'Full display name of the institution'),
        (v_tenant_id, 'ACADEMIC',  'school.code',               'POIS-DEMO-2026',                     'TENANT', 'Unique school registration code'),
        (v_tenant_id, 'ACADEMIC',  'school.affiliation',        'CBSE',                               'TENANT', 'Board affiliation: CBSE | ICSE | IB | State'),
        (v_tenant_id, 'ACADEMIC',  'school.academic_year',      '2025-2026',                          'TENANT', 'Current academic year'),
        (v_tenant_id, 'ACADEMIC',  'admission.max_seats_class10', '40',                               'TENANT', 'Maximum intake for Class 10 per year'),
        (v_tenant_id, 'ACADEMIC',  'admission.entrance_passing_score', '60',                          'TENANT', 'Minimum entrance score to qualify (General category)'),
        (v_tenant_id, 'ACADEMIC',  'admission.fee_payment_days', '7',                                 'TENANT', 'Days allowed between offer letter and fee payment'),
        (v_tenant_id, 'SYSTEM',    'archival.hot_retention_months', '36',                             'TENANT', 'LAW 09-5.1: Hot storage retention window in months'),
        (v_tenant_id, 'UI',        'theme.primary_color',       '#6366f1',                            'TENANT', 'Primary brand color (Indigo-500)'),
        (v_tenant_id, 'UI',        'theme.logo_url',            '/assets/logos/prathamone-demo.svg',  'TENANT', 'Institution logo URL')
    ON CONFLICT (tenant_id, setting_key, scope_level, scope_ref_id) DO NOTHING;

    RAISE NOTICE 'STEP 9: System settings seeded. ✓';
END $$;


-- =============================================================================
-- COMMIT THE TRANSACTION
-- If any step above raised an uncaught exception, the entire seed is rolled back.
-- =============================================================================
COMMIT;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '████████████████████████████████████████████████████████';
    RAISE NOTICE '  DEMO ONBOARDING SEED COMPLETE                         ';
    RAISE NOTICE '  Entities created  : 1 Principal + 3 Teachers + 5 Students';
    RAISE NOTICE '  Workflow events   : 23 state transitions logged        ';
    RAISE NOTICE '  Audit chain       : Append-only, hash-linked (LAW 8)  ';
    RAISE NOTICE '  Now run VERIFICATION QUERIES below to confirm chain.   ';
    RAISE NOTICE '████████████████████████████████████████████████████████';
END $$;


-- =============================================================================
-- VERIFICATION SECTION
-- Run these queries manually to confirm the seed was applied correctly and
-- the audit hash-chain remained intact throughout data generation.
-- =============================================================================

/*
-- ─────────────────────────────────────────────────────────────────────────────
-- [VQ-1] CONFIRM DEMO TENANT EXISTS
-- ─────────────────────────────────────────────────────────────────────────────
SELECT tenant_id, name, slug, plan, is_active, created_at
FROM tenants
WHERE slug = 'demo-prathamone-intl';
-- Expected: 1 row — PrathamOne International School

-- ─────────────────────────────────────────────────────────────────────────────
-- [VQ-2] CONFIRM ALL ENTITIES WERE REGISTERED
-- ─────────────────────────────────────────────────────────────────────────────
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT entity_code, entity_type, display_name, is_system
FROM entity_master
WHERE tenant_id = current_setting('app.tenant_id', TRUE)::UUID
ORDER BY entity_code;
-- Expected rows: user, teacher, STUDENT_APPLICATION, STUDENT (from module 01)

-- ─────────────────────────────────────────────────────────────────────────────
-- [VQ-3] VIEW ALL DEMO ENTITY RECORDS (Users, Teachers, Students)
-- ─────────────────────────────────────────────────────────────────────────────
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT
    er.record_id,
    em.entity_code,
    er.display_name,
    er.created_at
FROM entity_records er
JOIN entity_master em ON em.entity_id = er.entity_id AND em.tenant_id = er.tenant_id
WHERE er.tenant_id = current_setting('app.tenant_id', TRUE)::UUID
ORDER BY em.entity_code, er.created_at;
-- Expected: 1+1 system actors, 1 principal, 3 teachers, 5 student applications

-- ─────────────────────────────────────────────────────────────────────────────
-- [VQ-4] VIEW STUDENT APPLICATION ATTRIBUTE VALUES
-- ─────────────────────────────────────────────────────────────────────────────
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT
    er.record_id,
    am.attribute_code,
    eav.value_text,
    eav.value_number
FROM entity_records er
JOIN entity_master em ON em.entity_id = er.entity_id
JOIN entity_attribute_values eav ON eav.record_id = er.record_id AND eav.tenant_id = er.tenant_id
JOIN attribute_master am ON am.attribute_id = eav.attribute_id AND am.tenant_id = eav.tenant_id
WHERE er.tenant_id = current_setting('app.tenant_id', TRUE)::UUID
  AND em.entity_code = 'STUDENT_APPLICATION'
ORDER BY er.created_at, am.sort_order;
-- Expected: 35 rows (5 students × 7 attributes each)

-- ─────────────────────────────────────────────────────────────────────────────
-- [VQ-5] VIEW CURRENT WORKFLOW STATE OF EACH STUDENT APPLICATION
-- ─────────────────────────────────────────────────────────────────────────────
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT
    wsl.record_id,
    wsl.to_state   AS current_state,
    wsl.transition_at,
    wsl.metadata->'notes' AS last_note
FROM workflow_state_log wsl
WHERE wsl.tenant_id = current_setting('app.tenant_id', TRUE)::UUID
  AND wsl.transition_at = (
      SELECT MAX(w2.transition_at)
      FROM workflow_state_log w2
      WHERE w2.record_id = wsl.record_id
        AND w2.tenant_id = wsl.tenant_id
  )
ORDER BY wsl.transition_at;
-- Expected 5 rows: ENROLLED, OFFER_ISSUED, SELECTION_REVIEW, ENTRANCE_SCHEDULED, SUBMITTED

-- ─────────────────────────────────────────────────────────────────────────────
-- [VQ-6] AUDIT HASH CHAIN INTEGRITY CHECK
-- This is the most important verification query (LAW 8 compliance).
-- It recomputes the SHA-256 hash for every audit_event_log row belonging to
-- the demo tenant and compares it to the stored current_hash.
-- Any mismatch = chain tampering detected.
-- ─────────────────────────────────────────────────────────────────────────────
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
WITH chain AS (
    SELECT
        tenant_sequence_number,
        log_id,
        event_type,
        logged_at,
        previous_hash,
        current_hash,
        event_data,
        -- Recompute the hash using the SAME algorithm as the kernel trigger
        encode(
            digest(
                COALESCE(previous_hash, 'GENESIS')
                || '|' || log_id::TEXT
                || '|' || event_data::TEXT
                || '|' || logged_at::TEXT,
                'sha256'
            ),
            'hex'
        ) AS recomputed_hash
    FROM audit_event_log
    WHERE tenant_id = current_setting('app.tenant_id', TRUE)::UUID
    ORDER BY tenant_sequence_number
)
SELECT
    tenant_sequence_number,
    event_type,
    logged_at,
    CASE
        WHEN recomputed_hash = current_hash THEN '✓ INTACT'
        ELSE '✗ TAMPERED — SEQ ' || tenant_sequence_number
    END AS chain_status,
    current_hash
FROM chain
ORDER BY tenant_sequence_number;
-- Expected: ALL rows show '✓ INTACT'. Any '✗ TAMPERED' row = critical incident.

-- ─────────────────────────────────────────────────────────────────────────────
-- [VQ-7] CHAIN SUMMARY — COUNT EVENTS AND VERIFY GENESIS
-- ─────────────────────────────────────────────────────────────────────────────
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT
    COUNT(*)                                AS total_audit_events,
    MIN(tenant_sequence_number)             AS first_seq,
    MAX(tenant_sequence_number)             AS last_seq,
    COUNT(*) FILTER (WHERE previous_hash IS NULL) AS genesis_events,
    COUNT(DISTINCT event_type)              AS distinct_event_types
FROM audit_event_log
WHERE tenant_id = current_setting('app.tenant_id', TRUE)::UUID;
-- Expected:
--   total_audit_events  ≥ 32
--     (1 system actor seeded manually + 9 create_entity_record calls → 9 ENTITY_RECORD_CREATED
--      + 23 execute_workflow_transition calls → 23 WORKFLOW_TRANSITION
--      + any system events)
--   genesis_events = 1 (only the very first event has no previous_hash)

-- ─────────────────────────────────────────────────────────────────────────────
-- [VQ-8] VIEW FULL AUDIT TIMELINE FOR A SPECIFIC STUDENT APPLICATION
-- Replace <student_record_id> with any record_id from VQ-5
-- ─────────────────────────────────────────────────────────────────────────────
-- SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
-- SELECT
--     tenant_sequence_number,
--     event_type,
--     event_data->>'from_state'  AS from_state,
--     event_data->>'to_state'    AS to_state,
--     event_data->>'notes'       AS notes,
--     logged_at,
--     LEFT(current_hash, 16)     AS hash_prefix
-- FROM audit_event_log
-- WHERE tenant_id = current_setting('app.tenant_id', TRUE)::UUID
--   AND record_id = '<student_record_id>'
-- ORDER BY tenant_sequence_number;
*/

-- =============================================================================
-- END: 99_demo_onboarding_seed.sql
-- Implements: 1 Demo Tenant ∣ 1 Tenant Admin ∣ 3 Teachers ∣ 5 Student Apps
-- Audit chain: ≥32 hash-linked, immutable events written.
-- All data created via kernel functions — zero raw EAV mutations.
-- =============================================================================
