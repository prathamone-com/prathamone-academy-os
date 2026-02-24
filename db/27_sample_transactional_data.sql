-- =============================================================================
-- 27_sample_transactional_data.sql
-- Creates actual test records across all modules so every endpoint is testable:
--   • 5 FEE_DEMAND records (mix of PAID, partial, OVERDUE)
--   • 3 FEE_LEDGER_ENTRY payments (partial / full pay scenarios)
--   • 5 EXAM_ATTEMPT records
--   • 5 STUDENT records
-- =============================================================================
-- LAW 2 : All data via create_entity_record() kernel function
-- LAW 3 : Workflow transitions via execute_workflow_transition()
-- LAW 7 : tenant_id only via GUC — never from client
-- =============================================================================

DO $$
DECLARE
  v_tid   UUID := '00000000-0000-0000-0000-000000000001';
  v_actor UUID := '00000000-0000-0000-0000-000000000099';

  -- Student application record IDs
  v_apps  UUID[];

  -- Created record IDs
  v_demand_id   UUID;
  v_student_id  UUID;
  v_exam_id     UUID;
  v_attempt_id  UUID;
  v_entry_id    UUID;

  v_i  INTEGER;
  v_names TEXT[] := ARRAY['Arjun Mehta','Priya Sharma','Rohan Nair','Meera Iyer','Tej Malhotra'];
  v_fees  NUMERIC[] := ARRAY[45000, 52000, 48000, 45000, 50000];
  v_paid  NUMERIC[] := ARRAY[45000, 26000, 0, 45000, 15000];
  v_dob   TEXT[] := ARRAY['2012-03-15','2013-07-22','2011-11-08','2012-05-30','2012-09-14'];
  v_class TEXT[] := ARRAY['8','9','7','8','9'];

