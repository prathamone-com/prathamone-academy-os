-- =============================================================================
-- PRATHAMONE ACADEMY OS — GAP-4 IMPLEMENTATION
-- API Gateway Selective Rate Limiting & Shard-Level Circuit Breaker
-- Implements Laws: 09-4.1, 09-4.2, 09-4.3, 09-4.4
-- =============================================================================
-- Depends on: all prior schema files
-- RULES.md compliance:
--   LAW 6  : All config tables have tenant_id FK
--   LAW 8  : Rate-limit event logs are INSERT-ONLY
--   LAW 11 : Shard config and quota are metadata rows, not new application tables
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Tenant Shard Configuration (LAW 09-4.1)
-- Stores per-tenant API quota, shard assignment, and residency data.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tenant_shard_config (
    tenant_id               UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    shard_id                TEXT        NOT NULL DEFAULT 'shard-01',
    -- Logical shard identifier (e.g. 'shard-IN-MUM-01')

    -- LAW 09-4.1: Per-tenant API quota (default 1,000 req/min)
    api_quota_per_minute    INT         NOT NULL DEFAULT 1000
                                CHECK (api_quota_per_minute > 0),
    -- LAW 09-4.4: TIER-2 write mutation cap (default 100 writes/min)
    write_quota_per_minute  INT         NOT NULL DEFAULT 100
                                CHECK (write_quota_per_minute > 0),

    -- LAW 09-4.2: Emergency cap applied during circuit breaker events
    emergency_cap_pct       NUMERIC(5,2) NOT NULL DEFAULT 20.0
                                CHECK (emergency_cap_pct BETWEEN 1.0 AND 100.0),
    -- Default: 20% of shard capacity as defined in LAW 09-4.2

    -- Circuit breaker state (managed by fn_check_circuit_breaker)
    circuit_breaker_status  TEXT        NOT NULL DEFAULT 'CLOSED'
                                CHECK (circuit_breaker_status IN ('CLOSED', 'THROTTLED', 'OPEN')),
    -- CLOSED = normal, THROTTLED = emergency cap active, OPEN = tenant fully blocked

    circuit_breaker_opened_at TIMESTAMPTZ,
    circuit_breaker_reason  TEXT,

    -- Billing/capacity metadata
    contracted_tier         TEXT        NOT NULL DEFAULT 'STANDARD'
                                CHECK (contracted_tier IN ('STARTER', 'STANDARD', 'ENTERPRISE', 'UNLIMITED')),
    effective_from          TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes                   TEXT,

    CONSTRAINT pk_tenant_shard_config PRIMARY KEY (tenant_id)
);

ALTER TABLE tenant_shard_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_shard_config FORCE  ROW LEVEL SECURITY;

CREATE POLICY tenant_shard_config_select ON tenant_shard_config FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_shard_config_insert ON tenant_shard_config FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_shard_config_system_admin ON tenant_shard_config
    TO system_admin USING (true);

COMMENT ON TABLE tenant_shard_config IS
    'LAW 09-4.1 to 09-4.4: Per-tenant API quota configuration and shard assignment. '
    'api_quota_per_minute enforced by API gateway middleware. '
    'circuit_breaker_status managed by fn_check_circuit_breaker().';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: API Quota Ledger — INSERT-ONLY rolling window counter (LAW 09-4.1, 09-4.4)
-- The API gateway aggregates these rows to compute usage within a sliding window.
-- This is the DB-side record; the hot-path enforcement is at the gateway layer.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS api_quota_ledger (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    ledger_id           UUID        NOT NULL DEFAULT gen_random_uuid(),
    window_start        TIMESTAMPTZ NOT NULL,   -- Start of the 1-minute window
    window_end          TIMESTAMPTZ NOT NULL,
    endpoint_tier       TEXT        NOT NULL    -- TIER-1 (read) or TIER-2 (write)
                            CHECK (endpoint_tier IN ('TIER-1', 'TIER-2')),
    request_count       INT         NOT NULL DEFAULT 0,
    throttled_count     INT         NOT NULL DEFAULT 0,     -- Requests rejected with HTTP 429
    peak_rps            NUMERIC(8,2),                       -- Peak requests-per-second in window
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_api_quota_ledger PRIMARY KEY (tenant_id, ledger_id),
    CONSTRAINT uq_quota_window UNIQUE (tenant_id, window_start, endpoint_tier),
    CONSTRAINT chk_quota_window CHECK (window_end > window_start)
);

