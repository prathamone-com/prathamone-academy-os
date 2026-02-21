-- =============================================================================
-- PRATHAMONE ACADEMY OS — DATABASE SCHEMA
-- Layers 7 → 9  (AI Registry · System Settings · Immutable Audit Chain)
-- =============================================================================
-- Depends on: db/schema_layer0_layer3.sql  (must be applied first)
--             db/schema_layer4_layer6.sql  (must be applied second)
--
-- RULES.MD compliance checklist applied to every table in this file:
--   LAW 1  : All entities registered in entity_master (Layer 1)
--   LAW 2  : No custom columns — variable data lives in EAV (Layer 6)
--   LAW 3  : No if(status==) in code — workflow_transition_rules drive state
--   LAW 4  : Policies evaluate BEFORE workflow transitions
--   LAW 5  : system_settings implements "Settings decide DEFAULT" (LAW 5)
--   LAW 6  : tenant_id FK on EVERY table — no exceptions
--   LAW 7  : tenant_id injected server-side; frontend NEVER sends it
--   LAW 8  : All audit tables are INSERT-ONLY; triggers + role GRANT enforce it
--   LAW 9  : No raw SQL in feature code; reports are declarative metadata
--   LAW 10 : No rank/grade/pass-fail stored; derived at runtime
--   LAW 11 : New modules add rows, never new tables
--   LAW 12 : The kernel is locked; features are data
-- =============================================================================


-- =============================================================================
-- LAYER 7 — AI INTEGRATION LAYER
-- Purpose: Registers every AI/ML model the OS can call, and tracks every
--          async AI task (inference request, batch job, evaluation run) as
--          a first-class entity with workflow-backed lifecycle management.
--
-- Design principles:
--   • ai_model_registry is the single source of truth for model endpoints.
--     Application code NEVER hard-codes a model name or URL (LAW 12).
--   • ai_tasks integrates with Layer 4 workflow_master so task lifecycle
--     (QUEUED → RUNNING → SUCCEEDED / FAILED / RETRYING) is driven by
--     workflow_transition_rules, not by if(status==) checks (LAW 3).
--   • Prompt content and response payloads are stored as JSONB — never as
--     plain TEXT — so the AI layer can evolve its schema without migrations.
--   • No model response is ever persisted as a grade, rank, or score column
--     (LAW 10); downstream consumers derive those at query time.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- ai_model_registry
-- One row per AI/ML model or service the OS can invoke.
-- Covers LLMs, embedding models, vision models, custom classifiers, etc.
-- Application code resolves model endpoints by (tenant_id, model_code), never
-- by hard-coded URLs or provider names — satisfying LAW 12.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_model_registry (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    model_id            UUID        NOT NULL DEFAULT gen_random_uuid(),
    model_code          TEXT        NOT NULL,
    -- Machine identifier: e.g. 'gemini-3-pro', 'text-embedding-004', 'whisper-large-v3'
    display_name        TEXT        NOT NULL,
    provider            TEXT        NOT NULL,
    -- Provider label: GOOGLE | OPENAI | ANTHROPIC | MISTRAL | SELF_HOSTED | CUSTOM
    model_type          TEXT        NOT NULL
                            CHECK (model_type IN (
                                'LLM','EMBEDDING','VISION','SPEECH_TO_TEXT',
                                'TEXT_TO_SPEECH','CLASSIFIER','RERANKER','CUSTOM'
                            )),
    endpoint_url        TEXT,
    -- NULL for provider-SDK-resolved models (e.g. Gemini via API key)
    -- Non-NULL for self-hosted / custom inference servers
    api_key_secret_ref  TEXT,
    -- Reference to a secret manager key (never store the actual key here)
    -- e.g. 'projects/prathamone/secrets/gemini-api-key/versions/latest'
    capabilities        TEXT[]      NOT NULL DEFAULT '{}',
    -- e.g. {'chat','function_calling','json_mode','vision','long_context'}
    context_window      INT,
    -- Max tokens in context; NULL for non-LLM models
    max_output_tokens   INT,
    input_cost_per_1k   NUMERIC(12,6),
    -- USD per 1 000 input tokens/units; NULL = unknown / not applicable
    output_cost_per_1k  NUMERIC(12,6),
    -- USD per 1 000 output tokens/units
    is_default          BOOLEAN     NOT NULL DEFAULT FALSE,
    -- Is this the tenant's default model for a given model_type?
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    model_config        JSONB,
    -- Provider-specific config: temperature, top_p, safety_settings, etc.
    -- Stored as JSONB so it evolves without schema migrations (LAW 11)
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_ai_model_registry PRIMARY KEY (tenant_id, model_id),
    CONSTRAINT uq_ai_model_id UNIQUE (model_id),
    CONSTRAINT uq_ai_model_code UNIQUE (tenant_id, model_code)
);

