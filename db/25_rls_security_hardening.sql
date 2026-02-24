-- =============================================================================
-- 25_rls_security_hardening.sql
-- LAW L1-LAW-2 COMPLIANCE: Enable RLS on 4 security tables missing isolation.
-- Architect: Jawahar R Mallah — PrathamOne Academy OS
-- =============================================================================
-- Referenced laws:
--   L1-LAW-2 : Tenant Sovereignty & Isolation — RLS + Session Context (LOCKED)
--   L9-LAW-5 : Forensic Audit Spine — all security log tables protected by the
--               same isolation layer as the rest of the kernel.
-- NOTE: cbe_quorum_signatures and sovereign_admin_registry are SYSTEM-WIDE tables
-- (no tenant_id column). They use a permissive access policy for app_user while
-- still gaining protection against anonymous/unauthorised database connections.
-- =============================================================================

BEGIN;

-- ── 1. chain_break_events (tenant-scoped) ────────────────────────────────────
ALTER TABLE chain_break_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_break_events FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename='chain_break_events' AND policyname='cbe_tenant_isolation'
  ) THEN
    CREATE POLICY cbe_tenant_isolation ON chain_break_events
      USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
  END IF;
END $$;

-- ── 2. residency_violation_log (tenant-scoped) ───────────────────────────────
ALTER TABLE residency_violation_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE residency_violation_log FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename='residency_violation_log' AND policyname='rvl_tenant_isolation'
  ) THEN
    CREATE POLICY rvl_tenant_isolation ON residency_violation_log
      USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
  END IF;
END $$;

-- ── 3. sovereign_admin_registry (system-wide, no tenant_id) ──────────────────
-- This table is shared across the entire SARP installation.
-- RLS still protects against unauthenticated DB connections.
ALTER TABLE sovereign_admin_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE sovereign_admin_registry FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename='sovereign_admin_registry' AND policyname='sar_app_user_access'
  ) THEN
    CREATE POLICY sar_app_user_access ON sovereign_admin_registry
      TO app_user USING (true);
  END IF;
END $$;

-- ── 4. cbe_quorum_signatures (system-wide, no tenant_id) ─────────────────────
-- Linked to sovereign_admin_registry; no per-tenant filter applicable.
ALTER TABLE cbe_quorum_signatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE cbe_quorum_signatures FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename='cbe_quorum_signatures' AND policyname='cbeq_app_user_access'
  ) THEN
    CREATE POLICY cbeq_app_user_access ON cbe_quorum_signatures
      TO app_user USING (true);
  END IF;
END $$;

COMMIT;

-- ── Verification ─────────────────────────────────────────────────────────────
SELECT
  t.tablename,
  c.relrowsecurity::text  AS rls_enabled,
  c.relforcerowsecurity::text AS rls_forced,
  COUNT(p.policyname)     AS policies
FROM pg_tables t
JOIN pg_class c    ON c.relname = t.tablename
LEFT JOIN pg_policies p ON p.tablename = t.tablename
WHERE t.schemaname = 'public'
  AND t.tablename IN (
    'chain_break_events','cbe_quorum_signatures',
    'residency_violation_log','sovereign_admin_registry'
  )
GROUP BY t.tablename, c.relrowsecurity, c.relforcerowsecurity
ORDER BY t.tablename;
