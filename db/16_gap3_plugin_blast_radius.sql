-- =============================================================================
-- PRATHAMONE ACADEMY OS — GAP-3 IMPLEMENTATION
-- Plugin Blast Radius Control & Sandbox Enforcement
-- Implements Laws: 09-3.1, 09-3.2, 09-3.3, 09-3.4, 09-3.5
-- =============================================================================
-- Depends on: all prior schema files
-- RULES.md compliance:
--   LAW 9  : Plugin invocations tracked as first-class kernel entities
--   LAW 2  : Plugin resource limits stored in metadata kernel
--   LAW 8  : Plugin execution log is INSERT-ONLY (all events forensic)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Plugin Registry (LAW 09-3.5 — Blast Radius Score pre-activation)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS plugin_registry (
    tenant_id               UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    plugin_id               UUID        NOT NULL DEFAULT gen_random_uuid(),
    plugin_code             TEXT        NOT NULL,           -- Machine identifier
    display_name            TEXT        NOT NULL,
    vendor                  TEXT        NOT NULL,
    version                 TEXT        NOT NULL,
    -- Resource limits (Laws 09-3.1 to 09-3.3)
    max_execution_ms        INT         NOT NULL DEFAULT 5000,
    -- LAW 09-3.1: Hard limit 5,000ms. SIGKILL if exceeded.
    max_memory_mb           INT         NOT NULL DEFAULT 256,
    -- LAW 09-3.2: Hard limit 256 MB RAM. SIGKILL if exceeded.
    max_api_calls_per_min   INT         NOT NULL DEFAULT 100,
    -- LAW 09-3.3: Hard limit 100 kernel API calls per minute.
    -- Network isolation (LAW 09-3.4)
    allowed_egress_hosts    TEXT[]      NOT NULL DEFAULT '{}',
    -- Whitelist of kernel API hostnames the plugin may call. Empty = kernel only.
    vlan_id                 TEXT,
    -- Sandbox VLAN identifier. Populated by infrastructure layer upon deployment.
    -- Blast Radius Score (LAW 09-3.5)
    blast_radius_score      NUMERIC(3,1) NOT NULL DEFAULT 0.0
                                CHECK (blast_radius_score BETWEEN 0.0 AND 10.0),
    -- Score computed by static analysis engine. Scores > 7.0 require Architect approval.
    architect_approved      BOOLEAN     NOT NULL DEFAULT FALSE,
    approved_by             UUID,
    approved_at             TIMESTAMPTZ,
    -- Status
    status                  TEXT        NOT NULL DEFAULT 'PENDING_REVIEW'
                                CHECK (status IN (
                                    'PENDING_REVIEW',   -- Awaiting BRS computation
                                    'APPROVED',         -- Active and deployable
                                    'SUSPENDED',        -- Auto-suspended after limit violation
                                    'REVOKED'           -- Permanently disabled (security incident)
                                )),
    installed_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    suspended_at            TIMESTAMPTZ,
    suspension_reason       TEXT,
    metadata                JSONB,

    CONSTRAINT pk_plugin_registry PRIMARY KEY (tenant_id, plugin_id),
    CONSTRAINT uq_plugin_id UNIQUE (plugin_id),
    CONSTRAINT uq_plugin_code UNIQUE (tenant_id, plugin_code)
);

ALTER TABLE plugin_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE plugin_registry FORCE  ROW LEVEL SECURITY;

CREATE POLICY plugin_registry_tenant_select ON plugin_registry FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY plugin_registry_tenant_insert ON plugin_registry FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY plugin_registry_system_admin  ON plugin_registry
    TO system_admin USING (true);

COMMENT ON TABLE plugin_registry IS
    'LAW 09-3.1 to 09-3.5: Per-tenant registry of third-party plugins. '
    'Resource limits (execution_ms, memory_mb, api_calls) are kernel-enforced. '
    'Plugins with blast_radius_score > 7.0 require architect_approved=TRUE before activation.';


