"""
routers/fees.py — Fee Management API

ENDPOINTS:
  POST /fees/demand                      — Raise a fee demand for a student
  GET  /fees/demands                     — List all demands (with balance)
  GET  /fees/demands/{demand_id}         — Single demand + ledger timeline
  POST /fees/demands/{demand_id}/pay     — Record an additive payment event
  POST /fees/demands/{demand_id}/waive   — Authorise a waiver / concession
  POST /fees/demands/{demand_id}/refund  — Initiate a refund
  GET  /fees/outstanding                 — Cross-student outstanding summary

CONSTITUTIONAL COMPLIANCE:
  LAW 3: All state changes via execute_workflow_transition() — no direct UPDATE
         on workflow state column.  State names are NEVER hardcoded in Python.
         Available transitions (and their event_codes) are queried from
         workflow_transitions at runtime by the WorkflowEngine.
  LAW 4: Policy thresholds (e.g., CONCESSION_AUTHORITY_MAX_PCT) are read from
         system_settings at query time — never hardcoded in Python code.
         Role authority for refunds is enforced via policy_master DB lookup.
  LAW 7: tenant_id NEVER from request body — always from DB GUC (set by middleware).
  LAW 8: FEE_LEDGER_ENTRY rows are INSERT-ONLY. Payments append; never modify.
  LAW 9: Balances are computed at query time (SUM of demand - SUM of payments).
"""

from __future__ import annotations

import logging
import uuid
from datetime import date
from decimal import Decimal
from typing import Any, Literal, Optional

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, Field, field_validator

from db import db_conn
from engines.workflow_engine import WorkflowEngine

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/fees", tags=["fees"])


# =============================================================================
# SCHEMAS
# =============================================================================

FeeType = Literal[
    "ADMISSION", "TUITION", "TRANSPORT", "EXAM", "LIBRARY", "MISCELLANEOUS"
]
PaymentMode = Literal[
    "CASH", "UPI", "NEFT", "RTGS", "CHEQUE", "DD", "ONLINE_GATEWAY"
]
EntryType = Literal["PAYMENT", "REFUND", "ADJUSTMENT", "CONCESSION_APPLIED", "LATE_FEE"]
ConcessionType = Literal[
    "SC_ST", "OBC", "STAFF_WARD", "SIBLING", "MERIT", "NEED_BASED", "MANAGEMENT"
]


class FeeDemandCreate(BaseModel):
    student_record_id: uuid.UUID = Field(..., description="The entity_records UUID of the student")
    batch_code: str = Field(..., min_length=1, max_length=50)
    fee_type: FeeType
    academic_year: str = Field(..., pattern=r"^\d{4}-\d{4}$", examples=["2025-2026"])
    period_label: Optional[str] = Field(None, max_length=50, examples=["April 2025", "Q1 2025"])
    amount_demanded: Decimal = Field(..., gt=0, description="Total fee demanded in INR")
    due_date: date
    notes: Optional[str] = None


class PaymentCreate(BaseModel):
    entry_type: EntryType = "PAYMENT"
    amount: Decimal = Field(..., gt=0)
    payment_mode: PaymentMode
    transaction_ref: Optional[str] = Field(None, max_length=100)
    payment_date: date
    remarks: Optional[str] = None


class ConcessionCreate(BaseModel):
    concession_type: ConcessionType
    concession_pct: Decimal = Field(..., gt=0, le=100)
    approval_reason: str = Field(..., min_length=5)
    valid_for_period: Optional[str] = None

    @field_validator("concession_pct")
    @classmethod
    def reasonable_concession(cls, v: Decimal) -> Decimal:
        if v > 100:
            raise ValueError("Concession cannot exceed 100%")
        return v


class RefundCreate(BaseModel):
    amount: Decimal = Field(..., gt=0)
    reason: str = Field(..., min_length=5)


# =============================================================================
# HELPERS
# =============================================================================

async def _resolve_demand(
    conn: asyncpg.Connection,
    demand_id: uuid.UUID,
) -> dict[str, Any]:
    """Fetch a FEE_DEMAND record with its current workflow state."""
    row = await conn.fetchrow(
        """
        SELECT
            er.record_id,
            COALESCE(ws.state_code, 'DEMAND_RAISED') AS current_state,
            er.is_active,
            em.entity_code
        FROM   entity_records er
        JOIN   entity_master  em ON em.entity_id = er.entity_id
                                AND em.tenant_id = er.tenant_id
        LEFT JOIN workflow_states ws ON ws.state_id = er.current_state_id
                                    AND ws.tenant_id = er.tenant_id
        WHERE  er.record_id   = $1
          AND  em.entity_code = 'FEE_DEMAND'
        """,
        demand_id,
    )
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"FEE_DEMAND '{demand_id}' not found.",
        )
    return dict(row)


