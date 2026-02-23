-- =============================================================================
-- PRATHAMONE ACADEMY OS — MODULE 02: EXAMS SEED DATA
-- Purpose: Seeds the kernel with Exam entities, attributes, workflows,
--          policies, system settings, and reports.
-- LAW 10: Derived data (grades, ranks, pass/fail) is NEVER stored.
-- =============================================================================

DO $$
DECLARE
    v_tenant_id     UUID;
    v_entity_exam_id UUID;
    v_entity_comp_id UUID;
    v_entity_att_id  UUID;
    v_workflow_id    UUID;
BEGIN
    -- 1. Resolve Tenant (Prefer demo tenant)
    SELECT tenant_id INTO v_tenant_id FROM tenants WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    IF v_tenant_id IS NULL THEN
        SELECT tenant_id INTO v_tenant_id FROM tenants LIMIT 1;
    END IF;
    
    -- 2. Register Entities (LAW 1)
    INSERT INTO entity_master (tenant_id, entity_type, entity_code, display_name, description)
    VALUES 
        (v_tenant_id, 'ACADEMIC', 'EXAM',                  'Exam Definition',       'General exam configuration'),
        (v_tenant_id, 'ACADEMIC', 'EXAM_SCORE_COMPONENT', 'Exam Score Component', 'Sub-parts of an exam (Theory, Practical)'),
        (v_tenant_id, 'ACADEMIC', 'EXAM_ATTEMPT',         'Exam Attempt',         'Individual student exam attempt')
    ON CONFLICT (tenant_id, entity_code) DO NOTHING;

    SELECT entity_id INTO v_entity_exam_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'EXAM';
    SELECT entity_id INTO v_entity_comp_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'EXAM_SCORE_COMPONENT';
    SELECT entity_id INTO v_entity_att_id  FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'EXAM_ATTEMPT';

    -- 3. Define Attributes for EXAM_ATTEMPT (LAW 2)
    INSERT INTO attribute_master (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, sort_order)
    VALUES
        (v_tenant_id, v_entity_att_id, 'exam_reference',       'Exam Ref',             'text',    TRUE,  10),
        (v_tenant_id, v_entity_att_id, 'student_reference',    'Student Ref',          'text',    TRUE,  20),
        (v_tenant_id, v_entity_att_id, 'attempt_date',         'Attempt Date',         'date',    TRUE,  30),
        (v_tenant_id, v_entity_att_id, 'total_marks_obtained', 'Total Marks Obtained', 'number',  FALSE, 40),
        (v_tenant_id, v_entity_att_id, 'is_grace_applied',     'Is Grace Applied',     'boolean', FALSE, 50),
        (v_tenant_id, v_entity_att_id, 'grace_marks_applied',  'Grace Marks Applied',  'number',  FALSE, 60)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    -- 4. Define Workflow (LAW 3, 5)
    INSERT INTO workflow_master (tenant_id, workflow_code, display_name, entity_id, initial_state)
    VALUES (v_tenant_id, 'EXAM_LIFECYCLE', 'Exam Lifecycle', v_entity_exam_id, 'DRAFT')
    ON CONFLICT (tenant_id, workflow_code) DO UPDATE SET display_name = EXCLUDED.display_name
    RETURNING workflow_id INTO v_workflow_id;

    -- States
    INSERT INTO workflow_states (tenant_id, workflow_id, state_code, display_label, state_type, ui_color)
    VALUES
        (v_tenant_id, v_workflow_id, 'DRAFT',              'Draft',              'initial',      '#94a3b8'),
        (v_tenant_id, v_workflow_id, 'SCHEDULED',          'Scheduled',          'intermediate', '#3b82f6'),
        (v_tenant_id, v_workflow_id, 'ACTIVE',             'Active',             'intermediate', '#ef4444'),
        (v_tenant_id, v_workflow_id, 'EVALUATION',         'Evaluation',         'intermediate', '#f59e0b'),
        (v_tenant_id, v_workflow_id, 'MODERATION_REVIEW',  'Moderation Review',  'intermediate', '#8b5cf6'),
        (v_tenant_id, v_workflow_id, 'PUBLISHED',          'Published',          'intermediate', '#10b981'),
        (v_tenant_id, v_workflow_id, 'RECHECK_REQUESTED',  'Recheck Requested',  'intermediate', '#f97316'),
        (v_tenant_id, v_workflow_id, 'RECHECK_COMPLETED',  'Recheck Completed',  'intermediate', '#06b6d4'),
        (v_tenant_id, v_workflow_id, 'FINAL',              'Final',              'terminal',     '#16a34a')
    ON CONFLICT (tenant_id, workflow_id, state_code) DO NOTHING;

    -- Transitions
    INSERT INTO workflow_transitions (tenant_id, workflow_id, from_state, to_state, trigger_event, display_label, actor_roles)
    VALUES
        (v_tenant_id, v_workflow_id, 'DRAFT',              'SCHEDULED',          'SCHEDULE',         'Schedule Exam',   '{ADMIN, EXAM_CELL}'),
        (v_tenant_id, v_workflow_id, 'SCHEDULED',          'ACTIVE',             'START',            'Start Exam',      '{SYSTEM, ADMIN}'),
        (v_tenant_id, v_workflow_id, 'ACTIVE',             'EVALUATION',         'END',              'Finish & Collect', '{SYSTEM, ADMIN}'),
        (v_tenant_id, v_workflow_id, 'EVALUATION',         'MODERATION_REVIEW',  'SUBMIT_SCORES',    'Submit for Moderation', '{EVALUATOR}'),
        (v_tenant_id, v_workflow_id, 'MODERATION_REVIEW',  'PUBLISHED',          'PUBLISH',          'Publish Results', '{MODERATOR, ADMIN}'),
        (v_tenant_id, v_workflow_id, 'PUBLISHED',          'RECHECK_REQUESTED',  'REQUEST_RECHECK',  'Request Recheck', '{STUDENT}'),
        (v_tenant_id, v_workflow_id, 'RECHECK_REQUESTED',  'RECHECK_COMPLETED',  'COMPLETE_RECHECK', 'Complete Recheck', '{MODERATOR}'),
        (v_tenant_id, v_workflow_id, 'RECHECK_COMPLETED',  'PUBLISHED',          'RE_PUBLISH',       'Re-Publish Results', '{MODERATOR}'),
        (v_tenant_id, v_workflow_id, 'PUBLISHED',          'FINAL',              'LOCK',             'Finalise & Lock', '{ADMIN}')
    ON CONFLICT DO NOTHING;

    -- 5. System Settings (LAW 12)
    INSERT INTO system_settings (tenant_id, setting_category, setting_key, setting_value, scope_level, description)
    VALUES
        (v_tenant_id, 'ACADEMIC', 'DEFAULT_GRADING_SCALE', '"CBSE_10"',      'TENANT', 'Default scale for grade mapping'),
        (v_tenant_id, 'ACADEMIC', 'TOTAL_PASS_THRESHOLD',  '35',             'TENANT', 'Minimum percentage to pass'),
        (v_tenant_id, 'ACADEMIC', 'GRACE_MARKS_LIMIT',     '5',              'TENANT', 'Maximum grace marks allowed per exam')
    ON CONFLICT (tenant_id, setting_key, scope_level, scope_ref_id) DO UPDATE SET setting_value = EXCLUDED.setting_value;

    -- 6. Define Policies (LAW 4, 10)
    INSERT INTO policy_master (tenant_id, policy_code, display_name, entity_id, rule_definition)
    VALUES
        (v_tenant_id, 'GRADE_MAPPING',     'Calculate Grade',    v_entity_att_id, '{"method": "lookup_setting", "key": "GRADING_SCALE"}'),
        (v_tenant_id, 'PASS_THRESHOLD',    'Pass/Fail Check',    v_entity_att_id, '{"gte": [{"var": "total_marks_obtained"}, {"setting": "TOTAL_PASS_THRESHOLD"}]}'),
        (v_tenant_id, 'EXAM_ELIGIBILITY',  'Attendance Check',   v_entity_att_id, '{"gte": [{"var": "attendance_pct"}, 75]}')
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    -- 7. Reports (LAW 9)
    INSERT INTO report_master (tenant_id, report_code, display_name, report_category, primary_entity_id, report_query_type)
    VALUES
        (v_tenant_id, 'exams.class_ranklist',     'Class Ranklist',            'ACADEMIC', v_entity_att_id, 'AGGREGATE'),
        (v_tenant_id, 'exams.marks_distribution', 'Subject Marks Distribution', 'ACADEMIC', v_entity_att_id, 'AGGREGATE'),
        (v_tenant_id, 'exams.pass_percentage',    'Exam Pass Percentage',      'ACADEMIC', v_entity_att_id, 'AGGREGATE'),
        (v_tenant_id, 'exams.grade_distribution', 'Grade Distribution',        'ACADEMIC', v_entity_att_id, 'AGGREGATE'),
        (v_tenant_id, 'exams.board_compliance',   'Board Compliance Export',   'COMPLIANCE', v_entity_att_id, 'DETAIL')
    ON CONFLICT (tenant_id, report_code) DO NOTHING;

    -- Dimensions and Measures for Ranklist
    INSERT INTO report_measures (tenant_id, report_id, attribute_id, measure_source, aggregate_fn, display_label)
    SELECT v_tenant_id, r.report_id, a.attribute_id, 'ATTRIBUTE', 'SUM', 'Total Score'
    FROM report_master r
    JOIN attribute_master a ON a.tenant_id = r.tenant_id AND a.attribute_code = 'total_marks_obtained'
    WHERE r.tenant_id = v_tenant_id AND r.report_code = 'exams.class_ranklist';

END $$;
