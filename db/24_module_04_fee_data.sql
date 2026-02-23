-- =============================================================================
-- PRATHAMONE ACADEMY OS — MODULE 04: FEE MANAGEMENT
-- File: db/24_module_04_fee_data.sql
-- =============================================================================
-- Purpose : Seeds the FEE_DEMAND, FEE_LEDGER_ENTRY, and FEE_CONCESSION
--           entities, attributes, the FEE_COLLECTION workflow, policies,
--           report definitions, and the sidebar menu item.
--
-- CONSTITUTIONAL COMPLIANCE:
--   LAW 1  : All fee concepts are entity_master rows, NOT new tables.
--   LAW 2  : All fee attributes are attribute_master rows, NOT columns.
--   LAW 3  : Payment state changes ONLY via FEE_COLLECTION workflow.
--   LAW 4  : Policies evaluate BEFORE state transitions.
--   LAW 5  : Fee thresholds → system_settings, NOT hardcoded.
--   LAW 8  : FEE_LEDGER_ENTRY is INSERT-ONLY. Payments are additive events.
--   LAW 9  : Balances, totals, and summaries are computed at query time.
--   LAW 11 : Menu item inserted as data row, NOT as code.
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_tenant_id    UUID;
    v_actor_id     UUID := '00000000-0000-0000-0000-000000000099'::UUID;

    -- Entity IDs
    v_e_demand     UUID;
    v_e_ledger     UUID;
    v_e_concession UUID;

    -- Workflow
    v_wf_id        UUID;

    -- Menu
    v_menu_id      UUID;