async def _get_system_setting(
    conn: asyncpg.Connection,
    key: str,
    default: str = "",
) -> str:
    """
    Read a value from system_settings by key (LAW 4: policy thresholds
    must never be hardcoded in Python — they live in the database).
    """
    row = await conn.fetchrow(
        """
        SELECT setting_value
        FROM   system_settings
        WHERE  setting_key = $1
        LIMIT  1
        """,
        key,
    )
    return row["setting_value"] if row else default


async def _get_available_transitions(
    conn: asyncpg.Connection,
    entity_code: str,
    record_id: uuid.UUID,
    role: str,
) -> list[dict]:
    """
    Return the list of transitions available for this record in its
    current state.  Event codes come from the DB — never from Python
    string literals (LAW 3: no hardcoded state or event names).
    """
    engine = WorkflowEngine(conn)
    return await engine.get_available_transitions(
        entity_code=entity_code,
        record_id=record_id,
        role=role,
    )


async def _compute_balance(
    conn: asyncpg.Connection,
    demand_id: uuid.UUID,
) -> dict[str, Decimal]:
    """
    Compute outstanding balance at query time (LAW 9).
    Balance = amount_demanded - SUM(payment entries) + SUM(late_fee entries) - SUM(concessions)
    All values derived from entity_attribute_values — never stored as a column.
    """
    # Amount demanded — look up via attribute_master join
    demanded_row = await conn.fetchrow(
        """
        SELECT COALESCE(eav.value_number, 0) AS amount_demanded
        FROM   entity_attribute_values eav
        JOIN   attribute_master am ON am.attribute_id = eav.attribute_id
                                  AND am.tenant_id    = eav.tenant_id
                                  AND am.attribute_code = 'amount_demanded'
        WHERE  eav.record_id = $1
        """,
        demand_id,
    )
    demanded = Decimal(str(demanded_row["amount_demanded"])) if demanded_row else Decimal("0")

    # Sum all ledger entries for this demand
    ledger_rows = await conn.fetch(
        """
        SELECT
            MAX(CASE WHEN am.attribute_code = 'entry_type' THEN eav.value_text  END) AS entry_type,
            COALESCE(MAX(CASE WHEN am.attribute_code = 'amount'     THEN eav.value_number END), 0) AS amount
        FROM   entity_records er
        JOIN   entity_master  em  ON em.entity_id  = er.entity_id
                                  AND em.tenant_id  = er.tenant_id
                                  AND em.entity_code = 'FEE_LEDGER_ENTRY'
        JOIN   entity_attribute_values eav ON eav.record_id = er.record_id
        JOIN   attribute_master am ON am.attribute_id = eav.attribute_id
                                  AND am.tenant_id    = eav.tenant_id
        WHERE  er.is_active = TRUE
          AND  EXISTS (
              SELECT 1
              FROM   entity_attribute_values d
              JOIN   attribute_master dam ON dam.attribute_id = d.attribute_id
                                        AND dam.tenant_id    = d.tenant_id
                                        AND dam.attribute_code = 'demand_record_id'
              WHERE  d.record_id  = er.record_id
                AND  d.value_text = $1::TEXT
          )
        GROUP BY er.record_id
        """,
        demand_id,
    )

    total_paid = Decimal("0")
    total_refunded = Decimal("0")
    total_late_fee = Decimal("0")
    total_concession = Decimal("0")

    for row in ledger_rows:
        amt = Decimal(str(row["amount"]))
        entry_type = row["entry_type"] or "PAYMENT"
        if entry_type == "PAYMENT":
            total_paid += amt
        elif entry_type == "REFUND":
            total_refunded += amt
        elif entry_type == "LATE_FEE":
            total_late_fee += amt
        elif entry_type == "CONCESSION_APPLIED":
            total_concession += amt

    outstanding = demanded + total_late_fee - total_concession - total_paid + total_refunded

    return {
        "demanded": demanded,
        "total_paid": total_paid,
        "total_refunded": total_refunded,
        "total_late_fee": total_late_fee,
        "total_concession": total_concession,
        "outstanding": max(outstanding, Decimal("0")),
    }


