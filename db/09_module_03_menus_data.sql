-- =============================================================================
-- PRATHAMONE ACADEMY OS — SEEDING DATA
-- Module 03 : App Shell & Menus
-- =============================================================================
-- LAW 11: Application layout is data.
-- =============================================================================

DO $$
DECLARE
    v_tenant_id  UUID := '00000000-0000-0000-0000-000000000000'; -- SYSTEM tenant
    v_menu_id    UUID;
BEGIN
    -- 1. Create Main Sidebar Menu
    INSERT INTO menu_master (tenant_id, menu_code, display_name)
    VALUES (NULL, 'SIDEBAR_NAV', 'Main Navigation')
    ON CONFLICT (tenant_id, menu_code) DO UPDATE SET display_name = EXCLUDED.display_name
    RETURNING menu_id INTO v_menu_id;

    -- 2. Create Menu Items
    INSERT INTO menu_items (tenant_id, menu_id, label, icon_name, route_path, action_type, action_target, required_roles, sort_order)
    VALUES
        -- Admissions
        (NULL, v_menu_id, 'Admission App', 'FileText', '/admissions/apply', 'FORM',   'ADMISSION_APP_FORM', '{ADMIN, TENANT_ADMIN, ADMISSION_OFFICIAL, STUDENT}', 10),
        (NULL, v_menu_id, 'Admission Funnel', 'BarChart3',  '/reports/admissions/funnel', 'REPORT', 'admission.funnel', '{ADMIN, TENANT_ADMIN, ADMISSION_OFFICIAL}', 20),
        
        -- Exams
        (NULL, v_menu_id, 'Ranklist', 'Trophy', '/reports/exams/ranklist', 'REPORT', 'exams.class_ranklist', '{ADMIN, TENANT_ADMIN, TEACHER, STUDENT}', 30),
        (NULL, v_menu_id, 'Marks Dist.', 'PieChart', '/reports/exams/marks', 'REPORT', 'exams.marks_distribution', '{ADMIN, TENANT_ADMIN, TEACHER}', 40),
        
        -- System
        (NULL, v_menu_id, 'Settings', 'Settings', '/settings', 'ROUTE', NULL, '{ADMIN, TENANT_ADMIN}', 100)
    ON CONFLICT (tenant_id, menu_id, label) 
    DO UPDATE SET 
        required_roles = EXCLUDED.required_roles,
        icon_name = EXCLUDED.icon_name,
        route_path = EXCLUDED.route_path;

END $$;
