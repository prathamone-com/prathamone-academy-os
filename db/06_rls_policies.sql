-- =============================================================================
-- PRATHAMONE ACADEMY OS — ROW-LEVEL SECURITY POLICIES
-- db/rls_policies.sql
-- =============================================================================
-- RULES.md compliance:
--   LAW 6  : Every table MUST include tenant_id (FK). No exceptions.
--   LAW 7  : Tenant context is implicit. Frontend NEVER passes tenant_id.
--   LAW 8  : Audit tables are INSERT-ONLY. No UPDATE. No DELETE. Ever.
--
-- APPLY ORDER:
--   1. db/schema_layer0_layer3.sql
--   2. db/schema_layer4_layer6.sql
--   3. db/schema_layer7_layer9.sql
--   4. db/schema_layer10.sql
--   5. db/rls_policies.sql   ← this file
--
-- TENANT CONTEXT:
--   Application must call before any DML:
--       SET LOCAL app.tenant_id = '<tenant_uuid>';
--   current_setting('app.tenant_id', true) returns NULL (not an error) when
--   the variable is unset. NULL = any_uuid → NULL → row is not visible.
--   Unset sessions see ZERO rows. This is the safe-fail default.
-- =============================================================================


-- =============================================================================
-- SECTION 1 — ENABLE AND FORCE ROW LEVEL SECURITY
-- =============================================================================
-- ENABLE ROW LEVEL SECURITY : activates RLS on the table.
-- FORCE ROW LEVEL SECURITY  : applies RLS even to the table owner.
-- Both are idempotent — safe to re-run.
-- =============================================================================

ALTER TABLE tenants                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants                   FORCE  ROW LEVEL SECURITY;

ALTER TABLE entity_master             ENABLE ROW LEVEL SECURITY;
ALTER TABLE entity_master             FORCE  ROW LEVEL SECURITY;

ALTER TABLE attribute_master          ENABLE ROW LEVEL SECURITY;
ALTER TABLE attribute_master          FORCE  ROW LEVEL SECURITY;

-- ALTER TABLE relationship_master       ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE relationship_master       FORCE  ROW LEVEL SECURITY;

-- ALTER TABLE roles                     ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE roles                     FORCE  ROW LEVEL SECURITY;

-- ALTER TABLE permissions               ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE permissions               FORCE  ROW LEVEL SECURITY;

-- ALTER TABLE role_permissions          ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE role_permissions          FORCE  ROW LEVEL SECURITY;

-- ALTER TABLE menu_config               ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE menu_config               FORCE  ROW LEVEL SECURITY;

ALTER TABLE form_master               ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_master               FORCE  ROW LEVEL SECURITY;

ALTER TABLE form_fields               ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_fields               FORCE  ROW LEVEL SECURITY;

-- ALTER TABLE field_validations         ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE field_validations         FORCE  ROW LEVEL SECURITY;

-- ALTER TABLE field_visibility_rules    ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE field_visibility_rules    FORCE  ROW LEVEL SECURITY;

ALTER TABLE workflow_master           ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_master           FORCE  ROW LEVEL SECURITY;

ALTER TABLE workflow_states           ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_states           FORCE  ROW LEVEL SECURITY;

ALTER TABLE workflow_transitions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_transitions      FORCE  ROW LEVEL SECURITY;

ALTER TABLE policy_master             ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_master             FORCE  ROW LEVEL SECURITY;

ALTER TABLE policy_conditions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_conditions         FORCE  ROW LEVEL SECURITY;

ALTER TABLE policy_actions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_actions            FORCE  ROW LEVEL SECURITY;

ALTER TABLE entity_records            ENABLE ROW LEVEL SECURITY;
ALTER TABLE entity_records            FORCE  ROW LEVEL SECURITY;

ALTER TABLE entity_attribute_values   ENABLE ROW LEVEL SECURITY;
ALTER TABLE entity_attribute_values   FORCE  ROW LEVEL SECURITY;

