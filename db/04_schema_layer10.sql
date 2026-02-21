-- =============================================================================
-- PRATHAMONE ACADEMY OS — DATABASE SCHEMA
-- Layer 10  (Declarative Report Engine)
-- =============================================================================
-- Depends on: db/schema_layer0_layer3.sql  (must be applied first)
--             db/schema_layer4_layer6.sql  (must be applied second)
--             db/schema_layer7_layer9.sql  (must be applied third)
--
-- RULES.MD compliance checklist applied to every table in this file:
--   LAW 1  : All entities registered in entity_master (Layer 1)
--   LAW 2  : No custom columns — variable fields use EAV (Layer 6)
--   LAW 3  : No if(status==) in code — workflow_transition_rules drive state
--   LAW 4  : Policies evaluate BEFORE workflow transitions
--   LAW 5  : Settings decide DEFAULT — report defaults from system_settings
--   LAW 6  : tenant_id FK on EVERY TABLE — with one documented exception:
--             report_master.tenant_id IS NULLABLE so that NULL rows are
--             SYSTEM-level templates inherited by all tenants (see below)
--   LAW 7  : tenant_id injected server-side; frontend NEVER sends it
--   LAW 8  : report_execution_log is INSERT-ONLY (trigger enforced)
--   LAW 9  : Reports are DECLARATIVE METADATA ONLY — no raw SQL in rows
--   LAW 10 : No rank/grade/pass-fail stored; derived at runtime
--   LAW 11 : New report types add rows, not tables
--   LAW 12 : The kernel is locked; features are data
-- =============================================================================


-- =============================================================================
-- LAYER 10 — DECLARATIVE REPORT ENGINE
-- Purpose: Implements LAW 9 end-to-end. Every report in the OS is a set of
--          data rows in this layer — NEVER a hard-coded SQL query in feature
--          code. The report engine reads these rows and dynamically constructs
--          and executes the query at runtime.
--
-- Architecture overview:
--   report_master        — the named report envelope (nullable tenant_id for
--                           system templates shared across all tenants)
--   report_dimensions    — GROUP BY / row-axis columns (one row = one column)
--   report_measures      — aggregated metrics (SUM, COUNT, AVG, etc.)
--   report_filters       — WHERE-clause predicates in structured DSL
--   report_role_access   — RBAC: which roles may VIEW / EXPORT this report
--   report_execution_log — INSERT-ONLY audit of every report run
--
-- System-template pattern (tenant_id = NULL):
--   When report_master.tenant_id IS NULL the report is a SYSTEM template
--   that all tenants inherit. Tenant-specific overrides are separate rows
--   with a non-null tenant_id pointing back to the same base report via
--   base_report_id.  RLS is adjusted so NULL-tenant rows are visible to all.
--
-- No raw SQL anywhere in this layer. The engine resolves:
--   entity_id → entity_master → attribute_master → column name
--   measure function + attribute → aggregation expression
--   filter DSL → structured WHERE predicate
-- =============================================================================


