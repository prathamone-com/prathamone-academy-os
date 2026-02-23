-- =============================================================================
-- SEED: Studybuddy AI Metadata Registry
-- =============================================================================

BEGIN;

SET LOCAL app.tenant_id = '00000000-0000-0000-0000-000000000001';

-- 1. Register AI Capability (LAW SB-1)
INSERT INTO ai_capability_master (tenant_id, capability_code, display_name, decision_scope)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'STUDENT_STUDY_BUDDY',
    'AI Studybuddy',
    'ASSISTIVE'
) ON CONFLICT (tenant_id, capability_code) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    decision_scope = EXCLUDED.decision_scope;

-- Get the capability_id
DO $$
DECLARE
    v_cap_id UUID;
    v_tenant_id UUID := '00000000-0000-0000-0000-000000000001';
    v_menu_id   UUID;
BEGIN
    SELECT menu_id INTO v_menu_id FROM menu_master WHERE menu_code = 'SIDEBAR_NAV' AND tenant_id IS NULL;
    SELECT capability_id INTO v_cap_id FROM ai_capability_master
    WHERE capability_code = 'STUDENT_STUDY_BUDDY' AND tenant_id = v_tenant_id;

    -- 2. Configure Role Access (LAW SB-2)
    INSERT INTO ai_role_access (tenant_id, capability_id, role_code, access_level)
    VALUES (v_tenant_id, v_cap_id, 'STUDENT', 'INTERACT')
    ON CONFLICT DO NOTHING; -- No conflict on ARA but we can use DO NOTHING for seeds

    -- 3. Deploy via Menu Engine (LAW 11 & SB-6)
    -- Add AI Studybuddy to SIDEBAR_NAV
    INSERT INTO menu_items (tenant_id, menu_id, label, icon_name, route_path, action_type, required_roles, sort_order)
    VALUES (
        v_tenant_id,
        v_menu_id,
        'AI Studybuddy',
        'Sparkles', -- Lucid icon Sparkles is common for AI
        '/ai/studybuddy',
        'ROUTE',
        '{STUDENT}',
        25 -- Placed between Exams and Settings
    ) ON CONFLICT DO NOTHING;

END $$;

COMMIT;
