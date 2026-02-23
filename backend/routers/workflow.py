"""
routers/workflow.py — State transition endpoint.

LAW 3: No if(status == ...) in code. Transitions are driven by rows in the
        workflow_transitions table, evaluated by workflow_engine.py.
LAW 4: Policies evaluate BEFORE workflow transitions.
"""

import uuid

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel

from db import db_conn
from engines.workflow_engine import WorkflowEngine

router = APIRouter(prefix="/workflow", tags=["workflow"])


class TransitionRequest(BaseModel):
    entity_record_id: uuid.UUID
    entity_code: str
    target_state_code: str
    actor_id: uuid.UUID | None = None
    context: dict = {}


@router.post("/transition", summary="Trigger a workflow state transition")
async def trigger_transition(
    body: TransitionRequest,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """
    Attempt a workflow state transition for an entity record.
    Mutations occur via the PL/pgSQL Kernel (LAW 12), ensuring 
    forensic-grade audit and policy enforcement.
    """
    try:
        await conn.execute(
            "SELECT execute_workflow_transition($1, $2, $3::uuid, $4::uuid)",
            body.entity_code,
            body.target_state_code,
            body.actor_id or uuid.uuid4(),  # system actor if none
            body.entity_record_id,
        )
        return {"status": "success", "to_state": body.target_state_code}
    except asyncpg.RaiseError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc)
        )


@router.get("/state/{entity_code}/{record_id}", summary="Get current workflow state")
async def get_state(
    entity_code: str,
    record_id: uuid.UUID,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """Return the current workflow state for a given entity record."""
    row = await conn.fetchrow(
        """
        SELECT
            ws.state_code,
            ws.label,
            ws.is_terminal,
            wis.entered_at
        FROM   workflow_instance_state wis
        JOIN   workflow_states         ws  ON ws.state_id  = wis.current_state_id
                                          AND ws.tenant_id = wis.tenant_id
        JOIN   workflow_master         wm  ON wm.workflow_id = wis.workflow_id
                                          AND wm.tenant_id   = wis.tenant_id
                                          AND wm.entity_code = $2
        WHERE  wis.record_id = $1
        ORDER  BY wis.entered_at DESC
        LIMIT  1
        """,
        record_id, entity_code,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No workflow state found for record")
    return dict(row)


@router.get("/history/{entity_code}/{record_id}", summary="Get workflow state history")
async def get_history(
    entity_code: str,
    record_id: uuid.UUID,
    conn: asyncpg.Connection = Depends(db_conn),
) -> list[dict]:
    """Return the full immutable state-change history from workflow_state_log."""
    rows = await conn.fetch(
        """
        SELECT
            ws_new.state_code          AS state_code,
            ws_prev.state_code         AS previous_state_code,
            wsl.actor_id,
            wsl.transitioned_at
        FROM   workflow_state_log wsl
        JOIN   workflow_states ws_new  ON ws_new.state_id  = wsl.to_state_id
                                      AND ws_new.tenant_id = wsl.tenant_id
        LEFT JOIN workflow_states ws_prev ON ws_prev.state_id  = wsl.from_state_id
                                         AND ws_prev.tenant_id = wsl.tenant_id
        WHERE  wsl.record_id   = $1
          AND  wsl.entity_code = $2
        ORDER  BY wsl.transitioned_at ASC
        """,
        record_id, entity_code,
    )
    return [dict(r) for r in rows]


@router.get("/available-transitions/{entity_code}/{record_id}", summary="Get available transitions")
async def get_available_transitions(
    entity_code: str,
    record_id: uuid.UUID,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> list[dict]:
    """Return possible actions for the current record state and user role."""
    role = getattr(request.state, "role", "app_user")
    engine = WorkflowEngine(conn)
    return await engine.get_available_transitions(
        entity_code=entity_code,
        record_id=record_id,
        role=role
    )
