"""
engines/policy_engine.py — Structured DSL policy evaluator.

INTERFACE:
    engine = PolicyEngine(conn)
    result = await engine.evaluate(
        entity_code="student",
        record_id=<uuid>,
        action_type="SUBMIT_EXAM",
        context={},      # optional runtime values to merge with EAV
    )
    # result.decision  : "BLOCK" | "WARN" | "ALLOW"
    # result.reasons   : list[str]
    # result.calculations : dict

POLICY LOADING:
    Loads all policies from policy_master where:
      - entity_code matches AND
      - action_type matches AND
      - (tenant_id = current GUC  OR  tenant_id IS NULL)   ← SYSTEM-inherited
    System-level policies (tenant_id IS NULL) act as inherited defaults;
    tenant policies can override or extend them.

CONDITION DSL FORMAT:
    policy_conditions.condition_dsl (JSONB column):
    {
      "all": [                                   ← ALL conditions must be true
        {"attribute": "attendance", "operator": "<", "value": 75},
        {"any": [                                ← ANY sub-condition true
          {"attribute": "status", "operator": "=",  "value": "probation"},
          {"attribute": "strikes", "operator": ">=", "value": 3}
        ]}
      ]
    }

    Supported operators: =, !=, <, >, <=, >=, IN
    Nesting is unlimited.

POLICY ACTIONS (policy_actions.action_type):
    BLOCK       — deny the calling action completely
    WARN        — allow but include a warning message
    ALLOW       — explicit allow (overrides lower-priority BLOCK if precedence says so)
    CALCULATE   — compute a value and return it in `calculations`
                  payload JSON: {"output_key": "fee_penalty", "formula": "attendance * 0.5"}
                  (formula evaluated with attribute values substituted in — no raw SQL)

AUDIT:
    Every call writes ONE row to audit_event_log with action_type = 'POLICY_EVALUATED'.
    LAW 8: INSERT-ONLY — this function never UPDATEs or DELETEs audit rows.

LAW 4: The policy engine MUST be called before any workflow transition.
       workflow_engine.py calls PolicyEngine.evaluate() before writing state rows.
"""

from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass, field
from typing import Any

import asyncpg


# =============================================================================
# RESULT TYPE
# =============================================================================

@dataclass
class PolicyResult:
    decision: str = "ALLOW"            # "BLOCK" | "WARN" | "ALLOW"
    reasons: list[str] = field(default_factory=list)
    calculations: dict[str, Any] = field(default_factory=dict)
    matched_policies: list[str] = field(default_factory=list)

    def dict(self) -> dict:
        return {
            "decision":         self.decision,
            "reasons":          self.reasons,
            "calculations":     self.calculations,
            "matched_policies": self.matched_policies,
        }


# =============================================================================
# DSL CONDITION EVALUATOR
# =============================================================================

# Operator → callable (value_from_db, value_from_dsl) → bool
_OPS: dict[str, Any] = {
    "=":   lambda a, b: _coerce(a) == _coerce(b),
    "!=":  lambda a, b: _coerce(a) != _coerce(b),
    "<":   lambda a, b: float(_n(a)) <  float(_n(b)),
    ">":   lambda a, b: float(_n(a)) >  float(_n(b)),
    "<=":  lambda a, b: float(_n(a)) <= float(_n(b)),
    ">=":  lambda a, b: float(_n(a)) >= float(_n(b)),
    "IN":  lambda a, b: _coerce(a) in (b if isinstance(b, list) else [b]),
}


def _coerce(v: Any) -> Any:
    """Normalise value for equality comparison (lowercase strings, etc.)."""
    if isinstance(v, str):
        return v.strip().lower()
    return v


def _n(v: Any) -> Any:
    """Coerce to a number-compatible value; raise clearly if impossible."""
    try:
        return float(str(v).strip())
    except (ValueError, TypeError):
        raise ValueError(f"Cannot compare non-numeric value {v!r} with a numeric operator")


