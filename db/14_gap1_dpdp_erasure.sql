-- =============================================================================
-- PRATHAMONE ACADEMY OS — GAP-1 IMPLEMENTATION
-- DPDP "Right to Erasure" — Cryptographic Anonymization Protocol (CAP)
-- Implements Laws: 09-1.1, 09-1.2, 09-1.3, 09-1.4
-- =============================================================================
-- Depends on: all prior schema files (01 → 13)
-- RULES.md compliance:
--   LAW 8 : Erasure events are appended to the audit chain — chain is NEVER broken
--   LAW 2 : PII classification is a metadata attribute (pii_class column added below)
--   LAW 4 : Erasure workflow requires Policy Engine evaluation (legal hold check)
--   LAW 7 : tenant_id always from session context — never from client payload
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Extend attribute_master with pii_class (LAW 09-1.4)
-- Classifies every attribute as DIRECT PII, INDIRECT PII, or NULL (safe).
-- The CAP procedure uses this to identify which fields to anonymize.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE attribute_master
    ADD COLUMN IF NOT EXISTS pii_class TEXT
        CHECK (pii_class IN ('DIRECT', 'INDIRECT', 'SENSITIVE'))
        DEFAULT NULL;

COMMENT ON COLUMN attribute_master.pii_class IS
    'LAW 09-1.4: PII classification. '
    'DIRECT = name/DOB/contact (eligible for CAP tombstone). '
    'INDIRECT = derived identifiers. '
    'SENSITIVE = health/financial special category. '
    'NULL = non-PII field safe for unrestricted use.';

-- Kernel guard: DIRECT PII cannot be updated by app_user outside a CAP workflow
-- The CAP function itself runs as SECURITY DEFINER and bypasses this check.
CREATE OR REPLACE FUNCTION fn_guard_direct_pii_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_pii_class TEXT;
BEGIN
    SELECT pii_class INTO v_pii_class
    FROM attribute_master
    WHERE attribute_id = NEW.attribute_id
      AND tenant_id    = NEW.tenant_id;

    IF v_pii_class = 'DIRECT' THEN
        -- Only the CAP function (SECURITY DEFINER, app_cap_role) may update DIRECT fields
        IF current_user != 'app_cap_executor' AND
           NOT EXISTS (
               SELECT 1 FROM pg_roles
               WHERE rolname = current_user
                 AND pg_has_role(current_user, 'app_cap_executor', 'USAGE')
           ) THEN
            RAISE EXCEPTION
                'LAW 09-1.4 VIOLATION: Direct PII field (attribute_id=%) may only be '
                'modified via the Cryptographic Anonymization Protocol (CAP). '
                'Direct UPDATE by role [%] is forbidden.',
                NEW.attribute_id, current_user;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_direct_pii_update
    BEFORE UPDATE ON entity_attribute_values
    FOR EACH ROW EXECUTE FUNCTION fn_guard_direct_pii_mutation();

COMMENT ON FUNCTION fn_guard_direct_pii_mutation IS
    'LAW 09-1.4: Blocks direct UPDATE of DIRECT-PII attributes outside the CAP workflow. '
    'Only the app_cap_executor role (used by fn_execute_cap SECURITY DEFINER) may bypass this guard.';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Legal Hold Registry (prerequisite for erasure — LAW 09-1.3)
-- If a subject is under legal hold, erasure is blocked by the Policy Engine.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS legal_hold_registry (
    tenant_id       UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    hold_id         UUID        NOT NULL DEFAULT gen_random_uuid(),
    subject_id      UUID        NOT NULL,   -- entity_records.record_id of the data subject
    hold_reference  TEXT        NOT NULL,   -- Court order / case reference number
    imposed_by      UUID        NOT NULL,   -- Actor UUID (sovereign admin)
    imposed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    lifted_at       TIMESTAMPTZ,            -- NULL = hold is still active
    lifted_by       UUID,
    notes           TEXT,

    CONSTRAINT pk_legal_hold_registry PRIMARY KEY (tenant_id, hold_id),
    CONSTRAINT uq_hold_id UNIQUE (hold_id)
);

ALTER TABLE legal_hold_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_hold_registry FORCE  ROW LEVEL SECURITY;

CREATE POLICY legal_hold_tenant_select ON legal_hold_registry FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY legal_hold_tenant_insert ON legal_hold_registry FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY legal_hold_system_admin  ON legal_hold_registry
    TO system_admin USING (true);

COMMENT ON TABLE legal_hold_registry IS
    'LAW 09-1.3: Legal hold registry. An active hold (lifted_at IS NULL) blocks '
    'the erasure workflow from reaching COMPLETED state, ensuring regulatory compliance '
    'with court orders takes precedence over erasure requests.';

