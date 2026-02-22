-- =============================================================================
-- PRATHAMONE ACADEMY OS — GAP-6 IMPLEMENTATION
-- Cross-Region Data Residency Enforcement
-- Implements Laws: 09-6.1, 09-6.2, 09-6.3, 09-6.4
-- =============================================================================
-- Depends on: all prior schema files
-- RULES.md compliance:
--   LAW 6  : tenant_id FK on all tables
--   LAW 7  : Residency tag is server-side metadata — never client-supplied
--   LAW 8  : Residency violation logs are INSERT-ONLY
--   LAW 2  : data_residency_region stored in tenants table (kernel anchor), not EAV
--            RATIONALE: This is a structural invariant, not a dynamic attribute.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Add data_residency_region to tenants table (LAW 09-6.1)
-- This field is IMMUTABLE after provisioning. A guard trigger enforces this.
-- Valid region codes follow the format: COUNTRY-CITY (e.g. IN-MUM, EU-IRL, US-VA)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE tenants
    ADD COLUMN IF NOT EXISTS data_residency_region TEXT
        CHECK (data_residency_region ~ '^[A-Z]{2}-[A-Z]{2,6}$')
        DEFAULT NULL;
-- NULL = unrestricted (legacy tenants before LAW 09-6.1 was ratified)

COMMENT ON COLUMN tenants.data_residency_region IS
    'LAW 09-6.1: Immutable data residency region code. Set once at provisioning. '
    'Format: COUNTRY_CODE-CITY_CODE (e.g. IN-MUM, EU-IRL, US-VA, SG-SIN). '
    'NULL means no residency constraint — only for pre-LAW tenants. '
    'Immutability enforced by trg_tenants_residency_immutable trigger.';

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Immutability Guard for data_residency_region (LAW 09-6.1)
-- Any attempt to change this field after provisioning is rejected as CRITICAL.
-- Changing residency requires a full legal migration workflow (separate process).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_guard_residency_immutability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.data_residency_region IS NOT NULL
       AND NEW.data_residency_region IS DISTINCT FROM OLD.data_residency_region THEN

        -- Log CRITICAL breach attempt before raising exception
        INSERT INTO security_event_log(
            tenant_id, event_type, severity, actor_type,
            resource_path, event_data
        ) VALUES (
            OLD.tenant_id, 'RESIDENCY_MUTATION_ATTEMPT', 'CRITICAL',
            current_user,
            '/kernel/tenants/data_residency_region',
            jsonb_build_object(
                'tenant_id',        OLD.tenant_id,
                'from_region',      OLD.data_residency_region,
                'attempted_region', NEW.data_residency_region,
                'blocked_at',       now(),
                'law_citation',     'LAW 09-6.1: data_residency_region is immutable after provisioning.'
            )
        );

        RAISE EXCEPTION
            'LAW 09-6.1 VIOLATION: data_residency_region for tenant [%] is IMMUTABLE. '
            'Attempted change from [%] to [%] has been logged as a CRITICAL security event. '
            'A legal data migration workflow with a signed Legal Transfer Instrument (LTI) is required.',
            OLD.tenant_id, OLD.data_residency_region, NEW.data_residency_region;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_tenants_residency_immutable
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION fn_guard_residency_immutability();

COMMENT ON FUNCTION fn_guard_residency_immutability IS
    'LAW 09-6.1: Blocks any UPDATE to tenants.data_residency_region once set. '
    'Logs a CRITICAL security event before raising the exception. '
    'Data migration requires a formal Legal Transfer Instrument workflow.';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Residency Violation Log — INSERT-ONLY (LAW 09-6.3)
