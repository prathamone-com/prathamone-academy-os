-- =============================================================================
-- PRATHAMONE ACADEMY OS — DEMO USER DATA SEEDING
-- Purpose: Seeds a demo user for login verification.
-- LAW 11: No new tables. Users are entity_records with 'user' code.
-- =============================================================================

DO $$
DECLARE
    v_tenant_id     UUID;
    v_entity_user_id UUID;
    v_user_admin_id  UUID;
    v_attr_user     UUID;
    v_attr_pwd      UUID;
    v_attr_role     UUID;
BEGIN
    -- 1. Resolve Tenant
    SELECT tenant_id INTO v_tenant_id FROM tenants LIMIT 1;
    
    -- 2. Register 'user' Entity (LAW 1)
    INSERT INTO entity_master (tenant_id, entity_type, entity_code, display_name, description)
    VALUES 
        (v_tenant_id, 'SYSTEM', 'user', 'System User', 'User account for authentication')
    ON CONFLICT (tenant_id, entity_code) DO NOTHING;

    SELECT entity_id INTO v_entity_user_id FROM entity_master 
    WHERE tenant_id = v_tenant_id AND entity_code = 'user';

    -- 3. Define Authentication Attributes (LAW 2)
    INSERT INTO attribute_master (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, sort_order)
    VALUES
        (v_tenant_id, v_entity_user_id, 'username',      'Username',      'text', TRUE,  10),
        (v_tenant_id, v_entity_user_id, 'password_hash', 'Password Hash', 'text', TRUE,  20),
        (v_tenant_id, v_entity_user_id, 'role_name',     'Role Name',     'text', FALSE, 30)
    ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

    SELECT attribute_id INTO v_attr_user FROM attribute_master 
    WHERE entity_id = v_entity_user_id AND attribute_code = 'username';
    
    SELECT attribute_id INTO v_attr_pwd FROM attribute_master 
    WHERE entity_id = v_entity_user_id AND attribute_code = 'password_hash';
    
    SELECT attribute_id INTO v_attr_role FROM attribute_master 
    WHERE entity_id = v_entity_user_id AND attribute_code = 'role_name';

    -- 4. Create Demo User Account (admin / demo123)
    v_user_admin_id := gen_random_uuid();
    
    INSERT INTO entity_records (tenant_id, record_id, entity_id, display_name)
    VALUES (v_tenant_id, v_user_admin_id, v_entity_user_id, 'System Administrator')
    ON CONFLICT (record_id) DO NOTHING;

    -- If record was inserted or already existed, we update attribute values
    -- Using the specific record_id for 'admin' username check logic
    INSERT INTO entity_attribute_values (tenant_id, record_id, attribute_id, value_text)
    VALUES
        (v_tenant_id, v_user_admin_id, v_attr_user, 'admin'),
        (v_tenant_id, v_user_admin_id, v_attr_pwd,  '$2b$12$//zxFVDXg9nBqfaICyB7XeWTfRTTD/l62lYrUrVwRV3GoR26VRnQO'),
        (v_tenant_id, v_user_admin_id, v_attr_role, 'ADMIN')
    ON CONFLICT (tenant_id, record_id, attribute_id) DO UPDATE SET value_text = EXCLUDED.value_text;

    RAISE NOTICE 'Demo user seeded: admin / demo123';

END $$;