COMMENT ON TABLE  ai_model_registry                   IS 'Layer 7: Single source of truth for every AI/ML model the OS can invoke. Application code resolves endpoints here — never hard-codes URLs or model names (LAW 12).';
COMMENT ON COLUMN ai_model_registry.model_code        IS 'Tenant-scoped machine identifier e.g. "gemini-3-pro". Used by application code to resolve the model at runtime.';
COMMENT ON COLUMN ai_model_registry.provider          IS 'Commercial or hosting label: GOOGLE | OPENAI | ANTHROPIC | MISTRAL | SELF_HOSTED | CUSTOM.';
COMMENT ON COLUMN ai_model_registry.model_type        IS 'Task category: LLM | EMBEDDING | VISION | SPEECH_TO_TEXT | TEXT_TO_SPEECH | CLASSIFIER | RERANKER | CUSTOM.';
COMMENT ON COLUMN ai_model_registry.endpoint_url      IS 'Base inference URL for self-hosted models. NULL for provider-SDK models resolved via API key.';
COMMENT ON COLUMN ai_model_registry.api_key_secret_ref IS 'Secret Manager reference path. The actual credential is NEVER stored in this column.';
COMMENT ON COLUMN ai_model_registry.capabilities      IS 'Array of capability tags: chat, function_calling, json_mode, vision, long_context, streaming.';
COMMENT ON COLUMN ai_model_registry.context_window    IS 'Maximum token context length. NULL for non-token-based models.';
COMMENT ON COLUMN ai_model_registry.model_config      IS 'Provider-specific JSONB config (temperature, top_p, safety thresholds). Evolves without migrations (LAW 11).';
COMMENT ON COLUMN ai_model_registry.is_default        IS 'TRUE marks this as the tenant default for its model_type. Enforce at most one TRUE per (tenant_id, model_type) at application layer.';

CREATE INDEX IF NOT EXISTS idx_ai_model_type
    ON ai_model_registry(tenant_id, model_type, is_active);
CREATE INDEX IF NOT EXISTS idx_ai_model_default
    ON ai_model_registry(tenant_id, model_type, is_default)
    WHERE is_default = TRUE;


-- -----------------------------------------------------------------------------
-- ai_tasks
-- Every AI inference request, batch evaluation, or async AI job is a row here.
-- Task lifecycle is managed through Layer 4 workflow_master (LAW 3):
--   QUEUED → RUNNING → SUCCEEDED | FAILED | RETRYING → CANCELLED
-- Input and output are stored as JSONB so the schema is forward-compatible
-- with any model provider.  No derived scores or grades are stored (LAW 10).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_tasks (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    task_id             UUID        NOT NULL DEFAULT gen_random_uuid(),
    model_id            UUID        NOT NULL,
    -- FK → ai_model_registry
    task_type           TEXT        NOT NULL,
    -- e.g. QUESTION_GENERATION | ESSAY_EVALUATION | TRANSCRIPT_SUMMARY |
    --      EMBEDDING | CONTENT_MODERATION | TUTORING_RESPONSE | CUSTOM
    source_record_id    UUID,
    -- Optional: UUID of the entity record that triggered this task
    source_entity_id    UUID,
    -- Optional: entity_master.entity_id of the triggering record
    initiated_by        UUID,
    -- Actor UUID (user or system service); FK resolved at app layer
    workflow_instance_id UUID,
    -- FK → workflow_instance_state.instance_id (manages task lifecycle)
    input_payload       JSONB       NOT NULL,
    -- Structured prompt/input to the model; NEVER stored as raw TEXT (LAW 9)
    output_payload      JSONB,
    -- Structured model response; NULL until task completes
    -- LAW 10: no score/grade columns; calling code derives them at runtime
    token_usage         JSONB,
    -- {"input_tokens": N, "output_tokens": N, "total_tokens": N}
    cost_usd            NUMERIC(12,6),
    -- Actual billed cost; NULL until confirmed by provider callback
    error_payload       JSONB,
    -- Structured error details when task fails; NULL on success
    retry_count         INT         NOT NULL DEFAULT 0,
    max_retries         INT         NOT NULL DEFAULT 3,
    priority            INT         NOT NULL DEFAULT 50,
    -- 0 = highest, 100 = lowest; used by task queue scheduler
    queued_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    metadata            JSONB,
    -- Arbitrary context bag: correlation_id, request_id, feature_flag, etc.

    CONSTRAINT pk_ai_tasks PRIMARY KEY (tenant_id, task_id),
    CONSTRAINT uq_ai_task_id UNIQUE (task_id),
    CONSTRAINT fk_at_model FOREIGN KEY (tenant_id, model_id)
        REFERENCES ai_model_registry(tenant_id, model_id) ON DELETE RESTRICT,
    CONSTRAINT fk_at_workflow_instance FOREIGN KEY (tenant_id, workflow_instance_id)
        REFERENCES workflow_instance_state(tenant_id, instance_id) ON DELETE SET NULL
);

COMMENT ON TABLE  ai_tasks                        IS 'Layer 7: Every AI inference request and async AI job. Lifecycle managed by Layer 4 workflow. LAW 3: no if(status==) — transitions drive state. LAW 10: no scores stored.';
COMMENT ON COLUMN ai_tasks.task_type              IS 'Descriptor of the AI operation: QUESTION_GENERATION | ESSAY_EVALUATION | TRANSCRIPT_SUMMARY | EMBEDDING | CONTENT_MODERATION | TUTORING_RESPONSE | CUSTOM.';
COMMENT ON COLUMN ai_tasks.source_record_id       IS 'UUID of the entity_records row that triggered this task, enabling result linkage.';
COMMENT ON COLUMN ai_tasks.workflow_instance_id   IS 'FK to workflow_instance_state that governs this task''s QUEUED→RUNNING→DONE lifecycle.';
COMMENT ON COLUMN ai_tasks.input_payload          IS 'Structured JSONB prompt/input to the model. No raw text strings (LAW 9).';
COMMENT ON COLUMN ai_tasks.output_payload         IS 'Structured JSONB response from the model. NULL until completed. LAW 10: no score/grade columns.';
COMMENT ON COLUMN ai_tasks.token_usage            IS 'JSONB token accounting: {input_tokens, output_tokens, total_tokens}.';
COMMENT ON COLUMN ai_tasks.cost_usd               IS 'Billed cost in USD. NULL until confirmed by provider. Used for tenant cost reporting.';
COMMENT ON COLUMN ai_tasks.priority               IS 'Queue priority: 0 = highest, 100 = lowest. Scheduler orders by (priority, queued_at).';

