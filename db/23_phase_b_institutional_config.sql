-- =============================================================================
-- PRATHAMONE ACADEMY OS — PHASE B: INSTITUTIONAL CONFIGURATION
-- File: db/23_phase_b_institutional_config.sql
-- =============================================================================
-- Author      : Chief Kernel Guardian & Platform Operations
-- Purpose     : Execute Points 4–9 of the 15-Point Pilot Onboarding Technical
--               Checklist. Configures the academic entity structure, role
--               bindings, workflow activation, policy presets, system settings,
--               and AI governance registration for the pilot institution.
--
-- CHECKLIST COVERAGE:
--   ✓ Point 4  — Academic Structure (Sections, Subjects, Classes, Boards)
--   ✓ Point 5  — Role & Permission Mapping (actor_roles on workflow_transitions)
--   ✓ Point 6  — Workflow Activation (admission, exam, fee workflows)
--   ✓ Point 7  — Policy Configuration (age eligibility, score floor, seat cap,
--                                      late fee penalty, document checklist)
--   ✓ Point 8  — System Settings Baseline (academic year, board, thresholds)
--   ✓ Point 9  — AI Governance Registration (ai_model_registry, advisory bounds)
--
-- CONSTITUTIONAL COMPLIANCE:
--   LAW 1  : All new academic concepts → entity_master rows, NOT new tables
--   LAW 2  : All variable attributes → attribute_master rows, NOT columns
--   LAW 3  : Workflow state changes ONLY via execute_workflow_transition()
--   LAW 5  : System defaults → system_settings rows, NOT hardcoded values
--   LAW 11 : No new tables — every academic entity is a row in the kernel
--   LAW 12 : Kernel is sealed — all customisation is data, never code
--
-- PREREQUISITES:
--   ✓ db/21_phase_a_onboarding_readiness.sql — PASSED
--   ✓ app.tenant_id set to the pilot institution's UUID
--   ✓ db/07_module_01_admission_data.sql — applied (STUDENT_APPLICATION entity exists)
--   ✓ db/12_kernel_functions.sql — applied (create_entity_record() available)
-- =============================================================================

BEGIN;

-- Ensure tenant context is set (LAW 7)
-- ─────────────────────────────────────────────────────────────────────────────
-- OPERATOR: Replace this UUID with the actual pilot tenant_id from Point 3.
-- ─────────────────────────────────────────────────────────────────────────────
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';

DO $$
BEGIN
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'PHASE B — INSTITUTIONAL CONFIGURATION';
    RAISE NOTICE 'Tenant: %', current_setting('app.tenant_id', true);
    RAISE NOTICE 'Time  : %', now();
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
END $$;


-- =============================================================================
-- POINT 4 — ACADEMIC STRUCTURE
-- Register: Academic Boards, Classes, Sections, Subjects, Batches
-- LAW 1: Each academic concept is a registered entity type.
-- LAW 11: New data = new rows in entity_master, NOT new tables.
-- =============================================================================
DO $$
DECLARE
    v_tenant_id UUID := current_setting('app.tenant_id', true)::UUID;
    v_sys_actor UUID := '00000000-0000-0000-0000-000000000099'::UUID;

    -- Entity UUIDs — resolved after INSERT
    v_e_board    UUID;
    v_e_class    UUID;
    v_e_section  UUID;
    v_e_subject  UUID;
    v_e_batch    UUID;
    v_e_timetable UUID;

BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'POINT 4 — ACADEMIC STRUCTURE REGISTRATION';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';

    -- ── 4A. Register Entity Types ──────────────────────────────────────────
    INSERT INTO entity_master
        (tenant_id, entity_type, entity_code, display_name, description, is_system)
    VALUES
        -- Academic hierarchy entities
        (v_tenant_id, 'ACADEMIC', 'BOARD',      'Academic Board',  'Curriculum board e.g. CBSE, ICSE, IB, State', FALSE),
        (v_tenant_id, 'ACADEMIC', 'CLASS',      'Class / Grade',   'Academic class level e.g. Class 1 – 12',      FALSE),
        (v_tenant_id, 'ACADEMIC', 'SECTION',    'Section',         'Class division e.g. A, B, C',                 FALSE),
        (v_tenant_id, 'ACADEMIC', 'SUBJECT',    'Subject',         'Academic subject e.g. Mathematics, English',  FALSE),
        (v_tenant_id, 'ACADEMIC', 'BATCH',      'Academic Batch',  'Cohort for a class+section+academic year',    FALSE),
        (v_tenant_id, 'ACADEMIC', 'TIMETABLE',  'Timetable Slot',  'Single class period assignment',              FALSE)
    ON CONFLICT (tenant_id, entity_code) DO NOTHING;

    -- Resolve entity_ids
    SELECT entity_id INTO v_e_board    FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'BOARD';
    SELECT entity_id INTO v_e_class    FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'CLASS';
    SELECT entity_id INTO v_e_section  FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'SECTION';
    SELECT entity_id INTO v_e_subject  FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'SUBJECT';
    SELECT entity_id INTO v_e_batch    FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'BATCH';
    SELECT entity_id INTO v_e_timetable FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'TIMETABLE';

    RAISE NOTICE '  ✓ 6 academic entity types registered.';

    -- ── 4B. Register Attributes for Each Entity (LAW 2) ───────────────────

    -- BOARD attributes
    INSERT INTO attribute_master
        (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_e_board, 'board_code',    'Board Code',    'text', TRUE,  TRUE,  10),
        (v_tenant_id, v_e_board, 'board_name',    'Full Name',     'text', TRUE,  TRUE,  20),
        (v_tenant_id, v_e_board, 'affiliation_no','Affiliation No','text', FALSE, FALSE, 30),
        (v_tenant_id, v_e_board, 'region',        'Region',        'text', FALSE, TRUE,  40)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    -- CLASS attributes
    INSERT INTO attribute_master
        (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_e_class, 'class_code',      'Class Code',        'text',    TRUE,  TRUE,  10),
        (v_tenant_id, v_e_class, 'class_name',      'Display Name',      'text',    TRUE,  TRUE,  20),
        (v_tenant_id, v_e_class, 'class_level',     'Numeric Level',     'numeric', TRUE,  FALSE, 30),
        (v_tenant_id, v_e_class, 'board_code',      'Board Affiliation', 'text',    TRUE,  TRUE,  40),
        (v_tenant_id, v_e_class, 'max_strength',    'Max Strength',      'numeric', FALSE, FALSE, 50)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    -- SECTION attributes
    INSERT INTO attribute_master
        (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_e_section, 'section_code',  'Section Code',      'text',    TRUE,  TRUE,  10),
        (v_tenant_id, v_e_section, 'class_code',    'Parent Class Code', 'text',    TRUE,  TRUE,  20),
        (v_tenant_id, v_e_section, 'class_teacher', 'Class Teacher ID',  'text',    FALSE, FALSE, 30),
        (v_tenant_id, v_e_section, 'room_number',   'Room Number',       'text',    FALSE, FALSE, 40)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    -- SUBJECT attributes
    INSERT INTO attribute_master
        (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_e_subject, 'subject_code',    'Subject Code',      'text',    TRUE,  TRUE,  10),
        (v_tenant_id, v_e_subject, 'subject_name',    'Subject Name',      'text',    TRUE,  TRUE,  20),
        (v_tenant_id, v_e_subject, 'subject_type',    'Type',              'text',    FALSE, TRUE,  30),
        (v_tenant_id, v_e_subject, 'max_marks',       'Maximum Marks',     'numeric', FALSE, FALSE, 40),
        (v_tenant_id, v_e_subject, 'passing_marks',   'Passing Marks',     'numeric', FALSE, FALSE, 50),
        (v_tenant_id, v_e_subject, 'is_elective',     'Is Elective',       'boolean', FALSE, FALSE, 60)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    -- BATCH attributes
    INSERT INTO attribute_master
        (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_e_batch, 'batch_code',      'Batch Code',        'text',    TRUE,  TRUE,  10),
        (v_tenant_id, v_e_batch, 'class_code',      'Class Code',        'text',    TRUE,  TRUE,  20),
        (v_tenant_id, v_e_batch, 'section_code',    'Section Code',      'text',    TRUE,  TRUE,  30),
        (v_tenant_id, v_e_batch, 'academic_year',   'Academic Year',     'text',    TRUE,  TRUE,  40),
        (v_tenant_id, v_e_batch, 'strength',        'Current Strength',  'numeric', FALSE, FALSE, 50),
        (v_tenant_id, v_e_batch, 'is_active',       'Is Active',         'boolean', FALSE, FALSE, 60)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    RAISE NOTICE '  ✓ Attributes defined for BOARD, CLASS, SECTION, SUBJECT, BATCH.';

    -- ── 4C. Seed Academic Board (CBSE — Demo school default) ──────────────
    PERFORM create_entity_record(
        'BOARD',
        '[
            {"attribute_code": "board_code",     "value": "CBSE"},
            {"attribute_code": "board_name",     "value": "Central Board of Secondary Education"},
            {"attribute_code": "affiliation_no", "value": "1930569"},
            {"attribute_code": "region",         "value": "National — India"}
        ]'::JSONB,
        v_sys_actor
    );
    RAISE NOTICE '  ✓ CBSE board record created.';

    -- ── 4D. Seed Class Levels (for a secondary school: Classes 6 – 12) ────
    -- Using a VALUES list for cleaner inline seeding
    PERFORM create_entity_record('CLASS',
        format('[{"attribute_code":"class_code","value":"%s"},{"attribute_code":"class_name","value":"%s"},{"attribute_code":"class_level","value":"%s"},{"attribute_code":"board_code","value":"CBSE"},{"attribute_code":"max_strength","value":"40"}]',
            c.code, c.name, c.level)::JSONB,
        v_sys_actor
    )
    FROM (VALUES
        ('CLS-06','Class 6','6'),  ('CLS-07','Class 7','7'),
        ('CLS-08','Class 8','8'),  ('CLS-09','Class 9','9'),
        ('CLS-10','Class 10','10'),('CLS-11-SCI','Class 11 Science','11'),
        ('CLS-11-COM','Class 11 Commerce','11'),('CLS-12-SCI','Class 12 Science','12'),
        ('CLS-12-COM','Class 12 Commerce','12')
    ) AS c(code, name, level);
    RAISE NOTICE '  ✓ 9 class-level records created (Classes 6–12 + streams).';

    -- ── 4E. Seed Sections (A, B per class — example Class 10 only) ────────
    PERFORM create_entity_record('SECTION',
        format('[{"attribute_code":"section_code","value":"%s"},{"attribute_code":"class_code","value":"CLS-10"},{"attribute_code":"room_number","value":"%s"}]',
            s.code, s.room)::JSONB,
        v_sys_actor
    )
    FROM (VALUES
        ('CLS-10-A','Room 201'), ('CLS-10-B','Room 202')
    ) AS s(code, room);
    RAISE NOTICE '  ✓ 2 sections created for Class 10 (A, B).';

    -- ── 4F. Seed Core Subjects ─────────────────────────────────────────────
    PERFORM create_entity_record('SUBJECT',
        format('[{"attribute_code":"subject_code","value":"%s"},{"attribute_code":"subject_name","value":"%s"},{"attribute_code":"subject_type","value":"%s"},{"attribute_code":"max_marks","value":"100"},{"attribute_code":"passing_marks","value":"33"},{"attribute_code":"is_elective","value":"false"}]',
            sub.code, sub.name, sub.stype)::JSONB,
        v_sys_actor
    )
    FROM (VALUES
        ('SUB-MATH','Mathematics','CORE'),
        ('SUB-ENGL','English Language & Literature','CORE'),
        ('SUB-SCI','Science','CORE'),
        ('SUB-SST','Social Science','CORE'),
        ('SUB-HINDI','Hindi','CORE'),
        ('SUB-CS','Computer Science','ELECTIVE'),
        ('SUB-PHY','Physics','CORE'),
        ('SUB-CHEM','Chemistry','CORE'),
        ('SUB-BIO','Biology','ELECTIVE'),
        ('SUB-ECON','Economics','CORE'),
        ('SUB-ACCTS','Accountancy','CORE'),
        ('SUB-BST','Business Studies','CORE')
    ) AS sub(code, name, stype);
    RAISE NOTICE '  ✓ 12 subjects registered (core + electives).';

    -- ── 4G. Seed active academic batch for 2025-2026 ──────────────────────
    PERFORM create_entity_record('BATCH',
        '[
            {"attribute_code": "batch_code",    "value": "BATCH-10-A-2526"},
            {"attribute_code": "class_code",    "value": "CLS-10"},
            {"attribute_code": "section_code",  "value": "CLS-10-A"},
            {"attribute_code": "academic_year", "value": "2025-2026"},
            {"attribute_code": "strength",      "value": "1"},
            {"attribute_code": "is_active",     "value": "true"}
        ]'::JSONB,
        v_sys_actor
    );
    RAISE NOTICE '  ✓ Batch BATCH-10-A-2526 created.';

    RAISE NOTICE '';
    RAISE NOTICE 'POINT 4: ✓ COMPLETE — Academic structure established.';
    RAISE NOTICE '  Board: 1 | Classes: 9 | Sections: 2 | Subjects: 12 | Batches: 1';
