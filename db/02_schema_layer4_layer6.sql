-- =============================================================================
-- PRATHAMONE ACADEMY OS — DATABASE SCHEMA
-- Layers 4 → 6  (Workflow State Engine → Policy DSL → EAV Runtime Store)
-- =============================================================================
-- Depends on: db/schema_layer0_layer3.sql  (must be applied first)
--
-- RULES.MD compliance checklist applied to every table in this file:
--   LAW 1  : All entities registered in entity_master (Layer 1)
--   LAW 2  : No custom columns — all field data in entity_attribute_values (Layer 6)
--   LAW 3  : No if(status==) in code — workflow_transitions rows drive state changes
--   LAW 4  : Policies evaluate BEFORE workflow transitions (guard_policy_id FK)
--   LAW 5  : Policies=IF (policy_conditions DSL), Workflows=WHEN (transitions)
--   LAW 6  : tenant_id FK present on EVERY table in this file — no exceptions
--   LAW 7  : tenant_id injected server-side via RLS; frontend never sends it
--   LAW 8  : All *_audit_log tables are INSERT-ONLY; triggers prevent mutation
--   LAW 9  : Reports are declarative metadata only
--   LAW 10 : No rank/grade/pass-fail stored; derived at runtime from EAV values
--   LAW 11 : New modules add rows, never new tables
--   LAW 12 : The kernel is locked; features are data
-- =============================================================================


-- =============================================================================
-- PRE-FLIGHT: Extend Layer 1 attribute_master with the is_searchable flag.
-- This flag controls whether an attribute's value is mirrored into
-- entity_record_index (Layer 6) for fast full-text / equality search.
-- Without this flag entity_record_index would either index everything
-- (wasteful) or nothing (useless).
-- =============================================================================

ALTER TABLE attribute_master
    ADD COLUMN IF NOT EXISTS is_searchable BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN attribute_master.is_searchable
    IS 'When TRUE, written values for this attribute are synchronised into entity_record_index for fast search. Layer 6 dependency.';


-- =============================================================================
-- LAYER 4 — WORKFLOW STATE ENGINE
-- Purpose: Gives the abstract workflow_master (Layer 2) a concrete, enumerated
--          state registry (workflow_states) and a richer transition graph that
--          stores guard results, SLA hints, and notification hooks.
--
--          Layer 2 defined the skeleton (workflow_master, workflow_transitions).
--          Layer 4 adds:
--            • workflow_states  — the explicit set of valid states per workflow
--            • workflow_transition_rules — enriched transition rows that extend
--              Layer 2's workflow_transitions with SLA, hooks, and DSL guards
--          Layer 4 tables reference Layer 2's workflow_master as their parent.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- workflow_states
-- Enumerates every valid state for a given workflow.
-- Layer 2's workflow_master.initial_state must match a row here.
-- Prevents orphan states and enables UI-driven state-machine builders.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow_states (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    state_id        UUID            NOT NULL DEFAULT gen_random_uuid(),
    workflow_id     UUID            NOT NULL,
    state_code      TEXT            NOT NULL,           -- Machine identifier (SCREAMING_SNAKE_CASE)
    display_label   TEXT            NOT NULL,
    description     TEXT,
    state_type      TEXT            NOT NULL
                        CHECK (state_type IN ('initial','intermediate','terminal','error')),
    is_blocking     BOOLEAN         NOT NULL DEFAULT FALSE,  -- TRUE = entity awaits external action
    sla_hours       NUMERIC,                            -- Optional SLA until auto-escalation fires
    ui_color        TEXT,                               -- Hex color for Kanban / timeline display
    sort_order      INT             NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_workflow_states PRIMARY KEY (tenant_id, state_id),
    CONSTRAINT uq_workflow_state_id UNIQUE (state_id),
    CONSTRAINT uq_workflow_state_code UNIQUE (tenant_id, workflow_id, state_code),
    CONSTRAINT fk_ws_workflow FOREIGN KEY (tenant_id, workflow_id)
        REFERENCES workflow_master(tenant_id, workflow_id) ON DELETE CASCADE
);

COMMENT ON TABLE  workflow_states               IS 'Layer 4: Enumerates every valid state for a workflow. Gives workflow_master (Layer 2) a concrete, typed state registry.';
COMMENT ON COLUMN workflow_states.state_code    IS 'SCREAMING_SNAKE_CASE machine identifier; must match workflow_master.initial_state for entry states.';
COMMENT ON COLUMN workflow_states.state_type    IS 'Lifecycle role: initial | intermediate | terminal | error.';
COMMENT ON COLUMN workflow_states.is_blocking   IS 'TRUE means the entity is waiting on an external actor and should be surfaced in task queues.';
COMMENT ON COLUMN workflow_states.sla_hours     IS 'Soft SLA target. An escalation event fires when an entity remains in this state beyond this window.';