BEGIN
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'MODULE 04 — FEE MANAGEMENT DATA SEED';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';

    -- ── Resolve tenant (can be called for any provisioned tenant) ────────
    SELECT tenant_id INTO v_tenant_id FROM tenants WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    IF v_tenant_id IS NULL THEN
        SELECT tenant_id INTO v_tenant_id FROM tenants WHERE is_active = TRUE ORDER BY created_at LIMIT 1;
    END IF;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'No active tenant found. Run Phase A provisioning first.';
    END IF;

    -- Standard Kernel Requirement: Set the GUC for RLS and Kernel Functions
    EXECUTE format('SET app.tenant_id = %L', v_tenant_id);
    RAISE NOTICE 'Tenant context set to: %', v_tenant_id;

    SET app.tenant_id TO DEFAULT; -- Cleared before setting per-tenant
    PERFORM set_config('app.tenant_id', v_tenant_id::TEXT, TRUE);

    RAISE NOTICE 'Tenant: %', v_tenant_id;

    -- =========================================================================
    -- SECTION 1: ENTITY REGISTRATION (LAW 1)
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '── Section 1: Entity Registration ──────────────────────────';

    INSERT INTO entity_master (tenant_id, entity_type, entity_code, display_name, description)
    VALUES
        (v_tenant_id, 'FINANCIAL', 'FEE_DEMAND',      'Fee Demand',        'A fee obligation raised for a student (admission, tuition, transport, exam)'),
        (v_tenant_id, 'FINANCIAL', 'FEE_LEDGER_ENTRY','Fee Ledger Entry',  'An additive payment event against a fee demand. INSERT-ONLY per LAW 8.'),
        (v_tenant_id, 'FINANCIAL', 'FEE_CONCESSION',  'Fee Concession',    'An authorised waiver or discount applied to a fee demand')
    ON CONFLICT (tenant_id, entity_code) DO NOTHING;

    SELECT entity_id INTO v_e_demand     FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'FEE_DEMAND';
    SELECT entity_id INTO v_e_ledger     FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'FEE_LEDGER_ENTRY';
    SELECT entity_id INTO v_e_concession FROM entity_master WHERE tenant_id = v_tenant_id AND entity_code = 'FEE_CONCESSION';

    RAISE NOTICE '  ✓ 3 financial entity types registered.';

    -- =========================================================================
    -- SECTION 2: ATTRIBUTE REGISTRATION (LAW 2)
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '── Section 2: Attribute Registration ───────────────────────';

    -- ── FEE_DEMAND attributes ─────────────────────────────────────────────
    INSERT INTO attribute_master
        (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_e_demand, 'student_record_id', 'Student Record ID',   'uuid',    TRUE,  TRUE,  10),
        (v_tenant_id, v_e_demand, 'batch_code',         'Batch Code',          'text',    TRUE,  TRUE,  20),
        (v_tenant_id, v_e_demand, 'fee_type',           'Fee Type',            'text',    TRUE,  TRUE,  30),
        -- fee_type allowed values: ADMISSION | TUITION | TRANSPORT | EXAM | LIBRARY | MISCELLANEOUS
        (v_tenant_id, v_e_demand, 'academic_year',      'Academic Year',       'text',    TRUE,  TRUE,  40),
        (v_tenant_id, v_e_demand, 'period_label',       'Period / Installment','text',    FALSE, FALSE, 50),
        -- period_label: "Q1 2025", "April 2025", "Annual 2025-26" etc.
        (v_tenant_id, v_e_demand, 'amount_demanded',    'Amount Demanded',     'numeric', TRUE,  FALSE, 60),
        (v_tenant_id, v_e_demand, 'due_date',           'Due Date',            'date',    TRUE,  FALSE, 70),
        (v_tenant_id, v_e_demand, 'is_late_fee_applied','Late Fee Applied',    'boolean', FALSE, FALSE, 80),
        (v_tenant_id, v_e_demand, 'late_fee_amount',    'Late Fee Amount',     'numeric', FALSE, FALSE, 90),
        (v_tenant_id, v_e_demand, 'notes',              'Notes',               'text',    FALSE, FALSE, 100)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    -- ── FEE_LEDGER_ENTRY attributes (INSERT-ONLY per LAW 8) ──────────────
    -- These entries are NEVER updated — each payment is a new row.
    INSERT INTO attribute_master
        (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_e_ledger, 'demand_record_id',  'Demand Record ID',    'uuid',    TRUE,  TRUE,  10),
        (v_tenant_id, v_e_ledger, 'entry_type',        'Entry Type',          'text',    TRUE,  TRUE,  20),
        -- entry_type: PAYMENT | REFUND | ADJUSTMENT | CONCESSION_APPLIED
        (v_tenant_id, v_e_ledger, 'amount',            'Amount',              'numeric', TRUE,  FALSE, 30),
        (v_tenant_id, v_e_ledger, 'payment_mode',      'Payment Mode',        'text',    FALSE, FALSE, 40),
        -- payment_mode: CASH | UPI | NEFT | RTGS | CHEQUE | DD | ONLINE_GATEWAY
        (v_tenant_id, v_e_ledger, 'transaction_ref',   'Transaction Reference','text',   FALSE, FALSE, 50),
        (v_tenant_id, v_e_ledger, 'payment_date',      'Payment Date',        'date',    TRUE,  FALSE, 60),
        (v_tenant_id, v_e_ledger, 'received_by',       'Received By (actor)', 'uuid',    FALSE, FALSE, 70),
        (v_tenant_id, v_e_ledger, 'receipt_sequence',  'Receipt Sequence No', 'text',    FALSE, FALSE, 80),
        (v_tenant_id, v_e_ledger, 'remarks',           'Remarks',             'text',    FALSE, FALSE, 90)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    -- ── FEE_CONCESSION attributes ─────────────────────────────────────────
    INSERT INTO attribute_master
        (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
    VALUES
        (v_tenant_id, v_e_concession, 'demand_record_id',   'Demand Record ID',   'uuid',    TRUE,  TRUE,  10),
        (v_tenant_id, v_e_concession, 'concession_type',    'Concession Type',    'text',    TRUE,  TRUE,  20),
        -- concession_type: SC_ST | OBC | STAFF_WARD | SIBLING | MERIT | NEED_BASED | MANAGEMENT
        (v_tenant_id, v_e_concession, 'concession_pct',     'Concession %',       'numeric', TRUE,  FALSE, 30),
        (v_tenant_id, v_e_concession, 'concession_amount',  'Concession Amount',  'numeric', TRUE,  FALSE, 40),
        (v_tenant_id, v_e_concession, 'approved_by',        'Approved By',        'uuid',    TRUE,  FALSE, 50),
        (v_tenant_id, v_e_concession, 'approval_reason',    'Approval Reason',    'text',    FALSE, FALSE, 60),
        (v_tenant_id, v_e_concession, 'valid_for_period',   'Valid For Period',   'text',    FALSE, FALSE, 70)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    RAISE NOTICE '  ✓ Attributes: FEE_DEMAND (10), FEE_LEDGER_ENTRY (9), FEE_CONCESSION (7).';

    -- =========================================================================
    -- SECTION 3: FEE_COLLECTION WORKFLOW (LAW 3)
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '── Section 3: FEE_COLLECTION Workflow ──────────────────────';

    INSERT INTO workflow_master (tenant_id, workflow_code, display_name, entity_id, initial_state, is_active)
    VALUES (v_tenant_id, 'FEE_COLLECTION', 'Fee Collection', v_e_demand, 'DEMAND_RAISED', TRUE)
    ON CONFLICT (tenant_id, workflow_code)
    DO UPDATE SET is_active = TRUE, display_name = EXCLUDED.display_name
    RETURNING workflow_id INTO v_wf_id;

    IF v_wf_id IS NULL THEN
        SELECT workflow_id INTO v_wf_id
        FROM workflow_master
        WHERE tenant_id = v_tenant_id AND workflow_code = 'FEE_COLLECTION';
    END IF;

    -- States
    INSERT INTO workflow_states (tenant_id, workflow_id, state_code, display_label, state_type, ui_color)
    VALUES
        (v_tenant_id, v_wf_id, 'DEMAND_RAISED',    'Demand Raised',     'initial',      '#6366f1'),
        (v_tenant_id, v_wf_id, 'PARTIALLY_PAID',   'Partially Paid',    'intermediate', '#f59e0b'),
        (v_tenant_id, v_wf_id, 'PAID',             'Paid in Full',      'terminal',     '#10b981'),
        (v_tenant_id, v_wf_id, 'OVERDUE',          'Overdue',           'intermediate', '#ef4444'),
        (v_tenant_id, v_wf_id, 'WAIVED',           'Waived / Written Off','terminal',   '#8b5cf6'),
        (v_tenant_id, v_wf_id, 'REFUND_INITIATED', 'Refund Initiated',  'intermediate', '#0ea5e9'),
        (v_tenant_id, v_wf_id, 'REFUNDED',         'Refunded',          'terminal',     '#06b6d4')
    ON CONFLICT (tenant_id, workflow_id, state_code) DO NOTHING;

    -- Transitions
    INSERT INTO workflow_transitions (tenant_id, workflow_id, from_state, to_state, trigger_event, display_label, actor_roles)
    VALUES
        (v_tenant_id, v_wf_id, NULL,               'DEMAND_RAISED',  'START',            'Initialise',             ARRAY['SYSTEM','FINANCE_CLERK']),
        -- Normal payment path
        (v_tenant_id, v_wf_id, 'DEMAND_RAISED',   'PARTIALLY_PAID',  'PARTIAL_PAYMENT',  'Record Partial Payment', ARRAY['FINANCE_CLERK','TENANT_ADMIN']),
        (v_tenant_id, v_wf_id, 'DEMAND_RAISED',   'PAID',            'FULL_PAYMENT',     'Record Full Payment',    ARRAY['FINANCE_CLERK','TENANT_ADMIN']),
        (v_tenant_id, v_wf_id, 'PARTIALLY_PAID',  'PARTIALLY_PAID',  'ADDITIONAL_PAYMENT','Add More Payment',      ARRAY['FINANCE_CLERK','TENANT_ADMIN']),
        (v_tenant_id, v_wf_id, 'PARTIALLY_PAID',  'PAID',            'BALANCE_CLEARED',  'Clear Balance',          ARRAY['FINANCE_CLERK','TENANT_ADMIN']),

        -- Overdue path (triggered by scheduled job or FINANCE_CLERK after due_date)
        (v_tenant_id, v_wf_id, 'DEMAND_RAISED',   'OVERDUE',         'MARK_OVERDUE',     'Mark as Overdue',        ARRAY['FINANCE_CLERK','TENANT_ADMIN']),
        (v_tenant_id, v_wf_id, 'PARTIALLY_PAID',  'OVERDUE',         'MARK_OVERDUE',     'Mark as Overdue',        ARRAY['FINANCE_CLERK','TENANT_ADMIN']),
        (v_tenant_id, v_wf_id, 'OVERDUE',         'PAID',            'LATE_PAYMENT',     'Record Late Payment',    ARRAY['FINANCE_CLERK','TENANT_ADMIN']),
        (v_tenant_id, v_wf_id, 'OVERDUE',         'PARTIALLY_PAID',  'PARTIAL_LATE_PAYMENT','Partial Late Payment', ARRAY['FINANCE_CLERK','TENANT_ADMIN']),

        -- Waiver path (TENANT_ADMIN only — LAW 4 policy gates this)
        (v_tenant_id, v_wf_id, 'DEMAND_RAISED',   'WAIVED',          'AUTHORISE_WAIVER', 'Authorise Full Waiver',  ARRAY['TENANT_ADMIN']),
        (v_tenant_id, v_wf_id, 'PARTIALLY_PAID',  'WAIVED',          'WAIVE_BALANCE',    'Waive Outstanding Balance',ARRAY['TENANT_ADMIN']),
        (v_tenant_id, v_wf_id, 'OVERDUE',         'WAIVED',          'WRITE_OFF',        'Write Off Debt',         ARRAY['TENANT_ADMIN']),

        -- Refund path
        (v_tenant_id, v_wf_id, 'PAID',            'REFUND_INITIATED','INITIATE_REFUND',  'Initiate Refund',        ARRAY['TENANT_ADMIN']),
        (v_tenant_id, v_wf_id, 'REFUND_INITIATED','REFUNDED',        'COMPLETE_REFUND',  'Mark Refund Complete',   ARRAY['FINANCE_CLERK','TENANT_ADMIN'])
    ON CONFLICT DO NOTHING;

    RAISE NOTICE '  ✓ FEE_COLLECTION workflow: 7 states, 13 transitions.';

    -- =========================================================================
    -- SECTION 4: POLICY CONFIGURATION (LAW 4)
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '── Section 4: Policy Configuration ─────────────────────────';

    -- Policy: Late Fee Penalty
    -- Evaluated at: DEMAND_RAISED → OVERDUE transition
    INSERT INTO policy_master (tenant_id, policy_code, display_name, entity_id, rule_definition, is_active, evaluation_order)
    VALUES (v_tenant_id, 'LATE_FEE_PENALTY', 'Late Fee Penalty Calculation', v_e_demand, '{}'::JSONB, TRUE, 50)
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    INSERT INTO policy_conditions (tenant_id, policy_id, condition_code, operator, subject_type, rule_definition, description)
    SELECT
        v_tenant_id,
        pm.policy_id,
        'APPLY_LATE_PENALTY',
        'EXECUTE',
        'CUSTOM_DSL',
        '{
            "action": "CALCULATE_AND_APPEND",
            "trigger_when": "due_date_exceeded",
            "penalty_pct_setting_key": "financial.late_fee_penalty_pct",
            "capped_at_pct": 25,
            "applies_to_entry_type": "LATE_FEE",
            "audit_reason": "Late fee penalty calculated per LAW 4 policy"
        }'::JSONB,
        'Calculates late fee as % of outstanding amount, capped at 25% total'
    FROM policy_master pm
    WHERE pm.tenant_id = v_tenant_id AND pm.policy_code = 'LATE_FEE_PENALTY'
    ON CONFLICT (tenant_id, policy_id, condition_code) DO NOTHING;

    -- Policy: Concession Authority Gate
    -- > 20% concession requires TENANT_ADMIN; FINANCE_CLERK can grant up to 20%
    INSERT INTO policy_master (tenant_id, policy_code, display_name, entity_id, rule_definition, is_active, evaluation_order)
    VALUES (v_tenant_id, 'CONCESSION_AUTHORITY', 'Concession Authorisation Gate', v_e_concession, '{}'::JSONB, TRUE, 60)
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    INSERT INTO policy_conditions (tenant_id, policy_id, condition_code, operator, subject_type, rule_definition, description)
    SELECT
        v_tenant_id,
        pm.policy_id,
        'CONCESSION_ROLE_GATE',
        'EXECUTE',
        'CUSTOM_DSL',
        '{
            "operator": "ROLE_REQUIRED_IF",
            "condition": {"gt": [{"var": "concession_pct"}, 20]},
            "required_role": "TENANT_ADMIN",
            "denial_message": "Concessions above 20% require TENANT_ADMIN authorisation"
        }'::JSONB,
        'FINANCE_CLERK can grant up to 20% concession; above requires TENANT_ADMIN'
    FROM policy_master pm
    WHERE pm.tenant_id = v_tenant_id AND pm.policy_code = 'CONCESSION_AUTHORITY'
    ON CONFLICT (tenant_id, policy_id, condition_code) DO NOTHING;

    RAISE NOTICE '  ✓ 2 policies: LATE_FEE_PENALTY, CONCESSION_AUTHORITY.';

    -- =========================================================================
    -- SECTION 5: SYSTEM SETTINGS (LAW 5)
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '── Section 5: System Settings ───────────────────────────────';

    INSERT INTO system_settings
        (tenant_id, setting_category, setting_key, setting_value, scope_level, description)
    VALUES
        (v_tenant_id, 'FINANCIAL', 'financial.late_fee_penalty_pct',    '5',                                          'TENANT', 'Late fee penalty %: applied after due_date'),
        (v_tenant_id, 'FINANCIAL', 'financial.late_fee_grace_days',     '3',                                          'TENANT', 'Grace period (days) before late fee kicks in'),
        (v_tenant_id, 'FINANCIAL', 'financial.partial_payment_enabled', 'true',                                       'TENANT', 'Allow partial payment (PARTIALLY_PAID state)'),
        (v_tenant_id, 'FINANCIAL', 'financial.min_partial_pct',         '25',                                         'TENANT', 'Minimum % of demand required for partial payment'),
        (v_tenant_id, 'FINANCIAL', 'financial.payment_modes_allowed',   '["CASH","UPI","NEFT","RTGS","CHEQUE","DD","ONLINE_GATEWAY"]', 'TENANT', 'Allowed payment modes'),
        (v_tenant_id, 'FINANCIAL', 'financial.receipt_prefix',          '"RCT"',                                      'TENANT', 'Receipt number prefix e.g. RCT-2025-001'),
        (v_tenant_id, 'FINANCIAL', 'financial.concession_max_pct_clerk','20',                                         'TENANT', 'Max concession % a FINANCE_CLERK can grant'),
        (v_tenant_id, 'FINANCIAL', 'financial.currency',               '"INR"',                                       'TENANT', 'Currency for all financial amounts'),
        -- LAW 4: Policy thresholds for fees.py — never hardcoded in Python (LAW 4 compliance).
        -- These keys are queried at request time by the API to enforce policy gates.
        (v_tenant_id, 'FINANCIAL', 'CONCESSION_AUTHORITY_MAX_PCT',    '20',                                          'TENANT', 'LAW 4: Max concession % below which FINANCE_CLERK is self-authorised. Above this requires CONCESSION_AUTHORITY_ROLES.'),
        (v_tenant_id, 'FINANCIAL', 'CONCESSION_AUTHORITY_ROLES',       'TENANT_ADMIN',                               'TENANT', 'LAW 4: Comma-separated roles allowed to grant concessions above CONCESSION_AUTHORITY_MAX_PCT.'),
        (v_tenant_id, 'FINANCIAL', 'REFUND_AUTHORITY_ROLES',           'TENANT_ADMIN',                               'TENANT', 'LAW 4: Comma-separated roles allowed to initiate fee refunds.')
    ON CONFLICT (tenant_id, setting_key, scope_level, scope_ref_id) DO NOTHING;

    RAISE NOTICE '  ✓ 11 financial system settings seeded (incl. 3 new LAW 4 policy keys).';

    -- =========================================================================
    -- SECTION 6: REPORT DEFINITIONS (LAW 9)
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '── Section 6: Report Definitions ────────────────────────────';

    INSERT INTO report_master
        (tenant_id, report_code, display_name, report_category, primary_entity_id, report_query_type)
    VALUES
        (v_tenant_id, 'fees.collection_summary',   'Fee Collection Summary',       'FINANCIAL', v_e_demand,  'AGGREGATE'),
        (v_tenant_id, 'fees.defaulters_list',       'Fee Defaulters List',          'FINANCIAL', v_e_demand,  'DETAIL'),
        (v_tenant_id, 'fees.class_outstanding',     'Class-wise Outstanding Fees',  'FINANCIAL', v_e_demand,  'AGGREGATE'),
        (v_tenant_id, 'fees.receipts_by_date',      'Receipt Register (Date Range)','FINANCIAL', v_e_ledger,  'DETAIL'),
        (v_tenant_id, 'fees.concession_registry',   'Concession Registry',          'FINANCIAL', v_e_concession, 'DETAIL'),
        (v_tenant_id, 'fees.demand_vs_collection',  'Demand vs Collection Chart',   'FINANCIAL', v_e_demand,  'AGGREGATE')
    ON CONFLICT (tenant_id, report_code) DO NOTHING;

    RAISE NOTICE '  ✓ 6 financial report definitions seeded.';

    -- =========================================================================
    -- SECTION 7: SIDEBAR MENU ITEM (LAW 11)
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '── Section 7: Menu Registration ─────────────────────────────';

    SELECT menu_id INTO v_menu_id
    FROM menu_master
    WHERE menu_code = 'SIDEBAR_NAV'
    LIMIT 1;

    IF v_menu_id IS NOT NULL THEN
        INSERT INTO menu_items
            (tenant_id, menu_id, label, icon_name, route_path, action_type, action_target, required_roles, sort_order)
        VALUES
            -- Main Fee Ledger page
            (v_tenant_id, v_menu_id, 'Fee Ledger',     'CreditCard',  '/fees/ledger',    'ROUTE',  'FEE_LEDGER',               ARRAY['ADMIN','TENANT_ADMIN','FINANCE_CLERK'],                     35),
            -- Quick report links
            (v_tenant_id, v_menu_id, 'Defaulters',     'AlertCircle', '/reports/fees/defaulters', 'REPORT', 'fees.defaulters_list', ARRAY['ADMIN','TENANT_ADMIN','FINANCE_CLERK'],            36),
            (v_tenant_id, v_menu_id, 'Collection Report','BarChart3', '/reports/fees/summary',    'REPORT', 'fees.collection_summary', ARRAY['ADMIN','TENANT_ADMIN','FINANCE_CLERK'],          37)
        ON CONFLICT (tenant_id, menu_id, label) 
        DO UPDATE SET 
            required_roles = EXCLUDED.required_roles,
            icon_name = EXCLUDED.icon_name,
            route_path = EXCLUDED.route_path;
        RAISE NOTICE '  ✓ 3 menu items inserted into SIDEBAR_NAV.';
    ELSE
        RAISE WARNING '  ⚠ SIDEBAR_NAV menu not found — menu items skipped.';
        RAISE WARNING '  Run db/09_module_03_menus_data.sql first.';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '████████████████████████████████████████████████████████████';
    RAISE NOTICE '  MODULE 04 — FEE MANAGEMENT SEED COMPLETE                  ';
    RAISE NOTICE '  Entities: 3 | Attributes: 26 | Workflow: 7 states          ';
    RAISE NOTICE '  Transitions: 13 | Policies: 2 | Settings: 8 | Reports: 6   ';
    RAISE NOTICE '  Menu items: 3 (Fee Ledger, Defaulters, Collection Report)  ';
    RAISE NOTICE '████████████████████████████████████████████████████████████';