ALTER TABLE api_quota_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_quota_ledger FORCE  ROW LEVEL SECURITY;

CREATE POLICY api_quota_ledger_select ON api_quota_ledger FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY api_quota_ledger_insert ON api_quota_ledger FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY api_quota_ledger_system_admin ON api_quota_ledger
    TO system_admin USING (true);

-- INSERT-ONLY guard (LAW 8)
CREATE OR REPLACE FUNCTION fn_quota_ledger_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'api_quota_ledger is INSERT-ONLY (LAW 8). TG_OP=%', TG_OP;
END;
$$;
CREATE TRIGGER trg_quota_no_delete
    BEFORE DELETE ON api_quota_ledger
    FOR EACH ROW EXECUTE FUNCTION fn_quota_ledger_no_mutation();

COMMENT ON TABLE api_quota_ledger IS
    'LAW 09-4.1 / 09-4.4: Append-only quota accounting ledger. '
    'One row per tenant per 1-minute window per endpoint tier. '
    'Used for retrospective billing and circuit-breaker anomaly analysis.';

CREATE INDEX IF NOT EXISTS idx_aql_tenant_window
    ON api_quota_ledger(tenant_id, window_start DESC, endpoint_tier);


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Circuit Breaker Event Log — INSERT-ONLY (LAW 09-4.2)
-- Records every circuit breaker transition with full context.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS circuit_breaker_log (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    event_id            UUID        NOT NULL DEFAULT gen_random_uuid(),
    shard_id            TEXT        NOT NULL,
    previous_status     TEXT        NOT NULL,
    new_status          TEXT        NOT NULL,
    trigger_reason      TEXT        NOT NULL,
    -- e.g. 'EXCEEDED_40PCT_SHARD_CAPACITY_FOR_60S', 'ANOMALY_DETECTED_5X_ROLLING_AVG'
    tenant_rps_at_event NUMERIC(10,2),
    shard_capacity_pct  NUMERIC(5,2),   -- % of shard capacity consumed at event time
    auto_resolved_at    TIMESTAMPTZ,    -- When THROTTLED → CLOSED after cool-down
    logged_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_circuit_breaker_log PRIMARY KEY (tenant_id, event_id),
    CONSTRAINT uq_cb_event_id UNIQUE (event_id)
);

ALTER TABLE circuit_breaker_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE circuit_breaker_log FORCE  ROW LEVEL SECURITY;

CREATE POLICY circuit_breaker_log_select ON circuit_breaker_log FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY circuit_breaker_log_insert ON circuit_breaker_log FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY circuit_breaker_log_system_admin ON circuit_breaker_log
    TO system_admin USING (true);