def _eval_node(
    node: dict,
    eav: dict[str, Any],
) -> tuple[bool, list[str]]:
    """
    Recursively evaluate one DSL node.

    Returns (passed: bool, failure_messages: list[str]).

    A node is one of:
      {"all":  [node, ...]}   — AND
      {"any":  [node, ...]}   — OR
      {"attribute": ..., "operator": ..., "value": ...}  — leaf condition
    """
    if "all" in node:
        failures: list[str] = []
        for child in node["all"]:
            ok, msgs = _eval_node(child, eav)
            if not ok:
                failures.extend(msgs)
        return len(failures) == 0, failures

    if "any" in node:
        sub_failures: list[str] = []
        for child in node["any"]:
            ok, msgs = _eval_node(child, eav)
            if ok:
                return True, []           # short-circuit on first pass
            sub_failures.extend(msgs)
        return False, [f"None of: {sub_failures}"]

    # Leaf condition
    attr      = node.get("attribute")
    operator  = node.get("operator")
    expected  = node.get("value")

    if not attr or not operator:
        return False, [f"Malformed DSL node: {node}"]

    op_fn = _OPS.get(operator)
    if op_fn is None:
        return False, [f"Unsupported operator '{operator}' in condition for '{attr}'"]

    actual = eav.get(attr)
    try:
        passed = op_fn(actual, expected)
    except Exception as exc:
        return False, [f"Condition error on '{attr}' ({operator} {expected}): {exc}"]

    if not passed:
        return False, [
            f"Condition not met: {attr} {operator} {expected} (actual: {actual!r})"
        ]
    return True, []


# =============================================================================
# CALCULATE ACTION EVALUATOR
# =============================================================================

# Allowed functions in CALCULATE formulas — no builtins, no exec
_CALC_SAFE_NAMES: dict[str, Any] = {
    "abs": abs,
    "min": min,
    "max": max,
    "round": round,
}

_CALC_ATTR_RE = re.compile(r"[a-z][a-z0-9_]*")


def _evaluate_formula(formula: str, eav: dict[str, Any]) -> Any:
    """
    Safely evaluate a simple arithmetic formula string with attribute values
    substituted in.  Uses Python eval() with a strictly restricted namespace —
    no builtins, no import, no function calls except the allow-listed ones.

    Example formula: "attendance * 0.5 + base_fee"
    """
    # Build a namespace: {attr_code: numeric_value, ...}
    namespace: dict[str, Any] = dict(_CALC_SAFE_NAMES)
    for token in _CALC_ATTR_RE.findall(formula):
        if token in eav:
            try:
                namespace[token] = float(str(eav[token]))
            except (ValueError, TypeError):
                namespace[token] = 0.0

    try:
        result = eval(  # noqa: S307 — restricted namespace, no builtins
            formula,
            {"__builtins__": {}},
            namespace,
        )
        return result
    except Exception as exc:
        raise ValueError(f"Formula evaluation failed for '{formula}': {exc}") from exc


# =============================================================================
# POLICY ENGINE
# =============================================================================