-- Guard: Block activation of high-BRS plugins without explicit approval (LAW 09-3.5)
CREATE OR REPLACE FUNCTION fn_guard_plugin_brs_activation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'APPROVED' AND NEW.blast_radius_score > 7.0
       AND NOT NEW.architect_approved THEN
        RAISE EXCEPTION
            'LAW 09-3.5 VIOLATION: Plugin [%] has a Blast Radius Score of %.  '
            'Score > 7.0 requires Sovereign Architect approval (architect_approved=TRUE) '
            'before status may be set to APPROVED.',
            NEW.plugin_code, NEW.blast_radius_score;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_plugin_brs_guard
    BEFORE INSERT OR UPDATE ON plugin_registry
    FOR EACH ROW EXECUTE FUNCTION fn_guard_plugin_brs_activation();


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Plugin Execution Log — INSERT-ONLY (LAW 08, LAW 09-3.1 to 09-3.3)
-- Every invocation is logged. Limit violations set termination_reason.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS plugin_execution_log (
    tenant_id               UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    execution_id            UUID        NOT NULL DEFAULT gen_random_uuid(),
    plugin_id               UUID        NOT NULL,
    actor_id                UUID,                   -- User or system that triggered the plugin
    invocation_payload      JSONB,                  -- Sanitized input; no raw PII
    started_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at            TIMESTAMPTZ,
    duration_ms             INT,                    -- Actual execution duration
    memory_peak_mb          NUMERIC(8,2),           -- Peak memory observed during execution
    api_calls_made          INT         DEFAULT 0,  -- Kernel API calls during this invocation
    exit_status             TEXT        NOT NULL DEFAULT 'RUNNING'
                                CHECK (exit_status IN (
                                    'RUNNING', 'SUCCESS', 'TIMEOUT_KILLED', 'OOM_KILLED',
                                    'RATE_LIMITED', 'EGRESS_BLOCKED', 'FAILED', 'REVOKED'
                                )),
    termination_reason      TEXT,                   -- Populated on abnormal exit
    output_payload          JSONB,                  -- Sanitized output; no raw PII

    CONSTRAINT pk_plugin_execution_log PRIMARY KEY (tenant_id, execution_id),
    CONSTRAINT uq_execution_id UNIQUE (execution_id),
    CONSTRAINT fk_pel_plugin FOREIGN KEY (tenant_id, plugin_id)
        REFERENCES plugin_registry(tenant_id, plugin_id) ON DELETE RESTRICT
);

ALTER TABLE plugin_execution_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE plugin_execution_log FORCE  ROW LEVEL SECURITY;

CREATE POLICY plugin_exec_log_tenant_select ON plugin_execution_log FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY plugin_exec_log_tenant_insert ON plugin_execution_log FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY plugin_exec_log_system_admin  ON plugin_execution_log
    TO system_admin USING (true);