END $$;


-- =============================================================================
-- POINT 5 — ROLE & PERMISSION MAPPING
-- Binds actor_role codes to workflow transition edges so the workflow engine
-- can enforce "who can trigger what".
-- LAW 3: The engine checks actor_roles[] before allowing a transition.
-- =============================================================================
DO $$
DECLARE
    v_tenant_id UUID := current_setting('app.tenant_id', true)::UUID;
    v_wf_id     UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'POINT 5 — ROLE & PERMISSION MAPPING';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';

    -- Resolve ADMISSION_PROC workflow
    SELECT workflow_id INTO v_wf_id
    FROM workflow_master
    WHERE tenant_id = v_tenant_id AND workflow_code = 'ADMISSION_PROC';

    IF v_wf_id IS NULL THEN
        RAISE WARNING '  ⚠ ADMISSION_PROC workflow not found — skipping role binding.';
        RAISE WARNING '  Ensure db/07_module_01_admission_data.sql has been applied.';
    ELSE
        RAISE NOTICE '  ADMISSION_PROC workflow_id: %', v_wf_id;

        -- Assign actor_roles to each transition edge
        -- Roles: TENANT_ADMIN, ADMISSION_OFFICER, COMMITTEE_MEMBER, FINANCE_CLERK, STUDENT_GUARDIAN
        UPDATE workflow_transitions SET actor_roles = ARRAY['TENANT_ADMIN','ADMISSION_OFFICER']
        WHERE workflow_id = v_wf_id AND from_state = 'DRAFT' AND to_state = 'SUBMITTED';

        UPDATE workflow_transitions SET actor_roles = ARRAY['ADMISSION_OFFICER','TENANT_ADMIN']
        WHERE workflow_id = v_wf_id AND from_state = 'SUBMITTED' AND to_state = 'DOCUMENT_VERIFIED';

        UPDATE workflow_transitions SET actor_roles = ARRAY['ADMISSION_OFFICER']
        WHERE workflow_id = v_wf_id AND from_state = 'DOCUMENT_VERIFIED' AND to_state = 'ENTRANCE_SCHEDULED';

        UPDATE workflow_transitions SET actor_roles = ARRAY['ADMISSION_OFFICER']
        WHERE workflow_id = v_wf_id AND from_state = 'ENTRANCE_SCHEDULED' AND to_state = 'ENTRANCE_COMPLETED';

        UPDATE workflow_transitions SET actor_roles = ARRAY['COMMITTEE_MEMBER','TENANT_ADMIN']
        WHERE workflow_id = v_wf_id AND from_state = 'ENTRANCE_COMPLETED' AND to_state = 'SELECTION_REVIEW';

        UPDATE workflow_transitions SET actor_roles = ARRAY['COMMITTEE_MEMBER','TENANT_ADMIN']
        WHERE workflow_id = v_wf_id AND from_state = 'SELECTION_REVIEW' AND to_state = 'OFFER_ISSUED';

        UPDATE workflow_transitions SET actor_roles = ARRAY['STUDENT_GUARDIAN','ADMISSION_OFFICER']
        WHERE workflow_id = v_wf_id AND from_state = 'OFFER_ISSUED' AND to_state = 'FEE_PAID';

        UPDATE workflow_transitions SET actor_roles = ARRAY['FINANCE_CLERK','TENANT_ADMIN']
        WHERE workflow_id = v_wf_id AND from_state = 'FEE_PAID' AND to_state = 'ENROLLED';

        -- Rejection paths (authorised by committee or admin)
        UPDATE workflow_transitions SET actor_roles = ARRAY['COMMITTEE_MEMBER','TENANT_ADMIN']
        WHERE workflow_id = v_wf_id AND to_state IN ('REJECTED','WAITLISTED');

        RAISE NOTICE '  ✓ Role bindings applied to ADMISSION_PROC transitions.';
        RAISE NOTICE '  Roles in use: TENANT_ADMIN, ADMISSION_OFFICER, COMMITTEE_MEMBER,';
        RAISE NOTICE '               FINANCE_CLERK, STUDENT_GUARDIAN';
    END IF;

    -- ── Define EXAMINER and FINANCE_CLERK roles for future workflows ────────
    -- (Using system_settings as a role registry — LAW 5, no custom table needed)
    INSERT INTO system_settings (tenant_id, setting_category, setting_key, setting_value, scope_level, description)
    VALUES
        (v_tenant_id, 'RBAC', 'roles.admission_officer',  '"ADMISSION_OFFICER"',  'TENANT', 'Can manage student applications through the admission workflow'),
        (v_tenant_id, 'RBAC', 'roles.committee_member',   '"COMMITTEE_MEMBER"',   'TENANT', 'Can review and approve/reject admission selections'),
        (v_tenant_id, 'RBAC', 'roles.finance_clerk',      '"FINANCE_CLERK"',      'TENANT', 'Can confirm fee payments and trigger ENROLLED state'),
        (v_tenant_id, 'RBAC', 'roles.examiner',           '"EXAMINER"',           'TENANT', 'Can create, administer, and complete exam events'),
        (v_tenant_id, 'RBAC', 'roles.class_teacher',      '"CLASS_TEACHER"',      'TENANT', 'Can manage timetables and attendance for their assigned batch'),
        (v_tenant_id, 'RBAC', 'roles.student_guardian',   '"STUDENT_GUARDIAN"',   'TENANT', 'Can accept offers and submit fee confirmation')
    ON CONFLICT (tenant_id, setting_key, scope_level, scope_ref_id) DO NOTHING;

    RAISE NOTICE '  ✓ 6 role definitions seeded into system_settings (RBAC category).';
    RAISE NOTICE '';
    RAISE NOTICE 'POINT 5: ✓ COMPLETE — Role permissions bound to workflow transitions.';