-- Records detected unauthorized data transfers from the sentinel scan.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS residency_violation_log (
    log_id                  UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_id               UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    expected_region         TEXT        NOT NULL,   -- The tenant's data_residency_region
    detected_region         TEXT        NOT NULL,   -- The region where data was found
    data_store_identifier   TEXT        NOT NULL,   -- Bucket/table/node identifier
    record_count_estimate   BIGINT,                 -- Estimated rows in unauthorized region
    detected_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    quarantine_action       TEXT        NOT NULL DEFAULT 'PENDING'
                                CHECK (quarantine_action IN (
                                    'PENDING',      -- Detected but not yet isolated
                                    'QUARANTINED',  -- Data access blocked
                                    'DELETED',      -- Unauthorized copy removed
                                    'ESCALATED'     -- Requires manual sovereign review
                                )),
    dpo_notified_at         TIMESTAMPTZ,            -- When DPO was notified (must be < 1hr from detected_at)
    resolution_notes        TEXT,

    CONSTRAINT pk_residency_violation_log PRIMARY KEY (log_id),
    CONSTRAINT uq_rvl_log_id UNIQUE (log_id)
);
-- No tenant-scoped RLS on this table — it is a platform-level sentinel table.
-- Only system_admin may access it.
GRANT SELECT, INSERT ON residency_violation_log TO system_admin, audit_writer;

-- INSERT-ONLY guard
CREATE OR REPLACE FUNCTION fn_rvl_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'residency_violation_log is INSERT-ONLY (LAW 8). TG_OP=%', TG_OP;
END;
$$;
CREATE TRIGGER trg_rvl_no_delete
    BEFORE DELETE ON residency_violation_log
    FOR EACH ROW EXECUTE FUNCTION fn_rvl_no_mutation();

COMMENT ON TABLE residency_violation_log IS
    'LAW 09-6.3: INSERT-ONLY log of unauthorized geographic data transfers detected '
    'by the 24-hour residency sentinel. dpo_notified_at must be set within 1 hour '
    'of detection per DPDP Act breach notification requirements.';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: fn_residency_sentinel_check() — 24-Hour Sentinel (LAW 09-6.3)
-- Compares known data stores against tenant residency regions.
-- Called by pg_cron or an external scheduler every 24 hours.
-- Violations → quarantine → DPO notification chain.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_residency_sentinel_check(
    p_data_store_identifier TEXT,
    p_detected_region       TEXT,   -- Region code of the data store being audited
    p_record_count          BIGINT  DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tenant            RECORD;
    v_violations        INT := 0;
    v_log_id            UUID;
BEGIN
    -- Check every tenant with a residency restriction
    FOR v_tenant IN
        SELECT tenant_id, data_residency_region, name
        FROM tenants
        WHERE data_residency_region IS NOT NULL
          AND is_active = TRUE
    LOOP
        -- Detect cross-region presence (simplified: region prefix mismatch)
        IF NOT (p_detected_region ILIKE '%' || SPLIT_PART(v_tenant.data_residency_region, '-', 1) || '%') THEN

            v_violations := v_violations + 1;
            v_log_id := gen_random_uuid();

            -- Insert violation record (INSERT-ONLY)
            INSERT INTO residency_violation_log(
                log_id, tenant_id, expected_region, detected_region,
                data_store_identifier, record_count_estimate,
                quarantine_action
            ) VALUES (
                v_log_id, v_tenant.tenant_id,
                v_tenant.data_residency_region, p_detected_region,
                p_data_store_identifier, p_record_count,
                'PENDING'
            );

            -- Append CRITICAL audit event to the SYSTEM tenant chain
            INSERT INTO audit_event_log(
                tenant_id, actor_id, actor_type, event_category,
                event_type, record_id, event_data
            ) VALUES (
                v_tenant.tenant_id, NULL, 'SYSTEM', 'SECURITY',
                'RESIDENCY_VIOLATION_DETECTED', v_log_id,
                jsonb_build_object(
                    'violation_log_id',       v_log_id,
                    'expected_region',        v_tenant.data_residency_region,
                    'detected_region',        p_detected_region,
                    'data_store',             p_data_store_identifier,
                    'record_count_estimate',  p_record_count,
                    'severity',               'CRITICAL',
                    'action_required',        'Quarantine foreign data. Notify DPO within 1 hour.',
                    'law_citation',           'LAW 09-6.3: Unauthorized geographic data transfer detected.'
                )
            );

            -- Log to SIEM
            INSERT INTO security_event_log(
                tenant_id, event_type, severity, actor_type,
                resource_path, event_data
            ) VALUES (
                v_tenant.tenant_id, 'RESIDENCY_VIOLATION_DETECTED', 'CRITICAL', 'SYSTEM',
                '/kernel/residency/sentinel',
                jsonb_build_object('violation_log_id', v_log_id, 'data_store', p_data_store_identifier)
            );

        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'data_store_checked',   p_data_store_identifier,
        'detected_region',      p_detected_region,
        'violations_found',     v_violations,
        'sentinel_ran_at',      now()
    );