BEGIN
  PERFORM set_config('app.tenant_id', v_tid::TEXT, TRUE);

  -- ── Cleanup previous run attempts ──────────────────────────────────────────
  DELETE FROM entity_attribute_values WHERE tenant_id = v_tid AND record_id IN (
    SELECT record_id FROM entity_records WHERE entity_id IN (
      SELECT entity_id FROM entity_master WHERE entity_code IN ('STUDENT','FEE_DEMAND','FEE_LEDGER_ENTRY','EXAM','EXAM_ATTEMPT')
    )
  );
  DELETE FROM entity_records WHERE tenant_id = v_tid AND entity_id IN (
    SELECT entity_id FROM entity_master WHERE entity_code IN ('STUDENT','FEE_DEMAND','FEE_LEDGER_ENTRY','EXAM','EXAM_ATTEMPT')
  );
  DELETE FROM workflow_state_log WHERE tenant_id = v_tid AND record_id NOT IN (
    SELECT record_id FROM entity_records WHERE tenant_id = v_tid
  );

  -- ── Fetch the STUDENT_APPLICATION record IDs ───────────────────────────
  SELECT ARRAY_AGG(er.record_id ORDER BY er.created_at ASC)
  INTO v_apps
  FROM entity_records er
  JOIN entity_master em ON em.entity_id=er.entity_id AND em.tenant_id=er.tenant_id
  WHERE em.entity_code='STUDENT_APPLICATION' AND er.tenant_id=v_tid
  LIMIT 5;

  RAISE NOTICE '════════ TRANSACTIONAL SAMPLE DATA SEED ════════';

  -- ════════════════════════════════════════════════════════════════════════
  -- SECTION 1: STUDENT RECORDS
  -- ════════════════════════════════════════════════════════════════════════
  FOR v_i IN 1..5 LOOP
    v_student_id := create_entity_record(
      'STUDENT',
      json_build_array(
        json_build_object('attribute_code','full_name',       'value', v_names[v_i]),
        json_build_object('attribute_code','date_of_birth',   'value', v_dob[v_i]),
        json_build_object('attribute_code','class_enrolled',  'value', v_class[v_i]),
        json_build_object('attribute_code','admission_number','value', FORMAT('ADM-2025-%s', LPAD(v_i::TEXT,3,'0'))),
        json_build_object('attribute_code','application_ref', 'value', COALESCE(v_apps[v_i]::TEXT, 'N/A'))
      )::JSONB,
      v_actor
    );
    RAISE NOTICE 'STUDENT [%]: % → %', v_i, v_names[v_i], v_student_id;
  END LOOP;

  -- ════════════════════════════════════════════════════════════════════════
  -- SECTION 2: FEE_DEMAND RECORDS + PAYMENTS
  -- ════════════════════════════════════════════════════════════════════════
  FOR v_i IN 1..5 LOOP
    -- Create demand
    v_demand_id := create_entity_record(
      'FEE_DEMAND',
      json_build_array(
        json_build_object('attribute_code','student_name',  'value', v_names[v_i]),
        json_build_object('attribute_code','fee_type',      'value', 'TUITION'),
        json_build_object('attribute_code','amount_due',    'value', v_fees[v_i]),
        json_build_object('attribute_code','academic_year', 'value', '2025-26'),
        json_build_object('attribute_code','due_date',      'value', '2025-06-30'),
        json_build_object('attribute_code','description',   'value', FORMAT('Annual Tuition Fee — %s', v_names[v_i]))
      )::JSONB,
      v_actor
    );
    RAISE NOTICE 'FEE_DEMAND [%]: Rs.% for % → %', v_i, v_fees[v_i], v_names[v_i], v_demand_id;

    -- Advance to DEMAND_RAISED state (the initial state)
    BEGIN
      PERFORM execute_workflow_transition(
        'FEE_DEMAND', v_demand_id, 'DEMAND_RAISED', v_actor, 'Demand initialized.'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Transition DEMAND_RAISED failed: %', SQLERRM;
    END;

    -- Record payment if any
    IF v_paid[v_i] > 0 THEN
      v_entry_id := create_entity_record(
        'FEE_LEDGER_ENTRY',
        json_build_array(
          json_build_object('attribute_code','demand_record_id','value', v_demand_id::TEXT),
          json_build_object('attribute_code','entry_type',      'value', 'PAYMENT_RECEIVED'),
          json_build_object('attribute_code','amount',          'value', v_paid[v_i]),
          json_build_object('attribute_code','payment_date',    'value', '2025-07-05'),
          json_build_object('attribute_code','receipt_number',  'value', FORMAT('RCP-2025-%s', LPAD(v_i::TEXT,4,'0'))),
          json_build_object('attribute_code','payment_mode',    'value', CASE v_i WHEN 1 THEN 'ONLINE' WHEN 2 THEN 'CHEQUE' ELSE 'CASH' END),
          json_build_object('attribute_code','remarks',         'value', 'Sample payment')
        )::JSONB,
        v_actor
      );
      RAISE NOTICE '  ↳ PAYMENT Rs.% recorded → %', v_paid[v_i], v_entry_id;

      -- Transition logic
      IF v_paid[v_i] >= v_fees[v_i] THEN
        BEGIN
          PERFORM execute_workflow_transition(
            'FEE_DEMAND', v_demand_id, 'PAID', v_actor, 'Fully paid.'
          );
          RAISE NOTICE '  ↳ State → PAID';
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE '  ↳ PAID transition failed: %', SQLERRM;
        END;
      ELSE
        BEGIN
          PERFORM execute_workflow_transition(
            'FEE_DEMAND', v_demand_id, 'PARTIALLY_PAID', v_actor, 'Recent partial payment.'
          );
          RAISE NOTICE '  ↳ State → PARTIALLY_PAID';
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE '  ↳ PARTIALLY_PAID transition failed: %', SQLERRM;
        END;
      END IF;
    ELSE
      -- No payment = OVERDUE
      BEGIN
        PERFORM execute_workflow_transition(
          'FEE_DEMAND', v_demand_id, 'OVERDUE', v_actor, 'Marked overdue due to zero payment.'
        );
        RAISE NOTICE '  ↳ State → OVERDUE';
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '  ↳ OVERDUE transition failed: %', SQLERRM;
      END;
    END IF;
  END LOOP;

  -- ════════════════════════════════════════════════════════════════════════
  -- SECTION 3: EXAM RECORDS
  -- ════════════════════════════════════════════════════════════════════════
  v_exam_id := create_entity_record(
    'EXAM',
    json_build_array(
      json_build_object('attribute_code','exam_name',     'value', 'Half-Yearly Mathematics'),
      json_build_object('attribute_code','exam_date',     'value', '2025-09-15'),
      json_build_object('attribute_code','total_marks',   'value', 100),
      json_build_object('attribute_code','passing_marks', 'value', 35),
      json_build_object('attribute_code','class_code',    'value', '8')
    )::JSONB,
    v_actor
  );
  RAISE NOTICE 'EXAM: Half-Yearly Mathematics → %', v_exam_id;

  -- EXAM_ATTEMPT records for students
  DECLARE
    v_scores NUMERIC[] := ARRAY[87, 62, 45, 91, 38];
  BEGIN
    FOR v_i IN 1..5 LOOP
      v_attempt_id := create_entity_record(
        'EXAM_ATTEMPT',
        json_build_array(
          json_build_object('attribute_code','exam_reference',       'value', v_exam_id::TEXT),
          json_build_object('attribute_code','student_reference',    'value', v_names[v_i]),
          json_build_object('attribute_code','attempt_date',         'value', '2025-09-15'),
          json_build_object('attribute_code','total_marks_obtained', 'value', v_scores[v_i]),
          json_build_object('attribute_code','is_absent',            'value', false)
        )::JSONB,
        v_actor
      );
      RAISE NOTICE 'EXAM_ATTEMPT [%]: % scored %/100 → %', v_i, v_names[v_i], v_scores[v_i], v_attempt_id;
    END LOOP;
  END;

  RAISE NOTICE '';
  RAISE NOTICE '════════ SAMPLE DATA SEED COMPLETE ════════';
END $$;