END $$;


-- =============================================================================
-- POINT 6 — WORKFLOW ACTIVATION
-- Marks institutional workflows as active. Inactive workflows are invisible
-- to the workflow engine — no transitions can be triggered on them.
-- LAW 3: Workflow governs state — activation is a prerequisite.
-- =============================================================================
DO $$
DECLARE
    v_tenant_id UUID := current_setting('app.tenant_id', true)::UUID;
    v_activated INT := 0;
    v_rec       RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'POINT 6 — WORKFLOW ACTIVATION';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';

    -- Activate all workflows that belong to this tenant
    -- (at this stage: ADMISSION_PROC from Module 01, plus any pre-registered workflows)
    UPDATE workflow_master
    SET is_active = TRUE
    WHERE tenant_id = v_tenant_id
      AND workflow_code IN (
          'ADMISSION_PROC',        -- Module 01: Student Admission
          'FEE_COLLECTION',        -- Module 02: Fee Management (if applied)
          'EXAM_LIFECYCLE',        -- Module 03: Exam Management (if applied)
          'LEAVE_REQUEST',         -- HR: Staff Leave (if applied)
          'DOCUMENT_VERIFICATION', -- Cross-cutting: document workflow
          'GRIEVANCE_RESOLUTION'   -- Cross-cutting: complaint workflow
      )
    RETURNING workflow_code;

    GET DIAGNOSTICS v_activated = ROW_COUNT;
    RAISE NOTICE '  ✓ % workflow(s) activated.', v_activated;

    -- Confirm which workflows are now active
    FOR v_rec IN
        SELECT workflow_code, display_name, is_active
        FROM workflow_master
        WHERE tenant_id = v_tenant_id
        ORDER BY workflow_code
    LOOP
        IF v_rec.is_active THEN
            RAISE NOTICE '  ✓ ACTIVE   — % (%)', v_rec.workflow_code, v_rec.display_name;
        ELSE
            RAISE NOTICE '  ○ INACTIVE — % (%)', v_rec.workflow_code, v_rec.display_name;
        END IF;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE 'POINT 6: ✓ COMPLETE — Workflows activated.';
END $$;


