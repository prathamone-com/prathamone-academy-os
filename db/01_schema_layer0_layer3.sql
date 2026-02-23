-- =============================================================================
-- PRATHAMONE ACADEMY OS — DATABASE SCHEMA
-- Layers 0 → 3  (Tenant Kernel → Form Rendering Engine)
-- =============================================================================
-- Author    : Jawahar R Mallah
-- Role      : Founder & Technical Architect
-- Web       : https://aiTDL.com | https://pratham1.com
-- Version   : Author_Metadata_v1.0
-- Copyright : © 2026 Jawahar R Mallah. All rights reserved.
-- =============================================================================
-- RULES.MD compliance checklist applied to every table:
--   LAW 1  : All entities registered in entity_master
--   LAW 2  : No custom columns — variable fields go to attribute_master/values
--   LAW 3  : No status checks in code — use workflow_transitions
--   LAW 4  : Policies evaluate BEFORE workflow transitions
--   LAW 5  : Policies=IF, Workflows=WHEN, Settings=DEFAULT
--   LAW 6  : Every table has tenant_id FK — NO EXCEPTIONS
--   LAW 7  : tenant_id is injected server-side via RLS, never from frontend
--   LAW 8  : Audit tables are INSERT-ONLY (no UPDATE/DELETE triggers enforced)
--   LAW 9  : Reports are declarative metadata only
--   LAW 10 : No rank/grade/pass-fail stored; derived at runtime
--   LAW 11 : New modules → new DATA rows, not new tables
--   LAW 12 : The kernel is locked; features are data
-- =============================================================================


-- =============================================================================
-- LAYER 0 — TENANT KERNEL
-- Purpose: Multi-tenant root. Every other table references tenants here.
--          Tenant context is always set via SET app.tenant_id at session start;
--          the frontend NEVER passes tenant_id in API payloads.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- tenants
-- The root anchor for the entire multi-tenant system.
-- One row per organisation / school / institution.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenants (
    tenant_id       UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            TEXT            NOT NULL,           -- Display name of the tenant
    slug            TEXT            NOT NULL UNIQUE,    -- URL-safe short identifier
    plan            TEXT            NOT NULL DEFAULT 'free',  -- Subscription tier
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    -- Composite PK: tenant_id is both PK and self-referencing; record_id = tenant_id
    CONSTRAINT pk_tenants PRIMARY KEY (tenant_id)
);

COMMENT ON TABLE  tenants             IS 'Root anchor for all tenants (organisations/schools). The kernel; never deleted.';
COMMENT ON COLUMN tenants.tenant_id   IS 'Globally unique tenant identifier. Injected into every session via RLS.';
COMMENT ON COLUMN tenants.slug        IS 'URL-safe unique shortcode for the tenant (e.g. "greenwood-iit").';
COMMENT ON COLUMN tenants.plan        IS 'Subscription tier controlling feature flags (free | starter | pro | enterprise).';


-- -----------------------------------------------------------------------------
-- tenant_settings
-- Key-value settings per tenant. Implements LAW 5 (Settings decide DEFAULT).
-- Settings are NEVER read by feature code conditionally — they are fed into
-- policy/workflow resolution at runtime.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenant_settings (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    setting_key     TEXT            NOT NULL,
    setting_value   TEXT            NOT NULL,           -- Serialised (JSON string, number, bool)
    description     TEXT,
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_by      UUID,                               -- FK → users.user_id (set after users table exists)

    CONSTRAINT pk_tenant_settings PRIMARY KEY (tenant_id, setting_key)
);

COMMENT ON TABLE  tenant_settings               IS 'Per-tenant configuration key-value store. Implements LAW 5: Settings decide DEFAULT values.';
COMMENT ON COLUMN tenant_settings.tenant_id     IS 'Tenant that owns this setting.';
COMMENT ON COLUMN tenant_settings.setting_key   IS 'Namespaced key (e.g. "auth.mfa_required", "grading.passing_threshold").';
COMMENT ON COLUMN tenant_settings.setting_value IS 'JSON-serialised value. Interpret based on the key convention.';


