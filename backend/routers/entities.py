"""
routers/entities.py — Full CRUD for entity_records + entity_attribute_values.

ENDPOINTS:
  POST /entities/{entity_code}/records        — create record
  GET  /entities/{entity_code}/records        — list records (EAV resolved)
  GET  /entities/{entity_code}/records/{id}   — single record + all attributes
  PUT  /entities/{entity_code}/records/{id}   — update attribute values

EVERY ENDPOINT:
  1. Checks role_permissions for the operation before touching data.
  2. Validates incoming attribute values against attribute_master.data_type.
  3. Enforces field_validations rules (required, min/max length, regex pattern,
     allowed values) before any INSERT.
  4. Writes to audit_event_log  after every CREATE and UPDATE  (LAW 8 — INSERT-ONLY).
  5. Writes before/after snapshot to audit_state_snapshot on every UPDATE (LAW 8).
  6. tenant_id is NEVER read from the request — it comes from the DB session GUC
     which was set from the validated JWT by middleware/tenant.py (LAW 7).

RULES.md:
  LAW 2 : No custom columns — all field data in entity_attribute_values.
  LAW 6 : tenant_id FK on every table — enforced by RLS + DB GUC.
  LAW 7 : tenant_id server-side only — never from request body.
  LAW 8 : Audit tables INSERT-ONLY — no UPDATE/DELETE on audit rows ever.
"""

from __future__ import annotations

import json
import re
import uuid
from typing import Any

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, field_validator

from db import db_conn

router = APIRouter(prefix="/entities", tags=["entities"])


# =============================================================================
# SCHEMAS
# =============================================================================

class AttributeValueIn(BaseModel):
    attribute_code: str
    value: Any  # validated by type checking helpers below

    @field_validator("attribute_code")
    @classmethod
    def no_sql_injection(cls, v: str) -> str:
        if not re.match(r"^[a-z][a-z0-9_]{0,63}$", v):
            raise ValueError(f"Invalid attribute_code format: {v!r}")
        return v


class EntityCreateRequest(BaseModel):
    attributes: list[AttributeValueIn] = []


class EntityUpdateRequest(BaseModel):
    attributes: list[AttributeValueIn]


class AttributeOut(BaseModel):
    attribute_code: str
    label: str | None
    data_type: str
    value: Any


class EntityRecordOut(BaseModel):
    record_id: uuid.UUID
    entity_code: str
    is_active: bool
    attributes: list[dict]


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# ---------------------------------------------------------------------------
# 1. Role permission check
# ---------------------------------------------------------------------------

async def _check_permission(
    conn: asyncpg.Connection,
    request: Request,
    entity_code: str,
    operation: str,          # "CREATE" | "READ" | "UPDATE" | "DELETE"
) -> None:
    """
    Verify that the caller's role has the required permission on this entity.
    Reads role_permissions rows — no hard-coded role names in Python (LAW 3/12).

    Raises HTTP 403 if permission is denied.
    """
    role: str = getattr(request.state, "role", "app_user")

    row = await conn.fetchrow(
        """
        SELECT rp.is_allowed
        FROM   role_permissions rp
        JOIN   permissions      p  ON p.permission_id = rp.permission_id
                                  AND p.tenant_id     = rp.tenant_id
        JOIN   roles            r  ON r.role_id       = rp.role_id
                                  AND r.tenant_id     = rp.tenant_id
        WHERE  r.role_code        = $1
          AND  p.entity_code      = $2
          AND  p.operation        = $3
        LIMIT  1
        """,
        role, entity_code, operation,
    )

    if row is None or not row["is_allowed"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Role '{role}' does not have {operation} permission "
                f"on entity '{entity_code}'."
            ),
        )


# ---------------------------------------------------------------------------
# 2. Attribute type validation
# ---------------------------------------------------------------------------

