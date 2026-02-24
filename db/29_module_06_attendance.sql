-- =============================================================================
-- 29_module_06_attendance.sql
-- Module 06 : Attendance Management
-- =============================================================================
-- LAW 1: All domain data are entities.
-- LAW 8: Audit logs are INSERT-ONLY.
-- =============================================================================

DO $$
DECLARE
    v_tenant_id  UUID := '00000000-0000-0000-0000-000000000001';
    v_entity_id  UUID;
    v_wf_id      UUID;
BEGIN
    -- 1. Register Entity (LAW 1)
    INSERT INTO entity_master (tenant_id, entity_type, entity_code, display_name, description)
    VALUES (v_tenant_id, 'ACADEMIC', 'ATTENDANCE_RECORD', 'Attendance Record', 'Individual student daily attendance entry')
    ON CONFLICT (tenant_id, entity_code) DO NOTHING;

    SELECT entity_id INTO v_entity_id FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'ATTENDANCE_RECORD';

    -- 2. Register Attributes (LAW 2)
    INSERT INTO attribute_master (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_entity_id, 'student_record_id', 'Student Record ID', 'uuid', TRUE,  TRUE,  10),
        (v_tenant_id, v_entity_id, 'attendance_date',   'Attendance Date',   'date', TRUE,  TRUE,  20),
        (v_tenant_id, v_entity_id, 'status',            'Status',            'text', TRUE,  TRUE,  30),
        -- Status values: PRESENT | ABSENT | LATE | EXCUSED
        (v_tenant_id, v_entity_id, 'remarks',           'Remarks',           'text', FALSE, FALSE, 40)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    -- 3. Register Workflow (LAW 3)
    INSERT INTO workflow_master (tenant_id, workflow_code, display_name, entity_id, initial_state, is_active)
    VALUES (v_tenant_id, 'DAILY_MARKING', 'Daily Attendance Marking', v_entity_id, 'DRAFT', TRUE)
    ON CONFLICT (tenant_id, workflow_code) DO NOTHING
    RETURNING workflow_id INTO v_wf_id;

    IF v_wf_id IS NULL THEN
        SELECT workflow_id INTO v_wf_id FROM workflow_master WHERE tenant_id = v_tenant_id AND workflow_code = 'DAILY_MARKING';
    END IF;

    -- Workflow States
    INSERT INTO workflow_states (tenant_id, workflow_id, state_code, display_label, state_type, ui_color)
    VALUES
        (v_tenant_id, v_wf_id, 'DRAFT',    'Draft',    'initial',      '#94a3b8'),
        (v_tenant_id, v_wf_id, 'MARKED',   'Marked',   'intermediate', '#10b981'),
        (v_tenant_id, v_wf_id, 'VERIFIED', 'Verified', 'terminal',     '#0ea5e9')
    ON CONFLICT (tenant_id, workflow_id, state_code) DO NOTHING;

    -- Workflow Transitions
    INSERT INTO workflow_transitions (tenant_id, workflow_id, from_state, to_state, trigger_event, display_label, actor_roles)
    VALUES
        (v_tenant_id, v_wf_id, NULL,    'DRAFT',    'START',   'Initialise', ARRAY['TEACHER', 'ADMIN']),
        (v_tenant_id, v_wf_id, 'DRAFT', 'MARKED',   'SUBMIT',  'Finalise',   ARRAY['TEACHER', 'ADMIN']),
        (v_tenant_id, v_wf_id, 'MARKED','VERIFIED', 'APPROVE', 'Verify',     ARRAY['ADMIN', 'TENANT_ADMIN'])
    ON CONFLICT DO NOTHING;

    -- 4. Register Menu Item (LAW 11)
    INSERT INTO menu_items (tenant_id, menu_id, label, icon_name, route_path, action_type, action_target, required_roles, sort_order)
    SELECT v_tenant_id, menu_id, 'Attendance', 'CalendarCheck', '/attendance/mark', 'ROUTE', 'ATTENDANCE_MARKER', ARRAY['ADMIN','TENANT_ADMIN','TEACHER'], 25
    FROM menu_master WHERE menu_code = 'SIDEBAR_NAV'
    ON CONFLICT (tenant_id, menu_id, label) DO NOTHING;

    RAISE NOTICE 'Attendance Management Module Seeded.';
END $$;
