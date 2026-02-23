-- =============================================================================
-- PRATHAMONE ACADEMY OS — DATABASE SCHEMA
-- Layer 11  (App Shell & Dynamic Menus)
-- =============================================================================
-- Depends on: db/schema_layer0_layer3.sql
--
-- LAW 11: New modules → new DATA rows, not new tables.
--          The app shell (menus, sidebars) is fully declarative.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- menu_master
-- Registry of named menus (e.g. 'MAIN_SIDEBAR', 'USER_PROFILE_MENU').
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS menu_master (
    menu_id         UUID            NOT NULL DEFAULT gen_random_uuid(),
    tenant_id       UUID,           -- NULL = SYSTEM menu template
    menu_code       TEXT            NOT NULL, -- e.g. 'SIDEBAR_NAV'
    display_name    TEXT            NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT pk_menu_master PRIMARY KEY (menu_id),
    CONSTRAINT uq_menu_code UNIQUE (tenant_id, menu_code)
);

-- -----------------------------------------------------------------------------
-- menu_items
-- Individual links within a menu. Supports nesting and RBAC.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS menu_items (
    item_id         UUID            NOT NULL DEFAULT gen_random_uuid(),
    tenant_id       UUID,
    menu_id         UUID            NOT NULL REFERENCES menu_master(menu_id) ON DELETE CASCADE,
    parent_item_id  UUID            REFERENCES menu_items(item_id) ON DELETE CASCADE,
    label           TEXT            NOT NULL,
    icon_name       TEXT,           -- Lucide icon name
    route_path      TEXT,           -- Frontend route
    action_type     TEXT            NOT NULL DEFAULT 'ROUTE' CHECK (action_type IN ('ROUTE', 'REPORT', 'FORM', 'URL', 'DIVIDER')),
    action_target   TEXT,           -- report_code, form_code, or URL
    required_roles  TEXT[]          NOT NULL DEFAULT '{}',
    sort_order      INT             NOT NULL DEFAULT 0,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_menu_items PRIMARY KEY (item_id),
    CONSTRAINT uq_menu_item UNIQUE (tenant_id, menu_id, label)
);

-- RLS
ALTER TABLE menu_master ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items  ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_menu_master ON menu_master
    USING (tenant_id IS NULL OR tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

CREATE POLICY rls_menu_items ON menu_items
    USING (tenant_id IS NULL OR tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

-- Indexes
CREATE INDEX idx_menu_items_nav ON menu_items(menu_id, parent_item_id, sort_order);