_TYPE_VALIDATORS: dict[str, type] = {
    "text":    str,
    "numeric": (int, float),
    "boolean": bool,
    "uuid":    str,
    "json":    (dict, list),
    "date":    str,
    "datetime": str,
}

async def _load_attribute_master(
    conn: asyncpg.Connection,
    entity_code: str,
) -> dict[str, dict]:
    """
    Return a mapping of {attribute_code: {data_type, is_required, label}}
    for all attributes defined for this entity_code.
    """
    rows = await conn.fetch(
        """
        SELECT attribute_code, data_type, is_required, label
        FROM   attribute_master
        WHERE  entity_code = $1
          AND  tenant_id   = current_setting('app.tenant_id', true)::uuid
        """,
        entity_code,
    )
    return {r["attribute_code"]: dict(r) for r in rows}


def _validate_data_type(
    attribute_code: str,
    value: Any,
    data_type: str,
) -> None:
    """Raise ValueError if value does not match the declared data_type."""
    if value is None:
        return  # nullability enforced separately by field_validations

    expected = _TYPE_VALIDATORS.get(data_type)
    if expected is None:
        return  # unknown type — pass through

    if data_type == "uuid":
        try:
            uuid.UUID(str(value))
        except ValueError:
            raise ValueError(
                f"Attribute '{attribute_code}': expected a valid UUID, got {value!r}"
            )
        return

    if not isinstance(value, expected):
        raise ValueError(
            f"Attribute '{attribute_code}': expected type '{data_type}', "
            f"got {type(value).__name__!r} ({value!r})"
        )


# ---------------------------------------------------------------------------
# 3. Field validations
# ---------------------------------------------------------------------------

async def _run_field_validations(
    conn: asyncpg.Connection,
    entity_code: str,
    attributes: list[AttributeValueIn],
) -> None:
    """
    Load field_validations rows for the entity and apply them to the
    provided attribute values.  Raises HTTP 422 on the first failure.
    """
    val_rows = await conn.fetch(
        """
        SELECT
            fv.attribute_code,
            fv.rule_type,
            fv.rule_value,
            fv.error_message
        FROM   field_validations fv
        JOIN   form_fields ff ON ff.attribute_code = fv.attribute_code
                             AND ff.tenant_id      = fv.tenant_id
        JOIN   form_master fm ON fm.form_id        = ff.form_id
                             AND fm.tenant_id      = ff.tenant_id
        WHERE  fm.entity_code = $1
        ORDER  BY fv.attribute_code, fv.sort_order
        """,
        entity_code,
    )

    # Build {attribute_code: [rules]} map
    rules: dict[str, list[dict]] = {}
    for r in val_rows:
        rules.setdefault(r["attribute_code"], []).append(dict(r))

    attr_map: dict[str, Any] = {a.attribute_code: a.value for a in attributes}

    errors: list[str] = []

    for attr_code, attr_rules in rules.items():
        value = attr_map.get(attr_code)
        str_value = str(value) if value is not None else None

        for rule in attr_rules:
            rule_type  = rule["rule_type"]
            rule_value = rule["rule_value"]
            err_msg    = rule["error_message"] or f"Validation failed: {attr_code} / {rule_type}"

            # required
            if rule_type == "required" and rule_value == "true":
                if value is None or str_value == "":
                    errors.append(err_msg)

            # min_length
            elif rule_type == "min_length" and str_value is not None:
                if len(str_value) < int(rule_value):
                    errors.append(err_msg)

            # max_length
            elif rule_type == "max_length" and str_value is not None:
                if len(str_value) > int(rule_value):
                    errors.append(err_msg)

            # min_value (numeric)
            elif rule_type == "min_value" and value is not None:
                try:
                    if float(value) < float(rule_value):
                        errors.append(err_msg)
                except (TypeError, ValueError):
                    pass

            # max_value (numeric)
            elif rule_type == "max_value" and value is not None:
                try:
                    if float(value) > float(rule_value):
                        errors.append(err_msg)
                except (TypeError, ValueError):
                    pass

            # regex pattern
            elif rule_type == "pattern" and str_value is not None:
                if not re.fullmatch(rule_value, str_value):
                    errors.append(err_msg)

            # allowed_values (comma-separated list)
            elif rule_type == "allowed_values" and value is not None:
                allowed = [v.strip() for v in rule_value.split(",")]
                if str_value not in allowed:
                    errors.append(err_msg)

    if errors:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"validation_errors": errors},
        )