-- -----------------------------------------------------------------------------
-- workflow_transition_rules
-- Enriched transition graph that extends Layer 2 workflow_transitions.
-- Each row is one directed edge in the state machine with:
--   • typed from/to state references (FKs to workflow_states)
--   • a structured DSL guard condition (not free text)
--   • SLA-based auto-fire support
--   • notification hook specification
-- Layer 2's workflow_transitions stores the minimal edge;
-- this table stores the operational runtime metadata for the same edge.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow_transition_rules (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    rule_id             UUID        NOT NULL DEFAULT gen_random_uuid(),
    workflow_id         UUID        NOT NULL,
    from_state_id       UUID        NOT NULL,           -- FK → workflow_states
    to_state_id         UUID        NOT NULL,           -- FK → workflow_states
    trigger_event       TEXT        NOT NULL,           -- Event name fired by feature code
    guard_policy_id     UUID,                           -- FK → policy_master; evaluated FIRST (LAW 4)
    guard_dsl           JSONB,                          -- Inline JSON Logic guard (complement to policy)
    auto_fire_after_hours NUMERIC,                      -- Auto-fire transition if SLA window expires
    actor_roles         TEXT[]      NOT NULL DEFAULT '{}', -- Role codes allowed to fire this event
    notification_hook   JSONB,                          -- Structured hook: {channel, template_code, recipients}
    sort_order          INT         NOT NULL DEFAULT 0,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_workflow_transition_rules PRIMARY KEY (tenant_id, rule_id),
    CONSTRAINT uq_workflow_rule_id UNIQUE (rule_id),
    CONSTRAINT fk_wtr_workflow FOREIGN KEY (tenant_id, workflow_id)
        REFERENCES workflow_master(tenant_id, workflow_id) ON DELETE CASCADE,
    CONSTRAINT fk_wtr_from_state FOREIGN KEY (tenant_id, from_state_id)
        REFERENCES workflow_states(tenant_id, state_id) ON DELETE RESTRICT,
    CONSTRAINT fk_wtr_to_state FOREIGN KEY (tenant_id, to_state_id)
        REFERENCES workflow_states(tenant_id, state_id) ON DELETE RESTRICT,
    CONSTRAINT fk_wtr_guard_policy FOREIGN KEY (tenant_id, guard_policy_id)
        REFERENCES policy_master(tenant_id, policy_id) ON DELETE SET NULL
);

COMMENT ON TABLE  workflow_transition_rules                   IS 'Layer 4: Enriched transition graph edges. Extends Layer 2 workflow_transitions with typed state FKs, DSL guards, SLA auto-fire, and notification hooks.';
COMMENT ON COLUMN workflow_transition_rules.trigger_event     IS 'Event string fired by feature code; engine looks up matching edges and evaluates guards. No if(status==) in code (LAW 3).';
COMMENT ON COLUMN workflow_transition_rules.guard_policy_id   IS 'Policy evaluated BEFORE the transition fires. Denial blocks the transition (LAW 4).';
COMMENT ON COLUMN workflow_transition_rules.guard_dsl         IS 'Inline JSON Logic predicate as a quick guard without needing a full policy row.';
COMMENT ON COLUMN workflow_transition_rules.auto_fire_after_hours IS 'If set, a scheduler automatically fires this transition when the entity exceeds the SLA.';
COMMENT ON COLUMN workflow_transition_rules.actor_roles       IS 'RBAC: array of role codes whose members may fire this event manually.';
COMMENT ON COLUMN workflow_transition_rules.notification_hook IS 'Structured spec for notifications on transition: {channel: "email", template_code: "approval_needed", recipients: ["REVIEWER"]}.';


