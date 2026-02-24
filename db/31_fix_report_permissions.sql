-- =============================================================================
-- db/31_fix_report_permissions.sql
-- Grant explicit access to reports per LAW 12.
-- =============================================================================

DO $$
DECLARE
    v_tid UUID := '00000000-0000-0000-0000-000000000001';
    r_rep RECORD;
BEGIN
    RAISE NOTICE 'Granting report permissions for tenant %...', v_tid;

    -- Grant FULL access to TENANT_ADMIN and ADMIN for all seeded reports
    FOR r_rep IN 
        SELECT report_id FROM report_master WHERE tenant_id = v_tid
    LOOP
        -- TENANT_ADMIN
        INSERT INTO report_role_access (tenant_id, report_id, role_code, can_view, can_export)
        VALUES (v_tid, r_rep.report_id, 'TENANT_ADMIN', TRUE, TRUE)
        ON CONFLICT (tenant_id, report_id, role_code) DO UPDATE SET 
            can_view = TRUE, can_export = TRUE;

        -- ADMIN
        INSERT INTO report_role_access (tenant_id, report_id, role_code, can_view, can_export)
        VALUES (v_tid, r_rep.report_id, 'ADMIN', TRUE, TRUE)
        ON CONFLICT (tenant_id, report_id, role_code) DO UPDATE SET 
            can_view = TRUE, can_export = TRUE;
            
        -- TEACHER (view only)
        INSERT INTO report_role_access (tenant_id, report_id, role_code, can_view, can_export)
        VALUES (v_tid, r_rep.report_id, 'TEACHER', TRUE, FALSE)
        ON CONFLICT (tenant_id, report_id, role_code) DO UPDATE SET 
            can_view = TRUE;
    END LOOP;

    RAISE NOTICE 'Report permissions updated.';
END $$;