CREATE INDEX IF NOT EXISTS idx_at_model
    ON ai_tasks(tenant_id, model_id);
CREATE INDEX IF NOT EXISTS idx_at_source_record
    ON ai_tasks(tenant_id, source_record_id)
    WHERE source_record_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_at_queued
    ON ai_tasks(tenant_id, priority, queued_at)
    WHERE completed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_at_workflow_instance
    ON ai_tasks(tenant_id, workflow_instance_id)
    WHERE workflow_instance_id IS NOT NULL;


-- =============================================================================
-- LAYER 8 — SYSTEM SETTINGS
-- Purpose: Implements LAW 5 ("Settings decide DEFAULT").
--          Every configurable default in the OS is a row in this table.
--          Application code reads settings from here at runtime; it never
--          hard-codes defaults inside feature logic.
--
-- Key design decisions:
--   • setting_category partitions settings into domains (ACADEMIC | FINANCE |
--     UI | SYSTEM | AI | INTEGRATION) — enables domain-scoped bulk reads.
--   • scope_level (GLOBAL | TENANT | SCHOOL | CLASS) controls the resolution
--     hierarchy: CLASS overrides SCHOOL overrides TENANT overrides GLOBAL.
--   • is_encrypted flags settings whose values are stored as references to
--     a secret manager (e.g. API keys, OAuth secrets) — never as plaintext.
--   • version_number supports optimistic concurrency and change auditing.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- system_settings
-- Central, multi-scope configuration store.
-- Resolves the "Settings decide DEFAULT" clause of LAW 5.
-- The resolution hierarchy (narrowest wins):
--   GLOBAL < TENANT < SCHOOL < CLASS
-- Application code calls get_setting(tenant_id, key, scope_ref_id?) and
-- receives the most-specific matching row. It never uses hard-coded defaults.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS system_settings (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    setting_id          UUID        NOT NULL DEFAULT gen_random_uuid(),
    setting_category    TEXT        NOT NULL
                            CHECK (setting_category IN (
                                'ACADEMIC','FINANCE','UI','SYSTEM','AI','INTEGRATION'
                            )),
    setting_key         TEXT        NOT NULL,
    -- Dot-namespaced key: e.g. 'academic.grading.passing_threshold'
    --                         'ai.default_model_code'
    --                         'finance.fee.late_penalty_pct'
    --                         'ui.theme.primary_color'
    --                         'integration.sms.provider'
    setting_value       TEXT        NOT NULL,
    -- Plain value for non-encrypted settings; secret-ref string for encrypted ones
    -- e.g. 'projects/prathamone/secrets/sms-api-key/versions/latest'
    scope_level         TEXT        NOT NULL
                            CHECK (scope_level IN ('GLOBAL','TENANT','SCHOOL','CLASS')),
    scope_ref_id        UUID,
    -- NULL for GLOBAL/TENANT scope; entity_records.record_id for SCHOOL/CLASS scope
    is_encrypted        BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE: setting_value is a secret-manager reference path, NOT the actual value
    description         TEXT,
    -- Human-readable explanation of what this setting controls
    version_number      INT         NOT NULL DEFAULT 1,
    -- Incremented on every UPDATE; used for optimistic concurrency checks
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          UUID,
    -- Actor who last changed this setting; FK resolved at app layer

    CONSTRAINT pk_system_settings PRIMARY KEY (tenant_id, setting_id),
    CONSTRAINT uq_system_setting_id UNIQUE (setting_id),
    CONSTRAINT uq_system_setting_scope UNIQUE (tenant_id, setting_key, scope_level, scope_ref_id)
);

COMMENT ON TABLE  system_settings                   IS 'Layer 8: Central multi-scope settings store. Implements LAW 5: Settings decide DEFAULT. Resolution hierarchy: GLOBAL < TENANT < SCHOOL < CLASS (narrowest wins).';
COMMENT ON COLUMN system_settings.setting_category  IS 'Domain partition: ACADEMIC | FINANCE | UI | SYSTEM | AI | INTEGRATION. Enables domain-scoped bulk reads.';
COMMENT ON COLUMN system_settings.setting_key       IS 'Dot-namespaced key: e.g. "academic.grading.passing_threshold", "ai.default_model_code".';
COMMENT ON COLUMN system_settings.setting_value     IS 'Plain value for non-encrypted settings. For is_encrypted=TRUE this is a secret-manager reference path, never the actual secret.';
COMMENT ON COLUMN system_settings.scope_level       IS 'Scope tier: GLOBAL | TENANT | SCHOOL | CLASS. Narrowest matching scope wins at resolution time.';
COMMENT ON COLUMN system_settings.scope_ref_id      IS 'For SCHOOL/CLASS scope: the entity_records.record_id of the school or class. NULL for GLOBAL/TENANT.';
COMMENT ON COLUMN system_settings.is_encrypted      IS 'TRUE means setting_value is a secret-manager reference. The actual credential is NEVER stored in this column.';
COMMENT ON COLUMN system_settings.version_number    IS 'Optimistic concurrency stamp. Application layer must pass current version when updating to prevent lost-write races.';
COMMENT ON COLUMN system_settings.updated_by        IS 'UUID of the actor (user or automation) that last changed this setting.';

CREATE INDEX IF NOT EXISTS idx_ss_category_key
    ON system_settings(tenant_id, setting_category, setting_key);
CREATE INDEX IF NOT EXISTS idx_ss_scope
    ON system_settings(tenant_id, setting_key, scope_level, scope_ref_id);