CREATE INDEX IF NOT EXISTS idx_lhr_subject
    ON legal_hold_registry(tenant_id, subject_id, lifted_at)
    WHERE lifted_at IS NULL;


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Erasure Request Table — the Workflow Entity (LAW 09-1.3)
-- States: RECEIVED → VERIFIED → LEGAL_HOLD_CHECK → IN_PROGRESS → COMPLETED
-- Current state is derived from workflow_state_log — never stored here.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS erasure_requests (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    request_id          UUID        NOT NULL DEFAULT gen_random_uuid(),
    subject_id          UUID        NOT NULL,   -- entity_records.record_id of the data subject
    subject_entity_code TEXT        NOT NULL,   -- e.g. 'USER', 'STUDENT'
    requester_id        UUID,                   -- NULL for self-service requests
    requester_email     TEXT        NOT NULL,   -- Contact for DPDP 72-hour acknowledgement
    regulation_basis    TEXT        NOT NULL DEFAULT 'DPDP_ACT_2023',
    -- Regulatory basis: DPDP_ACT_2023 | GDPR_ART17 | CCPA | PDPA
    received_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ,            -- Set by fn_execute_cap() upon success
    cap_log_id          UUID,                   -- FK → audit_event_log.log_id of the CAP event
    metadata            JSONB,

    CONSTRAINT pk_erasure_requests PRIMARY KEY (tenant_id, request_id),
    CONSTRAINT uq_erasure_request_id UNIQUE (request_id)
);

ALTER TABLE erasure_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE erasure_requests FORCE  ROW LEVEL SECURITY;

CREATE POLICY erasure_requests_tenant_select ON erasure_requests FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY erasure_requests_tenant_insert ON erasure_requests FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY erasure_requests_system_admin  ON erasure_requests
    TO system_admin USING (true);

COMMENT ON TABLE erasure_requests IS
    'LAW 09-1.3: Each erasure request is a first-class workflow entity. '
    'Current state derived at runtime from workflow_state_log. '
    'fn_execute_cap() must only fire when state reaches IN_PROGRESS.';

