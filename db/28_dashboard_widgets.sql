-- =============================================================================
-- 28_dashboard_widgets.sql
-- Metadata for dashboard intelligence widgets (KPIs)
-- LAW 11: Configuration for widgets is data.
-- =============================================================================

DO $$
DECLARE
    v_tid UUID := '00000000-0000-0000-0000-000000000001';
    v_e_student UUID;
    v_e_fee_demand UUID;
    v_e_app UUID;
    v_e_exam UUID;
BEGIN
    -- 1. Create widget metadata table if not exists (LAW 11)
    CREATE TABLE IF NOT EXISTS dashboard_widgets (
        tenant_id     UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
        widget_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        widget_code   TEXT NOT NULL,
        display_name  TEXT NOT NULL,
        metric_type   TEXT NOT NULL, -- COUNT | SUM | AVG | RATIO
        icon_name     TEXT DEFAULT 'Activity',
        color_scheme  TEXT DEFAULT 'gold', -- gold | teal | rose | blue
        query_logic   JSONB NOT NULL,    -- Detailed logic for the engine to execute
        sort_order    INT DEFAULT 0,
        is_active     BOOLEAN DEFAULT TRUE,
        created_at    TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE(tenant_id, widget_code)
    );

    -- Enable RLS
    ALTER TABLE dashboard_widgets ENABLE ROW LEVEL SECURITY;
    
    DROP POLICY IF EXISTS rls_dashboard_widgets ON dashboard_widgets;
    CREATE POLICY rls_dashboard_widgets ON dashboard_widgets
        USING (tenant_id = (current_setting('app.tenant_id', true))::UUID);

    -- 2. Resolve Entity IDs
    SELECT entity_id INTO v_e_student    FROM entity_master WHERE tenant_id = v_tid AND entity_code = 'STUDENT';
    SELECT entity_id INTO v_e_fee_demand FROM entity_master WHERE tenant_id = v_tid AND entity_code = 'FEE_DEMAND';
    SELECT entity_id INTO v_e_app        FROM entity_master WHERE tenant_id = v_tid AND entity_code = 'STUDENT_APPLICATION';
    SELECT entity_id INTO v_e_exam       FROM entity_master WHERE tenant_id = v_tid AND entity_code = 'EXAM_ATTEMPT';

    -- 3. Seed Core Intelligence Widgets
    INSERT INTO dashboard_widgets (tenant_id, widget_code, display_name, metric_type, icon_name, color_scheme, sort_order, query_logic)
    VALUES
        (v_tid, 'total_students', 'Enrolled Students', 'COUNT', 'Users', 'teal', 1, 
         '{"entity_code": "STUDENT", "filter": {}}'),
        
        (v_tid, 'fee_collection', 'Total Collections', 'SUM', 'CreditCard', 'gold', 2, 
         '{"entity_code": "FEE_LEDGER_ENTRY", "attribute_code": "amount", "filter": {"entry_type": "PAYMENT_RECEIVED"}}'),
        
        (v_tid, 'pending_admissions', 'Pending Admissions', 'COUNT', 'FileText', 'rose', 3, 
         '{"entity_code": "STUDENT_APPLICATION", "filter": {"workflow_state": {"not_in": ["ENROLLED", "REJECTED"]}}}'),
        
        (v_tid, 'avg_performance', 'Academic Average', 'AVG', 'Trophy', 'blue', 4, 
         '{"entity_code": "EXAM_ATTEMPT", "attribute_code": "total_marks_obtained", "filter": {}}')
    ON CONFLICT (tenant_id, widget_code) DO UPDATE SET
        display_name = EXCLUDED.display_name,
        icon_name = EXCLUDED.icon_name,
        color_scheme = EXCLUDED.color_scheme,
        query_logic = EXCLUDED.query_logic;

    RAISE NOTICE 'Dashboard Intelligence Widgets seeded for tenant %', v_tid;
END $$;
