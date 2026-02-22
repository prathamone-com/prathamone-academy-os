-- =============================================================================
-- PRATHAMONE ACADEMY OS — DATABASE SCHEMA
-- Layer 13  (Local AI Governance & Studybuddy Protocols)
-- =============================================================================
-- Complies with KMC v1.0 and SB-1 to SB-12 Laws.
-- =============================================================================

BEGIN;

-- 1. AI Capability Master (Registry & Capability Binding - LAW SB-1)
CREATE TABLE IF NOT EXISTS ai_capability_master (
    tenant_id           UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    capability_id       UUID            NOT NULL DEFAULT gen_random_uuid(),
    capability_code     TEXT            NOT NULL, -- e.g. 'STUDENT_STUDY_BUDDY'
    display_name        TEXT            NOT NULL,
    decision_scope      TEXT            NOT NULL CHECK (decision_scope IN ('ASSISTIVE', 'ADVISORY', 'EVALUATIVE')),
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_ai_capability PRIMARY KEY (tenant_id, capability_id),
    CONSTRAINT uq_ai_capability_code UNIQUE (tenant_id, capability_code)
);

-- 2. AI Role Access (Role-Bound Access - LAW SB-2)
CREATE TABLE IF NOT EXISTS ai_role_access (
    tenant_id           UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    access_id           UUID            NOT NULL DEFAULT gen_random_uuid(),
    capability_id       UUID            NOT NULL,
    role_code           TEXT            NOT NULL,
    access_level        TEXT            NOT NULL CHECK (access_level IN ('INTERACT', 'DECISION_SUPPORT')),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_ai_role_access PRIMARY KEY (tenant_id, access_id),
    CONSTRAINT fk_ara_capability FOREIGN KEY (tenant_id, capability_id)
        REFERENCES ai_capability_master(tenant_id, capability_id) ON DELETE CASCADE
);

-- 3. AI Execution Log (Mandatory Forensic Logging - LAW SB-7 / SB-8 / SB-9)
-- INSERT-ONLY. SHA-256 Hash Chained.
CREATE TABLE IF NOT EXISTS ai_execution_log (
    tenant_id               UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    log_id                  UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_sequence_number  BIGINT      NOT NULL,
    capability_id           UUID,
    actor_id                UUID,
    model_version           TEXT        NOT NULL,
    input_hash              TEXT        NOT NULL,
    output_hash             TEXT        NOT NULL,
    confidence_score        NUMERIC(5,4),
    decision_reason_code    TEXT,       -- LAW SB-9
    execution_data          JSONB       NOT NULL, -- {prompt, response}
    previous_hash           TEXT,
    current_hash            TEXT        NOT NULL,
    logged_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_ai_execution_log PRIMARY KEY (tenant_id, log_id),
    CONSTRAINT fk_ael_capability FOREIGN KEY (tenant_id, capability_id)
        REFERENCES ai_capability_master(tenant_id, capability_id) ON DELETE SET NULL
);

-- 4. Audit Triggers for AI Execution Log (LAW 8 / SB-8)
CREATE OR REPLACE FUNCTION fn_ai_execution_log_before_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_next_seq      BIGINT;
    v_prev_hash     TEXT;
    v_hash_input    TEXT;
BEGIN
    -- Claim sequence
    INSERT INTO audit_tenant_sequence (tenant_id, last_seq)
    VALUES (NEW.tenant_id, 1)
    ON CONFLICT (tenant_id)
    DO UPDATE SET last_seq = audit_tenant_sequence.last_seq + 1
    RETURNING last_seq INTO v_next_seq;

    NEW.tenant_sequence_number := v_next_seq;

    -- Fetch previous hash
    SELECT current_hash INTO v_prev_hash FROM ai_execution_log
    WHERE tenant_id = NEW.tenant_id AND tenant_sequence_number = v_next_seq - 1;

    NEW.previous_hash := v_prev_hash;

    -- Compute current hash
    v_hash_input := COALESCE(v_prev_hash, 'GENESIS_AI')
                 || '|' || NEW.log_id::TEXT
                 || '|' || NEW.input_hash
                 || '|' || NEW.output_hash
                 || '|' || NEW.logged_at::TEXT;

    NEW.current_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ai_execution_log_before_insert
    BEFORE INSERT ON ai_execution_log
    FOR EACH ROW EXECUTE FUNCTION fn_ai_execution_log_before_insert();

-- Immutability Guard
CREATE OR REPLACE FUNCTION fn_ai_execution_log_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'ai_execution_log is INSERT-ONLY (LAW 8). Mutation forbidden.';
END;
$$;

CREATE TRIGGER trg_ai_ael_no_update BEFORE UPDATE ON ai_execution_log FOR EACH ROW EXECUTE FUNCTION fn_ai_execution_log_no_mutation();
CREATE TRIGGER trg_ai_ael_no_delete BEFORE DELETE ON ai_execution_log FOR EACH ROW EXECUTE FUNCTION fn_ai_execution_log_no_mutation();

-- 5. AI User Preferences (LAW SB-12)
CREATE TABLE IF NOT EXISTS ai_user_preferences (
    tenant_id           UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    user_id             UUID            NOT NULL,
    preference_key      TEXT            NOT NULL, -- e.g. 'explanation_depth'
    preference_value    TEXT            NOT NULL,
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_ai_user_prefs PRIMARY KEY (tenant_id, user_id, preference_key)
);

-- 6. RLS Policies
ALTER TABLE ai_capability_master  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_role_access       ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_execution_log     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_user_preferences   ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_ai_capability ON ai_capability_master USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);
CREATE POLICY rls_ai_role_access ON ai_role_access USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);
CREATE POLICY rls_ai_exec_log    ON ai_execution_log USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);
CREATE POLICY rls_ai_user_prefs  ON ai_user_preferences USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

COMMIT;