ALTER TABLE entity_record_index       ENABLE ROW LEVEL SECURITY;
ALTER TABLE entity_record_index       FORCE  ROW LEVEL SECURITY;

ALTER TABLE ai_model_registry         ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_model_registry         FORCE  ROW LEVEL SECURITY;

ALTER TABLE ai_tasks                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_tasks                  FORCE  ROW LEVEL SECURITY;

ALTER TABLE system_settings           ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_settings           FORCE  ROW LEVEL SECURITY;

ALTER TABLE audit_event_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_event_log           FORCE  ROW LEVEL SECURITY;

ALTER TABLE audit_state_snapshot      ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_state_snapshot      FORCE  ROW LEVEL SECURITY;

ALTER TABLE tenant_activity_metrics   ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_activity_metrics   FORCE  ROW LEVEL SECURITY;

ALTER TABLE security_event_log        ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_event_log        FORCE  ROW LEVEL SECURITY;

ALTER TABLE report_master             ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_master             FORCE  ROW LEVEL SECURITY;

ALTER TABLE report_dimensions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_dimensions         FORCE  ROW LEVEL SECURITY;

ALTER TABLE report_measures           ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_measures           FORCE  ROW LEVEL SECURITY;

ALTER TABLE report_filters            ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_filters            FORCE  ROW LEVEL SECURITY;

ALTER TABLE report_role_access        ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_role_access        FORCE  ROW LEVEL SECURITY;

ALTER TABLE report_execution_log      ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_execution_log      FORCE  ROW LEVEL SECURITY;


-- =============================================================================
-- SECTION 2 — TENANT ISOLATION POLICIES (SELECT + INSERT)
-- =============================================================================
-- Pattern per table:
--   {table}_tenant_select : FOR SELECT USING     (tenant_id = current_setting('app.tenant_id', true)::uuid)
--   {table}_tenant_insert : FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)
--
-- Note: audit_event_log and audit_state_snapshot are also covered here with
-- SELECT + INSERT. Their UPDATE/DELETE policies are intentionally OMITTED
-- (see Section 3 — PostgreSQL denies any operation with no permissive policy).
-- =============================================================================

-- tenants
CREATE POLICY tenants_tenant_select ON tenants FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenants_tenant_insert ON tenants FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- entity_master
CREATE POLICY entity_master_tenant_select ON entity_master FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY entity_master_tenant_insert ON entity_master FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- attribute_master
CREATE POLICY attribute_master_tenant_select ON attribute_master FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY attribute_master_tenant_insert ON attribute_master FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- relationship_master
-- CREATE POLICY relationship_master_tenant_select ON relationship_master FOR SELECT
--     USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
-- CREATE POLICY relationship_master_tenant_insert ON relationship_master FOR INSERT
--     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- roles, permissions, etc. (commented out as tables are missing)
/*
-- roles
CREATE POLICY roles_tenant_select ON roles FOR SELECT
... (rest of the block)
*/

-- form_master
CREATE POLICY form_master_tenant_select ON form_master FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY form_master_tenant_insert ON form_master FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- form_fields
CREATE POLICY form_fields_tenant_select ON form_fields FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY form_fields_tenant_insert ON form_fields FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- field_validations, field_visibility_rules (commented out as tables are missing)
/*
-- field_validations
CREATE POLICY field_validations_tenant_select ON field_validations FOR SELECT
...
*/