-- =============================================================================
-- POINT 7 — POLICY CONFIGURATION
-- Seeds the policy rule definitions for the pilot institution.
-- Each policy is a configurable row — not hardcoded logic.
-- LAW 4: Policies evaluate BEFORE state transitions.
-- LAW 5: All thresholds are settings rows, not code constants.
-- =============================================================================
DO $$
DECLARE
    v_tenant_id UUID := current_setting('app.tenant_id', true)::UUID;
    v_wf_id     UUID;
    v_pol_id    UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'POINT 7 — POLICY CONFIGURATION (CBSE School Default Preset)';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';

    SELECT workflow_id INTO v_wf_id
    FROM workflow_master
    WHERE tenant_id = v_tenant_id AND workflow_code = 'ADMISSION_PROC';

    -- ── Policy 1: Age Eligibility ──────────────────────────────────────────
    -- Each class has a minimum and maximum age at time of admission
    -- Evaluated at: SUBMITTED → DOCUMENT_VERIFIED transition
    INSERT INTO policy_master (tenant_id, policy_code, display_name, entity_id, rule_definition, is_active, evaluation_order)
    VALUES (v_tenant_id, 'AGE_ELIGIBILITY', 'Age Eligibility for Admission', 
            (SELECT entity_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'STUDENT_APPLICATION'),
            '{}'::JSONB, TRUE, 10)
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    SELECT policy_id INTO v_pol_id FROM policy_master
    WHERE tenant_id = v_tenant_id AND policy_code = 'AGE_ELIGIBILITY';

    INSERT INTO policy_conditions (tenant_id, policy_id, condition_code, rule_definition, description)
    VALUES (
        v_tenant_id, v_pol_id, 'MIN_AGE_AT_ADMISSION',
        '{
            "operator": "BETWEEN",
            "attribute_code": "date_of_birth",
            "min_age_years": 5,
            "max_age_years": 19,
            "evaluated_at": "SUBMITTED",
            "denial_message": "Applicant age does not meet CBSE eligibility criteria"
        }'::JSONB,
        'Checks applicant DOB is within the 5–19 year eligibility window'
    ) ON CONFLICT (tenant_id, policy_id, condition_code) DO NOTHING;

    RAISE NOTICE '  ✓ Policy AGE_ELIGIBILITY configured (ages 5–19).';

    -- ── Policy 2: Entrance Score Minimum (General Category) ───────────────
    -- Evaluated at: ENTRANCE_COMPLETED → SELECTION_REVIEW transition
    INSERT INTO policy_master (tenant_id, policy_code, display_name, entity_id, rule_definition, is_active, evaluation_order)
    VALUES (v_tenant_id, 'ENTRANCE_SCORE_MINIMUM', 'Minimum Entrance Score Requirement', 
            (SELECT entity_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'STUDENT_APPLICATION'),
            '{}'::JSONB, TRUE, 20)
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    SELECT policy_id INTO v_pol_id FROM policy_master
    WHERE tenant_id = v_tenant_id AND policy_code = 'ENTRANCE_SCORE_MINIMUM';

    INSERT INTO policy_conditions (tenant_id, policy_id, condition_code, rule_definition, description)
    VALUES
    (
        v_tenant_id, v_pol_id, 'GENERAL_MINIMUM_SCORE',
        '{
            "operator": "GTE",
            "attribute_code": "entrance_score",
            "threshold": 60,
            "applies_to_category": "GENERAL",
            "denial_message": "Entrance score below minimum threshold of 60 for GENERAL category"
        }'::JSONB,
        'General category: minimum entrance score 60/100'
    ),
    (
        v_tenant_id, v_pol_id, 'SC_ST_MINIMUM_SCORE',
        '{
            "operator": "GTE",
            "attribute_code": "entrance_score",
            "threshold": 45,
            "applies_to_category": ["SC","ST"],
            "denial_message": "Entrance score below minimum threshold of 45 for SC/ST category"
        }'::JSONB,
        'SC/ST category: minimum entrance score 45/100 (10% reservation concession)'
    ),
    (
        v_tenant_id, v_pol_id, 'OBC_MINIMUM_SCORE',
        '{
            "operator": "GTE",
            "attribute_code": "entrance_score",
            "threshold": 55,
            "applies_to_category": "OBC",
            "denial_message": "Entrance score below minimum threshold of 55 for OBC category"
        }'::JSONB,
        'OBC category: minimum entrance score 55/100 (5% concession)'
    )
    ON CONFLICT (tenant_id, policy_id, condition_code) DO NOTHING;

    RAISE NOTICE '  ✓ Policy ENTRANCE_SCORE_MINIMUM configured (60/55/45 by category).';

    -- ── Policy 3: Seat Capacity Limit ─────────────────────────────────────
    -- Evaluated at: OFFER_ISSUED — prevents issuing offers beyond seat limit
    INSERT INTO policy_master (tenant_id, policy_code, display_name, entity_id, rule_definition, is_active, evaluation_order)
    VALUES (v_tenant_id, 'SEAT_CAPACITY_LIMIT', 'Maximum Seat Capacity per Class', 
            (SELECT entity_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'STUDENT_APPLICATION'),
            '{}'::JSONB, TRUE, 30)
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    SELECT policy_id INTO v_pol_id FROM policy_master
    WHERE tenant_id = v_tenant_id AND policy_code = 'SEAT_CAPACITY_LIMIT';

    INSERT INTO policy_conditions (tenant_id, policy_id, condition_code, rule_definition, description)
    VALUES (
        v_tenant_id, v_pol_id, 'MAX_SEATS_PER_CLASS',
        '{
            "operator": "LTE",
            "metric": "enrolled_count",
            "threshold_setting_key": "admission.max_seats_class",
            "denial_message": "Class capacity reached. No further offers can be issued."
        }'::JSONB,
        'Reads max seats from system_settings.admission.max_seats_class at evaluation time'
    ) ON CONFLICT (tenant_id, policy_id, condition_code) DO NOTHING;

    RAISE NOTICE '  ✓ Policy SEAT_CAPACITY_LIMIT configured (reads from system_settings).';

    -- ── Policy 4: Fee Payment Deadline ────────────────────────────────────
    -- Evaluated at: OFFER_ISSUED — fee must be paid within N days of offer
    INSERT INTO policy_master (tenant_id, policy_code, display_name, entity_id, rule_definition, is_active, evaluation_order)
    VALUES (v_tenant_id, 'FEE_PAYMENT_DEADLINE', 'Fee Payment Window Enforcement', 
            (SELECT entity_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'STUDENT_APPLICATION'),
            '{}'::JSONB, TRUE, 40)
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    SELECT policy_id INTO v_pol_id FROM policy_master
    WHERE tenant_id = v_tenant_id AND policy_code = 'FEE_PAYMENT_DEADLINE';

    INSERT INTO policy_conditions (tenant_id, policy_id, condition_code, rule_definition, description)
    VALUES (
        v_tenant_id, v_pol_id, 'PAYMENT_WITHIN_WINDOW',
        '{
            "operator": "WITHIN_DAYS",
            "reference_event": "OFFER_ISSUED",
            "days_setting_key": "admission.fee_payment_days",
            "denial_message": "Fee payment window has expired. Application will be moved to WAITLISTED."
        }'::JSONB,
        'Verifies fee is paid within the window set in system_settings'
    ) ON CONFLICT (tenant_id, policy_id, condition_code) DO NOTHING;

    RAISE NOTICE '  ✓ Policy FEE_PAYMENT_DEADLINE configured.';

    -- ── Policy 5: Document Checklist Completeness ─────────────────────────
    INSERT INTO policy_master (tenant_id, policy_code, display_name, entity_id, rule_definition, is_active, evaluation_order)
    VALUES (v_tenant_id, 'DOCUMENT_COMPLETENESS', 'Mandatory Document Checklist', 
            (SELECT entity_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'STUDENT_APPLICATION'),
            '{}'::JSONB, TRUE, 15)
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    SELECT policy_id INTO v_pol_id FROM policy_master
    WHERE tenant_id = v_tenant_id AND policy_code = 'DOCUMENT_COMPLETENESS';

    INSERT INTO policy_conditions (tenant_id, policy_id, condition_code, rule_definition, description)
    VALUES (
        v_tenant_id, v_pol_id, 'MANDATORY_DOCS_PRESENT',
        '{
            "operator": "ALL_PRESENT",
            "required_documents": [
                "TRANSFER_CERTIFICATE",
                "BIRTH_CERTIFICATE",
                "PREVIOUS_MARKSHEET",
                "PASSPORT_PHOTO",
                "AADHAR_GUARDIAN"
            ],
            "denial_message": "Mandatory document(s) missing. Complete the document checklist before proceeding."
        }'::JSONB,
        'All 5 mandatory documents must be uploaded and verified'
    ) ON CONFLICT (tenant_id, policy_id, condition_code) DO NOTHING;

    RAISE NOTICE '  ✓ Policy DOCUMENT_COMPLETENESS configured (5 mandatory docs).';
    RAISE NOTICE '';
    RAISE NOTICE 'POINT 7: ✓ COMPLETE — 5 policy rules configured.';
    RAISE NOTICE '  AGE_ELIGIBILITY | ENTRANCE_SCORE_MINIMUM | SEAT_CAPACITY_LIMIT';
    RAISE NOTICE '  FEE_PAYMENT_DEADLINE | DOCUMENT_COMPLETENESS';