-- -----------------------------------------------------------------------------
-- tenant_audit_log
-- INSERT-ONLY audit trail of significant kernel-level events.
-- LAW 8: No UPDATE or DELETE allowed — enforced with a trigger below.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenant_audit_log (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    log_id          UUID            NOT NULL DEFAULT gen_random_uuid(),
    actor_id        UUID,                               -- User or system that performed the action
    action          TEXT            NOT NULL,           -- e.g. 'TENANT_CREATED', 'PLAN_CHANGED'
    payload         JSONB,                              -- Structured change details
    logged_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_tenant_audit_log PRIMARY KEY (tenant_id, log_id),
    CONSTRAINT uq_tenant_audit_log_id UNIQUE (log_id)
);

COMMENT ON TABLE  tenant_audit_log            IS 'INSERT-ONLY audit log for kernel-level actions. LAW 8: No UPDATE/DELETE ever.';
COMMENT ON COLUMN tenant_audit_log.actor_id   IS 'UUID of the user or service account that triggered the action.';
COMMENT ON COLUMN tenant_audit_log.action     IS 'Descriptor string for the event (SCREAMING_SNAKE_CASE convention).';
COMMENT ON COLUMN tenant_audit_log.payload    IS 'JSONB diff/context captured at action time. Immutable once written.';

-- Enforce INSERT-ONLY on tenant_audit_log (LAW 8)
CREATE OR REPLACE FUNCTION fn_audit_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Audit tables are INSERT-ONLY (LAW 8). UPDATE and DELETE are forbidden.';
END;
$$;

CREATE TRIGGER trg_tenant_audit_log_no_update
    BEFORE UPDATE ON tenant_audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_no_mutation();

CREATE TRIGGER trg_tenant_audit_log_no_delete
    BEFORE DELETE ON tenant_audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_no_mutation();


-- =============================================================================
-- LAYER 1 — ENTITY & ATTRIBUTE KERNEL
-- Purpose: Implements LAW 1 (entity_master) and LAW 2 (no custom columns).
--          Every "object" in the system is registered here; variable columns
--          are stored as attribute values, not as real DB columns.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- entity_master
-- LAW 1: No entity exists unless registered here.
-- An "entity" is any first-class concept: User, Course, Batch, Question, etc.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS entity_master (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    entity_id       UUID            NOT NULL DEFAULT gen_random_uuid(),
    entity_type     TEXT            NOT NULL,           -- e.g. 'USER', 'COURSE', 'BATCH', 'QUESTION'
    entity_code     TEXT            NOT NULL,           -- Unique shortcode within tenant
    display_name    TEXT            NOT NULL,
    description     TEXT,
    is_system       BOOLEAN         NOT NULL DEFAULT FALSE, -- TRUE for built-in kernel entities
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_entity_master PRIMARY KEY (tenant_id, entity_id),
    CONSTRAINT uq_entity_master_code UNIQUE (tenant_id, entity_code),
    CONSTRAINT uq_entity_master_id UNIQUE (entity_id)
);

COMMENT ON TABLE  entity_master              IS 'LAW 1: Central registry of every first-class entity type in the OS. No entity exists outside this table.';
COMMENT ON COLUMN entity_master.entity_type  IS 'Category/category of entity: USER | COURSE | BATCH | QUESTION | FORM | etc.';
COMMENT ON COLUMN entity_master.entity_code  IS 'Tenant-scoped short identifier, used in configuration/policy references.';
COMMENT ON COLUMN entity_master.is_system    IS 'TRUE for OS-built-in entities that tenants cannot delete.';


-- -----------------------------------------------------------------------------
-- attribute_master
-- LAW 2: No custom columns in entity tables. All variable fields are defined here.
-- Each row defines one "field" that can appear on an entity form.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attribute_master (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    attribute_id    UUID            NOT NULL DEFAULT gen_random_uuid(),
    entity_id       UUID            NOT NULL,           -- FK → entity_master.entity_id
    attribute_code  TEXT            NOT NULL,           -- Machine identifier (snake_case)
    display_label   TEXT            NOT NULL,
    data_type       TEXT            NOT NULL,           -- text | number | boolean | date | json | file
    is_required     BOOLEAN         NOT NULL DEFAULT FALSE,
    is_system       BOOLEAN         NOT NULL DEFAULT FALSE,
    default_value   TEXT,
    validation_rule JSONB,                              -- JSON Schema fragment for validation
    sort_order      INT             NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_attribute_master PRIMARY KEY (tenant_id, attribute_id),
    CONSTRAINT uq_attribute_id UNIQUE (attribute_id),
    CONSTRAINT uq_attribute_code UNIQUE (tenant_id, entity_id, attribute_code),
    CONSTRAINT fk_attribute_entity FOREIGN KEY (tenant_id, entity_id)
        REFERENCES entity_master(tenant_id, entity_id) ON DELETE CASCADE
);