END $$;

COMMIT;

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================
/*
-- [FVQ-1] Confirm 3 fee entity types registered
SET app.tenant_id = '<your-tenant-id>';
SELECT entity_code, entity_type, display_name
FROM entity_master
WHERE tenant_id = current_setting('app.tenant_id',TRUE)::UUID
  AND entity_code IN ('FEE_DEMAND','FEE_LEDGER_ENTRY','FEE_CONCESSION')
ORDER BY entity_code;

-- [FVQ-2] Confirm FEE_COLLECTION workflow is active
SET app.tenant_id = '<your-tenant-id>';
SELECT workflow_code, display_name, initial_state, is_active
FROM workflow_master
WHERE tenant_id = current_setting('app.tenant_id',TRUE)::UUID
  AND workflow_code = 'FEE_COLLECTION';
-- Expected: is_active = TRUE

-- [FVQ-3] Confirm all 13 workflow transitions
SET app.tenant_id = '<your-tenant-id>';
SELECT from_state, trigger_event, to_state, actor_roles
FROM workflow_transitions wt
JOIN workflow_master wm ON wm.workflow_id = wt.workflow_id
WHERE wm.tenant_id = current_setting('app.tenant_id',TRUE)::UUID
  AND wm.workflow_code = 'FEE_COLLECTION'
ORDER BY from_state, to_state;

-- [FVQ-4] Confirm reports are seeded
SET app.tenant_id = '<your-tenant-id>';
SELECT report_code, display_name, report_query_type
FROM report_master
WHERE tenant_id = current_setting('app.tenant_id',TRUE)::UUID
  AND report_code LIKE 'fees.%'
ORDER BY report_code;
-- Expected: 6 rows

-- [FVQ-5] Simulate additive payment (non-destructive check)
-- After recording a payment via the API, this should return 1 row per payment:
SET app.tenant_id = '<your-tenant-id>';
SELECT er.record_id,
       MAX(CASE WHEN eav.attribute_code = 'entry_type'  THEN eav.value_text END) AS entry_type,
       MAX(CASE WHEN eav.attribute_code = 'amount'      THEN eav.value_numeric END) AS amount,
       MAX(CASE WHEN eav.attribute_code = 'payment_date' THEN eav.value_text END) AS payment_date
FROM entity_records er
JOIN entity_master em ON em.entity_id = er.entity_id AND em.tenant_id = er.tenant_id
JOIN entity_attribute_values eav ON eav.record_id = er.record_id AND eav.tenant_id = er.tenant_id
WHERE em.entity_code = 'FEE_LEDGER_ENTRY'
  AND er.tenant_id = current_setting('app.tenant_id',TRUE)::UUID
GROUP BY er.record_id ORDER BY er.record_id;
*/