END $$;


-- =============================================================================
-- POINT 8 — SYSTEM SETTINGS BASELINE
-- All institutional defaults are settings rows, never hardcoded values.
-- LAW 5: System defaults are configuration, not constants.
-- =============================================================================
DO $$
DECLARE
    v_tenant_id UUID := current_setting('app.tenant_id', true)::UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'POINT 8 — SYSTEM SETTINGS BASELINE';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';

    INSERT INTO system_settings
        (tenant_id, setting_category, setting_key, setting_value, scope_level, description)
    VALUES
        -- ── Academic Identity ───────────────────────────────────────────────
        (v_tenant_id, 'ACADEMIC', 'school.name',              '"PrathamOne International School"',   'TENANT', 'Full legal name of the institution'),
        (v_tenant_id, 'ACADEMIC', 'school.code',              '"POIS-CBSE-2026"',                    'TENANT', 'Institution registration code'),
        (v_tenant_id, 'ACADEMIC', 'school.affiliation',       '"CBSE"',                              'TENANT', 'Board affiliation: CBSE|ICSE|IB|State'),
        (v_tenant_id, 'ACADEMIC', 'school.affiliation_no',    '"1930569"',                           'TENANT', 'Board-issued affiliation number'),
        (v_tenant_id, 'ACADEMIC', 'school.academic_year',     '"2025-2026"',                         'TENANT', 'Current active academic year'),
        (v_tenant_id, 'ACADEMIC', 'school.academic_year_start', '"2025-04-01"',                      'TENANT', 'Academic year start date (ISO 8601)'),
        (v_tenant_id, 'ACADEMIC', 'school.academic_year_end',   '"2026-03-31"',                      'TENANT', 'Academic year end date (ISO 8601)'),
        (v_tenant_id, 'ACADEMIC', 'school.timezone',          '"Asia/Kolkata"',                      'TENANT', 'Institution timezone (IANA format)'),

        -- ── Admission Thresholds ────────────────────────────────────────────
        (v_tenant_id, 'ACADEMIC', 'admission.max_seats_class',      '40',                            'TENANT', 'Default max seats per class section'),
        (v_tenant_id, 'ACADEMIC', 'admission.entrance_passing_general', '60',                        'TENANT', 'Minimum entrance score: General category'),
        (v_tenant_id, 'ACADEMIC', 'admission.entrance_passing_obc',     '55',                        'TENANT', 'Minimum entrance score: OBC category'),
        (v_tenant_id, 'ACADEMIC', 'admission.entrance_passing_sc_st',   '45',                        'TENANT', 'Minimum entrance score: SC/ST category'),
        (v_tenant_id, 'ACADEMIC', 'admission.fee_payment_days',     '7',                             'TENANT', 'Days from offer letter to fee payment deadline'),
        (v_tenant_id, 'ACADEMIC', 'admission.late_fee_penalty_pct', '5',                             'TENANT', 'Late fee penalty as % of total fee (after deadline)'),

        -- ── Exam Configuration ──────────────────────────────────────────────
        (v_tenant_id, 'ACADEMIC', 'exam.passing_marks_pct',    '33',                                 'TENANT', 'Default passing percentage (CBSE minimum)'),
        (v_tenant_id, 'ACADEMIC', 'exam.max_marks_per_subject','100',                                'TENANT', 'Default maximum marks per subject paper'),
        (v_tenant_id, 'ACADEMIC', 'exam.grace_marks_max',      '5',                                  'TENANT', 'Maximum grace marks grantable by committee'),

        -- ── Fee Structure (configurable per class — override per record) ────
        (v_tenant_id, 'FINANCIAL','fee.admission_fee_general',  '45000',                             'TENANT', 'One-time admission fee: General category (INR)'),
        (v_tenant_id, 'FINANCIAL','fee.admission_fee_sc_st',    '22500',                             'TENANT', 'One-time admission fee: SC/ST category (INR)'),
        (v_tenant_id, 'FINANCIAL','fee.tuition_monthly',        '8000',                              'TENANT', 'Monthly tuition fee (INR)'),
        (v_tenant_id, 'FINANCIAL','fee.transport_monthly',      '2500',                              'TENANT', 'Monthly transport fee (INR, optional)'),

        -- ── Data Governance ─────────────────────────────────────────────────
        (v_tenant_id, 'SYSTEM',  'archival.hot_retention_months', '36',                              'TENANT', 'LAW 09-5.1: Hot storage retention in months'),
        (v_tenant_id, 'SYSTEM',  'archival.cold_worm_years',      '10',                              'TENANT', 'WORM cold storage retention period in years'),
        (v_tenant_id, 'SYSTEM',  'data.residency_region',         '"IN-MUM"',                        'TENANT', 'GAP-6: Data residency region reference (informational)'),

        -- ── UI Branding ─────────────────────────────────────────────────────
        (v_tenant_id, 'UI',      'theme.primary_color',   '"#6366f1"',                               'TENANT', 'Primary brand color (Indigo-500)'),
        (v_tenant_id, 'UI',      'theme.secondary_color', '"#0ea5e9"',                               'TENANT', 'Secondary brand color (Sky-500)'),
        (v_tenant_id, 'UI',      'theme.logo_url',        '"/assets/logos/school-logo.svg"',         'TENANT', 'Institution logo URL for header display'),
        (v_tenant_id, 'UI',      'theme.display_name',    '"PrathamOne International School"',       'TENANT', 'Name displayed in the UI header')
    ON CONFLICT (tenant_id, setting_key, scope_level, scope_ref_id) DO NOTHING;

    RAISE NOTICE '  ✓ 28 system settings seeded across 4 categories:';
    RAISE NOTICE '    ACADEMIC | FINANCIAL | SYSTEM | UI';
    RAISE NOTICE '';
    RAISE NOTICE 'POINT 8: ✓ COMPLETE — System settings baseline established.';