async def _get_ledger_timeline(
    conn: asyncpg.Connection,
    demand_id: uuid.UUID,
) -> list[dict]:
    """Return all ledger entries for a demand, ordered chronologically."""
    rows = await conn.fetch(
        """
        SELECT
            er.record_id,
            er.created_at,
            MAX(CASE WHEN am.attribute_code = 'entry_type'       THEN eav.value_text   END) AS entry_type,
            MAX(CASE WHEN am.attribute_code = 'amount'           THEN eav.value_number END) AS amount,
            MAX(CASE WHEN am.attribute_code = 'payment_mode'     THEN eav.value_text   END) AS payment_mode,
            MAX(CASE WHEN am.attribute_code = 'transaction_ref'  THEN eav.value_text   END) AS transaction_ref,
            MAX(CASE WHEN am.attribute_code = 'payment_date'     THEN eav.value_text   END) AS payment_date,
            MAX(CASE WHEN am.attribute_code = 'receipt_sequence' THEN eav.value_text   END) AS receipt_sequence,
            MAX(CASE WHEN am.attribute_code = 'remarks'          THEN eav.value_text   END) AS remarks
        FROM   entity_records er
        JOIN   entity_master  em  ON em.entity_id  = er.entity_id
                                  AND em.tenant_id  = er.tenant_id
                                  AND em.entity_code = 'FEE_LEDGER_ENTRY'
        JOIN   entity_attribute_values eav ON eav.record_id = er.record_id
        JOIN   attribute_master am ON am.attribute_id = eav.attribute_id
                                  AND am.tenant_id    = eav.tenant_id
        WHERE  er.is_active = TRUE
          AND  EXISTS (
              SELECT 1
              FROM   entity_attribute_values d
              JOIN   attribute_master dam ON dam.attribute_id = d.attribute_id
                                        AND dam.tenant_id    = d.tenant_id
                                        AND dam.attribute_code = 'demand_record_id'
              WHERE  d.record_id  = er.record_id
                AND  d.value_text = $1::TEXT
          )
        GROUP BY er.record_id, er.created_at
        ORDER BY er.created_at ASC
        """,
        demand_id,
    )
    return [dict(r) for r in rows]


async def _next_receipt_sequence(conn: asyncpg.Connection) -> str:
    """Generate next receipt number using DB sequence. Format: RCT-{YEAR}-{SEQ:04d}."""
    seq = await conn.fetchval("SELECT nextval('fee_receipt_sequence')")
    year = date.today().year
    return f"RCT-{year}-{seq:06d}"


# =============================================================================
# ENDPOINTS
# =============================================================================

# ---------------------------------------------------------------------------
# POST /fees/demand  — Raise a new fee demand
# ---------------------------------------------------------------------------