-- -----------------------------------------------------------------------------
-- workflow_instance_state
-- Tracks the CURRENT state of a specific entity-record within a workflow.
-- This is the fast-read denormalised table; the authoritative audit trail is
-- workflow_state_log (Layer 2, INSERT-ONLY).
-- One row per (tenant_id, workflow_id, record_id) combination.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow_instance_state (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    instance_id     UUID            NOT NULL DEFAULT gen_random_uuid(),
    workflow_id     UUID            NOT NULL,
    record_id       UUID            NOT NULL,           -- UUID of the entity instance
    current_state_id UUID           NOT NULL,           -- FK → workflow_states
    entered_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    sla_deadline    TIMESTAMPTZ,                        -- Computed: entered_at + state.sla_hours
    assigned_to     UUID,                               -- FK → entity record for the current actor
    metadata        JSONB,

    CONSTRAINT pk_workflow_instance_state PRIMARY KEY (tenant_id, instance_id),
    CONSTRAINT uq_workflow_instance_id UNIQUE (instance_id),
    CONSTRAINT uq_wis_record UNIQUE (tenant_id, workflow_id, record_id),
    CONSTRAINT fk_wis_workflow FOREIGN KEY (tenant_id, workflow_id)
        REFERENCES workflow_master(tenant_id, workflow_id) ON DELETE RESTRICT,
    CONSTRAINT fk_wis_state FOREIGN KEY (tenant_id, current_state_id)
        REFERENCES workflow_states(tenant_id, state_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  workflow_instance_state                  IS 'Layer 4: Fast-read current-state table for each entity instance in a workflow. Denormalised from workflow_state_log (Layer 2).';
COMMENT ON COLUMN workflow_instance_state.record_id        IS 'UUID of the entity instance whose state is tracked (maps to entity_records.record_id in Layer 6).';
COMMENT ON COLUMN workflow_instance_state.current_state_id IS 'FK to workflow_states; updated on every transition. Authoritative source remains workflow_state_log.';
COMMENT ON COLUMN workflow_instance_state.sla_deadline     IS 'Pre-computed deadline: entered_at + state.sla_hours. Used by scheduler to fire auto-transitions.';

CREATE INDEX IF NOT EXISTS idx_wis_workflow_state
    ON workflow_instance_state(tenant_id, workflow_id, current_state_id);
CREATE INDEX IF NOT EXISTS idx_wis_record
    ON workflow_instance_state(tenant_id, record_id);
CREATE INDEX IF NOT EXISTS idx_wis_sla
    ON workflow_instance_state(tenant_id, sla_deadline)
    WHERE sla_deadline IS NOT NULL;


-- =============================================================================
-- LAYER 5 — POLICY DSL ENGINE
-- Purpose: Gives Layer 2's abstract policy_master concrete sub-tables for
--          structured DSL conditions (policy_conditions) and typed actions
--          (policy_actions). All conditions are stored as structured JSON DSL —
--          NEVER as free-text SQL fragments.
--
-- Architecture:
--   policy_master   (Layer 2)  — the named policy envelope
--   policy_conditions (Layer 5) — one or more structured predicates
--   policy_actions    (Layer 5) — effects to apply when policy fires
-- =============================================================================


-- -----------------------------------------------------------------------------
-- policy_conditions
-- Each row is ONE atomic predicate in a policy.
-- Multiple conditions on the same policy_id are combined via combine_operator.
-- Conditions are stored as a structured JSON DSL object to allow:
--   • machine evaluation (json_logic / CEL engine)
--   • UI rendering of a rule builder
--   • introspection / audit
-- NO free text. NO raw SQL. (LAW 9)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS policy_conditions (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    condition_id        UUID        NOT NULL DEFAULT gen_random_uuid(),
    policy_id           UUID        NOT NULL,
    condition_group     TEXT        NOT NULL DEFAULT 'default',  -- Groups allow nested AND/OR
    combine_operator    TEXT        NOT NULL DEFAULT 'AND'
                            CHECK (combine_operator IN ('AND','OR')),
    subject_type        TEXT        NOT NULL,
    -- subject_type options:
    --   ATTRIBUTE    — compares an entity attribute value
    --   ROLE         — checks actor's role membership
    --   TIME         — time-of-day / calendar constraint
    --   QUOTA        — checks a computed counter against a limit
    --   CUSTOM_DSL   — full JSON Logic expression in dsl_expression
    attribute_id        UUID,                           -- FK → attribute_master (when subject_type=ATTRIBUTE)
    operator            TEXT        NOT NULL,
    -- operator examples: eq | ne | lt | lte | gt | gte | in | not_in | contains | matches_regex
    comparison_value    JSONB       NOT NULL,           -- Typed expected value(s); always structured JSON
    dsl_expression      JSONB,                          -- Full JSON Logic tree for CUSTOM_DSL subject_type
    negate              BOOLEAN     NOT NULL DEFAULT FALSE,  -- TRUE = NOT(this condition)
    sort_order          INT         NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_policy_conditions PRIMARY KEY (tenant_id, condition_id),
    CONSTRAINT uq_policy_condition_id UNIQUE (condition_id),
    CONSTRAINT fk_pc_policy FOREIGN KEY (tenant_id, policy_id)
        REFERENCES policy_master(tenant_id, policy_id) ON DELETE CASCADE,
    CONSTRAINT fk_pc_attribute FOREIGN KEY (tenant_id, attribute_id)
        REFERENCES attribute_master(tenant_id, attribute_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  policy_conditions                   IS 'Layer 5: Structured DSL predicates for a policy. No free text or raw SQL ever (LAW 9). Evaluated by the policy engine BEFORE workflow transitions (LAW 4).';
COMMENT ON COLUMN policy_conditions.condition_group   IS 'Named group for scoping AND/OR nesting. Conditions in the same group share combine_operator.';
COMMENT ON COLUMN policy_conditions.combine_operator  IS 'How this condition combines with siblings in the same group: AND | OR.';
COMMENT ON COLUMN policy_conditions.subject_type      IS 'What kind of thing is being tested: ATTRIBUTE | ROLE | TIME | QUOTA | CUSTOM_DSL.';
COMMENT ON COLUMN policy_conditions.attribute_id      IS 'For subject_type=ATTRIBUTE: the attribute whose runtime value is evaluated.';
COMMENT ON COLUMN policy_conditions.operator          IS 'Comparison operator: eq | ne | lt | lte | gt | gte | in | not_in | contains | matches_regex.';
COMMENT ON COLUMN policy_conditions.comparison_value  IS 'Expected value(s) as typed JSON. E.g. 18 (number), "ACTIVE" (string), [1,2,3] (set).';
COMMENT ON COLUMN policy_conditions.dsl_expression    IS 'Full JSON Logic tree used when subject_type=CUSTOM_DSL. Overrides attribute_id + operator.';
COMMENT ON COLUMN policy_conditions.negate            IS 'When TRUE the condition is logically negated (NOT predicate).';

CREATE INDEX IF NOT EXISTS idx_pcond_policy
    ON policy_conditions(tenant_id, policy_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_pcond_attribute
    ON policy_conditions(tenant_id, attribute_id)
    WHERE attribute_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- policy_actions
-- Typed effects that execute when a policy evaluates to a given outcome.
-- Extends Layer 2's policy_action_map with richer typing and payload schema.
-- Each row is one action tied to one outcome of one policy.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS policy_actions (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    action_id           UUID        NOT NULL DEFAULT gen_random_uuid(),
    policy_id           UUID        NOT NULL,
    outcome             TEXT        NOT NULL
                            CHECK (outcome IN ('allow','deny','require','flag','escalate','notify')),
    action_type         TEXT        NOT NULL,
    -- action_type options:
    --   BLOCK_TRANSITION       — halt workflow progression
    --   SEND_NOTIFICATION      — push an in-app / email / SMS alert
    --   CREATE_TASK            — insert a follow-up task into the queue
    --   SET_ATTRIBUTE_VALUE    — override an EAV value on the record
    --   START_WORKFLOW         — trigger a child workflow on the record
    --   LOG_AUDIT_EVENT        — write a structured entry to an audit log
    --   CALL_WEBHOOK           — HTTP callback to an external system
    action_payload      JSONB       NOT NULL,           -- Typed structured arg bag (no raw SQL)
    priority            INT         NOT NULL DEFAULT 100,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_policy_actions PRIMARY KEY (tenant_id, action_id),
    CONSTRAINT uq_policy_action_id UNIQUE (action_id),
    CONSTRAINT fk_pa_policy FOREIGN KEY (tenant_id, policy_id)
        REFERENCES policy_master(tenant_id, policy_id) ON DELETE CASCADE
);

COMMENT ON TABLE  policy_actions                  IS 'Layer 5: Typed effects that fire when a policy produces a given outcome. Richer replacement for Layer 2 policy_action_map.';
COMMENT ON COLUMN policy_actions.outcome          IS 'The policy verdict that triggers this action: allow | deny | require | flag | escalate | notify.';
COMMENT ON COLUMN policy_actions.action_type      IS 'Enum of typed system actions: BLOCK_TRANSITION | SEND_NOTIFICATION | CREATE_TASK | SET_ATTRIBUTE_VALUE | START_WORKFLOW | LOG_AUDIT_EVENT | CALL_WEBHOOK.';
COMMENT ON COLUMN policy_actions.action_payload   IS 'Structured JSON argument bag specific to action_type. No raw SQL or template strings. E.g. {template_code: "approval_needed", recipients: ["REVIEWER"]}.';
COMMENT ON COLUMN policy_actions.priority         IS 'Execution order when multiple actions share the same outcome; lower = first.';

CREATE INDEX IF NOT EXISTS idx_paction_policy
    ON policy_actions(tenant_id, policy_id, outcome, priority);


-- -----------------------------------------------------------------------------
-- policy_evaluation_log
-- INSERT-ONLY record of every policy evaluation event.
-- LAW 8: No UPDATE or DELETE.
-- Enables post-hoc audit of "why was this entity blocked/allowed?"
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS policy_evaluation_log (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    log_id          UUID            NOT NULL DEFAULT gen_random_uuid(),
    policy_id       UUID            NOT NULL,
    record_id       UUID            NOT NULL,           -- Entity instance evaluated
    actor_id        UUID,                               -- User or service that triggered evaluation
    context_snapshot JSONB          NOT NULL,           -- Snapshot of attribute values at eval time
    outcome         TEXT            NOT NULL
                        CHECK (outcome IN ('allow','deny','require','flag','escalate','notify')),
    conditions_result JSONB,                            -- Per-condition pass/fail details
    evaluated_at    TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_policy_evaluation_log PRIMARY KEY (tenant_id, log_id),
    CONSTRAINT uq_policy_log_id UNIQUE (log_id),
    CONSTRAINT fk_pel_policy FOREIGN KEY (tenant_id, policy_id)
        REFERENCES policy_master(tenant_id, policy_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  policy_evaluation_log                    IS 'Layer 5 / LAW 8: INSERT-ONLY log of every policy evaluation. Used for audit trails and explainability ("why was I denied?").';
COMMENT ON COLUMN policy_evaluation_log.context_snapshot   IS 'JSONB snapshot of attribute values visible to the engine at evaluation time. Immutable.';
COMMENT ON COLUMN policy_evaluation_log.conditions_result  IS 'Per-condition pass/fail breakdown as JSONB, enabling granular audit.';

-- INSERT-ONLY guard (LAW 8)
CREATE OR REPLACE FUNCTION fn_policy_eval_log_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'policy_evaluation_log is INSERT-ONLY (LAW 8). UPDATE and DELETE are forbidden.';
END;
$$;

CREATE TRIGGER trg_pel_no_update
    BEFORE UPDATE ON policy_evaluation_log
    FOR EACH ROW EXECUTE FUNCTION fn_policy_eval_log_no_mutation();

CREATE TRIGGER trg_pel_no_delete
    BEFORE DELETE ON policy_evaluation_log
    FOR EACH ROW EXECUTE FUNCTION fn_policy_eval_log_no_mutation();

CREATE INDEX IF NOT EXISTS idx_pel_policy_record
    ON policy_evaluation_log(tenant_id, policy_id, record_id, evaluated_at DESC);
CREATE INDEX IF NOT EXISTS idx_pel_record
    ON policy_evaluation_log(tenant_id, record_id, evaluated_at DESC);


-- =============================================================================
-- LAYER 6 — EAV RUNTIME DATA STORE
-- Purpose: The actual runtime data of every entity instance in the OS lives
--          here. No domain data is stored as custom columns (LAW 2).
--
-- Three tables:
--   entity_records          — one row per object instance (envelope)
--   entity_attribute_values — EAV values (the actual data)
--   entity_record_index     — searchable mirror for is_searchable attributes
--
-- Relationship to Layer 1:
--   entity_master      defines TYPES  (what kinds of things exist)
--   attribute_master   defines FIELDS (what fields those types have)
--   entity_records     defines INSTANCES (actual objects)
--   entity_attribute_values stores INSTANCE FIELD VALUES
-- =============================================================================


-- -----------------------------------------------------------------------------
-- entity_records
-- One row per entity instance (e.g. one student, one course, one assignment).
-- The "envelope" — stores only universal lifecycle metadata.
-- Actual field data is in entity_attribute_values.
-- LAW 2: No custom columns here.
-- LAW 10: No rank/grade/pass-fail stored — derived at query time.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS entity_records (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    record_id       UUID            NOT NULL DEFAULT gen_random_uuid(),
    entity_id       UUID            NOT NULL,           -- FK → entity_master (type of this record)
    current_state_id UUID,                              -- FK → workflow_states (Layer 4)
    display_name    TEXT,                               -- Optional human-readable label for the record
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_by      UUID,                               -- Actor UUID; FK resolved at app layer
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,                        -- Soft-delete; NULL = not deleted

    CONSTRAINT pk_entity_records PRIMARY KEY (tenant_id, record_id),
    CONSTRAINT uq_record_id UNIQUE (record_id),
    CONSTRAINT fk_er_entity FOREIGN KEY (tenant_id, entity_id)
        REFERENCES entity_master(tenant_id, entity_id) ON DELETE RESTRICT,
    CONSTRAINT fk_er_current_state FOREIGN KEY (tenant_id, current_state_id)
        REFERENCES workflow_states(tenant_id, state_id) ON DELETE SET NULL
);

COMMENT ON TABLE  entity_records               IS 'Layer 6: One row per entity instance (student, course, batch, etc.). Envelope only — field data is in entity_attribute_values. LAW 2: no custom columns.';
COMMENT ON COLUMN entity_records.entity_id     IS 'FK to entity_master defining the type/schema of this instance.';
COMMENT ON COLUMN entity_records.display_name  IS 'Optional denormalised label for list views. Source of truth for the actual value remains entity_attribute_values.';
COMMENT ON COLUMN entity_records.deleted_at    IS 'Soft-delete timestamp. Application layer filters WHERE deleted_at IS NULL for live records.';

CREATE INDEX IF NOT EXISTS idx_er_entity
    ON entity_records(tenant_id, entity_id);
CREATE INDEX IF NOT EXISTS idx_er_created
    ON entity_records(tenant_id, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_er_active
    ON entity_records(tenant_id, entity_id, is_active)
    WHERE deleted_at IS NULL;


-- -----------------------------------------------------------------------------
-- entity_attribute_values
-- The EAV value store for ALL runtime entity data.
-- This is the canonical location for every dynamic field value in the OS.
-- Replaces and supersedes Layer 1's attribute_values; this table carries
-- richer versioning, author tracking, and source provenance.
--
-- Design note on typing:
--   Three physical value columns accommodate all data types without casting loss:
--     value_text   → text | file reference | JSON string | date ISO string
--     value_number → integer & decimal values
--     value_bool   → boolean flags
--   The correct column to read is determined by attribute_master.data_type.
-- LAW 10: No grade, rank, or pass/fail stored.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS entity_attribute_values (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    value_id        UUID            NOT NULL DEFAULT gen_random_uuid(),
    record_id       UUID            NOT NULL,           -- FK → entity_records
    attribute_id    UUID            NOT NULL,           -- FK → attribute_master
    value_text      TEXT,                               -- data_type IN (text, file, json, date)
    value_number    NUMERIC,                            -- data_type = number
    value_bool      BOOLEAN,                            -- data_type = boolean
    value_jsonb     JSONB,                              -- data_type = json (structured form)
    source          TEXT            NOT NULL DEFAULT 'user_input',
    -- source options: user_input | system_computed | import | api | default
    version         INT             NOT NULL DEFAULT 1,
    created_by      UUID,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_entity_attribute_values PRIMARY KEY (tenant_id, value_id),
    CONSTRAINT uq_eav_value_id UNIQUE (value_id),
    CONSTRAINT uq_eav_record_attribute UNIQUE (tenant_id, record_id, attribute_id),
    CONSTRAINT fk_eav_record FOREIGN KEY (tenant_id, record_id)
        REFERENCES entity_records(tenant_id, record_id) ON DELETE CASCADE,
    CONSTRAINT fk_eav_attribute FOREIGN KEY (tenant_id, attribute_id)
        REFERENCES attribute_master(tenant_id, attribute_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  entity_attribute_values               IS 'Layer 6: The canonical EAV value store. ALL runtime entity field data lives here. LAW 2 enforcement. LAW 10: no grade/rank/pass-fail columns.';
COMMENT ON COLUMN entity_attribute_values.record_id     IS 'FK to entity_records identifying the specific entity instance.';
COMMENT ON COLUMN entity_attribute_values.attribute_id  IS 'FK to attribute_master identifying the field whose value this row stores.';
COMMENT ON COLUMN entity_attribute_values.value_text    IS 'Value for data_type = text | file | date | json (as string).';
COMMENT ON COLUMN entity_attribute_values.value_number  IS 'Value for data_type = number (integer or decimal, full precision).';
COMMENT ON COLUMN entity_attribute_values.value_bool    IS 'Value for data_type = boolean.';
COMMENT ON COLUMN entity_attribute_values.value_jsonb   IS 'Value for data_type = json when structured traversal is needed (preferred over value_text for JSON).';
COMMENT ON COLUMN entity_attribute_values.source        IS 'Provenance: user_input | system_computed | import | api | default.';
COMMENT ON COLUMN entity_attribute_values.version       IS 'Optimistic concurrency counter; incremented on each write.';

CREATE INDEX IF NOT EXISTS idx_eav_record
    ON entity_attribute_values(tenant_id, record_id);
CREATE INDEX IF NOT EXISTS idx_eav_attribute_record
    ON entity_attribute_values(tenant_id, attribute_id, record_id);


-- -----------------------------------------------------------------------------
-- entity_attribute_value_history
-- INSERT-ONLY audit log that captures every previous value before it is
-- overwritten in entity_attribute_values.
-- LAW 8: No UPDATE or DELETE ever.
-- Provides full change history for compliance and "undo" features.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS entity_attribute_value_history (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    history_id      UUID            NOT NULL DEFAULT gen_random_uuid(),
    value_id        UUID            NOT NULL,           -- FK → entity_attribute_values.value_id
    record_id       UUID            NOT NULL,
    attribute_id    UUID            NOT NULL,
    old_value_text  TEXT,
    old_value_number NUMERIC,
    old_value_bool  BOOLEAN,
    old_value_jsonb JSONB,
    changed_by      UUID,
    change_reason   TEXT,
    superseded_at   TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_entity_attribute_value_history PRIMARY KEY (tenant_id, history_id),
    CONSTRAINT uq_eav_history_id UNIQUE (history_id),
    CONSTRAINT fk_eavh_attribute FOREIGN KEY (tenant_id, attribute_id)
        REFERENCES attribute_master(tenant_id, attribute_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  entity_attribute_value_history              IS 'Layer 6 / LAW 8: INSERT-ONLY value history. Every overwrite of entity_attribute_values creates a row here. Never updated or deleted.';
COMMENT ON COLUMN entity_attribute_value_history.value_id     IS 'References the entity_attribute_values row whose value was superseded.';
COMMENT ON COLUMN entity_attribute_value_history.superseded_at IS 'Timestamp when this value was replaced. Enables point-in-time reconstruction.';

-- INSERT-ONLY guard (LAW 8)
CREATE OR REPLACE FUNCTION fn_eavh_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'entity_attribute_value_history is INSERT-ONLY (LAW 8). UPDATE and DELETE are forbidden.';
END;
$$;

CREATE TRIGGER trg_eavh_no_update
    BEFORE UPDATE ON entity_attribute_value_history
    FOR EACH ROW EXECUTE FUNCTION fn_eavh_no_mutation();

CREATE TRIGGER trg_eavh_no_delete
    BEFORE DELETE ON entity_attribute_value_history
    FOR EACH ROW EXECUTE FUNCTION fn_eavh_no_mutation();

CREATE INDEX IF NOT EXISTS idx_eavh_value
    ON entity_attribute_value_history(tenant_id, value_id, superseded_at DESC);
CREATE INDEX IF NOT EXISTS idx_eavh_record
    ON entity_attribute_value_history(tenant_id, record_id, superseded_at DESC);


-- -----------------------------------------------------------------------------
-- entity_record_index
-- SEARCH-OPTIMISED mirror table.
-- ONLY attributes with is_searchable = TRUE in attribute_master are written here.
-- Purpose: enables fast text-search and faceted filtering across entities
--          without a full EAV scan.
-- Populated/updated by a database trigger on entity_attribute_values (see below).
-- Do NOT read this table for authoritative data — always read entity_attribute_values.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS entity_record_index (
    tenant_id       UUID            NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    index_id        UUID            NOT NULL DEFAULT gen_random_uuid(),
    record_id       UUID            NOT NULL,           -- FK → entity_records
    entity_id       UUID            NOT NULL,           -- Denormalised for filtered searches
    attribute_id    UUID            NOT NULL,           -- FK → attribute_master (is_searchable = TRUE)
    index_value     TEXT            NOT NULL,           -- Normalised text representation for search
    index_value_num NUMERIC,                            -- Numeric mirror for range queries
    tsvector_value  TSVECTOR,                           -- Pre-computed full-text search vector
    indexed_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_entity_record_index PRIMARY KEY (tenant_id, index_id),
    CONSTRAINT uq_index_id UNIQUE (index_id),
    CONSTRAINT uq_eri_record_attribute UNIQUE (tenant_id, record_id, attribute_id),
    CONSTRAINT fk_eri_record FOREIGN KEY (tenant_id, record_id)
        REFERENCES entity_records(tenant_id, record_id) ON DELETE CASCADE,
    CONSTRAINT fk_eri_attribute FOREIGN KEY (tenant_id, attribute_id)
        REFERENCES attribute_master(tenant_id, attribute_id) ON DELETE CASCADE
);

COMMENT ON TABLE  entity_record_index                   IS 'Layer 6: Search-optimised mirror of entity_attribute_values for is_searchable attributes only. NOT authoritative — source of truth is entity_attribute_values.';
COMMENT ON COLUMN entity_record_index.entity_id         IS 'Denormalised FK to entity_master; enables entity-type-scoped search without a join.';
COMMENT ON COLUMN entity_record_index.index_value       IS 'Normalised text representation of the attribute value, lowercased for case-insensitive matching.';
COMMENT ON COLUMN entity_record_index.index_value_num   IS 'Numeric mirror of the value for range queries (BETWEEN, >, <, etc.).';
COMMENT ON COLUMN entity_record_index.tsvector_value    IS 'Pre-computed PostgreSQL TSVECTOR for fast full-text search via GIN index.';

-- Equality / range search
CREATE INDEX IF NOT EXISTS idx_eri_tenant_entity
    ON entity_record_index(tenant_id, entity_id);
CREATE INDEX IF NOT EXISTS idx_eri_attribute_value
    ON entity_record_index(tenant_id, attribute_id, index_value);
CREATE INDEX IF NOT EXISTS idx_eri_attribute_num
    ON entity_record_index(tenant_id, attribute_id, index_value_num)
    WHERE index_value_num IS NOT NULL;
-- Full-text search via GIN
CREATE INDEX IF NOT EXISTS idx_eri_fts
    ON entity_record_index USING GIN (tsvector_value)
    WHERE tsvector_value IS NOT NULL;


-- -----------------------------------------------------------------------------
-- Trigger: auto-populate entity_record_index on EAV writes
-- Fires AFTER INSERT OR UPDATE on entity_attribute_values.
-- Only indexes the row when attribute_master.is_searchable = TRUE.
-- Keeps the index in sync without requiring application-layer glue.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_sync_entity_record_index()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_is_searchable BOOLEAN;
    v_entity_id     UUID;
    v_index_text    TEXT;
    v_index_num     NUMERIC;
BEGIN
    -- Check the is_searchable flag
    SELECT am.is_searchable, er.entity_id
    INTO   v_is_searchable, v_entity_id
    FROM   attribute_master am
    JOIN   entity_records   er
           ON er.tenant_id = NEW.tenant_id
          AND er.record_id  = NEW.record_id
    WHERE  am.tenant_id    = NEW.tenant_id
      AND  am.attribute_id = NEW.attribute_id;

    -- Only proceed for searchable attributes
    IF v_is_searchable IS NOT TRUE THEN
        RETURN NEW;
    END IF;

    -- Compute normalised index_value (text)
    v_index_text := COALESCE(
        lower(NEW.value_text),
        NEW.value_number::TEXT,
        NEW.value_bool::TEXT
    );

    v_index_num := NEW.value_number;

    INSERT INTO entity_record_index (
        tenant_id, record_id, entity_id, attribute_id,
        index_value, index_value_num, tsvector_value, indexed_at
    )
    VALUES (
        NEW.tenant_id,
        NEW.record_id,
        v_entity_id,
        NEW.attribute_id,
        COALESCE(v_index_text, ''),
        v_index_num,
        to_tsvector('english', COALESCE(v_index_text, '')),
        now()
    )
    ON CONFLICT (tenant_id, record_id, attribute_id)
    DO UPDATE SET
        index_value      = EXCLUDED.index_value,
        index_value_num  = EXCLUDED.index_value_num,
        tsvector_value   = EXCLUDED.tsvector_value,
        indexed_at       = now();

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_index_on_eav_write
    AFTER INSERT OR UPDATE ON entity_attribute_values
    FOR EACH ROW EXECUTE FUNCTION fn_sync_entity_record_index();

COMMENT ON FUNCTION fn_sync_entity_record_index IS 'Auto-syncs entity_record_index when is_searchable attribute values are written. Maintains full-text tsvector and normalised text/numeric mirrors.';


-- =============================================================================
-- ROW-LEVEL SECURITY (RLS) — Layer 4, 5, 6 tables
-- LAW 6 + RULES.md: RLS is mandatory on all tenant tables.
-- Tenant context is set via: SET LOCAL app.tenant_id = '<uuid>';
-- at the start of every transaction (server-side only — LAW 7).
-- =============================================================================

-- Layer 4
ALTER TABLE workflow_states               ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_transition_rules     ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_instance_state       ENABLE ROW LEVEL SECURITY;

-- Layer 5
ALTER TABLE policy_conditions             ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_actions                ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_evaluation_log         ENABLE ROW LEVEL SECURITY;

-- Layer 6
ALTER TABLE entity_records                ENABLE ROW LEVEL SECURITY;
ALTER TABLE entity_attribute_values       ENABLE ROW LEVEL SECURITY;
ALTER TABLE entity_attribute_value_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE entity_record_index           ENABLE ROW LEVEL SECURITY;

-- RLS policies (all keyed on current_setting('app.tenant_id', TRUE)::UUID)

-- Layer 4
CREATE POLICY rls_workflow_states
    ON workflow_states
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_workflow_transition_rules
    ON workflow_transition_rules
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_workflow_instance_state
    ON workflow_instance_state
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

-- Layer 5
CREATE POLICY rls_policy_conditions
    ON policy_conditions
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_policy_actions
    ON policy_actions
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_policy_evaluation_log
    ON policy_evaluation_log
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

-- Layer 6
CREATE POLICY rls_entity_records
    ON entity_records
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_entity_attribute_values
    ON entity_attribute_values
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_entity_attribute_value_history
    ON entity_attribute_value_history
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_entity_record_index
    ON entity_record_index
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);


-- =============================================================================
-- END OF SCHEMA: LAYERS 4 → 6
-- =============================================================================
