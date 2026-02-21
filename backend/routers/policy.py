"""
routers/policy.py — Policy evaluation endpoint.

LAW 4: Policies evaluate BEFORE workflow transitions. Policies win.
LAW 5: Policies decide IF. Workflows decide WHEN. Settings decide DEFAULT.
"""

from __future__ import annotations

import uuid

import asyncpg
from fastapi import APIRouter, Depends
from pydantic import BaseModel

from db import db_conn
from engines.policy_engine import PolicyEngine

router = APIRouter(prefix="/policy", tags=["policy"])


class EvaluationRequest(BaseModel):
    policy_code: str
    entity_record_id: uuid.UUID
    entity_code: str
    context: dict = {}


class EvaluationResult(BaseModel):
    policy_code: str
    allowed: bool
    matched_conditions: list[str]
    actions_triggered: list[str]
    reason: str | None = None


@router.post("/evaluate", response_model=EvaluationResult, summary="Evaluate a policy against an entity record")
async def evaluate_policy(
    body: EvaluationRequest,
    conn: asyncpg.Connection = Depends(db_conn),
) -> EvaluationResult:
    """
    Evaluate the named policy against the given entity record and context.

    The policy engine:
      1. Loads policy_conditions rows for the policy_code.
      2. Evaluates each condition against entity_attribute_values (EAV).
      3. Returns allowed = True only if ALL conditions pass.
      4. If allowed, looks up and returns applicable policy_actions.
      5. Writes an immutable row to policy_evaluation_log (LAW 8).
    """
    engine = PolicyEngine(conn)
    return await engine.evaluate(
        policy_code=body.policy_code,
        entity_record_id=body.entity_record_id,
        entity_code=body.entity_code,
        context=body.context,
    )


@router.get("/{policy_code}", summary="Describe a policy's conditions and actions")
async def describe_policy(
    policy_code: str,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """Return the policy definition including all conditions and actions."""
    policy = await conn.fetchrow(
        "SELECT * FROM policy_master WHERE policy_code = $1",
        policy_code,
    )
    if not policy:
        from fastapi import HTTPException, status
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")

    conditions = await conn.fetch(
        "SELECT * FROM policy_conditions WHERE policy_code = $1 ORDER BY sort_order",
        policy_code,
    )
    actions = await conn.fetch(
        "SELECT * FROM policy_actions WHERE policy_code = $1 ORDER BY sort_order",
        policy_code,
    )

    return {
        "policy": dict(policy),
        "conditions": [dict(c) for c in conditions],
        "actions": [dict(a) for a in actions],
    }