COMMENT ON TABLE  attribute_master                 IS 'LAW 2: Every dynamic field for every entity is defined here. No custom table columns allowed.';
COMMENT ON COLUMN attribute_master.attribute_code  IS 'Snake-case machine identifier for the field (e.g. "date_of_birth").';
COMMENT ON COLUMN attribute_master.data_type       IS 'Storage type: text | number | boolean | date | json | file.';
COMMENT ON COLUMN attribute_master.validation_rule IS 'JSON Schema fragment applied at write time (e.g. min/max, pattern).';
COMMENT ON COLUMN attribute_master.is_system       IS 'TRUE for kernel-defined attributes that tenants cannot delete.';


-- -----------------------------------------------------------------------------
-- attribute_values
-- Runtime storage for EAV (Entity-Attribute-Value) data.
-- The triple (tenant_id, entity_id, record_id) points to a specific object instance;
-- attribute_id points to the field definition.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attribute_values (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    attribute_id    UUID            NOT NULL,
    record_id       UUID            NOT NULL,           -- PK of the owning record in its native table
    value_text      TEXT,                               -- For data_type IN ('text','file','json','date')
    value_number    NUMERIC,                            -- For data_type = 'number'
    value_bool      BOOLEAN,                            -- For data_type = 'boolean'
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_attribute_values PRIMARY KEY (tenant_id, attribute_id, record_id),
    CONSTRAINT fk_attribute_values_attr FOREIGN KEY (tenant_id, attribute_id)
        REFERENCES attribute_master(tenant_id, attribute_id) ON DELETE CASCADE
);

COMMENT ON TABLE  attribute_values             IS 'EAV value store. Holds dynamic field values for any entity record. LAW 2 enforcement.';
COMMENT ON COLUMN attribute_values.record_id   IS 'UUID of the specific entity instance (e.g. a user_id, course_id, etc.).';
COMMENT ON COLUMN attribute_values.value_text  IS 'Stores text, JSON, date strings, and file references.';
COMMENT ON COLUMN attribute_values.value_number IS 'Stores numeric values with full precision.';

-- Index for efficient per-record lookups
CREATE INDEX IF NOT EXISTS idx_attribute_values_record
    ON attribute_values(tenant_id, record_id);


-- =============================================================================
-- LAYER 2 — POLICY & WORKFLOW ENGINE
-- Purpose: Implements LAW 3 (no if(status==) in code), LAW 4 (policies first),
--          LAW 5 (policies=IF, workflows=WHEN).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- policy_master
-- Declarative policy definitions. Evaluated BEFORE workflow transitions.
-- LAW 4: Policies win. LAW 5: Policies decide IF.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS policy_master (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    policy_id       UUID            NOT NULL DEFAULT gen_random_uuid(),
    policy_code     TEXT            NOT NULL,           -- Machine identifier
    display_name    TEXT            NOT NULL,
    entity_id       UUID            NOT NULL,           -- Which entity this policy governs
    rule_engine     TEXT            NOT NULL DEFAULT 'json_logic', -- Evaluation engine type
    rule_definition JSONB           NOT NULL,           -- Machine-readable rule (JSON Logic etc.)
    evaluation_order INT             NOT NULL DEFAULT 100, -- Lower = higher priority
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_policy_master PRIMARY KEY (tenant_id, policy_id),
    CONSTRAINT uq_policy_id UNIQUE (policy_id),
    CONSTRAINT uq_policy_code UNIQUE (tenant_id, policy_code),
    CONSTRAINT fk_policy_entity FOREIGN KEY (tenant_id, entity_id)
        REFERENCES entity_master(tenant_id, entity_id) ON DELETE CASCADE
);