-- -----------------------------------------------------------------------------
-- report_master
-- The named report envelope. One row = one report definition.
--
-- SPECIAL RULE — tenant_id IS NULLABLE (approved exception to LAW 6):
--   NULL  → SYSTEM template. Visible to every tenant. Managed by platform ops.
--   UUID  → TENANT report. Visible only to that tenant (enforced by RLS).
--
-- The composite PK uses a synthetic report_id rather than (tenant_id, X)
-- because tenant_id can be NULL and NULL != NULL in PostgreSQL uniqueness.
-- report_id alone is therefore the primary key; tenant_id is a side-channel FK.
--
-- LAW 9: report_query_type drives which engine path renders the report.
--        No raw SQL is stored in this table.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS report_master (
    report_id           UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_id           UUID,
    -- NULL  = SYSTEM template (visible to all tenants, managed by platform ops)
    -- UUID  = tenant-owned report (isolated by RLS)
    base_report_id      UUID,
    -- When this row is a tenant override of a SYSTEM template, this FK points
    -- to the system template's report_id. NULL for original reports.
    report_code         TEXT        NOT NULL,
    -- Dot-namespaced machine identifier:
    --   e.g. 'academic.attendance.monthly_summary'
    --        'finance.fees.outstanding_by_class'
    --        'ai.usage.token_consumption'
    display_name        TEXT        NOT NULL,
    description         TEXT,
    report_category     TEXT        NOT NULL
                            CHECK (report_category IN (
                                'ACADEMIC','FINANCE','AI','OPERATIONS',
                                'COMPLIANCE','CUSTOM'
                            )),
    primary_entity_id   UUID        NOT NULL,
    -- FK → entity_master.entity_id — the root entity this report queries.
    -- The engine resolves table and join paths from here.
    report_query_type   TEXT        NOT NULL DEFAULT 'AGGREGATE'
                            CHECK (report_query_type IN (
                                'AGGREGATE',    -- GROUP BY with measures
                                'DETAIL',       -- Row-level, no aggregation
                                'PIVOT',        -- Cross-tab pivot
                                'FUNNEL',       -- Step-based funnel analysis
                                'TIMESERIES'    -- Time-bucketed metric series
                            )),
    default_date_range  TEXT        NOT NULL DEFAULT 'CURRENT_MONTH'
                            CHECK (default_date_range IN (
                                'TODAY','CURRENT_WEEK','CURRENT_MONTH',
                                'CURRENT_TERM','CURRENT_YEAR','ALL_TIME','CUSTOM'
                            )),
    max_rows            INT         NOT NULL DEFAULT 10000,
    -- Safety cap on result size; engine enforces LIMIT max_rows
    is_exportable       BOOLEAN     NOT NULL DEFAULT TRUE,
    -- FALSE = report may be viewed but never downloaded / exported
    export_formats      TEXT[]      NOT NULL DEFAULT '{CSV,XLSX}',
    -- Allowed export formats: CSV | XLSX | PDF | JSON
    is_scheduled        BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = report can be queued for automated periodic delivery
    schedule_cron       TEXT,
    -- ISO 8601 / CRON expression for scheduled reports; NULL if not scheduled
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    sort_order          INT         NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          UUID,
    -- Actor UUID; FK resolved at app layer

    CONSTRAINT pk_report_master PRIMARY KEY (report_id),
    CONSTRAINT uq_report_code_tenant UNIQUE (tenant_id, report_code),
    -- tenant_id=NULL rows: NULLS are treated as distinct, so two system
    -- templates cannot share the same report_code due to the unique index below.
    CONSTRAINT fk_rm_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    CONSTRAINT fk_rm_base_report FOREIGN KEY (base_report_id)
        REFERENCES report_master(report_id) ON DELETE SET NULL,
    CONSTRAINT fk_rm_entity FOREIGN KEY (primary_entity_id)
        REFERENCES entity_master(entity_id) ON DELETE RESTRICT
);

-- Partial unique index: enforce report_code uniqueness for SYSTEM templates
-- (where tenant_id IS NULL), independently of the nullable UNIQUE constraint.
CREATE UNIQUE INDEX IF NOT EXISTS uq_report_code_system
    ON report_master(report_code)
    WHERE tenant_id IS NULL;

COMMENT ON TABLE  report_master                     IS 'Layer 10 / LAW 9: Declarative report envelope. No raw SQL stored anywhere. NULL tenant_id = SYSTEM template inherited by all tenants. UUID tenant_id = tenant-owned report.';
COMMENT ON COLUMN report_master.tenant_id           IS 'NULL = SYSTEM template (accessible to all tenants). UUID = tenant-specific report. LAW 6 exception documented and intentional.';
COMMENT ON COLUMN report_master.base_report_id      IS 'For tenant overrides of system templates: FK to the original system report_id. NULL for first-party reports.';
COMMENT ON COLUMN report_master.report_code         IS 'Dot-namespaced machine identifier unique within (tenant_id, report_code). E.g. "academic.attendance.monthly_summary".';
COMMENT ON COLUMN report_master.primary_entity_id   IS 'Root entity for this report. Engine traverses entity_master and attribute_master to resolve columns — no hard-coded table names.';
COMMENT ON COLUMN report_master.report_query_type   IS 'Engine path: AGGREGATE | DETAIL | PIVOT | FUNNEL | TIMESERIES.';
COMMENT ON COLUMN report_master.max_rows            IS 'Safety LIMIT applied by the engine to every execution. Prevents runaway queries.';
COMMENT ON COLUMN report_master.is_exportable       IS 'When FALSE the engine never produces a downloadable file regardless of user request or role.';
COMMENT ON COLUMN report_master.export_formats      IS 'Allowed export formats: CSV | XLSX | PDF | JSON. Engine validates against this list before generating.';