# ---------------------------------------------------------------------------
# 4. Audit helpers
# ---------------------------------------------------------------------------

async def _write_audit_event(
    conn: asyncpg.Connection,
    *,
    actor_id: str | None,
    action_type: str,          # "CREATE" | "UPDATE"
    entity_code: str,
    entity_record_id: uuid.UUID,
    payload: dict,
) -> None:
    """
    Append ONE immutable row to audit_event_log (LAW 8 — INSERT-ONLY).
    Never UPDATE or DELETE. The RLS policy and role REVOKE enforce this
    independently; this function never even attempts an UPDATE.
    """
    await conn.execute(
        """
        INSERT INTO audit_event_log
            (tenant_id, actor_id, action_type,
             entity_code, entity_record_id, payload, created_at)
        VALUES
            (current_setting('app.tenant_id', true)::uuid,
             $1::uuid, $2,
             $3, $4, $5::jsonb, now())
        """,
        actor_id,
        action_type,
        entity_code,
        entity_record_id,
        json.dumps(payload),
    )


async def _write_state_snapshot(
    conn: asyncpg.Connection,
    *,
    entity_record_id: uuid.UUID,
    entity_code: str,
    before: dict,
    after: dict,
    actor_id: str | None,
) -> None:
    """
    Append ONE immutable row to audit_state_snapshot capturing before/after
    attribute values for every UPDATE (LAW 8 — INSERT-ONLY).
    """
    await conn.execute(
        """
        INSERT INTO audit_state_snapshot
            (tenant_id, entity_record_id, entity_code,
             before_state, after_state, actor_id, snapshotted_at)
        VALUES
            (current_setting('app.tenant_id', true)::uuid,
             $1, $2,
             $3::jsonb, $4::jsonb,
             $5::uuid, now())
        """,
        entity_record_id,
        entity_code,
        json.dumps(before),
        json.dumps(after),
        actor_id,
    )


# ---------------------------------------------------------------------------
# 5. EAV fetch helper
# ---------------------------------------------------------------------------

async def _fetch_eav(
    conn: asyncpg.Connection,
    record_id: uuid.UUID,
) -> dict[str, Any]:
    """
    Return {attribute_code: resolved_value} for a single record.
    Value is resolved from the first non-null column (text > numeric > bool > json).
    """
    rows = await conn.fetch(
        """
        SELECT
            eav.attribute_code,
            am.label,
            am.data_type,
            CASE am.data_type
                WHEN 'numeric' THEN eav.value_numeric::text
                WHEN 'boolean' THEN eav.value_bool::text
                WHEN 'json'    THEN eav.value_json::text
                ELSE                eav.value_text
            END AS resolved_value
        FROM   entity_attribute_values eav
        JOIN   attribute_master        am  ON am.attribute_code = eav.attribute_code
                                          AND am.tenant_id      = eav.tenant_id
        WHERE  eav.entity_record_id = $1
        ORDER  BY am.sort_order NULLS LAST, eav.attribute_code
        """,
        record_id,
    )
    return {r["attribute_code"]: r["resolved_value"] for r in rows}


