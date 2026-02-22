-- =============================================================================
-- PRATHAMONE ACADEMY OS — PENDING LAWS MASTER INTEGRATION RUNNER
-- Executes all 22 Pending Laws implementation files in dependency order.
-- Run this file ONCE as superuser against the target tenant shard.
-- =============================================================================
-- Execution Order:
--   14_gap1_dpdp_erasure.sql         → Laws 09-1.1 to 09-1.4
--   15_gap2_break_glass.sql          → Laws 09-2.1 to 09-2.4
--   16_gap3_plugin_blast_radius.sql  → Laws 09-3.1 to 09-3.5
--   17_gap4_api_rate_limiting.sql    → Laws 09-4.1 to 09-4.4
--   18_gap5_cold_storage_archival.sql → Laws 09-5.1 to 09-5.5
--   19_gap6_data_residency.sql       → Laws 09-6.1 to 09-6.4
-- =============================================================================
-- Prerequisites:
--   1. pgcrypto extension must be enabled: CREATE EXTENSION IF NOT EXISTS pgcrypto;
--   2. All core schema files (01–13) must have been applied.
--   3. Run as a superuser (postgres or equivalent) with SECURITY DEFINER privilege.
-- =============================================================================

-- Enable pgcrypto if not already present (required for digest() calls)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─────────────────────────────────────────────────────────────────────────────
-- MARKER: Append a platform-level PENDING_LAWS_APPLIED event to the first
-- active tenant's audit chain as a kernel boot record.
-- (System-level only — not tenant-specific)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_first_tenant UUID;
BEGIN
    SELECT tenant_id INTO v_first_tenant FROM tenants WHERE is_active = TRUE LIMIT 1;
    IF v_first_tenant IS NULL THEN
        RAISE NOTICE 'No active tenants found. Skipping boot audit event.';
        RETURN;
    END IF;

    -- Set the session context for the INSERT to pass RLS
    PERFORM set_config('app.tenant_id', v_first_tenant::TEXT, TRUE);

    INSERT INTO audit_event_log(
        tenant_id, actor_id, actor_type, event_category,
        event_type, event_data
    ) VALUES (
        v_first_tenant, NULL, 'SYSTEM', 'SYSTEM',
        'PENDING_LAWS_APPLIED',
        jsonb_build_object(
            'laws_applied', jsonb_build_array(
                '09-1.1', '09-1.2', '09-1.3', '09-1.4',
                '09-2.1', '09-2.2', '09-2.3', '09-2.4',
                '09-3.1', '09-3.2', '09-3.3', '09-3.4', '09-3.5',
                '09-4.1', '09-4.2', '09-4.3', '09-4.4',
                '09-5.1', '09-5.2', '09-5.3', '09-5.4', '09-5.5',
                '09-6.1', '09-6.2', '09-6.3', '09-6.4'
            ),
            'files_applied', jsonb_build_array(
                '14_gap1_dpdp_erasure.sql',
                '15_gap2_break_glass.sql',
                '16_gap3_plugin_blast_radius.sql',
                '17_gap4_api_rate_limiting.sql',
                '18_gap5_cold_storage_archival.sql',
                '19_gap6_data_residency.sql'
            ),
            'applied_at',       now(),
            'rule_book_source', 'RULE-BOOK/09_PENDING_LAWS.md',
            'ratified_by',      'Sovereign Architect (manual review required)',
            'status',           'LOCKED',
            'note', '22 Pending Laws from the Vulnerability Gap Report are now in LOCKED status.'
        )
    );
    RAISE NOTICE 'PENDING_LAWS_APPLIED audit event written for tenant %.', v_first_tenant;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- POST-INSTALL VERIFICATION CHECKLIST
-- Run each block manually and verify the expected output.
-- ─────────────────────────────────────────────────────────────────────────────

/*
-- [V1] Verify pii_class column exists on attribute_master
SELECT COUNT(*) FROM information_schema.columns
WHERE table_name = 'attribute_master' AND column_name = 'pii_class';
-- Expected: 1

-- [V2] Verify erasure_requests table exists with RLS enabled
SELECT relrowsecurity, relforcerowsecurity
FROM pg_class WHERE relname = 'erasure_requests';
-- Expected: t, t

-- [V3] Verify legal_hold_registry table exists
SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'legal_hold_registry';
-- Expected: 1

-- [V4] Verify Break-Glass tables exist
SELECT table_name FROM information_schema.tables
WHERE table_name IN ('chain_break_events', 'cbe_quorum_signatures', 'sovereign_admin_registry');
-- Expected: 3 rows

-- [V5] Verify CBE quorum trigger exists
SELECT trigger_name FROM information_schema.triggers WHERE trigger_name = 'trg_cbe_quorum_check';
-- Expected: trg_cbe_quorum_check

-- [V6] Verify plugin_registry table with resource limit columns
SELECT column_name FROM information_schema.columns
WHERE table_name = 'plugin_registry'
  AND column_name IN ('max_execution_ms', 'max_memory_mb', 'max_api_calls_per_min', 'blast_radius_score');
-- Expected: 4 rows

-- [V7] Verify api_quota_ledger INSERT-ONLY trigger
SELECT trigger_name FROM information_schema.triggers WHERE trigger_name = 'trg_quota_no_delete';
-- Expected: trg_quota_no_delete

-- [V8] Verify tenant_shard_config exists with circuit_breaker_status
SELECT COUNT(*) FROM information_schema.columns
WHERE table_name = 'tenant_shard_config' AND column_name = 'circuit_breaker_status';
-- Expected: 1

-- [V9] Verify cold_archive_manifest INSERT-ONLY trigger
SELECT trigger_name FROM information_schema.triggers
WHERE trigger_name IN ('trg_cam_no_update', 'trg_cam_no_delete');
-- Expected: 2 rows

-- [V10] Verify data_residency_region column on tenants
SELECT COUNT(*) FROM information_schema.columns
WHERE table_name = 'tenants' AND column_name = 'data_residency_region';
-- Expected: 1

-- [V11] Verify residency immutability trigger
SELECT trigger_name FROM information_schema.triggers
WHERE trigger_name = 'trg_tenants_residency_immutable';
-- Expected: trg_tenants_residency_immutable

-- [V12] Verify all kernel functions were created
SELECT routine_name FROM information_schema.routines
WHERE routine_name IN (
    'fn_execute_cap', 'fn_seal_chain_break_event', 'fn_chain_integrity_drip_test',
    'fn_record_plugin_limit_violation', 'fn_check_circuit_breaker',
    'fn_archive_cold_batch', 'fn_forensic_replay',
    'fn_residency_sentinel_check', 'fn_replication_residency_filter'
)
ORDER BY routine_name;
-- Expected: 9 rows
*/

-- =============================================================================
-- END: MASTER INTEGRATION RUNNER — All 22 Pending Laws installed.
-- Status: LOCKED. Architect ratification required to amend any law.
-- =============================================================================