CREATE INDEX IF NOT EXISTS idx_rm_tenant_category
    ON report_master(tenant_id, report_category, is_active);
CREATE INDEX IF NOT EXISTS idx_rm_entity
    ON report_master(primary_entity_id);
CREATE INDEX IF NOT EXISTS idx_rm_system_templates
    ON report_master(report_category, sort_order)
    WHERE tenant_id IS NULL;


-- -----------------------------------------------------------------------------
-- report_dimensions
-- Defines the GROUP BY / row-axis columns for a report.
-- Each row is ONE column in the output that the engine will group or display.
-- Resolved via attribute_master — NEVER by hard-coded column names (LAW 9).
-- Ordering by sort_order determines left-to-right column sequence.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS report_dimensions (
    tenant_id           UUID,
    -- Mirrors report_master.tenant_id — NULL for system-template dimensions
    dimension_id        UUID        NOT NULL DEFAULT gen_random_uuid(),
    report_id           UUID        NOT NULL,
    attribute_id        UUID,
    -- FK → attribute_master. NULL when dimension_source = EXPRESSION.
    dimension_source    TEXT        NOT NULL DEFAULT 'ATTRIBUTE'
                            CHECK (dimension_source IN (
                                'ATTRIBUTE',    -- Resolved from attribute_master
                                'DATE_TRUNC',   -- Time bucket (day/week/month/year)
                                'EXPRESSION'    -- Structured DSL expression (JSONB)
                            )),
    date_trunc_unit     TEXT
                            CHECK (date_trunc_unit IN ('DAY','WEEK','MONTH','QUARTER','YEAR')),
    -- Required when dimension_source = DATE_TRUNC; NULL otherwise
    expression_dsl      JSONB,
    -- Required when dimension_source = EXPRESSION; structured JSON Logic only
    -- No raw SQL (LAW 9)
    display_label       TEXT        NOT NULL,
    -- Column header shown in the report UI and export file
    is_pivotable        BOOLEAN     NOT NULL DEFAULT FALSE,
    -- When TRUE this dimension can be used as the horizontal axis in PIVOT reports
    sort_order          INT         NOT NULL DEFAULT 0,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_report_dimensions PRIMARY KEY (dimension_id),
    CONSTRAINT fk_rd_report FOREIGN KEY (report_id)
        REFERENCES report_master(report_id) ON DELETE CASCADE,
    CONSTRAINT fk_rd_attribute FOREIGN KEY (attribute_id)
        REFERENCES attribute_master(attribute_id) ON DELETE RESTRICT
    -- No tenant REFERENCES constraint: tenant_id may be NULL (SYSTEM templates)
);

COMMENT ON TABLE  report_dimensions                     IS 'Layer 10 / LAW 9: GROUP BY / row-axis column definitions for a report. Resolved via attribute_master — no hard-coded column names.';
COMMENT ON COLUMN report_dimensions.tenant_id           IS 'NULL for dimensions belonging to SYSTEM template reports. UUID for tenant-owned report dimensions.';
COMMENT ON COLUMN report_dimensions.attribute_id        IS 'FK to attribute_master. The report engine resolves the physical column from here. NULL when dimension_source = EXPRESSION.';
COMMENT ON COLUMN report_dimensions.dimension_source    IS 'Resolution strategy: ATTRIBUTE (from attribute_master) | DATE_TRUNC (time bucket) | EXPRESSION (structured JSON Logic DSL).';
COMMENT ON COLUMN report_dimensions.date_trunc_unit     IS 'Time bucket granularity: DAY | WEEK | MONTH | QUARTER | YEAR. Used only when dimension_source = DATE_TRUNC.';
COMMENT ON COLUMN report_dimensions.expression_dsl      IS 'Structured JSON Logic expression — used only when dimension_source = EXPRESSION. No raw SQL ever stored here (LAW 9).';
COMMENT ON COLUMN report_dimensions.is_pivotable        IS 'When TRUE this dimension can become the horizontal header axis in PIVOT report_query_type runs.';

