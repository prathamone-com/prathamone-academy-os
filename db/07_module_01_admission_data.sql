-- =============================================================================
-- PRATHAMONE ACADEMY OS — MODULE 01: ADMISSION SEED DATA
-- Purpose: Seeds the kernel with Admission entities, attributes, workflows,
--          policies, forms, and reports.
-- LAW 11: No new tables. Everything is data in the existing kernel.
-- =============================================================================

DO $$
DECLARE
    v_tenant_id     UUID;
    v_entity_app_id UUID;
    v_entity_stu_id UUID;
    v_workflow_id   UUID;
    v_sec_personal  UUID;
    v_sec_academic  UUID;
    v_form_app_id   UUID;
    v_report_app_id UUID;
BEGIN
    -- 1. Resolve or Create Tenant
    -- For development seeding, we target the first tenant or a demo tenant.
    -- Prefer the standard demo tenant ID if it exists, otherwise pick first
    SELECT tenant_id INTO v_tenant_id 
    FROM tenants 
    WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

    IF v_tenant_id IS NULL THEN
        SELECT tenant_id INTO v_tenant_id FROM tenants LIMIT 1;
    END IF;
    
    IF v_tenant_id IS NULL THEN
        v_tenant_id := '00000000-0000-0000-0000-000000000001'::UUID;
        INSERT INTO tenants (tenant_id, name, slug)
        VALUES (v_tenant_id, 'PrathamOne International School', 'demo-prathamone-intl')
        ON CONFLICT (tenant_id) DO NOTHING;
    END IF;

    -- 2. Register Entities (LAW 1)
    INSERT INTO entity_master (tenant_id, entity_type, entity_code, display_name, description)
    VALUES 
        (v_tenant_id, 'ADMISSION', 'STUDENT_APPLICATION', 'Student Application', 'Initial application for admission'),
        (v_tenant_id, 'ACADEMIC',  'STUDENT',             'Student',             'Registered student record')
    ON CONFLICT (tenant_id, entity_code) DO NOTHING;

    -- Note: Retunning inside a loop or multi-insert is tricky in PL/pgSQL for multiple vars.
    -- Better to fetch them individually for clarity.
    SELECT entity_id INTO v_entity_app_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'STUDENT_APPLICATION';
    SELECT entity_id INTO v_entity_stu_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'STUDENT';

    -- 3. Define Attributes (LAW 2)
    INSERT INTO attribute_master (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, sort_order)
    VALUES
        (v_tenant_id, v_entity_app_id, 'applicant_name',    'Applicant Name',     'text',    TRUE,  10),
        (v_tenant_id, v_entity_app_id, 'date_of_birth',     'Date of Birth',      'date',    TRUE,  20),
        (v_tenant_id, v_entity_app_id, 'class_applied',     'Class Applied',      'text',    TRUE,  30),
        (v_tenant_id, v_entity_app_id, 'guardian_name',     'Guardian Name',      'text',    TRUE,  40),
        (v_tenant_id, v_entity_app_id, 'previous_school',   'Previous School',    'text',    FALSE, 50),
        (v_tenant_id, v_entity_app_id, 'entrance_score',    'Entrance Score',     'number',  FALSE, 60),
        (v_tenant_id, v_entity_app_id, 'admission_category', 'Admission Category', 'text',    TRUE,  70);

    -- Add validation for Admission Category via JSON Logic (LAW 9 / Rules Engine)
    UPDATE attribute_master 
    SET validation_rule = '{"in": [{"var": "admission_category"}, ["GENERAL", "OBC", "SC", "ST", "SPORTS", "MANAGEMENT"]]}'
    WHERE tenant_id = v_tenant_id AND attribute_code = 'admission_category';

    -- 4. Define Workflow (LAW 3, 5)
    INSERT INTO workflow_master (tenant_id, workflow_code, display_name, entity_id, initial_state)
    VALUES (v_tenant_id, 'ADMISSION_PROC', 'Admission Process', v_entity_app_id, 'DRAFT')
    RETURNING workflow_id INTO v_workflow_id;

    -- States
    INSERT INTO workflow_states (tenant_id, workflow_id, state_code, display_label, state_type, ui_color)
    VALUES
        (v_tenant_id, v_workflow_id, 'DRAFT',               'Draft',               'initial',      '#94a3b8'),
        (v_tenant_id, v_workflow_id, 'SUBMITTED',           'Submitted',           'intermediate', '#3b82f6'),
        (v_tenant_id, v_workflow_id, 'DOCUMENT_VERIFIED',   'Document Verified',   'intermediate', '#0ea5e9'),
        (v_tenant_id, v_workflow_id, 'ENTRANCE_SCHEDULED',  'Entrance Scheduled',  'intermediate', '#8b5cf6'),
        (v_tenant_id, v_workflow_id, 'ENTRANCE_COMPLETED',  'Entrance Completed',  'intermediate', '#a855f7'),
        (v_tenant_id, v_workflow_id, 'SELECTION_REVIEW',    'Selection Review',    'intermediate', '#f59e0b'),
        (v_tenant_id, v_workflow_id, 'OFFER_ISSUED',        'Offer Issued',        'intermediate', '#10b981'),
        (v_tenant_id, v_workflow_id, 'FEE_PAID',            'Fee Paid',            'intermediate', '#059669'),
        (v_tenant_id, v_workflow_id, 'ENROLLED',            'Enrolled',            'terminal',     '#16a34a'),
        (v_tenant_id, v_workflow_id, 'REJECTED',            'Rejected',            'terminal',     '#dc2626'),
        (v_tenant_id, v_workflow_id, 'WITHDRAWN',           'Withdrawn',           'terminal',     '#4b5563');

    -- Transitions
    INSERT INTO workflow_transitions (tenant_id, workflow_id, from_state, to_state, trigger_event, display_label, actor_roles)
    VALUES
        (v_tenant_id, v_workflow_id, NULL,                  'DRAFT',               'START',            'Initialise',         '{SYSTEM, ADMIN}'),
        (v_tenant_id, v_workflow_id, 'DRAFT',               'SUBMITTED',           'SUBMIT',           'Submit Application', '{APPLICANT, ADMIN}'),
        (v_tenant_id, v_workflow_id, 'SUBMITTED',           'DOCUMENT_VERIFIED',   'VERIFY_DOCS',      'Verify Documents',   '{ADMIN, ADMISSION_OFFICER}'),
        (v_tenant_id, v_workflow_id, 'DOCUMENT_VERIFIED',   'ENTRANCE_SCHEDULED',  'SCHEDULE_TEST',    'Schedule Entrance',  '{ADMISSION_OFFICER}'),
        (v_tenant_id, v_workflow_id, 'ENTRANCE_SCHEDULED',  'ENTRANCE_COMPLETED',  'RECORD_SCORE',     'Record Score',       '{EXAMINER}'),
        (v_tenant_id, v_workflow_id, 'ENTRANCE_COMPLETED',  'SELECTION_REVIEW',    'MOVE_TO_REVIEW',   'Move to Review',     '{ADMISSION_OFFICER}'),
        (v_tenant_id, v_workflow_id, 'SELECTION_REVIEW',    'OFFER_ISSUED',        'ISSUE_OFFER',      'Issue Letter',       '{ADMISSION_HEAD}'),
        (v_tenant_id, v_workflow_id, 'OFFER_ISSUED',        'FEE_PAID',            'PAY_FEE',          'Pay Admission Fee',  '{APPLICANT}'),
        (v_tenant_id, v_workflow_id, 'FEE_PAID',            'ENROLLED',            'ENROLL',           'Confirm Enrollment', '{ADMIN}'),
        -- Universal rejections/withdrawals
        (v_tenant_id, v_workflow_id, 'SUBMITTED',           'REJECTED',            'REJECT',           'Reject',             '{ADMISSION_OFFICER}'),
        (v_tenant_id, v_workflow_id, 'OFFER_ISSUED',        'WITHDRAWN',           'WITHDRAW',         'Withdraw',           '{APPLICANT}');

    -- 5. Define Policies (LAW 4, 5)
    INSERT INTO policy_master (tenant_id, policy_code, display_name, entity_id, rule_definition)
    VALUES
        (v_tenant_id, 'AGE_ELIGIBILITY',      'Age Eligibility Check',      v_entity_app_id, '{"diff_years": [{"var": "date_of_birth"}, "now"] }'), 
        (v_tenant_id, 'ENTRANCE_SCORE_MINIMUM', 'Minimum Entrance Score',    v_entity_app_id, '{"gte": [{"var": "entrance_score"}, 40]}'),
        (v_tenant_id, 'SEAT_CAPACITY',        'Seat Capacity Check',       v_entity_app_id, '{"true": []}'), 
        (v_tenant_id, 'FEE_PAYMENT_DEADLINE', 'Payment Deadline Validity', v_entity_app_id, '{"true": []}');

    -- 6. Forms (LAW 11)
    INSERT INTO form_master (tenant_id, form_code, display_name, entity_id, workflow_id)
    VALUES 
        (v_tenant_id, 'ADMISSION_APP_FORM',     'Admission Application Form', v_entity_app_id, v_workflow_id),
        (v_tenant_id, 'DOC_VERIFICATION_FORM', 'Document Verification Form', v_entity_app_id, v_workflow_id),
        (v_tenant_id, 'ACADEMIC_REVIEW_FORM',   'Academic Review Form',      v_entity_app_id, v_workflow_id),
        (v_tenant_id, 'ENROLLMENT_FORM',        'Enrollment Form',           v_entity_app_id, v_workflow_id);
    
    -- Explicitly fetch ID for the application form to bind sections
    SELECT form_id INTO v_form_app_id FROM form_master WHERE tenant_id = v_tenant_id AND form_code = 'ADMISSION_APP_FORM';

    INSERT INTO form_sections (tenant_id, form_id, section_code, display_label, sort_order)
    VALUES
        (v_tenant_id, v_form_app_id, 'PERSONAL', 'Personal Information', 10),
        (v_tenant_id, v_form_app_id, 'ACADEMIC', 'Academic History',     20);
    
    -- Re-fetch section IDs
    SELECT section_id INTO v_sec_personal FROM form_sections WHERE form_id = v_form_app_id AND section_code = 'PERSONAL';
    SELECT section_id INTO v_sec_academic FROM form_sections WHERE form_id = v_form_app_id AND section_code = 'ACADEMIC';

    -- Form Fields
    INSERT INTO form_fields (tenant_id, section_id, attribute_id, widget_type, sort_order)
    SELECT v_tenant_id, v_sec_personal, attribute_id, 'text_input', sort_order
    FROM attribute_master WHERE entity_id = v_entity_app_id AND attribute_code IN ('applicant_name', 'guardian_name');

    INSERT INTO form_fields (tenant_id, section_id, attribute_id, widget_type, sort_order)
    SELECT v_tenant_id, v_sec_personal, attribute_id, 'date_picker', sort_order
    FROM attribute_master WHERE entity_id = v_entity_app_id AND attribute_code = 'date_of_birth';

    INSERT INTO form_fields (tenant_id, section_id, attribute_id, widget_type, sort_order)
    SELECT v_tenant_id, v_sec_personal, attribute_id, 'select', sort_order
    FROM attribute_master WHERE entity_id = v_entity_app_id AND attribute_code = 'admission_category';

    -- 7. Reports (LAW 9)
    INSERT INTO report_master (tenant_id, report_code, display_name, report_category, primary_entity_id, report_query_type)
    VALUES
        (v_tenant_id, 'admission.app_by_class', 'Applications by Class', 'OPERATIONS', v_entity_app_id, 'AGGREGATE'),
        (v_tenant_id, 'admission.funnel',       'Conversion Funnel',     'OPERATIONS', v_entity_app_id, 'FUNNEL'),
        (v_tenant_id, 'admission.board_intake', 'Board-wise Intake',    'OPERATIONS', v_entity_app_id, 'AGGREGATE');

    -- Re-fetch for dimension seeding
    SELECT report_id INTO v_report_app_id FROM report_master WHERE tenant_id = v_tenant_id AND report_code = 'admission.app_by_class';

    INSERT INTO report_dimensions (tenant_id, report_id, attribute_id, display_label, sort_order)
    SELECT v_tenant_id, v_report_app_id, attribute_id, 'Class Name', 10
    FROM attribute_master WHERE entity_id = v_entity_app_id AND attribute_code = 'class_applied';

    INSERT INTO report_measures (tenant_id, report_id, measure_source, aggregate_fn, display_label)
    VALUES (v_tenant_id, v_report_app_id, 'RECORD_COUNT', 'COUNT', 'Total Applications');

END $$;