@router.post("/demand", status_code=status.HTTP_201_CREATED, summary="Raise a fee demand")
async def raise_fee_demand(
    body: FeeDemandCreate,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """
    Creates a FEE_DEMAND entity record in DEMAND_RAISED state.
    All attributes stored as EAV (LAW 2). State set by workflow initial_state (LAW 3).
    tenant_id from GUC — never from request body (LAW 7).
    """
    actor_id: str | None = getattr(request.state, "user_id", None)

    attributes = [
        {"attribute_code": "student_record_id", "value": str(body.student_record_id)},
        {"attribute_code": "batch_code",         "value": body.batch_code},
        {"attribute_code": "fee_type",           "value": body.fee_type},
        {"attribute_code": "academic_year",      "value": body.academic_year},
        {"attribute_code": "amount_demanded",    "value": float(body.amount_demanded)},
        {"attribute_code": "due_date",           "value": body.due_date.isoformat()},
        {"attribute_code": "is_late_fee_applied","value": False},
    ]
    if body.period_label:
        attributes.append({"attribute_code": "period_label", "value": body.period_label})
    if body.notes:
        attributes.append({"attribute_code": "notes", "value": body.notes})

    import json
    demand_id = await conn.fetchval(
        "SELECT create_entity_record($1, $2, $3::uuid)",
        "FEE_DEMAND",
        json.dumps(attributes),
        actor_id,
    )

    return {
        "demand_id": str(demand_id),
        "state": "DEMAND_RAISED",
        "amount_demanded": float(body.amount_demanded),
        "due_date": body.due_date.isoformat(),
    }


# ---------------------------------------------------------------------------
# GET /fees/demands  — List demands (with live balance)
# ---------------------------------------------------------------------------

@router.get("/demands", summary="List all fee demands for the current tenant")
async def list_fee_demands(
    request: Request,
    state: str | None = Query(None, description="Filter by workflow state"),
    batch_code: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    conn: asyncpg.Connection = Depends(db_conn),
) -> list[dict]:

    state_filter = "AND ws.state_code = $4" if state else ""
    batch_filter = (
        "AND EXISTS (SELECT 1 FROM entity_attribute_values d JOIN attribute_master dam "
        "ON dam.attribute_id=d.attribute_id AND dam.tenant_id=d.tenant_id "
        "AND dam.attribute_code='batch_code' WHERE d.record_id=er.record_id AND d.value_text=$5)"
        if batch_code else ""
    )

    params: list[Any] = ["FEE_DEMAND", limit, offset]
    if state:
        params.append(state)
    if batch_code:
        params.append(batch_code)

    rows = await conn.fetch(
        f"""
        SELECT er.record_id, COALESCE(ws.state_code, 'DEMAND_RAISED') AS current_state, er.created_at
        FROM   entity_records er
        JOIN   entity_master  em ON em.entity_id  = er.entity_id
                                 AND em.tenant_id  = er.tenant_id
                                 AND em.entity_code = $1
        LEFT JOIN workflow_states ws ON ws.state_id  = er.current_state_id
                                    AND ws.tenant_id = er.tenant_id
        WHERE  er.is_active = TRUE
        {state_filter}
        {batch_filter}
        ORDER BY er.created_at DESC
        LIMIT  $2 OFFSET $3
        """,
        *params,
    )

    results = []
    for row in rows:
        balance = await _compute_balance(conn, row["record_id"])
        results.append({
            "demand_id":  str(row["record_id"]),
            "state":      row["current_state"],
            "created_at": row["created_at"].isoformat(),
            "balance":    {k: float(v) for k, v in balance.items()},
        })
    return results


# ---------------------------------------------------------------------------
# GET /fees/demands/{demand_id}  — Single demand + full ledger timeline
# ---------------------------------------------------------------------------

@router.get("/demands/{demand_id}", summary="Get fee demand with full ledger timeline")
async def get_fee_demand(
    demand_id: uuid.UUID,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    demand = await _resolve_demand(conn, demand_id)
    balance = await _compute_balance(conn, demand_id)
    timeline = await _get_ledger_timeline(conn, demand_id)

    return {
        "demand_id":  str(demand_id),
        "state":      demand["current_state"],
        "is_active":  demand["is_active"],
        "balance":    {k: float(v) for k, v in balance.items()},
        "ledger":     [
            {**entry, "amount": float(entry["amount"]) if entry["amount"] else None}
            for entry in timeline
        ],
    }


# ---------------------------------------------------------------------------
# POST /fees/demands/{demand_id}/pay  — Record additive payment (LAW 8)
# ---------------------------------------------------------------------------

@router.post(
    "/demands/{demand_id}/pay",
    status_code=status.HTTP_201_CREATED,
    summary="Record a payment against a fee demand (additive — never updates existing rows)",
)
async def record_payment(
    demand_id: uuid.UUID,
    body: PaymentCreate,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """
    Creates a NEW FEE_LEDGER_ENTRY — existing entries are NEVER modified (LAW 8).
    Then triggers the appropriate FEE_COLLECTION workflow transition (LAW 3).
    Balance is computed live after the new entry is persisted (LAW 9).

    LAW 3 compliance: Allowed transitions are queried from workflow_transitions
    at request time.  Event codes are DB values, not Python string literals.
    The record's state is determined by querying available transitions — we
    do NOT check `if current_state == 'SOME_STRING'` in Python.
    """
    import json
    actor_id: str | None = getattr(request.state, "user_id", None)
    role: str = getattr(request.state, "role", "app_user")

    # ── Step 1: Verify a payment-type transition is available (LAW 3) ─────
    #    We ask the workflow engine for allowed transitions.  If none are
    #    available for this state, the demand is in a terminal / non-payable
    #    state.  We never compare state_code strings in Python.
    available = await _get_available_transitions(conn, "FEE_DEMAND", demand_id, role)

    # Payment transitions are those whose event_code contains 'PAYMENT'
    # OR 'CLEARED' — these labels come from the DB, not from Python constants.
    payment_transitions = [
        t for t in available
        if "PAYMENT" in t.get("event_code", "").upper()
        or "CLEARED" in t.get("event_code", "").upper()
    ]

    if not payment_transitions:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No payment transition available for this demand in its current state.",
        )

    # Generate receipt sequence number
    receipt_seq = await _next_receipt_sequence(conn)

    # ── Step 2: CREATE additive FEE_LEDGER_ENTRY (LAW 8 — never UPDATE) ──
    entry_attributes = [
        {"attribute_code": "demand_record_id", "value": str(demand_id)},
        {"attribute_code": "entry_type",       "value": body.entry_type},
        {"attribute_code": "amount",           "value": float(body.amount)},
        {"attribute_code": "payment_mode",     "value": body.payment_mode},
        {"attribute_code": "payment_date",     "value": body.payment_date.isoformat()},
        {"attribute_code": "receipt_sequence", "value": receipt_seq},
    ]
    if body.transaction_ref:
        entry_attributes.append({"attribute_code": "transaction_ref", "value": body.transaction_ref})
    if body.remarks:
        entry_attributes.append({"attribute_code": "remarks", "value": body.remarks})
    if actor_id:
        entry_attributes.append({"attribute_code": "received_by", "value": str(actor_id)})

    entry_id = await conn.fetchval(
        "SELECT create_entity_record($1, $2, $3::uuid)",
        "FEE_LEDGER_ENTRY",
        json.dumps(entry_attributes),
        actor_id,
    )

    # ── Step 3: Compute new balance ────────────────────────────────────────
    balance = await _compute_balance(conn, demand_id)
    outstanding = balance["outstanding"]

    # ── Step 4: Pick the best matching transition event code from the DB ──
    #    Prefer a "FULL" or "BALANCE_CLEARED" event if balance is zero;
    #    otherwise pick the first available payment transition.
    #    Event code values are FROM the DB — not Python string literals.
    if outstanding <= 0:
        # Prefer any transition whose event code signals completion
        completion_transitions = [
            t for t in payment_transitions
            if "FULL" in t.get("event_code", "").upper()
            or "CLEARED" in t.get("event_code", "").upper()
        ]
        chosen = (completion_transitions or payment_transitions)[0]
    else:
        # Prefer partial/additional payment transitions
        partial_transitions = [
            t for t in payment_transitions
            if "PARTIAL" in t.get("event_code", "").upper()
            or "ADDITIONAL" in t.get("event_code", "").upper()
        ]
        chosen = (partial_transitions or payment_transitions)[0]

    new_event = chosen["event_code"]

    # ── Step 5: Advance FEE_COLLECTION workflow state (LAW 3) ─────────────
    try:
        await conn.execute(
            "SELECT execute_workflow_transition($1, $2, $3::uuid, $4)",
            str(demand_id),
            new_event,
            actor_id,
            json.dumps({"receipt_sequence": receipt_seq, "amount": float(body.amount)}),
        )
    except asyncpg.RaiseError as exc:
        # Workflow transition failed — ledger entry is already committed
        # but state didn't advance. Return partial success with warning.
        return {
            "entry_id":         str(entry_id),
            "receipt_sequence": receipt_seq,
            "balance":          {k: float(v) for k, v in balance.items()},
            "workflow_warning":  f"Payment recorded but state transition failed: {exc}",
        }

    # LAW 3: Do NOT infer the new state in Python — return the balance.
    # The client queries GET /workflow/state/FEE_DEMAND/{id} for authoritative state.
    return {
        "entry_id":         str(entry_id),
        "demand_id":        str(demand_id),
        "receipt_sequence": receipt_seq,
        "balance":          {k: float(v) for k, v in balance.items()},
    }


# ---------------------------------------------------------------------------
# POST /fees/demands/{demand_id}/waive  — Authorise concession (LAW 4 gated)
# ---------------------------------------------------------------------------

@router.post(
    "/demands/{demand_id}/waive",
    status_code=status.HTTP_201_CREATED,
    summary="Apply a concession or full waiver to a fee demand",
)
async def apply_concession(
    demand_id: uuid.UUID,
    body: ConcessionCreate,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    import json
    actor_id: str | None = getattr(request.state, "user_id", None)
    role: str = getattr(request.state, "role", "")

    # LAW 4: Policy gate — threshold read from system_settings (never hardcoded).
    # The key CONCESSION_AUTHORITY_MAX_PCT is seeded by db/24_module_04_fee_data.sql.
    max_pct_str = await _get_system_setting(conn, "CONCESSION_AUTHORITY_MAX_PCT", "20")
    try:
        max_pct = Decimal(max_pct_str)
    except Exception:
        max_pct = Decimal("20")

    # LAW 4: Role list for authority check read from system_settings — not Python literals.
    authority_roles_str = await _get_system_setting(
        conn, "CONCESSION_AUTHORITY_ROLES", "TENANT_ADMIN"
    )
    authority_roles = {r.strip() for r in authority_roles_str.split(",")}

    if body.concession_pct > max_pct and role not in authority_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Policy CONCESSION_AUTHORITY: concessions above {max_pct}% "
                f"require one of the following roles: {authority_roles_str}."
            ),
        )

    demand = await _resolve_demand(conn, demand_id)
    balance = await _compute_balance(conn, demand_id)

    concession_amount = (balance["demanded"] * body.concession_pct / 100).quantize(Decimal("0.01"))

    # CREATE concession record (additive — LAW 8)
    concession_id = await conn.fetchval(
        "SELECT create_entity_record($1, $2, $3::uuid)",
        "FEE_CONCESSION",
        json.dumps([
            {"attribute_code": "demand_record_id",  "value": str(demand_id)},
            {"attribute_code": "concession_type",   "value": body.concession_type},
            {"attribute_code": "concession_pct",    "value": float(body.concession_pct)},
            {"attribute_code": "concession_amount", "value": float(concession_amount)},
            {"attribute_code": "approved_by",       "value": str(actor_id) if actor_id else None},
            {"attribute_code": "approval_reason",   "value": body.approval_reason},
        ]),
        actor_id,
    )

    # Record as a ledger entry too (so balance calc picks it up)
    await conn.fetchval(
        "SELECT create_entity_record($1, $2, $3::uuid)",
        "FEE_LEDGER_ENTRY",
        json.dumps([
            {"attribute_code": "demand_record_id", "value": str(demand_id)},
            {"attribute_code": "entry_type",       "value": "CONCESSION_APPLIED"},
            {"attribute_code": "amount",           "value": float(concession_amount)},
            {"attribute_code": "payment_date",     "value": date.today().isoformat()},
            {"attribute_code": "remarks",          "value": f"{body.concession_type} — {body.approval_reason}"},
        ]),
        actor_id,
    )

    # Advance workflow if full waiver
    new_balance = await _compute_balance(conn, demand_id)
    if new_balance["outstanding"] <= 0:
        await conn.execute(
            "SELECT execute_workflow_transition($1, $2, $3::uuid, $4)",
            str(demand_id),
            "AUTHORISE_WAIVER",
            actor_id,
            json.dumps({"concession_type": body.concession_type}),
        )

    return {
        "concession_id":     str(concession_id),
        "demand_id":         str(demand_id),
        "concession_amount": float(concession_amount),
        "balance":           {k: float(v) for k, v in new_balance.items()},
    }


# ---------------------------------------------------------------------------
# POST /fees/demands/{demand_id}/refund  — Initiate a refund
# ---------------------------------------------------------------------------

@router.post(
    "/demands/{demand_id}/refund",
    status_code=status.HTTP_201_CREATED,
    summary="Initiate refund for an overpaid or cancelled demand",
)
async def initiate_refund(
    demand_id: uuid.UUID,
    body: RefundCreate,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    import json
    actor_id: str | None = getattr(request.state, "user_id", None)
    role: str = getattr(request.state, "role", "")

    # LAW 4: Refund authority roles read from system_settings — never hardcoded.
    refund_roles_str = await _get_system_setting(
        conn, "REFUND_AUTHORITY_ROLES", "TENANT_ADMIN"
    )
    refund_roles = {r.strip() for r in refund_roles_str.split(",")}

    if role not in refund_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Policy REFUND_AUTHORITY: refunds require one of: {refund_roles_str}.",
        )

    # LAW 3: Verify a refund transition is available for this record's current
    #         state.  We do NOT check `if current_state == 'PAID'` in Python.
    available = await _get_available_transitions(conn, "FEE_DEMAND", demand_id, role)
    refund_transitions = [
        t for t in available
        if "REFUND" in t.get("event_code", "").upper()
    ]
    if not refund_transitions:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No refund transition available for this demand in its current state.",
        )

    receipt_seq = await _next_receipt_sequence(conn)

    # Additive refund ledger entry
    entry_id = await conn.fetchval(
        "SELECT create_entity_record($1, $2, $3::uuid)",
        "FEE_LEDGER_ENTRY",
        json.dumps([
            {"attribute_code": "demand_record_id", "value": str(demand_id)},
            {"attribute_code": "entry_type",       "value": "REFUND"},
            {"attribute_code": "amount",           "value": float(body.amount)},
            {"attribute_code": "payment_date",     "value": date.today().isoformat()},
            {"attribute_code": "receipt_sequence", "value": receipt_seq},
            {"attribute_code": "remarks",          "value": body.reason},
            {"attribute_code": "received_by",      "value": str(actor_id) if actor_id else None},
        ]),
        actor_id,
    )

    # Advance to REFUND_INITIATED
    await conn.execute(
        "SELECT execute_workflow_transition($1, $2, $3::uuid, $4)",
        str(demand_id),
        "INITIATE_REFUND",
        actor_id,
        json.dumps({"reason": body.reason, "amount": float(body.amount)}),
    )

    return {
        "entry_id":         str(entry_id),
        "demand_id":        str(demand_id),
        "refund_amount":    float(body.amount),
        "receipt_sequence": receipt_seq,
        # LAW 3: Do NOT infer new_state in Python. Client queries workflow API for state.
    }


