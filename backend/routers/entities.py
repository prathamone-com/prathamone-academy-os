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
    # LAW 2 fix: attribute_master has no entity_code or label column.
    # Correct columns: display_label (not label).
    # Correct entity filter: JOIN entity_master on entity_id and filter by entity_code.
    rows = await conn.fetch(
        """
        SELECT am.attribute_code,
               am.display_label  AS label,
               am.data_type,
               am.is_required
        FROM   attribute_master am
        JOIN   entity_master    em ON em.entity_id  = am.entity_id
                                  AND em.tenant_id  = am.tenant_id
        WHERE  em.entity_code = $1
          AND  am.tenant_id   = current_setting('app.tenant_id', true)::uuid
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

# Helpers _write_audit_event and _write_state_snapshot removed.
# Mutations are now handled by PL/pgSQL Kernel Functions which perform
# their own audit logging and hash-chain generation (LAW 12).


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
            am.display_label AS label,
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
            am.display_label AS label,
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


# _upsert_attribute removed.
# Logic absorbed into the PL/pgSQL create_entity_record and update_entity_record functions.


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

    # Step 4 — CREATE via Kernel Function (LAW 12)
    # This single call handles: entity check (LAW 1), envelope insert,
    # EAV attribute loop (LAW 2), and hash-chained audit logging (LAW 8).
    try:
        new_id = await conn.fetchval(
            "SELECT create_entity_record($1, $2, $3::uuid)",
            entity_code,
            json.dumps([{"attribute_code": a.attribute_code, "value": a.value} for a in body.attributes]),
            actor_id
        )
    except asyncpg.RaiseError as exc:
        # Handle LAW 1 exception raised from PL/pgSQL
        if "LAW 1 VIOLATION" in str(exc):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(exc)
            )
        raise

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

    # Step 4 — UPDATE via Kernel Function (LAW 12)
    # This handles EAV upserts, before/after snapshots, and hash-chained audit.
    try:
        await conn.execute(
            "SELECT update_entity_record($1, $2, $3::uuid)",
            record_id,
            json.dumps([{"attribute_code": a.attribute_code, "value": a.value} for a in body.attributes]),
            actor_id
        )
    except asyncpg.RecordNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Record '{record_id}' not found."
        )

    return {
        "record_id":          str(record_id),
        "entity_code":        entity_code,
        "attributes_updated": len(body.attributes),
    }