COMMENT ON TABLE  policy_master                  IS 'LAW 4+5: Declarative policy registry. Evaluated BEFORE workflow transitions. Policies decide IF.';
COMMENT ON COLUMN policy_master.rule_engine      IS 'Engine used to evaluate rule_definition (json_logic | cel | rego).';
COMMENT ON COLUMN policy_master.rule_definition  IS 'Machine-readable predicate evaluated at runtime against the request context.';
COMMENT ON COLUMN policy_master.evaluation_order IS 'Evaluation order; lower number = higher priority. Ties broken by created_at.';


-- -----------------------------------------------------------------------------
-- policy_action_map
-- Maps a policy outcome to a concrete action/effect.
-- Keeps policies pure (predicate only) and actions separate (SRP).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS policy_action_map (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    mapping_id      UUID            NOT NULL DEFAULT gen_random_uuid(),
    policy_id       UUID            NOT NULL,
    outcome         TEXT            NOT NULL CHECK (outcome IN ('allow','deny','require','flag')),
    action_type     TEXT            NOT NULL,           -- e.g. 'BLOCK_TRANSITION', 'SEND_NOTIFICATION'
    action_payload  JSONB,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_policy_action_map PRIMARY KEY (tenant_id, mapping_id),
    CONSTRAINT uq_mapping_id UNIQUE (mapping_id),
    CONSTRAINT fk_pam_policy FOREIGN KEY (tenant_id, policy_id)
        REFERENCES policy_master(tenant_id, policy_id) ON DELETE CASCADE
);

COMMENT ON TABLE  policy_action_map              IS 'Maps policy evaluation outcomes to concrete system actions (block, notify, flag, etc.).';
COMMENT ON COLUMN policy_action_map.outcome      IS 'Policy verdict: allow | deny | require | flag.';
COMMENT ON COLUMN policy_action_map.action_type  IS 'System action to execute when this outcome fires.';


-- -----------------------------------------------------------------------------
-- workflow_master
-- Named workflows; each workflow contains ordered transitions.
-- LAW 3: Transitions replace if(status==) checks in feature code.
-- LAW 5: Workflows decide WHEN.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow_master (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    workflow_id     UUID            NOT NULL DEFAULT gen_random_uuid(),
    workflow_code   TEXT            NOT NULL,           -- Machine identifier
    display_name    TEXT            NOT NULL,
    entity_id       UUID            NOT NULL,           -- Entity type this workflow manages
    initial_state   TEXT            NOT NULL,           -- Entry state name
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_workflow_master PRIMARY KEY (tenant_id, workflow_id),
    CONSTRAINT uq_workflow_id UNIQUE (workflow_id),
    CONSTRAINT uq_workflow_code UNIQUE (tenant_id, workflow_code),
    CONSTRAINT fk_workflow_entity FOREIGN KEY (tenant_id, entity_id)
        REFERENCES entity_master(tenant_id, entity_id) ON DELETE CASCADE
);

COMMENT ON TABLE  workflow_master               IS 'LAW 3+5: Named state machine definitions. Replaces status-check conditionals in code.';
COMMENT ON COLUMN workflow_master.initial_state IS 'State name that new entity instances are placed into upon creation.';


-- -----------------------------------------------------------------------------
-- workflow_transitions
-- Individual edges in the state machine graph.
-- feature code NEVER checks "if status == X"; it requests a transition and
-- the engine evaluates policies + guards here.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow_transitions (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    transition_id   UUID            NOT NULL DEFAULT gen_random_uuid(),
    workflow_id     UUID            NOT NULL,
    from_state      TEXT,                               -- Source state (NULL = START)
    to_state        TEXT            NOT NULL,           -- Target state
    trigger_event   TEXT            NOT NULL,           -- Event name that fires this transition
    display_label   TEXT,                               -- Human readable label for this transition button
    guard_policy_id UUID,                               -- Optional FK → policy_master (evaluated first)
    actor_roles     TEXT[],                             -- Roles allowed to fire this transition
    sort_order      INT             NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_workflow_transitions PRIMARY KEY (tenant_id, transition_id),
    CONSTRAINT uq_transition_id UNIQUE (transition_id),
    CONSTRAINT fk_wt_workflow FOREIGN KEY (tenant_id, workflow_id)
        REFERENCES workflow_master(tenant_id, workflow_id) ON DELETE CASCADE,
    CONSTRAINT fk_wt_guard FOREIGN KEY (tenant_id, guard_policy_id)
        REFERENCES policy_master(tenant_id, policy_id) ON DELETE SET NULL
);

