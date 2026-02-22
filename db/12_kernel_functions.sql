-- =============================================================================
-- PRATHAMONE ACADEMY OS — KERNEL FUNCTIONS (LAYER 12)
-- Sovereign Kernel Transaction Functions for Entity & Workflow Mutations
-- =============================================================================

-- -----------------------------------------------------------------------------
-- FUNCTION: create_entity_record
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_entity_record(
    p_entity_code   TEXT,
    p_attributes    JSONB,     -- Array of {"attribute_code": "...", "value": "..."}
    p_actor_id      UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_entity_id     UUID;
    v_record_id     UUID := gen_random_uuid();
    v_tenant_id     UUID := current_setting('app.tenant_id', true)::UUID;
    v_attr          JSONB;
    v_attr_meta     RECORD;
BEGIN
    -- 1. Resolve and validate entity (LAW 1)
    SELECT entity_id INTO v_entity_id
    FROM entity_master 
    WHERE entity_code = p_entity_code AND tenant_id = v_tenant_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'LAW 1 VIOLATION: Entity code % not registered in entity_master', p_entity_code;
    END IF;

    -- 2. Insert record envelope
    INSERT INTO entity_records(tenant_id, record_id, entity_id, created_by)
    VALUES (v_tenant_id, v_record_id, v_entity_id, p_actor_id);

    -- 3. Loop through attributes and upsert (LAW 2)
    FOR v_attr IN SELECT * FROM jsonb_array_elements(p_attributes)
    LOOP
        -- Resolve attribute metadata to route value to correct typed column
        SELECT attribute_id, data_type INTO v_attr_meta
        FROM attribute_master
        WHERE attribute_code = v_attr->>'attribute_code' AND tenant_id = v_tenant_id;

        IF NOT FOUND THEN
            CONTINUE; 
        END IF;

        INSERT INTO entity_attribute_values(
            tenant_id, record_id, attribute_id,
            value_text, value_number, value_bool, value_jsonb
        ) VALUES (
            v_tenant_id, v_record_id, v_attr_meta.attribute_id,
            CASE WHEN v_attr_meta.data_type IN ('text','uuid','date','datetime')
                 THEN v_attr->>'value' END,
            CASE WHEN v_attr_meta.data_type = 'numeric'
                 THEN (v_attr->>'value')::NUMERIC END,
            CASE WHEN v_attr_meta.data_type = 'boolean'
                 THEN (v_attr->>'value')::BOOLEAN END,
            CASE WHEN v_attr_meta.data_type = 'json'
                 THEN (v_attr->'value') END -- Pass as JSONB
        )
        ON CONFLICT (tenant_id, record_id, attribute_id)
        DO UPDATE SET
            value_text    = EXCLUDED.value_text,
            value_number  = EXCLUDED.value_number,
            value_bool    = EXCLUDED.value_bool,
            value_jsonb   = EXCLUDED.value_jsonb,
            updated_at    = now();
    END LOOP;

    -- 4. Audit Event Logging (LAW 8 - hash chain auto-computed by trigger)
    INSERT INTO audit_event_log(
        tenant_id, actor_id, actor_type, event_category,
        event_type, entity_id, record_id, event_data
    ) VALUES (
        v_tenant_id, p_actor_id, 'USER', 'SYSTEM',
        'ENTITY_RECORD_CREATED', v_entity_id, v_record_id,
        jsonb_build_object(
            'entity_code', p_entity_code,
            'attributes', p_attributes
        )
    );

    RETURN v_record_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- FUNCTION: update_entity_record
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_entity_record(
    p_record_id     UUID,
    p_attributes    JSONB,
    p_actor_id      UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_tenant_id     UUID := current_setting('app.tenant_id', true)::UUID;
    v_entity_id     UUID;
    v_attr          JSONB;
    v_attr_meta     RECORD;
    v_log_id        UUID := gen_random_uuid();
    v_before        JSONB;
    v_after         JSONB;
BEGIN
    -- 1. Get current state and entity_id (Forensic Requirement)
    SELECT entity_id INTO v_entity_id FROM entity_records
    WHERE record_id = p_record_id AND tenant_id = v_tenant_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Record % not found for tenant %', p_record_id, v_tenant_id;
    END IF;

    -- Capture BEFORE state
    SELECT jsonb_object_agg(
        am.attribute_code, 
        COALESCE(eav.value_text, eav.value_number::text, eav.value_bool::text, eav.value_jsonb::text)
    ) INTO v_before
    FROM entity_attribute_values eav
    JOIN attribute_master am ON am.attribute_id = eav.attribute_id AND am.tenant_id = eav.tenant_id
    WHERE eav.record_id = p_record_id AND eav.tenant_id = v_tenant_id;

    -- 2. Upsert attributes
    FOR v_attr IN SELECT * FROM jsonb_array_elements(p_attributes)
    LOOP
        SELECT attribute_id, data_type INTO v_attr_meta
        FROM attribute_master
        WHERE attribute_code = v_attr->>'attribute_code' AND tenant_id = v_tenant_id;

        IF NOT FOUND THEN CONTINUE; END IF;

        INSERT INTO entity_attribute_values(
            tenant_id, record_id, attribute_id,
            value_text, value_number, value_bool, value_jsonb
        ) VALUES (
            v_tenant_id, p_record_id, v_attr_meta.attribute_id,
            CASE WHEN v_attr_meta.data_type IN ('text','uuid','date','datetime')
                 THEN v_attr->>'value' END,
            CASE WHEN v_attr_meta.data_type = 'numeric'
                 THEN (v_attr->>'value')::NUMERIC END,
            CASE WHEN v_attr_meta.data_type = 'boolean'
                 THEN (v_attr->>'value')::BOOLEAN END,
            CASE WHEN v_attr_meta.data_type = 'json'
                 THEN (v_attr->'value') END
        )
        ON CONFLICT (tenant_id, record_id, attribute_id)
        DO UPDATE SET
            value_text    = EXCLUDED.value_text,
            value_number  = EXCLUDED.value_number,
            value_bool    = EXCLUDED.value_bool,
            value_jsonb   = EXCLUDED.value_jsonb,
            updated_at    = now();
    END LOOP;

    -- Capture AFTER state
    SELECT jsonb_object_agg(
        am.attribute_code, 
        COALESCE(eav.value_text, eav.value_number::text, eav.value_bool::text, eav.value_jsonb::text)
    ) INTO v_after
    FROM entity_attribute_values eav
    JOIN attribute_master am ON am.attribute_id = eav.attribute_id AND am.tenant_id = eav.tenant_id
    WHERE eav.record_id = p_record_id AND eav.tenant_id = v_tenant_id;

    -- 3. Write Audit Event Log
    INSERT INTO audit_event_log(
        tenant_id, log_id, actor_id, actor_type, event_category,
        event_type, entity_id, record_id, event_data
    ) VALUES (
        v_tenant_id, v_log_id, p_actor_id, 'USER', 'SYSTEM',
        'ENTITY_RECORD_UPDATED', v_entity_id, p_record_id,
        jsonb_build_object('changed', p_attributes)
    );

    -- 4. Write Forensic Snapshots
    INSERT INTO audit_state_snapshot(
        tenant_id, audit_log_id, record_id, entity_id,
        snapshot_type, state_data
    ) VALUES 
    (v_tenant_id, v_log_id, p_record_id, v_entity_id, 'BEFORE', COALESCE(v_before, '{}'::jsonb)),
    (v_tenant_id, v_log_id, p_record_id, v_entity_id, 'AFTER', COALESCE(v_after, '{}'::jsonb));

    RETURN TRUE;
END;
$$;

-- -----------------------------------------------------------------------------
-- FUNCTION: execute_workflow_transition
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION execute_workflow_transition(
    p_entity_code   TEXT,
    p_record_id     UUID,
    p_to_state      TEXT,
    p_actor_id      UUID,
    p_notes         TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_tenant_id     UUID := current_setting('app.tenant_id', true)::UUID;
    v_entity_id     UUID;
    v_workflow_id   UUID;
    v_from_state    TEXT;
    v_transition_id UUID;
    v_log_id        UUID := gen_random_uuid();
BEGIN
    -- 1. Resolve entity and workflow
    SELECT em.entity_id, wm.workflow_id 
    INTO v_entity_id, v_workflow_id
    FROM entity_master em
    JOIN workflow_master wm ON wm.entity_id = em.entity_id AND wm.tenant_id = em.tenant_id
    WHERE em.entity_code = p_entity_code AND em.tenant_id = v_tenant_id;
    
    -- 2. Get current state
    SELECT to_state INTO v_from_state 
    FROM workflow_state_log
    WHERE tenant_id = v_tenant_id AND record_id = p_record_id
    ORDER BY transition_at DESC LIMIT 1;

    -- 3. Validate transition exists (LAW 3)
    SELECT wt.transition_id
    INTO v_transition_id
    FROM workflow_transitions wt
    WHERE wt.workflow_id     = v_workflow_id
      AND wt.to_state_code   = p_to_state
      AND wt.tenant_id       = v_tenant_id
      AND (
          (v_from_state IS NULL AND wt.from_state_code IS NULL)
          OR (wt.from_state_code = v_from_state)
      );

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LAW 3 VIOLATION: Invalid transition to % for entity % (current state: %)',
            p_to_state, p_entity_code, COALESCE(v_from_state, 'START');
    END IF;

    -- 4. Record the transition in state log
    INSERT INTO workflow_state_log(
        tenant_id, log_id, workflow_id, record_id, 
        from_state, to_state, trigger_event, actor_id, metadata
    ) VALUES (
        v_tenant_id, v_log_id, v_workflow_id, p_record_id,
        v_from_state, p_to_state, 'TRANSITION', p_actor_id, 
        jsonb_build_object('notes', p_notes)
    );

    -- 5. Update current instance state table
    INSERT INTO workflow_instance_state (
        tenant_id, record_id, entity_code, state_code
    ) VALUES (
        v_tenant_id, p_record_id, p_entity_code, p_to_state
    )
    ON CONFLICT (tenant_id, record_id)
    DO UPDATE SET 
        state_code = EXCLUDED.state_code,
        entered_at = now();

    -- 6. Audit
    INSERT INTO audit_event_log(
        tenant_id, log_id, actor_id, actor_type, event_category,
        event_type, entity_id, record_id, event_data
    ) VALUES (
        v_tenant_id, v_log_id, p_actor_id, 'USER', 'WORKFLOW',
        'WORKFLOW_TRANSITION', v_entity_id, p_record_id,
        jsonb_build_object(
            'from_state', v_from_state,
            'to_state', p_to_state,
            'notes', p_notes
        )
    );

    RETURN TRUE;
END;
$$;