END $$;


-- =============================================================================
-- POINT 9 — AI GOVERNANCE REGISTRATION
-- Registers the AI model with advisory-only bounds.
-- LAW 12: AI operates as an advisory layer. It cannot modify records directly.
-- No API keys are stored in plain text — secret reference only.
-- =============================================================================
DO $$
DECLARE
    v_tenant_id  UUID := current_setting('app.tenant_id', true)::UUID;
    v_model_id   UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'POINT 9 — AI GOVERNANCE REGISTRATION';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';

    -- ── 9A. Register AI Model ──────────────────────────────────────────────
    -- api_key_secret_ref points to Secret Manager — NEVER a raw key (LAW 12)
    INSERT INTO ai_model_registry (
        tenant_id, model_code, display_name, provider,
        model_type, api_key_secret_ref,
        capabilities, is_default, is_active,
        sarp_advisory_bounds
    ) VALUES (
        v_tenant_id,
        'gemini-2.0-flash',
        'Gemini 2.0 Flash',
        'GOOGLE',
        'LLM',
        -- This is a Secret Manager reference path, not a key value
        'projects/prathamone-prod/secrets/gemini-api-key/versions/latest',
        ARRAY['chat', 'function_calling', 'json_mode', 'essay_evaluation'],
        TRUE,   -- default model for this tenant
        TRUE,
        -- SARP Advisory Bounds (LAW 12):
        -- AI can ADVISE but never WRITE to entity_records or workflow_state_log
        '{
            "can_initiate_workflow_transitions": false,
            "can_write_entity_records": false,
            "can_read_audit_log": false,
            "max_output_tokens": 8192,
            "allowed_task_types": [
                "ESSAY_EVALUATION",
                "DOCUMENT_CLASSIFICATION",
                "ADMISSION_SHORTLISTING_ADVISORY",
                "TIMETABLE_OPTIMISATION_ADVISORY",
                "REPORT_NARRATIVE_GENERATION"
            ],
            "forbidden_task_types": [
                "DIRECT_GRADE_ASSIGNMENT",
                "AUTONOMOUS_ADMISSION_DECISION",
                "AUTONOMOUS_FEE_PROCESSING"
            ],
            "human_in_the_loop_required": true,
            "advisory_output_storage": "ai_tasks.output_payload JSONB only"
        }'::JSONB
    )
    ON CONFLICT (tenant_id, model_code) DO UPDATE
        SET is_active = TRUE,
            sarp_advisory_bounds = EXCLUDED.sarp_advisory_bounds;

    SELECT model_id INTO v_model_id
    FROM ai_model_registry
    WHERE tenant_id = v_tenant_id AND model_code = 'gemini-2.0-flash';

    RAISE NOTICE '  ✓ AI model registered: gemini-2.0-flash (model_id: %)', v_model_id;
    RAISE NOTICE '  ✓ Advisory-only bounds set (LAW 12):';
    RAISE NOTICE '    can_initiate_transitions = FALSE';
    RAISE NOTICE '    can_write_entity_records = FALSE';
    RAISE NOTICE '    human_in_the_loop_required = TRUE';
    RAISE NOTICE '    forbidden: DIRECT_GRADE_ASSIGNMENT, AUTONOMOUS_ADMISSION_DECISION';

    -- ── 9B. Seed AI governance settings ───────────────────────────────────
    INSERT INTO system_settings (tenant_id, setting_category, setting_key, setting_value, scope_level, description)
    VALUES
        (v_tenant_id, 'AI', 'ai.default_model_code',    '"gemini-2.0-flash"',     'TENANT', 'Default AI model for this institution'),
        (v_tenant_id, 'AI', 'ai.advisory_only',          'true',                   'TENANT', 'LAW 12: AI is advisory-only. No autonomous decisions.'),
        (v_tenant_id, 'AI', 'ai.human_approval_required','true',                   'TENANT', 'All AI recommendations require human approval before action'),
        (v_tenant_id, 'AI', 'ai.max_tokens_per_call',    '8192',                   'TENANT', 'Maximum output tokens per AI task'),
        (v_tenant_id, 'AI', 'ai.studybuddy_enabled',     'true',                   'TENANT', 'Studybuddy AI assistant enabled for students'),
        (v_tenant_id, 'AI', 'ai.studybuddy_roles',       '["STUDENT","TEACHER"]',  'TENANT', 'Roles permitted to access Studybuddy AI feature'),
        (v_tenant_id, 'AI', 'ai.essay_eval_enabled',     'true',                   'TENANT', 'AI-assisted essay evaluation enabled for teachers')
    ON CONFLICT (tenant_id, setting_key, scope_level, scope_ref_id) DO NOTHING;

    RAISE NOTICE '  ✓ AI governance settings seeded (7 settings in AI category).';
    RAISE NOTICE '';
    RAISE NOTICE 'POINT 9: ✓ COMPLETE — AI model registered with SARP advisory bounds.';