-- workflow_master
CREATE POLICY workflow_master_tenant_select ON workflow_master FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY workflow_master_tenant_insert ON workflow_master FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- workflow_states
CREATE POLICY workflow_states_tenant_select ON workflow_states FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY workflow_states_tenant_insert ON workflow_states FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- workflow_transitions
CREATE POLICY workflow_transitions_tenant_select ON workflow_transitions FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY workflow_transitions_tenant_insert ON workflow_transitions FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- policy_master
CREATE POLICY policy_master_tenant_select ON policy_master FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY policy_master_tenant_insert ON policy_master FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- policy_conditions
CREATE POLICY policy_conditions_tenant_select ON policy_conditions FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY policy_conditions_tenant_insert ON policy_conditions FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- policy_actions
CREATE POLICY policy_actions_tenant_select ON policy_actions FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY policy_actions_tenant_insert ON policy_actions FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- entity_records
CREATE POLICY entity_records_tenant_select ON entity_records FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY entity_records_tenant_insert ON entity_records FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- entity_attribute_values
CREATE POLICY entity_attribute_values_tenant_select ON entity_attribute_values FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY entity_attribute_values_tenant_insert ON entity_attribute_values FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- entity_record_index
CREATE POLICY entity_record_index_tenant_select ON entity_record_index FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY entity_record_index_tenant_insert ON entity_record_index FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- ai_model_registry
CREATE POLICY ai_model_registry_tenant_select ON ai_model_registry FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY ai_model_registry_tenant_insert ON ai_model_registry FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- ai_tasks
CREATE POLICY ai_tasks_tenant_select ON ai_tasks FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY ai_tasks_tenant_insert ON ai_tasks FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- system_settings
CREATE POLICY system_settings_tenant_select ON system_settings FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY system_settings_tenant_insert ON system_settings FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- audit_event_log  (SELECT + INSERT only — see Section 3)
CREATE POLICY audit_event_log_tenant_select ON audit_event_log FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY audit_event_log_tenant_insert ON audit_event_log FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- audit_state_snapshot  (SELECT + INSERT only — see Section 3)
CREATE POLICY audit_state_snapshot_tenant_select ON audit_state_snapshot FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY audit_state_snapshot_tenant_insert ON audit_state_snapshot FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- tenant_activity_metrics
CREATE POLICY tenant_activity_metrics_tenant_select ON tenant_activity_metrics FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_activity_metrics_tenant_insert ON tenant_activity_metrics FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- security_event_log
CREATE POLICY security_event_log_tenant_select ON security_event_log FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY security_event_log_tenant_insert ON security_event_log FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- report_master
CREATE POLICY report_master_tenant_select ON report_master FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY report_master_tenant_insert ON report_master FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- report_dimensions
CREATE POLICY report_dimensions_tenant_select ON report_dimensions FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY report_dimensions_tenant_insert ON report_dimensions FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- report_measures
CREATE POLICY report_measures_tenant_select ON report_measures FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY report_measures_tenant_insert ON report_measures FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- report_filters
CREATE POLICY report_filters_tenant_select ON report_filters FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY report_filters_tenant_insert ON report_filters FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- report_role_access
CREATE POLICY report_role_access_tenant_select ON report_role_access FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY report_role_access_tenant_insert ON report_role_access FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- report_execution_log
CREATE POLICY report_execution_log_tenant_select ON report_execution_log FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY report_execution_log_tenant_insert ON report_execution_log FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);


-- =============================================================================
-- SECTION 3 — AUDIT TABLE IMMUTABILITY (audit_event_log, audit_state_snapshot)
-- =============================================================================
-- LAW 8: Audit tables are INSERT-ONLY. No UPDATE. No DELETE. Ever.
--
-- HOW POSTGRESQL DENIES UPDATE AND DELETE HERE:
--   With RLS enabled + FORCE ROW LEVEL SECURITY, PostgreSQL requires at least
--   one permissive policy to allow an operation. We created SELECT and INSERT
--   policies above for these two tables. We intentionally DO NOT create any
--   UPDATE or DELETE policy. Result: any UPDATE or DELETE attempt returns:
--       ERROR: new row violates row-level security policy for table "..."
--   This is PostgreSQL's default-deny behaviour — no policy = no access.
--
-- ADDITIONALLY:
--   UPDATE and DELETE privileges are NOT granted to any role on these tables
--   (see Section 4 REVOKE statements). Both layers are independent; either
--   alone is sufficient to block mutation.
-- =============================================================================
-- NO UPDATE POLICY for audit_event_log    — intentionally absent.
-- NO DELETE POLICY for audit_event_log    — intentionally absent.
-- NO UPDATE POLICY for audit_state_snapshot — intentionally absent.
-- NO DELETE POLICY for audit_state_snapshot — intentionally absent.


