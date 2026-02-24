"""
engines/workflow_engine.py — Data-driven state transition executor.

RULES.md:
  LAW 3 : No if(status == X) in code. Valid transitions must be rows in the
          workflow_transitions table.
  LAW 4 : Policies evaluate BEFORE workflow transitions. BLOCK decision
          from PolicyEngine aborts the transition immediately.
  LAW 8 : Transitions are mandatory audit events. Every successful move
          writes to both workflow_state_log and audit_event_log.

Logic Flow:
  1. Load current state from entity_records.current_state_id.
  2. Find valid transition for (current_state, action_label).
  3. Verify current actor role has permission (actor_roles check).
  4. Call PolicyEngine.evaluate(action_type=action_label) — FIRST.
  5. If ALLOW/WARN, perform UPDATE on entity_records.
  6. Insert into workflow_state_log and audit_event_log.
"""

from __future__ import annotations

import json
import uuid
from typing import Any

import asyncpg
from engines.policy_engine import PolicyEngine


# Sentinel for records that have not yet entered any state (LAW 3)
_INITIAL_STATE = "INITIAL"


class WorkflowEngine:
    """
    Executes state transitions for any entity governed by a workflow.

    The engine contains NO hard-coded state logic. All valid edges
    are read from the database at runtime.
    """

    def __init__(self, conn: asyncpg.Connection) -> None:
        self._conn = conn

    async def transition(
        self,
        *,
        entity_code: str,
        record_id: uuid.UUID,
        action_label: str,          # matches workflow_transitions.trigger_event
        actor_id: str | None = None,
        role: str = "app_user",
        context: dict[str, Any] | None = None,  # mutable default avoided
    ) -> dict:
        """
        Attempt to move an entity record to its next state.

        Aborts if:
          - No valid transition exists for the current state + action.
          - The current state is terminal.
          - The actor role is not authorised for this specific edge.
          - The policy engine returns BLOCK (LAW 4).
        """
        effective_context = context or {}

        # --- 1. Load current state from entity_records ---
        record = await self._conn.fetchrow(
            """
            SELECT er.current_state_id, ws.state_code,
                   (ws.state_type = 'terminal') AS is_terminal
            FROM   entity_records er
            JOIN   entity_master  em ON em.entity_id = er.entity_id
                                    AND em.tenant_id = er.tenant_id
            LEFT JOIN workflow_states ws ON ws.state_id = er.current_state_id
                                       AND ws.tenant_id = er.tenant_id
            WHERE  er.record_id   = $1
              AND  em.entity_code = $2
            """,
            record_id, entity_code,
        )

        if not record:
            return {"allowed": False, "reason": "Record not found"}

        current_state_id   = record["current_state_id"]
        current_state_code = record["state_code"] or _INITIAL_STATE
        is_terminal        = record["is_terminal"] or False

        # --- 2. Check if terminal ---
        if is_terminal:
            return {
                "allowed": False,
                "reason": (
                    f"Record is in terminal state '{current_state_code}'"
                    " and cannot transition further."
                ),
            }

        # --- 3. Find valid transition (LAW 3: validated against DB rows) ---
        transition = await self._conn.fetchrow(
            """
            SELECT wt.transition_id, wt.to_state, wt.guard_policy_id, wt.actor_roles
            FROM   workflow_transitions wt
            JOIN   workflow_master      wm ON wm.workflow_id = wt.workflow_id
                                          AND wm.tenant_id   = wt.tenant_id
            JOIN   entity_master        em ON em.entity_id   = wm.entity_id
                                          AND em.tenant_id   = wm.tenant_id
            WHERE  em.entity_code    = $1
              AND  wt.from_state     = $2
              AND  wt.trigger_event  = $3
              AND  wt.tenant_id      = current_setting('app.tenant_id', true)::uuid
            LIMIT  1
            """,
            entity_code, current_state_code, action_label,
        )

        if not transition:
            return {
                "allowed": False,
                "reason": (
                    f"No valid transition from '{current_state_code}'"
                    f" via action '{action_label}'"
                ),
            }

        # --- 4. Verify Role Permission ---
        allowed_roles = transition["actor_roles"] or []
        if allowed_roles and role not in allowed_roles:
            return {
                "allowed": False,
                "reason": (
                    f"Role '{role}' is not authorised for this transition."
                    f" Allowed: {allowed_roles}"
                ),
            }

        # --- 5. Call Policy Engine FIRST (LAW 4) ---
        policy_engine  = PolicyEngine(self._conn)
        policy_result  = await policy_engine.evaluate(
            entity_code=entity_code,
            record_id=record_id,
            action_type=action_label,
            context=effective_context,
            actor_id=actor_id,
        )

        if policy_result.decision == "BLOCK":
            return {
                "allowed": False,
                "reason": f"Blocked by policy engine: {'; '.join(policy_result.reasons)}",
                "policy_result": policy_result.dict(),
            }

        # --- 6. Execute: Resolve to_state UUID and update record ---
        to_state_row = await self._conn.fetchrow(
            """
            SELECT state_id FROM workflow_states
            WHERE  state_code = $1
              AND  tenant_id  = current_setting('app.tenant_id', true)::uuid
            LIMIT  1
            """,
            transition["to_state"],
        )
        if not to_state_row:
            return {
                "allowed": False,
                "reason": f"Target state '{transition['to_state']}' not found in registry",
            }

        new_state_id = to_state_row["state_id"]

        await self._conn.execute(
            """
            UPDATE entity_records
            SET    current_state_id = $1,
                   updated_at       = now()
            WHERE  record_id = $2
              AND  tenant_id = current_setting('app.tenant_id', true)::uuid
            """,
            new_state_id, record_id,
        )

        # --- 7. Mandatory Audit Logs (LAW 8: INSERT-ONLY) ---
        # a. workflow_state_log
        await self._conn.execute(
            """
            INSERT INTO workflow_state_log
                (tenant_id, workflow_id, record_id, from_state, to_state,
                 trigger_event, actor_id, transition_at)
            SELECT tenant_id, workflow_id, $1, $2, $3, $4, $5::uuid, now()
            FROM   workflow_transitions
            WHERE  transition_id = $6
            """,
            record_id, current_state_code, transition["to_state"],
            action_label, actor_id, transition["transition_id"],
        )

        # b. audit_event_log — uses record_id per schema (LAW 8)
        await self._conn.execute(
            """
            INSERT INTO audit_event_log
                (tenant_id, actor_id, actor_type,
                 event_category, event_type,
                 entity_id, record_id, event_data, logged_at)
            VALUES
                (current_setting('app.tenant_id', true)::uuid,
                 $1::uuid, 'USER',
                 'WORKFLOW', 'STATE_TRANSITION',
                 (SELECT entity_id FROM entity_master
                  WHERE entity_code = $2
                    AND tenant_id = current_setting('app.tenant_id', true)::uuid
                  LIMIT 1),
                 $3, $4::jsonb, now())
            """,
            actor_id, entity_code, record_id,
            json.dumps({
                "from_state":      current_state_code,
                "to_state":        transition["to_state"],
                "trigger":         action_label,
                "policy_decision": policy_result.decision,
            }),
        )

        return {
            "allowed":        True,
            "decision":       policy_result.decision,
            "from_state":     current_state_code,
            "to_state":       transition["to_state"],
            "policy_reasons": policy_result.reasons,
        }

    async def get_available_transitions(
        self,
        *,
        entity_code: str,
        record_id: uuid.UUID,
        role: str = "app_user",
    ) -> list[dict]:
        """
        Returns all possible actions for the current record state,
        filtered by the actor's role.
        """
        record = await self._conn.fetchrow(
            """
            SELECT ws.state_code
            FROM   entity_records er
            JOIN   entity_master  em ON em.entity_id = er.entity_id
                                    AND em.tenant_id = er.tenant_id
            LEFT JOIN workflow_states ws ON ws.state_id = er.current_state_id
            WHERE  er.record_id = $1 AND em.entity_code = $2
            """,
            record_id, entity_code,
        )
        current_state_code = (record["state_code"] if record and record["state_code"] else _INITIAL_STATE)

        transitions = await self._conn.fetch(
            """
            SELECT wt.trigger_event as action, wt.to_state, wt.actor_roles, wt.display_label
            FROM   workflow_transitions wt
            JOIN   workflow_master      wm ON wm.workflow_id = wt.workflow_id
                                          AND wm.tenant_id   = wt.tenant_id
            JOIN   entity_master        em ON em.entity_id   = wm.entity_id
                                          AND em.tenant_id   = wm.tenant_id
            WHERE  em.entity_code = $1
              AND  wt.from_state  = $2
              AND  wt.tenant_id   = current_setting('app.tenant_id', true)::uuid
            """,
            entity_code, current_state_code,
        )

        return [
            {
                "action":   t["action"],
                "to_state": t["to_state"],
                "label":    t["display_label"] or t["action"],
            }
            for t in transitions
            if not t["actor_roles"] or role in t["actor_roles"]
        ]