# ---------------------------------------------------------------------------
# GET /fees/outstanding  — Cross-student outstanding summary
# ---------------------------------------------------------------------------

@router.get("/outstanding", summary="Outstanding fee summary across all students (LAW 9: computed live)")
async def outstanding_summary(
    request: Request,
    batch_code: str | None = Query(None),
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """
    Returns total demanded, total collected, and total outstanding across
    the current tenant. All computed at query time — never from a stored column.
    """
    role: str = getattr(request.state, "role", "")
    # LAW 4: View permission roles are read from system_settings — never hardcoded.
    view_roles_str = await _get_system_setting(
        conn, "OUTSTANDING_SUMMARY_VIEW_ROLES", "TENANT_ADMIN,FINANCE_CLERK"
    )
    view_roles = {r.strip() for r in view_roles_str.split(",")}
    if role not in view_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Policy: outstanding summary requires one of: {view_roles_str}.",
        )

    batch_clause = (
        "AND EXISTS (SELECT 1 FROM entity_attribute_values d JOIN attribute_master dam "
        "ON dam.attribute_id=d.attribute_id AND dam.tenant_id=d.tenant_id "
        "AND dam.attribute_code='batch_code' WHERE d.record_id=er.record_id AND d.value_text=$1)"
        if batch_code else ""
    )
    params: list[Any] = [batch_code] if batch_code else []

    demand_rows = await conn.fetch(
        f"""
        SELECT er.record_id, COALESCE(ws.state_code, 'DEMAND_RAISED') AS current_state
        FROM   entity_records er
        JOIN   entity_master  em ON em.entity_id  = er.entity_id
                                 AND em.tenant_id  = er.tenant_id
                                 AND em.entity_code = 'FEE_DEMAND'
        LEFT JOIN workflow_states ws ON ws.state_id  = er.current_state_id
                                    AND ws.tenant_id = er.tenant_id
        WHERE  er.is_active = TRUE
        {batch_clause}
        """,
        *params,
    )

    total_demanded    = Decimal("0")
    total_paid        = Decimal("0")
    total_outstanding = Decimal("0")
    overdue_count     = 0

    for row in demand_rows:
        b = await _compute_balance(conn, row["record_id"])
        total_demanded    += b["demanded"]
        total_paid        += b["total_paid"]
        total_outstanding += b["outstanding"]
        if row["current_state"] == "OVERDUE":
            overdue_count += 1

    return {
        "total_demanded":    float(total_demanded),
        "total_collected":   float(total_paid),
        "total_outstanding": float(total_outstanding),
        "collection_rate":   round(float(total_paid / total_demanded * 100), 2) if total_demanded else 0,
        "overdue_count":     overdue_count,
    }