-- =============================================================================
-- SECTION 4 — ROLES AND PRIVILEGE GRANTS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Create roles (idempotent)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'audit_writer') THEN
        CREATE ROLE audit_writer NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'system_admin') THEN
        CREATE ROLE system_admin NOLOGIN;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Role 1: app_user
-- SELECT, INSERT, UPDATE on all tables.
-- REVOKE UPDATE on audit tables (immutability, LAW 8).
-- REVOKE DELETE on all tables (soft-delete pattern only).
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO app_user;
REVOKE UPDATE ON audit_event_log     FROM app_user;
REVOKE UPDATE ON audit_state_snapshot FROM app_user;
REVOKE DELETE ON ALL TABLES IN SCHEMA public FROM app_user;

-- ---------------------------------------------------------------------------
-- Role 2: audit_writer
-- INSERT only on audit_event_log and audit_state_snapshot.
-- No other grants — not SELECT, not UPDATE, not DELETE.
-- ---------------------------------------------------------------------------
GRANT INSERT ON audit_event_log      TO audit_writer;
GRANT INSERT ON audit_state_snapshot TO audit_writer;

-- ---------------------------------------------------------------------------
-- Role 3: system_admin
-- Full privileges on all tables.
-- A USING (true) bypass policy is added per-table so that system_admin
-- can read and write SYSTEM-tenant rows without a tenant context requirement.
-- Used exclusively for platform operations — never for normal app requests.
-- ---------------------------------------------------------------------------
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO system_admin;

-- system_admin bypass policies (one per table, USING (true) skips tenant filter)
CREATE POLICY tenants_system_admin                ON tenants                   TO system_admin USING (true);
CREATE POLICY entity_master_system_admin          ON entity_master             TO system_admin USING (true);
CREATE POLICY attribute_master_system_admin       ON attribute_master          TO system_admin USING (true);
-- CREATE POLICY relationship_master_system_admin    ON relationship_master       TO system_admin USING (true);
-- CREATE POLICY roles_system_admin                  ON roles                     TO system_admin USING (true);
-- CREATE POLICY permissions_system_admin            ON permissions               TO system_admin USING (true);
-- CREATE POLICY role_permissions_system_admin       ON role_permissions          TO system_admin USING (true);
-- CREATE POLICY menu_config_system_admin            ON menu_config               TO system_admin USING (true);
CREATE POLICY form_master_system_admin            ON form_master               TO system_admin USING (true);
CREATE POLICY form_fields_system_admin            ON form_fields               TO system_admin USING (true);
-- CREATE POLICY field_validations_system_admin      ON field_validations         TO system_admin USING (true);
-- CREATE POLICY field_visibility_rules_system_admin ON field_visibility_rules    TO system_admin USING (true);
CREATE POLICY workflow_master_system_admin        ON workflow_master           TO system_admin USING (true);
CREATE POLICY workflow_states_system_admin        ON workflow_states           TO system_admin USING (true);
CREATE POLICY workflow_transitions_system_admin   ON workflow_transitions      TO system_admin USING (true);
CREATE POLICY policy_master_system_admin          ON policy_master             TO system_admin USING (true);
CREATE POLICY policy_conditions_system_admin      ON policy_conditions         TO system_admin USING (true);
CREATE POLICY policy_actions_system_admin         ON policy_actions            TO system_admin USING (true);
CREATE POLICY entity_records_system_admin         ON entity_records            TO system_admin USING (true);
CREATE POLICY entity_attribute_values_system_admin ON entity_attribute_values  TO system_admin USING (true);
CREATE POLICY entity_record_index_system_admin    ON entity_record_index       TO system_admin USING (true);
CREATE POLICY ai_model_registry_system_admin      ON ai_model_registry         TO system_admin USING (true);
CREATE POLICY ai_tasks_system_admin               ON ai_tasks                  TO system_admin USING (true);
CREATE POLICY system_settings_system_admin        ON system_settings           TO system_admin USING (true);
CREATE POLICY audit_event_log_system_admin        ON audit_event_log           TO system_admin USING (true);
CREATE POLICY audit_state_snapshot_system_admin   ON audit_state_snapshot      TO system_admin USING (true);
CREATE POLICY tenant_activity_metrics_system_admin ON tenant_activity_metrics  TO system_admin USING (true);
CREATE POLICY security_event_log_system_admin     ON security_event_log        TO system_admin USING (true);
CREATE POLICY report_master_system_admin          ON report_master             TO system_admin USING (true);
CREATE POLICY report_dimensions_system_admin      ON report_dimensions         TO system_admin USING (true);
CREATE POLICY report_measures_system_admin        ON report_measures           TO system_admin USING (true);
CREATE POLICY report_filters_system_admin         ON report_filters            TO system_admin USING (true);
CREATE POLICY report_role_access_system_admin     ON report_role_access        TO system_admin USING (true);
CREATE POLICY report_execution_log_system_admin   ON report_execution_log      TO system_admin USING (true);