CREATE INDEX IF NOT EXISTS idx_rdim_report
    ON report_dimensions(report_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_rdim_attribute
    ON report_dimensions(attribute_id)
    WHERE attribute_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- report_measures
-- Defines the aggregated metric columns for a report (the "numbers").
-- Each row is ONE aggregated column: COUNT, SUM, AVG, MIN, MAX, COUNT_DISTINCT.
-- The engine builds the SELECT aggregate expression from these rows.
-- LAW 9: no raw SQL — everything is expressed as (aggregate_fn, attribute_id).
-- LAW 10: no rank/grade output columns — this table stores metric definitions only.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS report_measures (
    tenant_id           UUID,
    -- NULL for system-template measures
    measure_id          UUID        NOT NULL DEFAULT gen_random_uuid(),
    report_id           UUID        NOT NULL,
    attribute_id        UUID,
    -- FK → attribute_master. NULL when measure_source = EXPRESSION or COUNT(*).
    measure_source      TEXT        NOT NULL DEFAULT 'ATTRIBUTE'
                            CHECK (measure_source IN (
                                'ATTRIBUTE',    -- aggregate_fn applied to an attribute value
                                'RECORD_COUNT', -- COUNT(*) — no attribute needed
                                'EXPRESSION'    -- Structured JSON Logic DSL
                            )),
    aggregate_fn        TEXT        NOT NULL
                            CHECK (aggregate_fn IN (
                                'COUNT','COUNT_DISTINCT','SUM','AVG',
                                'MIN','MAX','MEDIAN','PERCENTILE_90'
                            )),
    expression_dsl      JSONB,
    -- For measure_source = EXPRESSION; structured JSON Logic only; no raw SQL
    display_label       TEXT        NOT NULL,
    -- Column header shown in output and export
    format_type         TEXT        NOT NULL DEFAULT 'NUMBER'
                            CHECK (format_type IN (
                                'NUMBER','CURRENCY','PERCENTAGE','DURATION_HRS','CUSTOM'
                            )),
    -- Drives UI and export cell formatting; no derived values stored (LAW 10)
    decimal_places      INT         NOT NULL DEFAULT 0,
    is_primary          BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE marks the "headline" measure shown in summary cards
    sort_order          INT         NOT NULL DEFAULT 0,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_report_measures PRIMARY KEY (measure_id),
    CONSTRAINT fk_rmeas_report FOREIGN KEY (report_id)
        REFERENCES report_master(report_id) ON DELETE CASCADE,
    CONSTRAINT fk_rmeas_attribute FOREIGN KEY (attribute_id)
        REFERENCES attribute_master(attribute_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  report_measures                     IS 'Layer 10 / LAW 9: Aggregated metric column definitions for a report. Engine builds SELECT aggregates from these rows — no raw SQL stored. LAW 10: no grade/rank columns.';
COMMENT ON COLUMN report_measures.tenant_id           IS 'NULL for measures belonging to SYSTEM template reports.';
COMMENT ON COLUMN report_measures.attribute_id        IS 'FK to attribute_master. Required for ATTRIBUTE source; NULL for RECORD_COUNT or EXPRESSION.';
COMMENT ON COLUMN report_measures.measure_source      IS 'What to aggregate: ATTRIBUTE | RECORD_COUNT (COUNT(*)) | EXPRESSION (JSON Logic DSL).';
COMMENT ON COLUMN report_measures.aggregate_fn        IS 'Aggregation function: COUNT | COUNT_DISTINCT | SUM | AVG | MIN | MAX | MEDIAN | PERCENTILE_90.';
COMMENT ON COLUMN report_measures.format_type         IS 'Rendering hint for UI and export: NUMBER | CURRENCY | PERCENTAGE | DURATION_HRS | CUSTOM.';
COMMENT ON COLUMN report_measures.is_primary          IS 'TRUE = headline measure for dashboard summary cards.';

CREATE INDEX IF NOT EXISTS idx_rmeas_report
    ON report_measures(report_id, sort_order);


-- -----------------------------------------------------------------------------
-- report_filters
-- Defines the WHERE-clause predicates for a report.
-- Each row is ONE structured filter condition.
-- Filters can be static (baked into the report definition) or dynamic
-- (user-supplied values at runtime — flagged by is_user_facing = TRUE).
-- NEVER raw SQL (LAW 9). Always structured DSL using attribute_master + operator.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS report_filters (
    tenant_id           UUID,
    -- NULL for system-template filters
    filter_id           UUID        NOT NULL DEFAULT gen_random_uuid(),
    report_id           UUID        NOT NULL,
    filter_group        TEXT        NOT NULL DEFAULT 'default',
    -- Filters in the same group are combined with group_operator.
    -- Different groups are combined with AND.
    group_operator      TEXT        NOT NULL DEFAULT 'AND'
                            CHECK (group_operator IN ('AND','OR')),
    attribute_id        UUID,
    -- FK → attribute_master. Required unless filter_source = EXPRESSION.
    filter_source       TEXT        NOT NULL DEFAULT 'ATTRIBUTE'
                            CHECK (filter_source IN (
                                'ATTRIBUTE',    -- Attribute comparison
                                'DATE_RANGE',   -- Applies to a date/timestamp attribute
                                'CONTEXT',      -- Resolved from RLS context: CURRENT_TENANT | CURRENT_USER | CURRENT_SCOPE
                                'EXPRESSION'    -- Full JSON Logic tree
                            )),
    operator            TEXT        NOT NULL,
    -- Supported operators: eq | ne | lt | lte | gt | gte | in | not_in |
    --                      is_null | is_not_null | contains | starts_with | matches_regex
    static_value        JSONB,
    -- Typed value baked into the report. NULL when is_user_facing = TRUE.
    context_key         TEXT,
    -- For filter_source = CONTEXT: the context variable to resolve.
    -- e.g. 'CURRENT_TENANT' | 'CURRENT_USER' | 'CURRENT_SCHOOL'
    expression_dsl      JSONB,
    -- For filter_source = EXPRESSION: full JSON Logic tree. No raw SQL (LAW 9).
    is_user_facing      BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = filter is shown in the UI and the value is supplied by the user at runtime.
    -- FALSE = static filter baked permanently into the report.
    ui_label            TEXT,
    -- Label shown to the user in the filter panel. NULL for non-user-facing filters.
    ui_input_type       TEXT
                            CHECK (ui_input_type IN (
                                'TEXT','NUMBER','DATE','DATE_RANGE',
                                'DROPDOWN','MULTI_SELECT','BOOLEAN', NULL
                            )),
    -- Input widget type for user-facing filters
    is_required         BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = user must supply a value before the report can run
    sort_order          INT         NOT NULL DEFAULT 0,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_report_filters PRIMARY KEY (filter_id),
    CONSTRAINT fk_rf_report FOREIGN KEY (report_id)
        REFERENCES report_master(report_id) ON DELETE CASCADE,
    CONSTRAINT fk_rf_attribute FOREIGN KEY (attribute_id)
        REFERENCES attribute_master(attribute_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  report_filters                      IS 'Layer 10 / LAW 9: Structured WHERE-clause predicate definitions. No raw SQL stored. Static or user-facing runtime values resolved by the report engine.';
COMMENT ON COLUMN report_filters.tenant_id            IS 'NULL for filters belonging to SYSTEM template reports.';
COMMENT ON COLUMN report_filters.filter_group         IS 'Conditions in the same group share group_operator (AND|OR). Groups are combined with AND between them.';
COMMENT ON COLUMN report_filters.filter_source        IS 'Resolution strategy: ATTRIBUTE | DATE_RANGE | CONTEXT (RLS var) | EXPRESSION (JSON Logic).';
COMMENT ON COLUMN report_filters.operator             IS 'Comparison operator: eq | ne | lt | lte | gt | gte | in | not_in | is_null | is_not_null | contains | starts_with | matches_regex.';
COMMENT ON COLUMN report_filters.static_value         IS 'Typed JSONB value baked into the definition. NULL for user-facing filters where value is supplied at runtime.';
COMMENT ON COLUMN report_filters.context_key          IS 'For CONTEXT source: runtime variable name e.g. CURRENT_TENANT | CURRENT_USER | CURRENT_SCHOOL.';
COMMENT ON COLUMN report_filters.is_user_facing       IS 'TRUE = shown in the UI filter panel; user supplies value at runtime. FALSE = hidden, always applied automatically.';
COMMENT ON COLUMN report_filters.is_required          IS 'TRUE = report engine blocks execution until user provides a value for this filter.';

CREATE INDEX IF NOT EXISTS idx_rf_report
    ON report_filters(report_id, filter_group, sort_order);
CREATE INDEX IF NOT EXISTS idx_rf_user_facing
    ON report_filters(report_id, is_user_facing)
    WHERE is_user_facing = TRUE;


-- -----------------------------------------------------------------------------
-- report_role_access
-- Controls which roles may VIEW or EXPORT a specific report.
-- Implements field-level RBAC for the report engine.
-- A role entry with can_export = FALSE can see results on-screen but cannot
-- trigger any download or scheduled delivery.
-- LAW 4: The policy engine evaluates BEFORE the report executes.
-- LAW 9: Access decisions are data rows here — never if(role==) in code.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS report_role_access (
    tenant_id           UUID,
    -- NULL for system-template access rules (apply to all tenants)
    access_id           UUID        NOT NULL DEFAULT gen_random_uuid(),
    report_id           UUID        NOT NULL,
    role_code           TEXT        NOT NULL,
    -- Role code string matching role definitions in the application layer.
    -- e.g. 'SUPER_ADMIN' | 'SCHOOL_ADMIN' | 'TEACHER' | 'STUDENT' | 'PARENT'
    can_view            BOOLEAN     NOT NULL DEFAULT TRUE,
    -- TRUE = this role may execute the report and see results
    can_export          BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = this role may download the result in any of report_master.export_formats
    max_rows_override   INT,
    -- If set, overrides report_master.max_rows for this role (e.g. SUPER_ADMIN gets unlimited)
    row_filter_policy_id UUID,
    -- Optional FK → policy_master. When set, the engine applies this policy's
    -- conditions as an additional WHERE clause, restricting which rows this role sees.
    -- Enables row-level data visibility without separate report definitions (LAW 11).
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_report_role_access PRIMARY KEY (access_id),
    CONSTRAINT uq_report_role UNIQUE (report_id, role_code, tenant_id),
    CONSTRAINT fk_rra_report FOREIGN KEY (report_id)
        REFERENCES report_master(report_id) ON DELETE CASCADE,
    CONSTRAINT fk_rra_row_filter_policy FOREIGN KEY (tenant_id, row_filter_policy_id)
        REFERENCES policy_master(tenant_id, policy_id) ON DELETE SET NULL
);

COMMENT ON TABLE  report_role_access                         IS 'Layer 10 / LAW 9: RBAC control for report VIEW and EXPORT. Access decisions are data rows — no if(role==) in code. LAW 4: policy engine evaluates before execution.';
COMMENT ON COLUMN report_role_access.tenant_id               IS 'NULL for access rules on SYSTEM template reports that apply to all tenants.';
COMMENT ON COLUMN report_role_access.role_code               IS 'Role identifier matching application RBAC definitions: SUPER_ADMIN | SCHOOL_ADMIN | TEACHER | STUDENT | PARENT | custom.';
COMMENT ON COLUMN report_role_access.can_view                IS 'TRUE = role may see on-screen results.';
COMMENT ON COLUMN report_role_access.can_export              IS 'TRUE = role may download in allowed export_formats. Overrides is_exportable for this role.';
COMMENT ON COLUMN report_role_access.max_rows_override       IS 'Overrides report_master.max_rows for this specific role. NULL = use the report default.';
COMMENT ON COLUMN report_role_access.row_filter_policy_id    IS 'Optional policy_master FK whose conditions are appended as additional WHERE predicates for rows visible to this role.';

CREATE INDEX IF NOT EXISTS idx_rra_report_role
    ON report_role_access(report_id, role_code);
CREATE INDEX IF NOT EXISTS idx_rra_role
    ON report_role_access(role_code, can_view);


-- -----------------------------------------------------------------------------
-- report_execution_log
-- INSERT-ONLY audit record of every report execution event.
-- LAW 8: No UPDATE or DELETE — enforced by trigger + app_role GRANT.
-- LAW 9: applied_filters stores the exact runtime filter values used,
--        not the filter definitions (which live in report_filters).
--
-- Captured per execution:
--   who ran it      → actor_id + actor_role_code
--   when            → executed_at
--   what filters    → applied_filters (JSONB snapshot of runtime values)
--   how many rows   → row_count
--   was it exported → was_exported + export_format
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS report_execution_log (
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    execution_id        UUID        NOT NULL DEFAULT gen_random_uuid(),
    report_id           UUID        NOT NULL,
    actor_id            UUID,
    -- UUID of the user or service that triggered the execution.
    -- NULL for scheduled / system-initiated runs.
    actor_role_code     TEXT,
    -- Role the actor held at execution time (denormalised for forensic audit)
    execution_mode      TEXT        NOT NULL DEFAULT 'INTERACTIVE'
                            CHECK (execution_mode IN (
                                'INTERACTIVE',  -- Triggered by a user in the UI
                                'SCHEDULED',    -- Triggered by the scheduler
                                'API',          -- Triggered via REST API call
                                'SYSTEM'        -- Triggered by internal system logic
                            )),
    applied_filters     JSONB       NOT NULL DEFAULT '{}',
    -- SNAPSHOT of the actual runtime filter key-value pairs used in this run.
    -- Format: {"filter_id": "<uuid>", "attribute_code": "...", "value": <typed>}
    -- Stored even if no user filters were applied (empty object = no extra filters).
    -- This is the runtime value snapshot, NOT the static definition rows.
    row_count           BIGINT      NOT NULL DEFAULT 0,
    -- Number of rows returned by the query (after LIMIT enforcement)
    was_truncated       BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE when row_count == max_rows (result was capped by the engine safety limit)
    was_exported        BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE when the actor downloaded the result as a file
    export_format       TEXT
                            CHECK (export_format IN ('CSV','XLSX','PDF','JSON',NULL)),
    -- Export format used. NULL when was_exported = FALSE.
    execution_duration_ms BIGINT,
    -- Wall-clock time of the query execution in milliseconds
    query_hash          TEXT,
    -- SHA-256 of the final resolved query string (for deduplication & caching analytics)
    -- Never the actual query text — only its hash (LAW 9: no raw SQL stored)
    error_code          TEXT,
    -- Non-NULL when execution failed e.g. 'TIMEOUT' | 'PERMISSION_DENIED' | 'FILTER_MISSING'
    error_message       TEXT,
    -- Human-readable failure reason. NULL on success.
    executed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_report_execution_log PRIMARY KEY (tenant_id, execution_id),
    CONSTRAINT uq_report_execution_id UNIQUE (execution_id),
    CONSTRAINT fk_rel_report FOREIGN KEY (report_id)
        REFERENCES report_master(report_id) ON DELETE RESTRICT
);

COMMENT ON TABLE  report_execution_log                       IS 'Layer 10 / LAW 8: INSERT-ONLY execution audit for every report run. Captures who, when, what filters, row count, and export status. Immutable — trigger blocked + app_role INSERT-only.';
COMMENT ON COLUMN report_execution_log.actor_id             IS 'UUID of the triggering user/service. NULL for scheduled/system runs.';
COMMENT ON COLUMN report_execution_log.actor_role_code      IS 'Role held by actor at execution time. Denormalised for forensic audit (roles may change after the fact).';
COMMENT ON COLUMN report_execution_log.execution_mode       IS 'How the run was triggered: INTERACTIVE | SCHEDULED | API | SYSTEM.';
COMMENT ON COLUMN report_execution_log.applied_filters      IS 'Runtime filter snapshot: {"filter_id": ..., "attribute_code": ..., "value": ...}. Immutable after insert.';
COMMENT ON COLUMN report_execution_log.row_count            IS 'Number of result rows returned. Compared with max_rows to determine was_truncated.';
COMMENT ON COLUMN report_execution_log.was_truncated        IS 'TRUE when row_count reached max_rows — the engine enforced its safety LIMIT.';
COMMENT ON COLUMN report_execution_log.was_exported         IS 'TRUE when the actor downloaded the result as a file.';
COMMENT ON COLUMN report_execution_log.export_format        IS 'Download format used: CSV | XLSX | PDF | JSON. NULL when was_exported = FALSE.';
COMMENT ON COLUMN report_execution_log.execution_duration_ms IS 'Wall-clock query runtime in milliseconds. Used for performance analytics and SLA monitoring.';
COMMENT ON COLUMN report_execution_log.query_hash           IS 'SHA-256 of the resolved query. Never the query text itself (LAW 9). Used for caching analytics and deduplication.';
COMMENT ON COLUMN report_execution_log.error_code           IS 'Machine-readable failure code: TIMEOUT | PERMISSION_DENIED | FILTER_MISSING | INTERNAL_ERROR. NULL on success.';

-- INSERT-ONLY guard (LAW 8) — primary enforcement layer
CREATE OR REPLACE FUNCTION fn_report_execution_log_no_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION
        'report_execution_log is INSERT-ONLY (LAW 8). '
        'UPDATE and DELETE are forbidden. '
        'TG_OP=%, tenant_id=%, execution_id=%',
        TG_OP,
        COALESCE(OLD.tenant_id::TEXT, ''),
        COALESCE(OLD.execution_id::TEXT, '');
END;
$$;

CREATE TRIGGER trg_rel_no_update
    BEFORE UPDATE ON report_execution_log
    FOR EACH ROW EXECUTE FUNCTION fn_report_execution_log_no_mutation();

CREATE TRIGGER trg_rel_no_delete
    BEFORE DELETE ON report_execution_log
    FOR EACH ROW EXECUTE FUNCTION fn_report_execution_log_no_mutation();

COMMENT ON FUNCTION fn_report_execution_log_no_mutation
    IS 'BEFORE UPDATE/DELETE guard on report_execution_log. Raises exception immediately. Primary immutability enforcement (LAW 8).';

-- Role-level enforcement (secondary layer — defence in depth)
-- app_role is the FastAPI application server role (created in Layer 9).
GRANT INSERT, SELECT ON TABLE report_execution_log TO app_role;
REVOKE UPDATE, DELETE ON TABLE report_execution_log FROM app_role;

CREATE INDEX IF NOT EXISTS idx_rel_report
    ON report_execution_log(tenant_id, report_id, executed_at DESC);
CREATE INDEX IF NOT EXISTS idx_rel_actor
    ON report_execution_log(tenant_id, actor_id, executed_at DESC)
    WHERE actor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rel_executed
    ON report_execution_log(tenant_id, executed_at DESC);
CREATE INDEX IF NOT EXISTS idx_rel_exports
    ON report_execution_log(tenant_id, report_id, was_exported)
    WHERE was_exported = TRUE;
CREATE INDEX IF NOT EXISTS idx_rel_errors
    ON report_execution_log(tenant_id, error_code, executed_at DESC)
    WHERE error_code IS NOT NULL;


-- =============================================================================
-- ROW-LEVEL SECURITY (RLS) — Layer 10 tables
-- LAW 6 + RULES.md: RLS mandatory on all tenant-scoped tables.
-- Tenant context: SET LOCAL app.tenant_id = '<uuid>'; at transaction start.
-- LAW 7: tenant_id never supplied by the frontend.
--
-- SPECIAL HANDLING for nullable tenant_id tables (report_master, dimensions,
-- measures, filters, role_access):
--   The RLS policy grants access when:
--     a) tenant_id matches the session tenant (tenant-owned rows), OR
--     b) tenant_id IS NULL (SYSTEM template rows visible to everyone)
-- =============================================================================

-- Layer 10 — enable RLS
ALTER TABLE report_master        ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_dimensions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_measures      ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_filters       ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_role_access   ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_execution_log ENABLE ROW LEVEL SECURITY;

-- report_master: tenant rows + system templates (tenant_id IS NULL)
CREATE POLICY rls_report_master
    ON report_master
    USING (
        tenant_id IS NULL
        OR tenant_id = current_setting('app.tenant_id', TRUE)::UUID
    );

-- report_dimensions: same dual-visibility rule
CREATE POLICY rls_report_dimensions
    ON report_dimensions
    USING (
        tenant_id IS NULL
        OR tenant_id = current_setting('app.tenant_id', TRUE)::UUID
    );

-- report_measures
CREATE POLICY rls_report_measures
    ON report_measures
    USING (
        tenant_id IS NULL
        OR tenant_id = current_setting('app.tenant_id', TRUE)::UUID
    );

-- report_filters
CREATE POLICY rls_report_filters
    ON report_filters
    USING (
        tenant_id IS NULL
        OR tenant_id = current_setting('app.tenant_id', TRUE)::UUID
    );

-- report_role_access
CREATE POLICY rls_report_role_access
    ON report_role_access
    USING (
        tenant_id IS NULL
        OR tenant_id = current_setting('app.tenant_id', TRUE)::UUID
    );

-- report_execution_log: strictly tenant-scoped (tenant_id is NOT NULL here)
CREATE POLICY rls_report_execution_log
    ON report_execution_log
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);


-- =============================================================================
-- END OF SCHEMA: LAYER 10
-- =============================================================================