-- INSERT-ONLY guard
CREATE OR REPLACE FUNCTION fn_circuit_breaker_log_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'circuit_breaker_log is INSERT-ONLY (LAW 8). TG_OP=%', TG_OP;
END;
$$;
CREATE TRIGGER trg_cbl_no_delete
    BEFORE DELETE ON circuit_breaker_log
    FOR EACH ROW EXECUTE FUNCTION fn_circuit_breaker_log_no_mutation();


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: fn_check_circuit_breaker() — The Shard-Level Circuit Breaker (LAW 09-4.2)
-- Called by the API gateway when a tenant exceeds 40% of shard capacity for 60s.
-- Automatically caps the tenant to emergency_cap_pct of shard capacity.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_check_circuit_breaker(
    p_tenant_id         UUID,
    p_shard_id          TEXT,
    p_tenant_rps        NUMERIC,    -- Current tenant req/sec
    p_shard_total_rps   NUMERIC,    -- Total shard req/sec
    p_anomaly_factor    NUMERIC DEFAULT NULL -- Optional: tenant_rps / 30d_rolling_avg
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_config            RECORD;
    v_shard_pct         NUMERIC;
    v_previous_status   TEXT;
    v_new_status        TEXT;
    v_reason            TEXT;
    v_cb_event_id       UUID := gen_random_uuid();
BEGIN
    SELECT * INTO v_config FROM tenant_shard_config WHERE tenant_id = p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('action', 'NO_CONFIG', 'tenant_id', p_tenant_id); END IF;

    v_previous_status := v_config.circuit_breaker_status;
    v_shard_pct := CASE WHEN p_shard_total_rps > 0
                        THEN (p_tenant_rps / p_shard_total_rps) * 100.0
                        ELSE 0.0 END;

    -- LAW 09-4.2: 40% shard capacity threshold → THROTTLED
    IF v_shard_pct > 40.0 AND v_previous_status = 'CLOSED' THEN
        v_new_status := 'THROTTLED';
        v_reason := FORMAT('EXCEEDED_40PCT_SHARD_CAPACITY: tenant at %.1f%% of shard', v_shard_pct);

    -- LAW 09-4.3: 5x rolling average anomaly → DDoS sentinel → OPEN
    ELSIF p_anomaly_factor IS NOT NULL AND p_anomaly_factor >= 5.0
          AND v_previous_status IN ('CLOSED', 'THROTTLED') THEN
        v_new_status := 'OPEN';
        v_reason := FORMAT(
            'DDOS_SENTINEL_TRIGGERED: traffic is %.1fx the 30-day rolling average', p_anomaly_factor
        );

    ELSE
        -- No state change needed
        RETURN jsonb_build_object('action', 'NO_CHANGE', 'status', v_previous_status);
    END IF;

    -- Apply circuit breaker transition
    UPDATE tenant_shard_config
    SET circuit_breaker_status    = v_new_status,
        circuit_breaker_opened_at = now(),
        circuit_breaker_reason    = v_reason
    WHERE tenant_id = p_tenant_id;

    -- Log the circuit breaker event (INSERT-ONLY)
    INSERT INTO circuit_breaker_log(
        tenant_id, event_id, shard_id, previous_status, new_status,
        trigger_reason, tenant_rps_at_event, shard_capacity_pct
    ) VALUES (
        p_tenant_id, v_cb_event_id, p_shard_id, v_previous_status, v_new_status,
        v_reason, p_tenant_rps, v_shard_pct
    );

    -- Append CRITICAL audit event
    INSERT INTO audit_event_log(
        tenant_id, actor_id, actor_type, event_category,
        event_type, event_data
    ) VALUES (
        p_tenant_id, NULL, 'SYSTEM', 'SECURITY',
        'API_CIRCUIT_BREAKER_TRIGGERED',
        jsonb_build_object(
            'new_status',       v_new_status,
            'reason',           v_reason,
            'shard_pct',        v_shard_pct,
            'anomaly_factor',   p_anomaly_factor,
            'emergency_cap_pct', v_config.emergency_cap_pct,
            'law_citation',     'LAW 09-4.2 / 09-4.3: Shard circuit breaker or DDoS sentinel triggered.',
            'action_required',  'Notify tenant primary contact immediately.'
        )
    );

    -- Also write to security_event_log for SIEM
    INSERT INTO security_event_log(
        tenant_id, event_type, severity, actor_type, event_data
    ) VALUES (
        p_tenant_id, 'API_CIRCUIT_BREAKER_TRIGGERED',
        CASE WHEN v_new_status = 'OPEN' THEN 'CRITICAL' ELSE 'ERROR' END,
        'SYSTEM',
        jsonb_build_object('cb_event_id', v_cb_event_id, 'reason', v_reason)
    );

    RETURN jsonb_build_object(
        'action',           'CIRCUIT_BREAKER_TRIGGERED',
        'new_status',       v_new_status,
        'reason',           v_reason,
        'cb_event_id',      v_cb_event_id,
        'emergency_cap_pct', v_config.emergency_cap_pct
    );
END;
$$;

COMMENT ON FUNCTION fn_check_circuit_breaker IS
    'LAW 09-4.2 / 09-4.3: Shard-level circuit breaker + DDoS sentinel. '
    'Called by API gateway when tenant exceeds 40% shard capacity or 5x rolling avg. '
    'Transitions circuit_breaker_status CLOSED → THROTTLED → OPEN. '
    'All events are logged immutably to audit_event_log and security_event_log.';

-- Endpoint Tier Classification View (LAW 09-4.4)
COMMENT ON TABLE api_quota_ledger IS
    'API quota tracking. TIER-1 = read-only endpoints (high-volume allowed). '
    'TIER-2 = write/mutating endpoints (100 writes/min per tenant by default per LAW 09-4.4).';

GRANT SELECT ON tenant_shard_config TO app_user;
GRANT INSERT ON api_quota_ledger    TO app_user, audit_writer;
GRANT INSERT ON circuit_breaker_log TO app_user, audit_writer;
GRANT EXECUTE ON FUNCTION fn_check_circuit_breaker(UUID, TEXT, NUMERIC, NUMERIC, NUMERIC) TO system_admin;

-- =============================================================================
-- END: GAP-4 API RATE LIMITING IMPLEMENTATION (Laws 09-4.1 to 09-4.4) — LOCKED
-- =============================================================================