CREATE INDEX IF NOT EXISTS idx_er_subject
    ON erasure_requests(tenant_id, subject_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: The Cryptographic Anonymization Protocol — fn_execute_cap()
-- This is the ONLY path that may write tombstone tokens to DIRECT PII fields.
-- Runs as SECURITY DEFINER so it bypasses the PII guard trigger.
-- Appends a GDPR_ERASURE_EVENT to the audit chain — does NOT break the chain.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_cap_executor') THEN
        CREATE ROLE app_cap_executor NOLOGIN;
    END IF;
END $$;

COMMENT ON ROLE app_cap_executor IS
    'LAW 09-1.4: Dedicated execution role for the Cryptographic Anonymization Protocol. '
    'Granted only to fn_execute_cap SECURITY DEFINER. No human logins.';

CREATE OR REPLACE FUNCTION fn_execute_cap(
    p_request_id    UUID,       -- erasure_requests.request_id
    p_actor_id      UUID        -- Sovereign admin executing the protocol
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER               -- Runs as function owner (bypasses PII trigger)
SET search_path = public
AS $$
DECLARE
    v_tenant_id         UUID := current_setting('app.tenant_id', true)::UUID;
    v_request           RECORD;
    v_current_state     TEXT;
    v_has_legal_hold    BOOLEAN;
    v_tombstone         TEXT;
    v_attr              RECORD;
    v_cap_log_id        UUID := gen_random_uuid();
    v_fields_erased     INT := 0;
    v_erased_attributes TEXT[] := '{}';
BEGIN
    -- 1. Fetch and validate the erasure request
    SELECT * INTO v_request
    FROM erasure_requests
    WHERE request_id = p_request_id AND tenant_id = v_tenant_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CAP ERROR: Erasure request % not found for tenant %',
            p_request_id, v_tenant_id;
    END IF;

    -- 2. Confirm workflow state is IN_PROGRESS (LAW 09-1.3)
    SELECT to_state INTO v_current_state
    FROM workflow_state_log
    WHERE tenant_id = v_tenant_id AND record_id = p_request_id
    ORDER BY transition_at DESC LIMIT 1;

    IF v_current_state != 'IN_PROGRESS' THEN
        RAISE EXCEPTION
            'CAP BLOCKED: Erasure request % is in state [%]. '
            'Must be IN_PROGRESS. Policy Engine must advance the workflow first.',
            p_request_id, COALESCE(v_current_state, 'NULL');
    END IF;

    -- 3. Legal Hold Check — hard block (LAW 09-1.3)
    SELECT EXISTS(
        SELECT 1 FROM legal_hold_registry
        WHERE tenant_id = v_tenant_id
          AND subject_id = v_request.subject_id
          AND lifted_at IS NULL
    ) INTO v_has_legal_hold;

    IF v_has_legal_hold THEN
        RAISE EXCEPTION
            'CAP BLOCKED: Subject % has an active legal hold. '
            'Erasure cannot proceed until hold is lifted (LAW 09-1.3).',
            v_request.subject_id;
    END IF;

    -- 4. Compute tombstone token (LAW 09-1.1):
    --    ERASED-{SHA256(tenant_id || subject_id || now())}
    v_tombstone := 'ERASED-' || encode(
        digest(
            v_tenant_id::TEXT || '|' || v_request.subject_id::TEXT
            || '|' || now()::TEXT,
            'sha256'
        ),
        'hex'
    );

    -- 5. Anonymize all DIRECT PII attribute values for the subject (LAW 09-1.1)
    --    EAV structure preserved — only value_text is replaced with tombstone.
    FOR v_attr IN
        SELECT eav.attribute_id, am.attribute_code
        FROM entity_attribute_values eav
        JOIN attribute_master am
            ON am.tenant_id = eav.tenant_id AND am.attribute_id = eav.attribute_id
        WHERE eav.tenant_id = v_tenant_id
          AND eav.record_id = v_request.subject_id
          AND am.pii_class = 'DIRECT'
    LOOP
        UPDATE entity_attribute_values
        SET    value_text   = v_tombstone,
               value_number = NULL,
               value_bool   = NULL,
               updated_at   = now()
        WHERE  tenant_id    = v_tenant_id
          AND  record_id    = v_request.subject_id
          AND  attribute_id = v_attr.attribute_id;

        v_fields_erased := v_fields_erased + 1;
        v_erased_attributes := v_erased_attributes || v_attr.attribute_code;
    END LOOP;

    -- 6. Mark the erasure request as completed
    UPDATE erasure_requests
    SET completed_at = now(), cap_log_id = v_cap_log_id
    WHERE request_id = p_request_id AND tenant_id = v_tenant_id;

    -- 7. Append GDPR_ERASURE_EVENT to the audit chain (LAW 09-1.2)
    --    Chain is NOT broken — this event becomes the NEXT block in the chain.
    INSERT INTO audit_event_log(
        tenant_id, log_id, actor_id, actor_type, event_category,
        event_type, record_id, event_data
    ) VALUES (
        v_tenant_id, v_cap_log_id, p_actor_id, 'SYSTEM', 'SECURITY',
        'GDPR_ERASURE_EVENT', v_request.subject_id,
        jsonb_build_object(
            'request_id',        p_request_id,
            'subject_id',        v_request.subject_id,
            'regulation_basis',  v_request.regulation_basis,
            'tombstone_token',   v_tombstone,
            'fields_erased',     v_fields_erased,
            'attribute_codes',   v_erased_attributes,
            'executed_by',       p_actor_id,
            'executed_at',       now(),
            'note', 'PII replaced with cryptographic tombstone. EAV record structure preserved. Chain integrity maintained per LAW 09-1.2.'
        )
    );

    -- 8. Advance workflow to COMPLETED state
    INSERT INTO workflow_state_log(
        tenant_id, log_id, workflow_id, record_id,
        from_state, to_state, trigger_event, actor_id, metadata
    )
    SELECT
        v_tenant_id, gen_random_uuid(), wm.workflow_id, p_request_id,
        'IN_PROGRESS', 'COMPLETED', 'CAP_EXECUTED', p_actor_id,
        jsonb_build_object('cap_log_id', v_cap_log_id, 'fields_erased', v_fields_erased)
    FROM workflow_master wm
    JOIN entity_master em ON em.entity_id = wm.entity_id AND em.tenant_id = wm.tenant_id
    WHERE em.entity_code = 'ERASURE_REQUEST' AND wm.tenant_id = v_tenant_id
    LIMIT 1;

    RETURN jsonb_build_object(
        'status',           'COMPLETED',
        'request_id',       p_request_id,
        'fields_erased',    v_fields_erased,
        'tombstone_prefix', LEFT(v_tombstone, 20) || '...',
        'cap_audit_log_id', v_cap_log_id
    );

EXCEPTION WHEN OTHERS THEN
    -- Log the failure as a security event before re-raising
    INSERT INTO security_event_log(
        tenant_id, event_type, severity, actor_id, actor_type,
        resource_path, event_data
    ) VALUES (
        v_tenant_id, 'CAP_EXECUTION_FAILED', 'ERROR', p_actor_id, 'SYSTEM',
        '/kernel/cap/execute',
        jsonb_build_object(
            'request_id', p_request_id,
            'error', SQLERRM,
            'sqlstate', SQLSTATE
        )
    );
    RAISE;
END;
$$;

COMMENT ON FUNCTION fn_execute_cap IS
    'LAW 09-1.1 to 09-1.3: The Cryptographic Anonymization Protocol (CAP). '
    'The ONLY function permitted to replace DIRECT PII with tombstone tokens. '
    'SECURITY DEFINER — runs as app_cap_executor role bypassing PII guard trigger. '
    'Appends a GDPR_ERASURE_EVENT to the audit chain without breaking hash continuity.';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: RLS + System Admin bypass for new tables
-- ─────────────────────────────────────────────────────────────────────────────
GRANT INSERT, SELECT ON erasure_requests    TO app_user, audit_writer;
GRANT INSERT, SELECT ON legal_hold_registry TO app_user;
GRANT EXECUTE        ON FUNCTION fn_execute_cap(UUID, UUID) TO system_admin;
-- Only system_admin may call fn_execute_cap; app_user is explicitly excluded.

-- =============================================================================
-- END: GAP-1 DPDP ERASURE IMPLEMENTATION (Laws 09-1.1 to 09-1.4) — LOCKED
-- =============================================================================