async def _fetch_eav_full(
    conn: asyncpg.Connection,
    record_id: uuid.UUID,
) -> list[dict]:
    """Return full attribute list (code + label + type + value) for API responses."""
    rows = await conn.fetch(
        """
        SELECT
            eav.attribute_code,
            am.label,
            am.data_type,
            CASE am.data_type
                WHEN 'numeric' THEN eav.value_numeric::text
                WHEN 'boolean' THEN eav.value_bool::text
                WHEN 'json'    THEN eav.value_json::text
                ELSE                eav.value_text
            END AS value
        FROM   entity_attribute_values eav
        JOIN   attribute_master        am  ON am.attribute_code = eav.attribute_code
                                          AND am.tenant_id      = eav.tenant_id
        WHERE  eav.entity_record_id = $1
        ORDER  BY am.sort_order NULLS LAST, eav.attribute_code
        """,
        record_id,
    )
    return [dict(r) for r in rows]


async def _upsert_attribute(
    conn: asyncpg.Connection,
    record_id: uuid.UUID,
    attribute_code: str,
    data_type: str,
    value: Any,
) -> None:
    """
    Upsert a single attribute value into entity_attribute_values.
    Routes the scalar into the correct typed column.
    """
    text_val    = str(value) if data_type in ("text", "uuid", "date", "datetime") and value is not None else (str(value) if data_type not in ("numeric", "boolean", "json") and value is not None else None)
    num_val     = float(value) if data_type == "numeric" and value is not None else None
    bool_val    = bool(value)  if data_type == "boolean" and value is not None else None
    json_val    = json.dumps(value) if data_type == "json" and value is not None else None

    await conn.execute(
        """
        INSERT INTO entity_attribute_values
            (entity_record_id, tenant_id, attribute_code,
             value_text, value_numeric, value_bool, value_json)
        VALUES
            ($1, current_setting('app.tenant_id', true)::uuid, $2,
             $3, $4, $5, $6::jsonb)
        ON CONFLICT (entity_record_id, tenant_id, attribute_code)
        DO UPDATE SET
            value_text    = EXCLUDED.value_text,
            value_numeric = EXCLUDED.value_numeric,
            value_bool    = EXCLUDED.value_bool,
            value_json    = EXCLUDED.value_json,
            updated_at    = now()
        """,
        record_id, attribute_code,
        text_val, num_val, bool_val, json_val,
    )


# =============================================================================
# ENDPOINTS
# =============================================================================

# ---------------------------------------------------------------------------
# POST /entities/{entity_code}/records   — CREATE
# ---------------------------------------------------------------------------

@router.post(
    "/{entity_code}/records",
    status_code=status.HTTP_201_CREATED,
    summary="Create a new entity record",
)
async def create_entity_record(
    entity_code: str,
    body: EntityCreateRequest,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """
    Create a new entity_record and persist attribute values.

    Steps:
      1. Check role_permissions for CREATE on this entity.
      2. Load attribute_master and validate data types.
      3. Run field_validations rules (required, length, regex, allowed values).
      4. Insert entity_records row (tenant_id from GUC — LAW 7).
      5. Upsert each attribute value into entity_attribute_values.
      6. Write to audit_event_log (LAW 8 — INSERT-ONLY).
    """
    actor_id: str | None = getattr(request.state, "user_id", None)

    # Step 1 — Permission check
    await _check_permission(conn, request, entity_code, "CREATE")

    # Step 2 — Load attribute master and validate types
    attr_master = await _load_attribute_master(conn, entity_code)
    type_errors: list[str] = []
    for attr in body.attributes:
        defn = attr_master.get(attr.attribute_code)
        if defn is None:
            type_errors.append(
                f"Unknown attribute '{attr.attribute_code}' for entity '{entity_code}'. "
                "Register it in attribute_master first (LAW 2)."
            )
            continue
        try:
            _validate_data_type(attr.attribute_code, attr.value, defn["data_type"])
        except ValueError as exc:
            type_errors.append(str(exc))

    if type_errors:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"type_errors": type_errors},
        )

    # Step 3 — Field validations
    await _run_field_validations(conn, entity_code, body.attributes)

    # Step 4 — Insert entity_records.
    # JOIN entity_master to enforce LAW 1: every entity MUST be registered.
    # tenant_id comes from the GUC (LAW 7 — never from the request body).
    new_id = uuid.uuid4()
    rows_inserted = await conn.execute(
        """
        INSERT INTO entity_records (record_id, entity_id, tenant_id, is_active)
        SELECT $1, em.entity_id,
               current_setting('app.tenant_id', true)::uuid,
               true
        FROM   entity_master em
        WHERE  em.entity_code = $2
          AND  em.tenant_id   = current_setting('app.tenant_id', true)::uuid
        """,
        new_id, entity_code,
    )
    # asyncpg returns 'INSERT 0 <count>' — a count of 0 means entity not registered (LAW 1).
    if rows_inserted == "INSERT 0 0":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Entity '{entity_code}' is not registered in entity_master (LAW 1). "
                "Register it before creating records."
            ),
        )

    # Step 5 — Upsert attribute values
    for attr in body.attributes:
        defn = attr_master[attr.attribute_code]
        await _upsert_attribute(conn, new_id, attr.attribute_code, defn["data_type"], attr.value)

    # Step 6 — Audit CREATE event (LAW 8)
    await _write_audit_event(
        conn,
        actor_id=actor_id,
        action_type="CREATE",
        entity_code=entity_code,
        entity_record_id=new_id,
        payload={"attributes": {a.attribute_code: a.value for a in body.attributes}},
    )

    return {
        "record_id": str(new_id),
        "entity_code": entity_code,
        "is_active": True,
    }


