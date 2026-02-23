-- =============================================================================
-- 25_rls_security_hardening.sql
-- LAW 1-LAW 2 COMPLIANCE: Enable RLS on 4 security tables missing isolation
-- Architect: Jawahar R Mallah — PrathamOne Academy OS
-- =============================================================================
-- Referenced laws:
--   L1-LAW-2: Tenant Sovereignty & Isolation — RLS + Session Context (LOCKED)
--   L9-LAW-5: Forensic Audit Spine (Immutability) — all security log tables must
--              be protected by the same isolation layer as the rest of the kernel.

BEGIN;

-- 1. Chain Break Events (Emergency Break-Glass — GAP-2 implementation)
ALTER TABLE chain_break_events       ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_break_events       FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='chain_break_events' AND policyname='cbe_system_admin') THEN
    CREATE POLICY cbe_system_admin ON chain_break_events TO system_admin USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='chain_break_events' AND policyname='cbe_tenant_read') THEN
    CREATE POLICY cbe_tenant_read ON chain_break_events FOR SELECT
      USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
  END IF;
END $$;

-- 2. CBE Quorum Signatures
ALTER TABLE cbe_quorum_signatures    ENABLE ROW LEVEL SECURITY;
ALTER TABLE cbe_quorum_signatures    FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cbe_quorum_signatures' AND policyname='cbeq_system_admin') THEN
    CREATE POLICY cbeq_system_admin ON cbe_quorum_signatures TO system_admin USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cbe_quorum_signatures' AND policyname='cbeq_tenant_read') THEN
    CREATE POLICY cbeq_tenant_read ON cbe_quorum_signatures FOR SELECT
      USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
  END IF;
END $$;

-- 3. Residency Violation Log (Cross-Region Residency — GAP-6 implementation)
ALTER TABLE residency_violation_log  ENABLE ROW LEVEL SECURITY;
ALTER TABLE residency_violation_log  FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='residency_violation_log' AND policyname='rvl_system_admin') THEN
    CREATE POLICY rvl_system_admin ON residency_violation_log TO system_admin USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='residency_violation_log' AND policyname='rvl_tenant_read') THEN
    CREATE POLICY rvl_tenant_read ON residency_violation_log FOR SELECT
      USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
  END IF;
END $$;

-- 4. Sovereign Admin Registry (System-scoped — global, no tenant filter on SELECTs)
ALTER TABLE sovereign_admin_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE sovereign_admin_registry FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sovereign_admin_registry' AND policyname='sar_system_admin') THEN
    CREATE POLICY sar_system_admin ON sovereign_admin_registry TO system_admin USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sovereign_admin_registry' AND policyname='sar_app_read') THEN
    -- Sovereign registry is global, but only TENANT_ADMIN+ can read (enforced in application layer)
    CREATE POLICY sar_app_read ON sovereign_admin_registry FOR SELECT TO app_user USING (true);
  END IF;
END $$;

COMMIT;

-- Verification
SELECT tablename, relrowsecurity::text AS rls_enabled, relforcerowsecurity::text AS rls_forced
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE t.schemaname = 'public'
  AND t.tablename IN ('chain_break_events','cbe_quorum_signatures','residency_violation_log','sovereign_admin_registry')
ORDER BY tablename;