END $$;


-- =============================================================================
-- COMMIT
-- =============================================================================
COMMIT;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '████████████████████████████████████████████████████████████';
    RAISE NOTICE '  PHASE B — INSTITUTIONAL CONFIGURATION COMPLETE            ';
    RAISE NOTICE '                                                            ';
    RAISE NOTICE '  ✓ Point 4  Academic structure: Board, Classes, Subjects   ';
    RAISE NOTICE '  ✓ Point 5  Role bindings on all ADMISSION_PROC edges      ';
    RAISE NOTICE '  ✓ Point 6  Workflows activated                            ';
    RAISE NOTICE '  ✓ Point 7  5 policies configured (CBSE default preset)   ';
    RAISE NOTICE '  ✓ Point 8  28 system settings seeded across 4 categories ';
    RAISE NOTICE '  ✓ Point 9  AI model registered with advisory-only bounds  ';
    RAISE NOTICE '                                                            ';
    RAISE NOTICE '  NEXT: Run db/22_phase_c_governance_drills.sql             ';
    RAISE NOTICE '        Then conduct Point 15 admin training session.       ';
    RAISE NOTICE '████████████████████████████████████████████████████████████';
END $$;


-- =============================================================================
-- PHASE B VERIFICATION QUERIES
-- =============================================================================
/*
-- [BVQ-1] Confirm all 6 entity types are registered
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT entity_code, display_name, entity_type
FROM entity_master
WHERE tenant_id = current_setting('app.tenant_id',TRUE)::UUID
ORDER BY entity_type, entity_code;

-- [BVQ-2] Confirm academic records were created
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT
    em.entity_code,
    COUNT(er.record_id) AS record_count
FROM entity_records er
JOIN entity_master em ON em.entity_id = er.entity_id AND em.tenant_id = er.tenant_id
WHERE er.tenant_id = current_setting('app.tenant_id',TRUE)::UUID
  AND em.entity_code IN ('BOARD','CLASS','SECTION','SUBJECT','BATCH')
GROUP BY em.entity_code ORDER BY em.entity_code;
-- Expected: BOARD=1, CLASS=9, SECTION=2, SUBJECT=12, BATCH=1

-- [BVQ-3] Confirm role bindings on workflow transitions
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT from_state, to_state, actor_roles
FROM workflow_transitions wt
JOIN workflow_master wm ON wm.workflow_id = wt.workflow_id
WHERE wm.tenant_id = current_setting('app.tenant_id',TRUE)::UUID
  AND wm.workflow_code = 'ADMISSION_PROC'
ORDER BY from_state;

-- [BVQ-4] Confirm all 5 policies are active
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT policy_code, display_name, is_active, evaluation_order
FROM policy_master
WHERE tenant_id = current_setting('app.tenant_id',TRUE)::UUID
ORDER BY evaluation_order;

-- [BVQ-5] Confirm 28 system settings seeded
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT setting_category, COUNT(*) AS count
FROM system_settings
WHERE tenant_id = current_setting('app.tenant_id',TRUE)::UUID
GROUP BY setting_category ORDER BY setting_category;

-- [BVQ-6] Confirm AI model is registered and active
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT model_code, provider, is_default, is_active,
       sarp_advisory_bounds->>'human_in_the_loop_required' AS human_required,
       sarp_advisory_bounds->>'can_initiate_workflow_transitions' AS can_transition
FROM ai_model_registry
WHERE tenant_id = current_setting('app.tenant_id',TRUE)::UUID;
-- Expected: human_required='true', can_transition='false'
*/