COMMENT ON TABLE  workflow_transitions                IS 'LAW 3: Each row is one valid state-machine edge. Code fires events; engine resolves transitions.';
COMMENT ON COLUMN workflow_transitions.from_state     IS 'State the entity must be in for this transition to be allowed.';
COMMENT ON COLUMN workflow_transitions.to_state       IS 'State the entity will be in after a successful transition.';
COMMENT ON COLUMN workflow_transitions.trigger_event  IS 'Named event that activates this edge (e.g. SUBMIT, APPROVE, REJECT).';
COMMENT ON COLUMN workflow_transitions.display_label  IS 'Label shown on the UI button for this transition.';
COMMENT ON COLUMN workflow_transitions.guard_policy_id IS 'Policy evaluated BEFORE the transition; transition is blocked if policy returns deny.';
COMMENT ON COLUMN workflow_transitions.actor_roles    IS 'Array of role codes authorised to fire this event.';


-- -----------------------------------------------------------------------------
-- workflow_state_log
-- INSERT-ONLY record of every state transition that has occurred.
-- LAW 8: No UPDATE or DELETE.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow_state_log (
    seq_id          BIGSERIAL       NOT NULL,
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    log_id          UUID            NOT NULL DEFAULT gen_random_uuid(),
    workflow_id     UUID            NOT NULL,
    record_id       UUID            NOT NULL,           -- ID of the entity instance that transitioned
    from_state      TEXT,
    to_state        TEXT            NOT NULL,
    trigger_event   TEXT            NOT NULL,
    actor_id        UUID,
    transition_at   TIMESTAMPTZ     NOT NULL DEFAULT now(),
    metadata        JSONB,

    CONSTRAINT pk_workflow_state_log PRIMARY KEY (tenant_id, log_id),
    CONSTRAINT uq_workflow_log_id UNIQUE (log_id),
    CONSTRAINT fk_wsl_workflow FOREIGN KEY (tenant_id, workflow_id)
        REFERENCES workflow_master(tenant_id, workflow_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  workflow_state_log            IS 'LAW 8: INSERT-ONLY history of all state transitions. Source of truth for current state (latest row per record_id).';
COMMENT ON COLUMN workflow_state_log.record_id  IS 'UUID of the entity instance whose state changed.';
COMMENT ON COLUMN workflow_state_log.actor_id   IS 'User or automated agent that fired the transition.';
COMMENT ON COLUMN workflow_state_log.metadata   IS 'Contextual data at transition time (e.g. policy result, payload).';

-- INSERT-ONLY guards (LAW 8)
CREATE TRIGGER trg_workflow_state_log_no_update
    BEFORE UPDATE ON workflow_state_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_no_mutation();

CREATE TRIGGER trg_workflow_state_log_no_delete
    BEFORE DELETE ON workflow_state_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_no_mutation();


-- =============================================================================
-- LAYER 3 — FORM RENDERING ENGINE
-- Purpose: Fully declarative, data-driven form definitions.
--          LAW 11: New modules = new DATA rows, not new tables.
--          Forms reference entity attributes for field binding.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- form_master
-- Top-level form definition. One row per logical form (e.g. "Admission Form",
-- "Quiz Submission Form").
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS form_master (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    form_id         UUID            NOT NULL DEFAULT gen_random_uuid(),
    form_code       TEXT            NOT NULL,           -- Machine identifier
    display_name    TEXT            NOT NULL,
    entity_id       UUID            NOT NULL,           -- Entity type this form collects data for
    workflow_id     UUID,                               -- Optional: submission triggers this workflow
    description     TEXT,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    version         INT             NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_form_master PRIMARY KEY (tenant_id, form_id),
    CONSTRAINT uq_form_id UNIQUE (form_id),
    CONSTRAINT uq_form_code UNIQUE (tenant_id, form_code),
    CONSTRAINT fk_form_entity FOREIGN KEY (tenant_id, entity_id)
        REFERENCES entity_master(tenant_id, entity_id) ON DELETE CASCADE,
    CONSTRAINT fk_form_workflow FOREIGN KEY (tenant_id, workflow_id)
        REFERENCES workflow_master(tenant_id, workflow_id) ON DELETE SET NULL
);

COMMENT ON TABLE  form_master              IS 'LAW 11: Every form in the OS is a data row here. No new table needed per form type.';
COMMENT ON COLUMN form_master.entity_id   IS 'The entity whose attributes this form collects (drives field binding).';
COMMENT ON COLUMN form_master.workflow_id IS 'If set, form submission fires the initial_state entry event of this workflow.';
COMMENT ON COLUMN form_master.version     IS 'Monotonically increasing version counter; bump on structural change.';


-- -----------------------------------------------------------------------------
-- form_sections
-- Logical groupings of fields within a form (e.g. "Personal Info", "Documents").
-- Sections support collapsing, conditional visibility, and page breaks.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS form_sections (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    section_id      UUID            NOT NULL DEFAULT gen_random_uuid(),
    form_id         UUID            NOT NULL,
    section_code    TEXT            NOT NULL,
    display_label   TEXT            NOT NULL,
    description     TEXT,
    sort_order      INT             NOT NULL DEFAULT 0,
    is_collapsible  BOOLEAN         NOT NULL DEFAULT FALSE,
    visibility_rule JSONB,                              -- JSON Logic predicate; NULL = always visible
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_form_sections PRIMARY KEY (tenant_id, section_id),
    CONSTRAINT uq_section_id UNIQUE (section_id),
    CONSTRAINT uq_form_section_code UNIQUE (tenant_id, form_id, section_code),
    CONSTRAINT fk_fs_form FOREIGN KEY (tenant_id, form_id)
        REFERENCES form_master(tenant_id, form_id) ON DELETE CASCADE
);

COMMENT ON TABLE  form_sections                   IS 'Logical groupings of form fields. Supports conditional visibility and page-layout control.';
COMMENT ON COLUMN form_sections.sort_order        IS 'Rendering order within the form; lower = rendered first.';
COMMENT ON COLUMN form_sections.visibility_rule   IS 'JSON Logic predicate evaluated against current form values; NULL means always visible.';


-- -----------------------------------------------------------------------------
-- form_fields
-- Individual field bindings within a section. Each row links an attribute_master
-- entry to a position in a section with rendering overrides.
-- LAW 2: No storage here — values go to attribute_values.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS form_fields (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    field_id            UUID        NOT NULL DEFAULT gen_random_uuid(),
    section_id          UUID        NOT NULL,
    attribute_id        UUID        NOT NULL,           -- FK → attribute_master (field definition)
    widget_type         TEXT        NOT NULL DEFAULT 'text_input',
    -- Widget types: text_input | number_input | textarea | select | multi_select
    --               date_picker | file_upload | checkbox | radio | rich_text | hidden
    label_override      TEXT,                           -- Overrides attribute_master.display_label if set
    placeholder         TEXT,
    help_text           TEXT,
    is_required_override BOOLEAN,                       -- Overrides attribute_master.is_required if not NULL
    visibility_rule     JSONB,                          -- JSON Logic predicate; NULL = always visible
    validation_override JSONB,                          -- Overrides attribute_master.validation_rule if set
    sort_order          INT         NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_form_fields PRIMARY KEY (tenant_id, field_id),
    CONSTRAINT uq_field_id UNIQUE (field_id),
    CONSTRAINT fk_ff_section FOREIGN KEY (tenant_id, section_id)
        REFERENCES form_sections(tenant_id, section_id) ON DELETE CASCADE,
    CONSTRAINT fk_ff_attribute FOREIGN KEY (tenant_id, attribute_id)
        REFERENCES attribute_master(tenant_id, attribute_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  form_fields                        IS 'Binds an attribute to a form section with rendering overrides. LAW 2: values go to attribute_values.';
COMMENT ON COLUMN form_fields.widget_type            IS 'UI widget used to render this field (text_input, select, date_picker, etc.).';
COMMENT ON COLUMN form_fields.label_override         IS 'Context-specific label; falls back to attribute_master.display_label if NULL.';
COMMENT ON COLUMN form_fields.visibility_rule        IS 'JSON Logic evaluated against current form state; controls conditional field show/hide.';
COMMENT ON COLUMN form_fields.validation_override    IS 'JSON Schema fragment that overrides the attribute-level validation only for this form.';
COMMENT ON COLUMN form_fields.is_required_override   IS 'When not NULL, overrides the required flag from attribute_master.';


-- -----------------------------------------------------------------------------
-- form_submissions
-- Tracks each submission event (the "envelope").
-- Actual field values are stored in attribute_values with record_id = submission_id.
-- LAW 8:  No mutable state stored here. current_state is REMOVED.
--         Current state is always derived at runtime from workflow_state_log
--         via the view v_submission_current_state (see below).
-- LAW 10: No grade/rank stored here — derived at runtime.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS form_submissions (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    submission_id   UUID            NOT NULL DEFAULT gen_random_uuid(),
    form_id         UUID            NOT NULL,
    submitted_by    UUID            NOT NULL,           -- FK → users (resolved by app layer)
    submitted_at    TIMESTAMPTZ     NOT NULL DEFAULT now(),
    metadata        JSONB,                              -- Supplemental context (device, IP hash, etc.)

    CONSTRAINT pk_form_submissions PRIMARY KEY (tenant_id, submission_id),
    CONSTRAINT uq_submission_id UNIQUE (submission_id),
    CONSTRAINT fk_fsub_form FOREIGN KEY (tenant_id, form_id)
        REFERENCES form_master(tenant_id, form_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  form_submissions              IS 'Submission envelope. Actual field answers are in attribute_values (record_id=submission_id). current_state was removed (LAW 8) — use v_submission_current_state.';
COMMENT ON COLUMN form_submissions.submitted_by IS 'User UUID; kept here for fast query. Full auth resolved by app layer.';
COMMENT ON COLUMN form_submissions.metadata     IS 'Non-answer context: browser info, IP hash, attempt number, etc.';


-- -----------------------------------------------------------------------------
-- Migration guard: drop current_state if the table already exists with it.
-- Safe to run on a fresh DB (column won't exist) or on an existing DB.
-- LAW 8 fix: eliminates the only UPDATE-requiring column in form_submissions.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE  table_name   = 'form_submissions'
          AND  column_name  = 'current_state'
    ) THEN
        ALTER TABLE form_submissions DROP COLUMN current_state;
        RAISE NOTICE 'LAW 8 fix: dropped mutable column current_state from form_submissions';
    END IF;
END;
$$;


-- -----------------------------------------------------------------------------
-- v_submission_current_state
-- Read-only view that derives the current workflow state for each submission
-- from the INSERT-ONLY workflow_state_log.  No UPDATE ever needed.
-- LAW 8 compliant: state is always the latest immutable log row.
-- LAW 3 compliant: no if(status==) checks — derived declaratively.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_submission_current_state AS
    SELECT DISTINCT ON (wsl.tenant_id, wsl.record_id)
        wsl.tenant_id,
        wsl.record_id   AS submission_id,
        wsl.to_state    AS current_state,
        wsl.transition_at AS state_entered_at
    FROM   workflow_state_log wsl
    ORDER  BY wsl.tenant_id, wsl.record_id, wsl.transition_at DESC;

COMMENT ON VIEW v_submission_current_state IS
    'LAW 8: Derives current workflow state from the INSERT-ONLY workflow_state_log. '
    'Replaces the removed mutable column form_submissions.current_state. '
    'Join on (tenant_id, submission_id) to get current_state.';


-- -----------------------------------------------------------------------------
-- form_submission_audit_log
-- INSERT-ONLY per-submission audit trail. LAW 8.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS form_submission_audit_log (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    log_id          UUID            NOT NULL DEFAULT gen_random_uuid(),
    submission_id   UUID            NOT NULL,
    actor_id        UUID,
    action          TEXT            NOT NULL,           -- e.g. SUBMITTED, REVIEWED, APPROVED, FLAGGED
    payload         JSONB,
    logged_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_form_submission_audit_log PRIMARY KEY (tenant_id, log_id),
    CONSTRAINT uq_form_submission_log_id UNIQUE (log_id),
    CONSTRAINT fk_fsal_submission FOREIGN KEY (tenant_id, submission_id)
        REFERENCES form_submissions(tenant_id, submission_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  form_submission_audit_log           IS 'LAW 8: INSERT-ONLY audit trail for every action taken on a form submission.';
COMMENT ON COLUMN form_submission_audit_log.action    IS 'Screaming-snake descriptor of the event (SUBMITTED | REVIEWED | APPROVED | FLAGGED | REOPENED).';
COMMENT ON COLUMN form_submission_audit_log.payload   IS 'Snapshot of relevant state at the time of the action.';

-- INSERT-ONLY guards (LAW 8)
CREATE TRIGGER trg_fsal_no_update
    BEFORE UPDATE ON form_submission_audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_no_mutation();

CREATE TRIGGER trg_fsal_no_delete
    BEFORE DELETE ON form_submission_audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_no_mutation();


-- =============================================================================
-- ROW-LEVEL SECURITY (RLS)
-- LAW 6 + RULES.md: RLS is mandatory on all tenant tables.
-- The application sets:  SET LOCAL app.tenant_id = '<uuid>';
-- at the start of every transaction. RLS policies enforce isolation.
-- =============================================================================

ALTER TABLE tenants                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_settings           ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_audit_log          ENABLE ROW LEVEL SECURITY;
ALTER TABLE entity_master             ENABLE ROW LEVEL SECURITY;
ALTER TABLE attribute_master          ENABLE ROW LEVEL SECURITY;
ALTER TABLE attribute_values          ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_master             ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_action_map         ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_master           ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_transitions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_state_log        ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_master               ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_sections             ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_fields               ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_submissions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_submission_audit_log ENABLE ROW LEVEL SECURITY;

-- Generic RLS policy: each table only shows rows for the active tenant.
-- Tenants table is the special case — only the row matching the session tenant.
CREATE POLICY rls_tenants ON tenants
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_tenant_settings ON tenant_settings
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_tenant_audit_log ON tenant_audit_log
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_entity_master ON entity_master
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_attribute_master ON attribute_master
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_attribute_values ON attribute_values
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_policy_master ON policy_master
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_policy_action_map ON policy_action_map
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_workflow_master ON workflow_master
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_workflow_transitions ON workflow_transitions
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_workflow_state_log ON workflow_state_log
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_form_master ON form_master
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_form_sections ON form_sections
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_form_fields ON form_fields
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_form_submissions ON form_submissions
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_form_submission_audit_log ON form_submission_audit_log
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);


-- =============================================================================
-- SUPPORTING INDEXES
-- =============================================================================

-- Layer 1
CREATE INDEX IF NOT EXISTS idx_entity_master_type     ON entity_master(tenant_id, entity_type);
CREATE INDEX IF NOT EXISTS idx_attribute_master_entity ON attribute_master(tenant_id, entity_id);

-- Layer 2 — Policy
CREATE INDEX IF NOT EXISTS idx_policy_entity          ON policy_master(tenant_id, entity_id, evaluation_order);

-- Layer 2 — Workflow
CREATE INDEX IF NOT EXISTS idx_workflow_entity        ON workflow_master(tenant_id, entity_id);
CREATE INDEX IF NOT EXISTS idx_wt_workflow_from       ON workflow_transitions(tenant_id, workflow_id, from_state);
CREATE INDEX IF NOT EXISTS idx_wsl_record             ON workflow_state_log(tenant_id, record_id, transition_at DESC);

-- Layer 3 — Forms
CREATE INDEX IF NOT EXISTS idx_form_entity            ON form_master(tenant_id, entity_id);
CREATE INDEX IF NOT EXISTS idx_form_sections_form     ON form_sections(tenant_id, form_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_form_fields_section    ON form_fields(tenant_id, section_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_form_submissions_form  ON form_submissions(tenant_id, form_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_form_submissions_user  ON form_submissions(tenant_id, submitted_by);

-- =============================================================================
-- END OF SCHEMA: LAYERS 0 → 3
-- =============================================================================