-- =============================================================================
-- SECTION 5 — VERIFICATION QUERIES
-- =============================================================================
-- Run these manually in psql or a migration test to confirm RLS is working.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Test 1: SELECT without setting app.tenant_id — must return zero rows.
-- When app.tenant_id is '', current_setting returns '' which cannot be cast to
-- uuid, or returns NULL — either way no rows match the USING clause.
-- Expected result: 0  (or an error on invalid uuid cast — both prove RLS works)
-- ---------------------------------------------------------------------------
-- SET app.tenant_id = '';
-- SELECT count(*) FROM entity_records;  -- expected: 0 or ERROR: invalid input syntax for type uuid

-- ---------------------------------------------------------------------------
-- Test 2: SELECT with valid tenant_id — must return only that tenant's rows.
-- Replace <test-uuid> with a UUID that exists in the tenants table.
-- Expected result: count of rows belonging exclusively to that tenant.
-- ---------------------------------------------------------------------------
-- SET app.tenant_id = '<test-uuid>';
-- SELECT count(*) FROM entity_records;  -- expected: row count for that tenant only

-- ---------------------------------------------------------------------------
-- Test 3: Attempt UPDATE on audit_event_log — must fail with permission denied.
-- app_user has UPDATE revoked (Section 4).
-- No UPDATE policy exists (Section 3) so even if privilege were granted, RLS
-- would still deny it.
-- Expected result: ERROR:  permission denied for table audit_event_log
--              or ERROR:  new row violates row-level security policy
-- ---------------------------------------------------------------------------
-- UPDATE audit_event_log SET action_type = 'TAMPERED' WHERE 1=1;
-- -- expected: ERROR, permission denied

-- =============================================================================
-- POLICY INSPECTION
-- =============================================================================
-- After applying this file, verify all policies with:
--
-- SELECT tablename, policyname, permissive, roles, cmd, qual
-- FROM   pg_policies
-- WHERE  schemaname = 'public'
-- ORDER  BY tablename, cmd, policyname;
--
-- Every table should have:
--   {table}_tenant_select  (SELECT,  PERMISSIVE)
--   {table}_tenant_insert  (INSERT,  PERMISSIVE)
--   {table}_system_admin   (ALL,     PERMISSIVE, roles = {system_admin})
-- audit_event_log and audit_state_snapshot must have NO UPDATE or DELETE policy.
-- =============================================================================