# ---------------------------------------------------------------------------
# GET /entities/{entity_code}/records   — LIST
# ---------------------------------------------------------------------------

@router.get(
    "/{entity_code}/records",
    summary="List records with all EAV attribute values resolved",
)
async def list_entity_records(
    entity_code: str,
    request: Request,
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    active_only: bool = Query(True),
    conn: asyncpg.Connection = Depends(db_conn),
) -> list[dict]:
    """
    Return a page of entity_records.

    All attribute values are resolved and returned in-line.
    RLS enforces tenant isolation — no manual WHERE tenant_id needed.
    """
    # Step 1 — Permission
    await _check_permission(conn, request, entity_code, "READ")

    active_filter = "AND er.is_active = true" if active_only else ""

    rows = await conn.fetch(
        f"""
        SELECT er.record_id, em.entity_code, er.is_active
        FROM   entity_records er
        JOIN   entity_master  em ON em.entity_id = er.entity_id
                                AND em.tenant_id = er.tenant_id
        WHERE  em.entity_code = $1
        {active_filter}
        ORDER  BY er.record_id
        LIMIT  $2 OFFSET $3
        """,
        entity_code, limit, offset,
    )

    results = []
    for row in rows:
        attrs = await _fetch_eav_full(conn, row["record_id"])
        results.append({
            "record_id":   str(row["record_id"]),
            "entity_code": row["entity_code"],
            "is_active":   row["is_active"],
            "attributes":  attrs,
        })
    return results


# ---------------------------------------------------------------------------
# GET /entities/{entity_code}/records/{record_id}   — SINGLE RECORD
# ---------------------------------------------------------------------------

@router.get(
    "/{entity_code}/records/{record_id}",
    summary="Get a single entity record with all attribute values",
)
async def get_entity_record(
    entity_code: str,
    record_id: uuid.UUID,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """
    Return one entity_record with its full attribute list.
    RLS filters to the current tenant automatically.
    """
    # Step 1 — Permission
    await _check_permission(conn, request, entity_code, "READ")

    row = await conn.fetchrow(
        """
        SELECT er.record_id, em.entity_code, er.is_active
        FROM   entity_records er
        JOIN   entity_master  em ON em.entity_id = er.entity_id
                                AND em.tenant_id = er.tenant_id
        WHERE  er.record_id   = $1
          AND  em.entity_code = $2
        """,
        record_id, entity_code,
    )

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Record '{record_id}' not found for entity '{entity_code}'.",
        )

    attrs = await _fetch_eav_full(conn, record_id)
    return {
        "record_id":   str(row["record_id"]),
        "entity_code": row["entity_code"],
        "is_active":   row["is_active"],
        "attributes":  attrs,
    }