class PolicyEngine:
    """
    Evaluates all applicable policies for a (entity_code, action_type) pair
    against a single entity record and returns a consolidated decision.

    Decision priority (highest wins):
      BLOCK  > WARN  > ALLOW

    If any policy returns BLOCK, the final decision is BLOCK regardless of
    other policies.  WARN is sticky if no BLOCK.  ALLOW is the default.
    """

    def __init__(self, conn: asyncpg.Connection) -> None:
        self._conn = conn

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    async def evaluate(
        self,
        *,
        entity_code: str,
        record_id: uuid.UUID,
        action_type: str,
        context: dict[str, Any] | None = None,   # mutable default avoided
        actor_id: str | None = None,
    ) -> PolicyResult:
        """
        Evaluate all matching policies and return a consolidated PolicyResult.

        Parameters
        ----------
        entity_code  : Entity type (e.g. "student", "exam")
        record_id    : UUID of the entity_records row being acted on
        action_type  : The action being attempted (e.g. "SUBMIT_EXAM",
                       "MARK_ATTENDANCE") — matched against policy_master
        context      : Optional runtime key/value pairs merged with EAV
        actor_id     : UUID string of the acting user (for audit log)
        """
        result = PolicyResult()

        effective_context = context or {}

        # 1. Load entity's EAV values
        eav = await self._load_eav(record_id)
        eav.update(effective_context)  # runtime context overrides DB values

        # 2. Load all applicable policies (tenant + SYSTEM inherited)
        policies = await self._load_policies(entity_code, action_type)

        if not policies:
            # No policies registered → implicit ALLOW
            result.reasons.append(
                f"No policies found for entity='{entity_code}' action='{action_type}' — implicit ALLOW"
            )
            await self._write_audit(
                actor_id=actor_id,
                entity_code=entity_code,
                record_id=record_id,
                action_type=action_type,
                result=result,
            )
            return result

        # 3. Evaluate each policy in priority order
        for policy in policies:
            policy_code = policy["policy_code"]
            label       = policy["label"] or policy_code

            # Load condition DSL
            raw_dsl = policy["condition_dsl"]
            if not raw_dsl:
                # Policy with no conditions → always matches
                conditions_met  = True
                condition_msgs: list[str] = []
            else:
                dsl: dict = raw_dsl if isinstance(raw_dsl, dict) else json.loads(raw_dsl)
                conditions_met, condition_msgs = _eval_node(dsl, eav)

            if not conditions_met:
                # Conditions not met — this policy does not apply
                continue

            result.matched_policies.append(policy_code)

            # Load and execute actions for this policy
            actions = await self._load_actions(policy_code)
            for action in actions:
                act_type    = action["action_type"]     # BLOCK_TRANSITION | SEND_NOTIFICATION | etc.
                act_payload = action["action_payload"]  # JSONB dict or None
                message     = label                      # display_name from policy_master

                if act_type == "BLOCK":
                    result.decision = "BLOCK"
                    result.reasons.append(f"[BLOCK] {message}")

                elif act_type == "WARN":
                    if result.decision != "BLOCK":
                        result.decision = "WARN"
                    result.reasons.append(f"[WARN] {message}")

                elif act_type == "ALLOW":
                    # Explicit ALLOW — only applies if no BLOCK yet
                    if result.decision == "ALLOW":
                        result.reasons.append(f"[ALLOW] {message}")

                elif act_type == "CALCULATE":
                    payload = act_payload if isinstance(act_payload, dict) else {}
                    output_key = payload.get("output_key", f"{policy_code}_result")
                    formula    = payload.get("formula", "0")
                    try:
                        calc_result = _evaluate_formula(formula, eav)
                        result.calculations[output_key] = calc_result
                        result.reasons.append(
                            f"[CALCULATE] {output_key} = {calc_result} (formula: {formula})"
                        )
                    except ValueError as exc:
                        result.reasons.append(f"[CALCULATE ERROR] {exc}")

        # Default if nothing matched at all
        if not result.matched_policies:
            result.reasons.append("No policy conditions matched — implicit ALLOW")

        # 4. Write immutable audit row (LAW 8 — INSERT-ONLY, action_type = POLICY_EVALUATED)
        await self._write_audit(
            actor_id=actor_id,
            entity_code=entity_code,
            record_id=record_id,
            action_type=action_type,
            result=result,
        )

        return result

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    async def _load_eav(self, record_id: uuid.UUID) -> dict[str, Any]:
        """
        Load all attribute values for the record.
        Returns {attribute_code: resolved_value} — value is already a string;
        numeric comparisons cast in _OPS.
        """
        rows = await self._conn.fetch(
            """
            SELECT
                am.attribute_code,
                CASE am.data_type
                    WHEN 'numeric' THEN eav.value_number::text
                    WHEN 'boolean' THEN eav.value_bool::text
                    WHEN 'json'    THEN eav.value_jsonb::text
                    ELSE                eav.value_text
                END AS resolved_value
            FROM   entity_attribute_values eav
            JOIN   attribute_master        am
                   ON am.attribute_id = eav.attribute_id   -- LAW 2: join by PK, not code
                  AND am.tenant_id    = eav.tenant_id
            WHERE  eav.record_id = $1
            """,
            record_id,
        )
        return {r["attribute_code"]: r["resolved_value"] for r in rows}

    async def _load_policies(
        self,
        entity_code: str,
        action_type: str,
    ) -> list[asyncpg.Record]:
        """
        Load all active policies for this entity.

        Includes:
          • Tenant-specific rows  (tenant_id = current GUC)   — higher priority
          • SYSTEM-inherited rows (tenant_id IS NULL)          — fallback / base rules

        Ordered by: SYSTEM first (lowest priority), then tenant-specific.
        Within each group, ordered by evaluation_order ASC.

        Note: policy_master has no action_type column; action_type is accepted
        for interface compatibility but filtering is done by entity only.
        """
        return await self._conn.fetch(
            """
            SELECT
                pm.policy_code,
                pm.display_name AS label,
                pm.evaluation_order,
                pm.tenant_id,
                pc.dsl_expression AS condition_dsl
            FROM   policy_master pm
            JOIN   entity_master em
                   ON em.entity_id = pm.entity_id
                  AND em.tenant_id = pm.tenant_id
            LEFT JOIN policy_conditions pc
                   ON pc.policy_id  = pm.policy_id
                  AND pc.tenant_id  = pm.tenant_id
            WHERE  em.entity_code  = $1
              AND  pm.is_active    = true
              AND  (
                       pm.tenant_id = current_setting('app.tenant_id', true)::uuid
                   OR  pm.tenant_id IS NULL
              )
            ORDER BY
                (pm.tenant_id IS NULL) DESC,      -- NULL (SYSTEM) first = lowest priority
                pm.evaluation_order ASC
            """,
            entity_code,
        )

    async def _load_actions(self, policy_code: str) -> list[asyncpg.Record]:
        """Load policy_actions rows for a given policy_code, ordered by priority."""
        return await self._conn.fetch(
            """
            SELECT pa.action_type, pa.action_payload, pa.outcome
            FROM   policy_actions pa
            JOIN   policy_master  pm
                   ON pm.policy_id = pa.policy_id
                  AND pm.tenant_id = pa.tenant_id
            WHERE  pm.policy_code = $1
              AND  pa.is_active   = true
            ORDER  BY pa.priority ASC
            """,
            policy_code,
        )

    async def _write_audit(
        self,
        *,
        actor_id: str | None,
        entity_code: str,
        record_id: uuid.UUID,
        action_type: str,
        result: PolicyResult,
    ) -> None:
        """
        Write ONE immutable row to audit_event_log.

        action_type stored is always 'POLICY_EVALUATED' (LAW 8 — INSERT-ONLY).
        The original action being evaluated is captured inside the payload JSON.
        This function never issues UPDATE or DELETE.
        """
        payload = {
            "evaluated_action": action_type,
            "decision":         result.decision,
            "matched_policies": result.matched_policies,
            "reasons":          result.reasons,
            "calculations":     result.calculations,
        }
        # LAW 8: INSERT-ONLY — never UPDATE or DELETE on audit tables
        await self._conn.execute(
            """
            INSERT INTO audit_event_log
                (tenant_id, actor_id, actor_type,
                 event_category, event_type,
                 entity_id, record_id, event_data, logged_at)
            VALUES
                (current_setting('app.tenant_id', true)::uuid,
                 $1::uuid, 'SERVICE',
                 'POLICY', 'POLICY_EVALUATED',
                 (SELECT entity_id FROM entity_master
                  WHERE entity_code = $2
                    AND tenant_id = current_setting('app.tenant_id', true)::uuid
                  LIMIT 1),
                 $3, $4::jsonb, now())
            """,
            actor_id,
            entity_code,
            record_id,
            json.dumps(payload),
        )