-- INSERT-ONLY guard (LAW 8)
CREATE OR REPLACE FUNCTION fn_plugin_execution_log_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'plugin_execution_log is INSERT-ONLY (LAW 8). TG_OP=%', TG_OP;
END;
$$;
CREATE TRIGGER trg_pel_no_delete
    BEFORE DELETE ON plugin_execution_log
    FOR EACH ROW EXECUTE FUNCTION fn_plugin_execution_log_no_mutation();


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: fn_record_plugin_limit_violation()
-- Called by the plugin runtime (Docker/Kubernetes sidecar) when a limit is hit.
-- Triggers automatic suspension and HIGH severity audit event.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_record_plugin_limit_violation(
    p_execution_id  UUID,
    p_violation     TEXT,   -- TIMEOUT_KILLED | OOM_KILLED | RATE_LIMITED | EGRESS_BLOCKED
    p_detail        TEXT    DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tenant_id UUID;
    v_plugin_id UUID;
    v_plugin_code TEXT;
    v_audit_event TEXT;
BEGIN
    -- Resolve tenant and plugin from the execution log
    SELECT pel.tenant_id, pel.plugin_id, pr.plugin_code
    INTO v_tenant_id, v_plugin_id, v_plugin_code
    FROM plugin_execution_log pel
    JOIN plugin_registry pr ON pr.plugin_id = pel.plugin_id AND pr.tenant_id = pel.tenant_id
    WHERE pel.execution_id = p_execution_id;

    IF NOT FOUND THEN
        RAISE WARNING 'fn_record_plugin_limit_violation: execution_id % not found.', p_execution_id;
        RETURN;
    END IF;

    -- Map violation type to audit event code
    v_audit_event := CASE p_violation
        WHEN 'TIMEOUT_KILLED'   THEN 'PLUGIN_TIMEOUT_KILL'      -- LAW 09-3.1
        WHEN 'OOM_KILLED'       THEN 'PLUGIN_MEMORY_EXCEEDED'   -- LAW 09-3.2
        WHEN 'RATE_LIMITED'     THEN 'PLUGIN_RATE_LIMITED'      -- LAW 09-3.3
        WHEN 'EGRESS_BLOCKED'   THEN 'PLUGIN_EGRESS_BLOCKED'    -- LAW 09-3.4
        ELSE                         'PLUGIN_VIOLATION_GENERIC'
    END;

    -- Auto-suspend the plugin (LAW 09-3.1 through 09-3.4)
    UPDATE plugin_registry
    SET status           = 'SUSPENDED',
        suspended_at     = now(),
        suspension_reason = FORMAT('AUTO_SUSPENDED: %s — %s', p_violation, COALESCE(p_detail, 'No detail.'))
    WHERE tenant_id = v_tenant_id AND plugin_id = v_plugin_id
      AND status NOT IN ('REVOKED');

    -- Append HIGH severity audit event (LAW 09-3.1)
    INSERT INTO audit_event_log(
        tenant_id, actor_id, actor_type, event_category,
        event_type, record_id, event_data
    ) VALUES (
        v_tenant_id, NULL, 'SYSTEM', 'SECURITY',
        v_audit_event, v_plugin_id,
        jsonb_build_object(
            'execution_id',  p_execution_id,
            'plugin_code',   v_plugin_code,
            'violation',     p_violation,
            'detail',        p_detail,
            'action_taken',  'AUTO_SUSPENDED',
            'severity',      'HIGH',
            'law_citation',  FORMAT('LAW 09-3: Plugin blast radius violation. '
                                   'Plugin auto-suspended per sandbox enforcement rules.')
        )
    );

    -- Also log to security_event_log for SIEM
    INSERT INTO security_event_log(
        tenant_id, event_type, severity, actor_type,
        resource_path, event_data
    ) VALUES (
        v_tenant_id, v_audit_event, 'ERROR', 'SYSTEM',
        '/kernel/plugin/enforcer',
        jsonb_build_object('execution_id', p_execution_id, 'plugin_code', v_plugin_code)
    );
END;
$$;

COMMENT ON FUNCTION fn_record_plugin_limit_violation IS
    'LAW 09-3.1 to 09-3.4: Called by the plugin runtime sidecar when a resource '
    'limit is breached. Automatically suspends the plugin and emits HIGH severity '
    'audit events to both audit_event_log and security_event_log.';

CREATE INDEX IF NOT EXISTS idx_pel_plugin ON plugin_execution_log(tenant_id, plugin_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_pel_exit   ON plugin_execution_log(tenant_id, exit_status, started_at DESC);

GRANT INSERT, SELECT ON plugin_execution_log TO app_user, audit_writer;
GRANT SELECT         ON plugin_registry      TO app_user;
GRANT EXECUTE ON FUNCTION fn_record_plugin_limit_violation(UUID, TEXT, TEXT) TO system_admin;

-- =============================================================================
-- END: GAP-3 PLUGIN BLAST RADIUS IMPLEMENTATION (Laws 09-3.1 to 09-3.5) — LOCKED
-- =============================================================================
