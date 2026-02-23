-- =============================================================================
-- PRATHAMONE ACADEMY OS — QUICK DEMO USER SEED
-- Creates demo tenant + admin user with a REAL bcrypt hash.
-- Run this when 99_demo_onboarding_seed.sql fails due to missing GAP tables.
-- Password: Admin123
-- =============================================================================

BEGIN;

-- Step 1: Create demo tenant
INSERT INTO tenants (tenant_id, name, slug, plan, is_active)
VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    'PrathamOne International School',
    'demo-prathamone-intl',
    'enterprise',
    TRUE
)
ON CONFLICT (tenant_id) DO NOTHING;

-- Step 2: Set session context (LAW 7)
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';

-- Step 3: Register 'user' entity
INSERT INTO entity_master (tenant_id, entity_type, entity_code, display_name, description, is_system)
VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    'SYSTEM', 'user', 'System User', 'User account for authentication and RBAC', TRUE
)
ON CONFLICT (tenant_id, entity_code) DO NOTHING;

-- Step 4: Register user attributes
INSERT INTO attribute_master (tenant_id, entity_id, attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
SELECT
    '00000000-0000-0000-0000-000000000001'::UUID,
    entity_id,
    attr.attribute_code,
    attr.display_label,
    attr.data_type,
    attr.is_required,
    attr.is_searchable,
    attr.sort_order
FROM entity_master,
LATERAL (VALUES
    ('username',      'Username',      'text',    TRUE,  TRUE,  10),
    ('password_hash', 'Password Hash', 'text',    TRUE,  FALSE, 20),
    ('role_name',     'Role Name',     'text',    FALSE, TRUE,  30),
    ('full_name',     'Full Name',     'text',    FALSE, TRUE,  40),
    ('email',         'Email Address', 'text',    FALSE, TRUE,  50),
    ('is_active',     'Is Active',     'boolean', FALSE, FALSE, 70)
) AS attr(attribute_code, display_label, data_type, is_required, is_searchable, sort_order)
WHERE entity_master.tenant_id = '00000000-0000-0000-0000-000000000001'::UUID
  AND entity_master.entity_code = 'user'
ON CONFLICT (tenant_id, entity_id, attribute_code) DO NOTHING;

-- Step 5: Create system actor record
INSERT INTO entity_records (tenant_id, record_id, entity_id, display_name, created_by)
SELECT
    '00000000-0000-0000-0000-000000000001'::UUID,
    '00000000-0000-0000-0000-000000000099'::UUID,
    entity_id,
    'SYSTEM_ONBOARDING_ACTOR',
    '00000000-0000-0000-0000-000000000099'::UUID
FROM entity_master
WHERE tenant_id = '00000000-0000-0000-0000-000000000001'::UUID AND entity_code = 'user'
ON CONFLICT (record_id) DO NOTHING;

-- Step 6: Create admin user record
INSERT INTO entity_records (tenant_id, record_id, entity_id, display_name, created_by)
SELECT
    '00000000-0000-0000-0000-000000000001'::UUID,
    '00000000-0000-0000-0000-000000000002'::UUID,
    entity_id,
    'Dr. Ananya Sharma (Principal)',
    '00000000-0000-0000-0000-000000000099'::UUID
FROM entity_master
WHERE tenant_id = '00000000-0000-0000-0000-000000000001'::UUID AND entity_code = 'user'
ON CONFLICT (record_id) DO NOTHING;

-- Step 7: Set admin user attributes (including real bcrypt hash for "Admin123")
INSERT INTO entity_attribute_values (tenant_id, record_id, attribute_id, value_text, value_bool, source)
SELECT
    '00000000-0000-0000-0000-000000000001'::UUID,
    '00000000-0000-0000-0000-000000000002'::UUID,
    am.attribute_id,
    CASE am.attribute_code
        WHEN 'username'      THEN 'principal_admin'
        WHEN 'password_hash' THEN '$2b$12$YTkK6gKlHiOMLz.vriAN8OMi7Pl1cFhRej3jrvI7Tgm/tT192ecqe'
        WHEN 'role_name'     THEN 'TENANT_ADMIN'
        WHEN 'full_name'     THEN 'Dr. Ananya Sharma'
        WHEN 'email'         THEN 'ananya.sharma@prathamone-demo.in'
        ELSE NULL
    END,
    CASE am.attribute_code WHEN 'is_active' THEN TRUE ELSE NULL END,
    'seed'
FROM attribute_master am
WHERE am.tenant_id = '00000000-0000-0000-0000-000000000001'::UUID
  AND am.attribute_code IN ('username','password_hash','role_name','full_name','email','is_active')
  AND am.entity_id = (SELECT entity_id FROM entity_master WHERE tenant_id = '00000000-0000-0000-0000-000000000001'::UUID AND entity_code = 'user')
ON CONFLICT (tenant_id, record_id, attribute_id) DO UPDATE
    SET value_text = EXCLUDED.value_text,
        value_bool = EXCLUDED.value_bool;

COMMIT;

-- Verify
SET app.tenant_id = '00000000-0000-0000-0000-000000000001';
SELECT am.attribute_code, eav.value_text
FROM entity_attribute_values eav
JOIN attribute_master am ON am.attribute_id = eav.attribute_id
WHERE eav.record_id = '00000000-0000-0000-0000-000000000002'::UUID
  AND am.attribute_code IN ('username','role_name','full_name')
ORDER BY am.sort_order;