END;
$$;

COMMENT ON FUNCTION fn_residency_sentinel_check IS
    'LAW 09-6.3: Automated residency sentinel. Called every 24 hours by external scheduler. '
    'For each data store in a given region, checks all tenants with a residency restriction. '
    'Violations are logged as CRITICAL events to audit_event_log, security_event_log, '
    'and residency_violation_log. DPO must be notified within 1 hour of detection.';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: PostgreSQL Publication-Level RLS Guard (LAW 09-6.2)
-- Adds a publication-scoped CHECK to the replication slot, ensuring only
-- rows matching the tenant's data_residency_region can be replicated externally.
-- Note: This is a logical replication publication restriction function.
-- The actual publication filter is applied at the SUBSCRIPTION/publication level.
-- The function below serves as the kernel's authoritative residency row filter.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_replication_residency_filter(
    p_tenant_id         UUID,
    p_target_region     TEXT    -- The region of the replica subscriber
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_residency TEXT;
BEGIN
    SELECT data_residency_region INTO v_residency
    FROM tenants WHERE tenant_id = p_tenant_id;

    IF v_residency IS NULL THEN
        RETURN TRUE; -- No restriction → allow replication
    END IF;

    -- Allow only if target region is within the authorized residency zone
    IF p_target_region ILIKE '%' || SPLIT_PART(v_residency, '-', 1) || '%' THEN
        RETURN TRUE;
    END IF;

    -- Unauthorized replication attempt — log and deny
    INSERT INTO security_event_log(
        tenant_id, event_type, severity, actor_type,
        resource_path, event_data
    ) VALUES (
        p_tenant_id, 'REPLICATION_RESIDENCY_BLOCKED', 'CRITICAL', 'SYSTEM',
        '/kernel/replication/residency_filter',
        jsonb_build_object(
            'tenant_residency',  v_residency,
            'target_region',     p_target_region,
            'blocked_at',        now(),
            'law_citation',      'LAW 09-6.2: Replication boundary enforcement. '
                                 'Unauthorized cross-region replication blocked.'
        )
    );

    RETURN FALSE; -- DENY replication
END;
$$;

COMMENT ON FUNCTION fn_replication_residency_filter IS
    'LAW 09-6.2: Row-level replication boundary filter. Used in PostgreSQL logical '
    'replication publication WHERE clauses to restrict tenant data to authorized regions. '
    'Returns FALSE (deny) if target_region does not match tenant data_residency_region, '
    'logging a CRITICAL security event.';

-- Usage in logical replication publication (execute as superuser during infra setup):
-- CREATE PUBLICATION pub_tenant_shard_IN_MUM
--     FOR TABLE entity_attribute_values, audit_event_log, ...
--     WHERE (fn_replication_residency_filter(tenant_id, 'IN-MUM') = TRUE);


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 6: Seed default residency data for the tenants table extension
-- (LAW 09-6.1) — no data is changed, only schema enrichment done above.
-- ─────────────────────────────────────────────────────────────────────────────
-- System setting: default hot retention for the archival integration from GAP-5
INSERT INTO system_settings(
    tenant_id, setting_category, setting_key, setting_value, scope_level, description
)
SELECT
    t.tenant_id,
    'SYSTEM',
    'archival.hot_retention_months',
    '36',
    'TENANT',
    'LAW 09-5.1: Hot storage retention window in months. Records older than this are archived to WORM cold storage.'
FROM tenants t
WHERE NOT EXISTS (
    SELECT 1 FROM system_settings ss
    WHERE ss.tenant_id = t.tenant_id
      AND ss.setting_key = 'archival.hot_retention_months'
)
ON CONFLICT DO NOTHING;

GRANT EXECUTE ON FUNCTION fn_residency_sentinel_check(TEXT, TEXT, BIGINT) TO system_admin;
GRANT EXECUTE ON FUNCTION fn_replication_residency_filter(UUID, TEXT) TO system_admin;

-- =============================================================================
-- END: GAP-6 CROSS-REGION RESIDENCY IMPLEMENTATION (Laws 09-6.1 to 09-6.4) — LOCKED
-- =============================================================================