CREATE INDEX IF NOT EXISTS idx_ss_scope_ref
    ON system_settings(tenant_id, scope_ref_id)
    WHERE scope_ref_id IS NOT NULL;


-- =============================================================================
-- LAYER 9 — IMMUTABLE AUDIT CHAIN
-- Purpose: Cryptographically-chained, legally admissible audit storage.
--          Every significant event in the OS is appended here.
--          No row may ever be mutated or deleted (LAW 8, hard-enforced).
--
-- Immutability is enforced at THREE independent levels:
--   1. Database triggers: BEFORE UPDATE/DELETE → RAISE EXCEPTION
--   2. PostgreSQL role GRANT: app_role gets INSERT only (no UPDATE/DELETE)
--   3. Hash chain: each row hashes the previous row's hash, making any
--      tampering cryptographically detectable by chain verification.
--
-- Tables in this layer:
--   audit_event_log         — primary append-only event ledger (hash-chained)
--   audit_state_snapshot    — full-record state captures at key moments
--   tenant_activity_metrics — aggregated counters for analytics / billing
--   security_event_log      — authentication, authorisation, anomaly events
-- =============================================================================


-- -----------------------------------------------------------------------------
-- ROLE SETUP
-- Create the application role if it does not already exist.
-- This role is used by the FastAPI application server.
-- Privileges are STRIPPED to INSERT-only on all audit tables.
-- Note: CREATE ROLE is idempotent when wrapped in a DO block.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_role') THEN
        CREATE ROLE app_role NOLOGIN;
    END IF;
END;
$$;

COMMENT ON ROLE app_role
    IS 'Application server role. Granted INSERT-only on audit tables (Layer 9). UPDATE and DELETE are deliberately never granted.';


-- -----------------------------------------------------------------------------
-- audit_event_log
-- The primary, cryptographically-chained audit ledger.
-- Every row captures ONE event in the system.
-- Immutability enforced by:
--   1. fn_audit_event_log_no_mutation() trigger (BEFORE UPDATE/DELETE)
--   2. GRANT INSERT only to app_role (see GRANT statements below)
--   3. Hash chain: current_hash = SHA-256(previous_hash || event payload)
--
-- Hash-chain verification procedure:
--   For a given (tenant_id), iterate rows ordered by tenant_sequence_number.
--   Re-compute SHA-256(prev_row.current_hash || this_row.event_data::text).
--   Any mismatch indicates tampering.
--
-- tenant_sequence_number is a monotonic counter per tenant implemented via
-- a BEFORE INSERT trigger using a pg_sequence per tenant (or advisory lock).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_event_log (
    tenant_id               UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    log_id                  UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_sequence_number  BIGINT      NOT NULL,
    -- Monotonic per-tenant sequence; NEVER gaps. Used for chain verification.
    -- Set by trigger fn_audit_set_sequence() — app code MUST NOT write this column.
    actor_id                UUID,
    -- UUID of the user, service-account, or system agent that triggered the event
    actor_type              TEXT        NOT NULL DEFAULT 'USER',
    -- USER | SERVICE | SYSTEM | SCHEDULER | WEBHOOK
    event_category          TEXT        NOT NULL,
    -- ACADEMIC | FINANCE | AI | WORKFLOW | POLICY | SECURITY | SYSTEM | INTEGRATION
    event_type              TEXT        NOT NULL,
    -- Screaming-snake descriptor: e.g. SUBMISSION_CREATED, POLICY_DENIED, FEE_PAID
    entity_id               UUID,
    -- entity_master.entity_id of the affected entity type
    record_id               UUID,
    -- entity_records.record_id of the specific affected instance
    event_data              JSONB       NOT NULL,
    -- Full structured event payload — never raw SQL or PII in plaintext
    previous_hash           TEXT,
    -- SHA-256 hex of the PREVIOUS row's current_hash for this tenant.
    -- NULL only for the very first row of each tenant (genesis row).
    current_hash            TEXT        NOT NULL,
    -- SHA-256 hex of: SHA256(previous_hash || log_id::text || event_data::text || logged_at::text)
    -- Computed by trigger fn_audit_compute_hash() BEFORE INSERT.
    ip_address_hash         TEXT,
    -- SHA-256 hash of the actor's IP address (never store raw IP — privacy)
    session_id              TEXT,
    -- Opaque session reference; correlated with security_event_log
    logged_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_audit_event_log PRIMARY KEY (tenant_id, log_id),
    CONSTRAINT uq_audit_log_id UNIQUE (log_id),
    CONSTRAINT uq_audit_sequence UNIQUE (tenant_id, tenant_sequence_number)
);

COMMENT ON TABLE  audit_event_log                          IS 'Layer 9 / LAW 8: Primary cryptographically-chained, INSERT-ONLY audit ledger. Immutability enforced by trigger + role GRANT. Hash chain detects tampering.';
COMMENT ON COLUMN audit_event_log.tenant_sequence_number   IS 'Monotonic per-tenant sequence number. Set by trigger — never supplied by app code. No gaps; used for hash-chain verification.';
COMMENT ON COLUMN audit_event_log.actor_type               IS 'Source of the event: USER | SERVICE | SYSTEM | SCHEDULER | WEBHOOK.';
COMMENT ON COLUMN audit_event_log.event_category           IS 'Domain partition: ACADEMIC | FINANCE | AI | WORKFLOW | POLICY | SECURITY | SYSTEM | INTEGRATION.';
COMMENT ON COLUMN audit_event_log.event_type               IS 'Screaming-snake event descriptor: e.g. SUBMISSION_CREATED, POLICY_DENIED, FEE_PAID.';
COMMENT ON COLUMN audit_event_log.event_data               IS 'Structured JSONB event payload. No raw SQL fragments or plaintext PII.';
COMMENT ON COLUMN audit_event_log.previous_hash            IS 'SHA-256 hex of the previous row''s current_hash. NULL for genesis row (tenant_sequence_number = 1).';
COMMENT ON COLUMN audit_event_log.current_hash             IS 'SHA-256 hex digest chaining this row to the previous one. Recomputing and comparing detects tampering.';
COMMENT ON COLUMN audit_event_log.ip_address_hash          IS 'SHA-256 hash of actor IP address. Raw IP is never stored (privacy compliance).';