# ---------------------------------------------------------------------------
# PUT /entities/{entity_code}/records/{record_id}   — UPDATE
# ---------------------------------------------------------------------------

@router.put(
    "/{entity_code}/records/{record_id}",
    summary="Update attribute values on an entity record",
)
async def update_entity_record(
    entity_code: str,
    record_id: uuid.UUID,
    body: EntityUpdateRequest,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """
    Update one or more attribute values on an existing record.

    Steps:
      1. Check role_permissions for UPDATE on this entity.
      2. Verify record exists and belongs to the current tenant (via RLS).
      3. Capture BEFORE state from entity_attribute_values.
      4. Validate incoming types against attribute_master.
      5. Run field_validations rules.
      6. Upsert attribute values (INSERT … ON CONFLICT DO UPDATE).
      7. Capture AFTER state.
      8. Write audit_state_snapshot (before + after, LAW 8).
      9. Write audit_event_log entry (LAW 8).
    """
    actor_id: str | None = getattr(request.state, "user_id", None)

    # Step 1 — Permission
    await _check_permission(conn, request, entity_code, "UPDATE")

    # Step 2 — Confirm record exists (RLS ensures it's the right tenant)
    exists = await conn.fetchrow(
        """
        SELECT er.record_id 
        FROM   entity_records er
        JOIN   entity_master  em ON em.entity_id = er.entity_id
                                AND em.tenant_id = er.tenant_id
        WHERE  er.record_id = $1 AND em.entity_code = $2
        """,
        record_id, entity_code,
    )
    if not exists:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Record '{record_id}' not found for entity '{entity_code}'.",
        )

    # Step 3 — Capture BEFORE state
    before_state = await _fetch_eav(conn, record_id)

    # Step 4 — Type validation against attribute_master
    attr_master = await _load_attribute_master(conn, entity_code)
    type_errors: list[str] = []
    for attr in body.attributes:
        defn = attr_master.get(attr.attribute_code)
        if defn is None:
            type_errors.append(
                f"Unknown attribute '{attr.attribute_code}' for entity '{entity_code}'. "
                "Register it in attribute_master first (LAW 2)."
            )
            continue
        try:
            _validate_data_type(attr.attribute_code, attr.value, defn["data_type"])
        except ValueError as exc:
            type_errors.append(str(exc))

    if type_errors:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"type_errors": type_errors},
        )

    # Step 5 — Field validations
    await _run_field_validations(conn, entity_code, body.attributes)

    # Step 6 — Upsert attribute values
    for attr in body.attributes:
        defn = attr_master[attr.attribute_code]
        await _upsert_attribute(conn, record_id, attr.attribute_code, defn["data_type"], attr.value)

    # Step 7 — Capture AFTER state
    after_state = await _fetch_eav(conn, record_id)

    # Step 8 — Write audit_state_snapshot: before + after (LAW 8)
    await _write_state_snapshot(
        conn,
        entity_record_id=record_id,
        entity_code=entity_code,
        before=before_state,
        after=after_state,
        actor_id=actor_id,
    )

    # Step 9 — Write audit_event_log (LAW 8)
    changed = {
        a.attribute_code: {"before": before_state.get(a.attribute_code), "after": str(a.value)}
        for a in body.attributes
    }
    await _write_audit_event(
        conn,
        actor_id=actor_id,
        action_type="UPDATE",
        entity_code=entity_code,
        entity_record_id=record_id,
        payload={"changed_attributes": changed},
    )

    return {
        "record_id":          str(record_id),
        "entity_code":        entity_code,
        "attributes_updated": len(body.attributes),
    }