CREATE INDEX IF NOT EXISTS idx_ael_tenant_seq
    ON audit_event_log(tenant_id, tenant_sequence_number);
CREATE INDEX IF NOT EXISTS idx_ael_actor
    ON audit_event_log(tenant_id, actor_id, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_ael_record
    ON audit_event_log(tenant_id, record_id, logged_at DESC)
    WHERE record_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ael_event_type
    ON audit_event_log(tenant_id, event_category, event_type, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_ael_logged_at
    ON audit_event_log(tenant_id, logged_at DESC);


-- ·············································································
-- SEQUENCE TABLE for per-tenant monotonic audit counters
-- We use a dedicated keyed table (rather than one pg_sequence per tenant)
-- to avoid DDL churn when new tenants are provisioned.
-- The BEFORE INSERT trigger acquires a row-level lock on this table to
-- guarantee strict monotonicity without gaps.
-- ·············································································
CREATE TABLE IF NOT EXISTS audit_tenant_sequence (
    tenant_id       UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    last_seq        BIGINT      NOT NULL DEFAULT 0,

    CONSTRAINT pk_audit_tenant_sequence PRIMARY KEY (tenant_id)
);

COMMENT ON TABLE  audit_tenant_sequence         IS 'Layer 9: Per-tenant monotonic counter backing audit_event_log.tenant_sequence_number. Row-locked by trigger to guarantee strict ordering.';
COMMENT ON COLUMN audit_tenant_sequence.last_seq IS 'Most recently assigned sequence number for this tenant. Trigger increments atomically.';


-- ·············································································
-- TRIGGER 1: Compute hash and assign tenant_sequence_number
-- Fires BEFORE INSERT on audit_event_log.
-- Acquires a row-level FOR UPDATE lock on audit_tenant_sequence to serialize
-- concurrent inserts per tenant and guarantee no gaps.
-- ·············································································
CREATE OR REPLACE FUNCTION fn_audit_event_log_before_insert()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER     -- Runs as the function owner, not the caller
SET search_path = public
AS $$
DECLARE
    v_next_seq      BIGINT;
    v_prev_hash     TEXT;
    v_hash_input    TEXT;
BEGIN
    -- 1. Atomically claim the next sequence number (serialises concurrent inserts)
    INSERT INTO audit_tenant_sequence (tenant_id, last_seq)
    VALUES (NEW.tenant_id, 1)
    ON CONFLICT (tenant_id)
    DO UPDATE SET last_seq = audit_tenant_sequence.last_seq + 1
    RETURNING last_seq INTO v_next_seq;

    NEW.tenant_sequence_number := v_next_seq;

    -- 2. Fetch the current_hash of the previous row for this tenant
    SELECT current_hash
    INTO   v_prev_hash
    FROM   audit_event_log
    WHERE  tenant_id              = NEW.tenant_id
      AND  tenant_sequence_number = v_next_seq - 1;

    -- Genesis row has no predecessor; previous_hash stays NULL
    NEW.previous_hash := v_prev_hash;

    -- 3. Compute current_hash = SHA-256(previous_hash || log_id || event_data || logged_at)
    v_hash_input := COALESCE(v_prev_hash, 'GENESIS')
                 || '|' || NEW.log_id::TEXT
                 || '|' || NEW.event_data::TEXT
                 || '|' || NEW.logged_at::TEXT;

    NEW.current_hash := encode(
        digest(v_hash_input, 'sha256'),
        'hex'
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_event_log_before_insert
    BEFORE INSERT ON audit_event_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_event_log_before_insert();

COMMENT ON FUNCTION fn_audit_event_log_before_insert
    IS 'Assigns tenant_sequence_number (monotonic, no gaps) and computes SHA-256 hash chain for audit_event_log. Runs BEFORE INSERT; app code must not supply these columns.';


-- ·············································································
-- TRIGGER 2: Block UPDATE and DELETE on audit_event_log (LAW 8)
-- This trigger is the primary enforcement layer.
-- The role GRANT below (INSERT-only) is the secondary enforcement layer.
-- Both must INDEPENDENTLY prevent mutation.
-- ·············································································
CREATE OR REPLACE FUNCTION fn_audit_event_log_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION
        'audit_event_log is INSERT-ONLY forever (LAW 8). '
        'UPDATE and DELETE are criminally forbidden. '
        'TG_OP=%, tenant_id=%, log_id=%',
        TG_OP,
        COALESCE(OLD.tenant_id::TEXT, NEW.tenant_id::TEXT),
        COALESCE(OLD.log_id::TEXT,    NEW.log_id::TEXT);
END;
$$;

CREATE TRIGGER trg_audit_event_log_no_update
    BEFORE UPDATE ON audit_event_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_event_log_no_mutation();

CREATE TRIGGER trg_audit_event_log_no_delete
    BEFORE DELETE ON audit_event_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_event_log_no_mutation();

COMMENT ON FUNCTION fn_audit_event_log_no_mutation
    IS 'BEFORE UPDATE/DELETE guard on audit_event_log. Raises an exception immediately. Primary immutability enforcement layer for LAW 8.';


-- ·············································································
-- ROLE-LEVEL ENFORCEMENT (secondary layer — defence in depth)
-- app_role is the role used by the FastAPI application server.
-- It receives INSERT on audit_event_log but explicitly NOT UPDATE or DELETE.
-- This means even a compromised application cannot issue a mutating statement
-- against the audit log — the database will reject it at the authorization
-- layer BEFORE the trigger even fires.
-- ·············································································
GRANT INSERT ON TABLE audit_event_log          TO app_role;
GRANT INSERT ON TABLE audit_tenant_sequence    TO app_role;
-- Explicitly deny UPDATE and DELETE (belt-and-suspenders):
REVOKE UPDATE, DELETE ON TABLE audit_event_log       FROM app_role;
REVOKE UPDATE, DELETE ON TABLE audit_tenant_sequence FROM app_role;

-- Also grant SELECT so the application can perform chain verification reads:
GRANT SELECT ON TABLE audit_event_log          TO app_role;
GRANT SELECT ON TABLE audit_tenant_sequence    TO app_role;


-- -----------------------------------------------------------------------------
-- audit_state_snapshot
-- Full-record state capture at moments of high legal / compliance significance:
--   before and after a critical state transition, at financial events, etc.
-- Stores the complete EAV snapshot of a record as a JSONB blob so future
-- schema changes do not invalidate historical snapshots.
-- LAW 8: INSERT-ONLY.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_state_snapshot (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    snapshot_id         UUID        NOT NULL DEFAULT gen_random_uuid(),
    audit_log_id        UUID        NOT NULL,
    -- FK → audit_event_log.log_id; links snapshot to its triggering event
    record_id           UUID        NOT NULL,
    entity_id           UUID        NOT NULL,
    snapshot_type       TEXT        NOT NULL
                            CHECK (snapshot_type IN ('BEFORE','AFTER','POINT_IN_TIME')),
    state_data          JSONB       NOT NULL,
    -- Full attribute-value snapshot of the record at this moment.
    -- Format: {"attribute_code": value, ...}
    -- Captured from entity_attribute_values at snapshot time.
    workflow_state_code TEXT,
    -- Current workflow state of the record at snapshot time (if applicable)
    captured_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_audit_state_snapshot PRIMARY KEY (tenant_id, snapshot_id),
    CONSTRAINT uq_snapshot_id UNIQUE (snapshot_id),
    CONSTRAINT fk_ass_audit_log FOREIGN KEY (tenant_id, audit_log_id)
        REFERENCES audit_event_log(tenant_id, log_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  audit_state_snapshot                  IS 'Layer 9 / LAW 8: Full-record state captures linked to audit events. JSONB snapshot survives future schema changes. INSERT-ONLY.';
COMMENT ON COLUMN audit_state_snapshot.audit_log_id     IS 'FK to the audit_event_log entry that triggered this snapshot.';
COMMENT ON COLUMN audit_state_snapshot.snapshot_type    IS 'Timing of capture: BEFORE (pre-transition) | AFTER (post-transition) | POINT_IN_TIME (on-demand).';
COMMENT ON COLUMN audit_state_snapshot.state_data       IS 'JSONB map of {attribute_code: value} for the record at capture time. Immutable after insert.';
COMMENT ON COLUMN audit_state_snapshot.workflow_state_code IS 'workflow_states.state_code at capture time — denormalised for forensic readability.';

-- INSERT-ONLY guard (LAW 8)
CREATE OR REPLACE FUNCTION fn_audit_state_snapshot_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit_state_snapshot is INSERT-ONLY (LAW 8). UPDATE and DELETE are forbidden. TG_OP=%', TG_OP;
END;
$$;

CREATE TRIGGER trg_ass_no_update
    BEFORE UPDATE ON audit_state_snapshot
    FOR EACH ROW EXECUTE FUNCTION fn_audit_state_snapshot_no_mutation();

CREATE TRIGGER trg_ass_no_delete
    BEFORE DELETE ON audit_state_snapshot
    FOR EACH ROW EXECUTE FUNCTION fn_audit_state_snapshot_no_mutation();

GRANT INSERT, SELECT ON TABLE audit_state_snapshot TO app_role;
REVOKE UPDATE, DELETE ON TABLE audit_state_snapshot FROM app_role;

CREATE INDEX IF NOT EXISTS idx_ass_audit_log
    ON audit_state_snapshot(tenant_id, audit_log_id);
CREATE INDEX IF NOT EXISTS idx_ass_record
    ON audit_state_snapshot(tenant_id, record_id, captured_at DESC);


-- -----------------------------------------------------------------------------
-- tenant_activity_metrics
-- Aggregated counters and usage metrics per tenant per time window.
-- Used for billing, capacity planning, and usage dashboards.
-- This table is INSERT-ONLY: each row is a time-window aggregate that is
-- written once and never mutated.  New windows produce new rows.
-- LAW 9: Raw SQL is never written here; a background aggregation job reads
--        audit_event_log and writes pre-computed summaries.
-- LAW 10: No grades, ranks, or pass/fail counts. Only operational metrics.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenant_activity_metrics (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    metric_id           UUID        NOT NULL DEFAULT gen_random_uuid(),
    metric_category     TEXT        NOT NULL
                            CHECK (metric_category IN (
                                'API_CALLS','AI_TOKENS','STORAGE_BYTES',
                                'ACTIVE_USERS','WORKFLOW_TRANSITIONS',
                                'FORM_SUBMISSIONS','AUDIT_EVENTS','CUSTOM'
                            )),
    window_start        TIMESTAMPTZ NOT NULL,
    window_end          TIMESTAMPTZ NOT NULL,
    window_granularity  TEXT        NOT NULL
                            CHECK (window_granularity IN ('HOURLY','DAILY','WEEKLY','MONTHLY')),
    scope_ref_id        UUID,
    -- Optional: narrow metric to a school/class entity_records.record_id
    count_value         BIGINT      NOT NULL DEFAULT 0,
    -- Discrete event count (API calls, workflow transitions, etc.)
    sum_value           NUMERIC(20,6),
    -- Continuous total (bytes, tokens, USD cost)
    peak_value          NUMERIC(20,6),
    -- Highest instantaneous value within the window
    metadata            JSONB,
    -- Arbitrary breakdown: {"model_type": "LLM", "operation": "QUESTION_GENERATION"}
    aggregated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_tenant_activity_metrics PRIMARY KEY (tenant_id, metric_id),
    CONSTRAINT uq_activity_metric_id UNIQUE (metric_id),
    CONSTRAINT uq_metric_window UNIQUE (tenant_id, metric_category, window_start, window_granularity, scope_ref_id),
    CONSTRAINT chk_window_order CHECK (window_end > window_start)
);

COMMENT ON TABLE  tenant_activity_metrics                   IS 'Layer 9: Pre-aggregated operational metrics per tenant per time window. Written by background aggregation job — INSERT-ONLY. LAW 9: no raw SQL queries inline.';
COMMENT ON COLUMN tenant_activity_metrics.metric_category   IS 'What is counted: API_CALLS | AI_TOKENS | STORAGE_BYTES | ACTIVE_USERS | WORKFLOW_TRANSITIONS | FORM_SUBMISSIONS | AUDIT_EVENTS | CUSTOM.';
COMMENT ON COLUMN tenant_activity_metrics.window_granularity IS 'Aggregation bucket: HOURLY | DAILY | WEEKLY | MONTHLY.';
COMMENT ON COLUMN tenant_activity_metrics.scope_ref_id      IS 'Optional entity_records.record_id to narrow metrics to a specific school or class.';
COMMENT ON COLUMN tenant_activity_metrics.count_value       IS 'Discrete event count within the window (e.g. number of API calls).';
COMMENT ON COLUMN tenant_activity_metrics.sum_value         IS 'Continuous total within the window (e.g. total tokens consumed, total bytes written).';
COMMENT ON COLUMN tenant_activity_metrics.peak_value        IS 'Peak instantaneous value observed within the window (e.g. peak concurrent users).';

-- INSERT-ONLY guard (LAW 8)
CREATE OR REPLACE FUNCTION fn_tenant_activity_metrics_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'tenant_activity_metrics is INSERT-ONLY (LAW 8). Amend by inserting a new corrected row. TG_OP=%', TG_OP;
END;
$$;

CREATE TRIGGER trg_tam_no_update
    BEFORE UPDATE ON tenant_activity_metrics
    FOR EACH ROW EXECUTE FUNCTION fn_tenant_activity_metrics_no_mutation();

CREATE TRIGGER trg_tam_no_delete
    BEFORE DELETE ON tenant_activity_metrics
    FOR EACH ROW EXECUTE FUNCTION fn_tenant_activity_metrics_no_mutation();

GRANT INSERT, SELECT ON TABLE tenant_activity_metrics TO app_role;
REVOKE UPDATE, DELETE ON TABLE tenant_activity_metrics FROM app_role;

CREATE INDEX IF NOT EXISTS idx_tam_category_window
    ON tenant_activity_metrics(tenant_id, metric_category, window_start DESC);
CREATE INDEX IF NOT EXISTS idx_tam_scope
    ON tenant_activity_metrics(tenant_id, scope_ref_id, metric_category)
    WHERE scope_ref_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- security_event_log
-- Dedicated, INSERT-ONLY log for authentication, authorisation, and anomaly
-- events. Kept separate from audit_event_log for:
--   • SIEM system integration (can tail this table independently)
--   • PII minimisation: raw fields like ip_address are hashed here too
--   • Higher-volume events that need granular indexing
-- LAW 8: INSERT-ONLY. Trigger + role GRANT enforce immutability.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS security_event_log (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    log_id              UUID        NOT NULL DEFAULT gen_random_uuid(),
    event_type          TEXT        NOT NULL,
    -- AUTH_LOGIN_SUCCESS | AUTH_LOGIN_FAILURE | AUTH_LOGOUT | AUTH_TOKEN_REFRESH
    -- AUTHZ_DENIED | AUTHZ_ESCALATION_ATTEMPT
    -- MFA_CHALLENGED | MFA_SUCCESS | MFA_FAILURE
    -- SESSION_EXPIRED | SESSION_REVOKED
    -- ANOMALY_DETECTED | RATE_LIMIT_EXCEEDED | SUSPICIOUS_PATTERN
    -- PASSWORD_CHANGED | PASSWORD_RESET_REQUESTED | ACCOUNT_LOCKED
    severity            TEXT        NOT NULL DEFAULT 'INFO'
                            CHECK (severity IN ('DEBUG','INFO','WARN','ERROR','CRITICAL')),
    actor_id            UUID,
    -- NULL for failed authentications (actor not yet identified)
    actor_type          TEXT        NOT NULL DEFAULT 'USER',
    -- USER | SERVICE | ANONYMOUS | SYSTEM
    ip_address_hash     TEXT,
    -- SHA-256 of raw IP (never stored in plaintext)
    user_agent_hash     TEXT,
    -- SHA-256 of raw User-Agent string
    session_id          TEXT,
    -- Opaque session reference; correlates with audit_event_log
    resource_path       TEXT,
    -- API path or logical resource being accessed: e.g. '/api/submissions'
    policy_id           UUID,
    -- FK → policy_master if a policy evaluation triggered this event
    decision            TEXT
                            CHECK (decision IN ('ALLOW','DENY','CHALLENGE',NULL)),
    -- Outcome of the access decision; NULL for informational events
    event_data          JSONB,
    -- Structured context: {reason, rule_matched, attempt_count, geo_region, ...}
    -- No raw PII; sensitive fields must be hashed or omitted
    correlation_id      TEXT,
    -- Distributed tracing ID; correlates with application APM spans
    logged_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_security_event_log PRIMARY KEY (tenant_id, log_id),
    CONSTRAINT uq_security_log_id UNIQUE (log_id),
    CONSTRAINT fk_sel_policy FOREIGN KEY (tenant_id, policy_id)
        REFERENCES policy_master(tenant_id, policy_id) ON DELETE SET NULL
);

COMMENT ON TABLE  security_event_log                  IS 'Layer 9 / LAW 8: INSERT-ONLY dedicated security event log for auth, authz, and anomaly events. Separated from audit_event_log for SIEM integration and high-volume indexing.';
COMMENT ON COLUMN security_event_log.event_type       IS 'Screaming-snake security event descriptor: AUTH_LOGIN_SUCCESS | AUTHZ_DENIED | MFA_FAILURE | ANOMALY_DETECTED | RATE_LIMIT_EXCEEDED | etc.';
COMMENT ON COLUMN security_event_log.severity         IS 'Log severity level: DEBUG | INFO | WARN | ERROR | CRITICAL.';
COMMENT ON COLUMN security_event_log.ip_address_hash  IS 'SHA-256 of the actor IP address. Raw IP is NEVER stored (privacy compliance).';
COMMENT ON COLUMN security_event_log.user_agent_hash  IS 'SHA-256 of the raw User-Agent string. Enables fingerprinting without PII storage.';
COMMENT ON COLUMN security_event_log.resource_path    IS 'API or logical resource being accessed. No query parameters or PII in this column.';
COMMENT ON COLUMN security_event_log.policy_id        IS 'FK to policy_master when a policy evaluation produced this security event.';
COMMENT ON COLUMN security_event_log.decision         IS 'Access decision: ALLOW | DENY | CHALLENGE. NULL for informational / audit-only events.';
COMMENT ON COLUMN security_event_log.correlation_id   IS 'Distributed tracing ID. Correlates this event with APM spans and audit_event_log entries.';

-- INSERT-ONLY guard (LAW 8)
CREATE OR REPLACE FUNCTION fn_security_event_log_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'security_event_log is INSERT-ONLY (LAW 8). UPDATE and DELETE are forbidden. TG_OP=%', TG_OP;
END;
$$;

CREATE TRIGGER trg_sel_no_update
    BEFORE UPDATE ON security_event_log
    FOR EACH ROW EXECUTE FUNCTION fn_security_event_log_no_mutation();

CREATE TRIGGER trg_sel_no_delete
    BEFORE DELETE ON security_event_log
    FOR EACH ROW EXECUTE FUNCTION fn_security_event_log_no_mutation();

GRANT INSERT, SELECT ON TABLE security_event_log TO app_role;
REVOKE UPDATE, DELETE ON TABLE security_event_log FROM app_role;

CREATE INDEX IF NOT EXISTS idx_sel_actor
    ON security_event_log(tenant_id, actor_id, logged_at DESC)
    WHERE actor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sel_event_type
    ON security_event_log(tenant_id, event_type, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_sel_severity
    ON security_event_log(tenant_id, severity, logged_at DESC)
    WHERE severity IN ('WARN','ERROR','CRITICAL');
CREATE INDEX IF NOT EXISTS idx_sel_session
    ON security_event_log(tenant_id, session_id)
    WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sel_policy
    ON security_event_log(tenant_id, policy_id)
    WHERE policy_id IS NOT NULL;


-- =============================================================================
-- ROW-LEVEL SECURITY (RLS) — Layer 7, 8, 9 tables
-- LAW 6 + RULES.md: RLS is mandatory on all tenant tables.
-- Tenant context set via: SET LOCAL app.tenant_id = '<uuid>';
-- at the start of every transaction (server-side only — LAW 7).
-- =============================================================================

-- Layer 7
ALTER TABLE ai_model_registry           ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_tasks                    ENABLE ROW LEVEL SECURITY;

-- Layer 8
ALTER TABLE system_settings             ENABLE ROW LEVEL SECURITY;

-- Layer 9
ALTER TABLE audit_event_log             ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_tenant_sequence       ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_state_snapshot        ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_activity_metrics     ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_event_log          ENABLE ROW LEVEL SECURITY;

-- RLS policies (all keyed on current_setting('app.tenant_id', TRUE)::UUID)

-- Layer 7
CREATE POLICY rls_ai_model_registry
    ON ai_model_registry
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_ai_tasks
    ON ai_tasks
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

-- Layer 8
CREATE POLICY rls_system_settings
    ON system_settings
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

-- Layer 9
CREATE POLICY rls_audit_event_log
    ON audit_event_log
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_audit_tenant_sequence
    ON audit_tenant_sequence
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_audit_state_snapshot
    ON audit_state_snapshot
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_tenant_activity_metrics
    ON tenant_activity_metrics
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_security_event_log
    ON security_event_log
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);


-- =============================================================================
-- END OF SCHEMA: LAYERS 7 → 9
-- =============================================================================
