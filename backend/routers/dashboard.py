"""
routers/dashboard.py — Dashboard Intelligence Aggregator.

RULES.md:
  LAW 9 : Derived/computed metrics (KPIs) are calculated live at query time
          to guarantee absolute truth and eliminate sync lag.
  LAW 7 : tenant_id is read exclusively from JWT via middleware — never from
          the request body.
  LAW 2 : Attribute values are fetched from entity_attribute_values using
          typed value columns (value_number for numeric aggregates).
"""

from __future__ import annotations

import json
import logging

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Request, status

from db import db_conn

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/dashboard", tags=["dashboard"])

# LAW 9: only these aggregate functions may be injected into SQL
_ALLOWED_AGG_FNS: frozenset[str] = frozenset({"SUM", "AVG"})


@router.get("/metrics", summary="Live KPI metrics for the authenticated tenant (LAW 9)")
async def get_dashboard_metrics(
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> list[dict]:
    """
    Fetch all active dashboard widgets and execute their aggregate query logic.
    Widget configuration is stored in dashboard_widgets.query_logic (JSONB).
    Metrics are computed live — no cache layer (LAW 9).
    """
    # LAW 7: tenant_id from JWT only — already validated by TenantMiddleware
    tenant_id = getattr(request.state, "tenant_id", None)
    if not tenant_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Tenant context missing.",
        )

    try:
        widgets = await conn.fetch(
            """
            SELECT widget_code, display_name, metric_type,
                   icon_name, color_scheme, query_logic
            FROM   dashboard_widgets
            WHERE  tenant_id = $1 AND is_active = TRUE
            ORDER  BY sort_order ASC
            """,
            tenant_id,
        )

        results: list[dict] = []

        for w in widgets:
            # query_logic is JSONB but asyncpg may return a string in some driver versions
            logic = w["query_logic"]
            if isinstance(logic, str):
                try:
                    logic = json.loads(logic)
                except json.JSONDecodeError:
                    logger.error(
                        "Widget %s has invalid query_logic JSON — skipping",
                        w["widget_code"],
                    )
                    continue

            entity_code = logic.get("entity_code")
            metric_type = w["metric_type"]

            # Resolve entity_id for this tenant
            entity_id_row = await conn.fetchrow(
                "SELECT entity_id FROM entity_master WHERE entity_code = $1 AND tenant_id = $2",
                entity_code, tenant_id,
            )
            if not entity_id_row:
                logger.warning(
                    "Widget %s references unknown entity '%s' — skipping",
                    w["widget_code"], entity_code,
                )
                continue

            entity_id    = entity_id_row["entity_id"]
            metric_value: float | int = 0

            if metric_type == "COUNT":
                # Optional filter: exclude records in certain workflow states
                wf_filter = logic.get("filter", {}).get("workflow_state", {})
                if wf_filter and "not_in" in wf_filter:
                    states = wf_filter["not_in"]
                    metric_value = await conn.fetchval(
                        """
                        SELECT COUNT(er.record_id)
                        FROM   entity_records er
                        LEFT JOIN workflow_state_log wsl
                               ON wsl.record_id = er.record_id
                              AND wsl.seq_id = (
                                      SELECT MAX(seq_id)
                                      FROM   workflow_state_log
                                      WHERE  record_id = er.record_id
                                  )
                        WHERE  er.entity_id = $1
                          AND  er.tenant_id = $2
                          AND  (wsl.to_state IS NULL
                                OR wsl.to_state NOT IN (SELECT unnest($3::text[])))
                        """,
                        entity_id, tenant_id, states,
                    ) or 0
                else:
                    metric_value = await conn.fetchval(
                        "SELECT COUNT(*) FROM entity_records WHERE entity_id = $1 AND tenant_id = $2",
                        entity_id, tenant_id,
                    ) or 0

            elif metric_type in _ALLOWED_AGG_FNS:
                attr_code  = logic.get("attribute_code")
                filter_obj = logic.get("filter", {})

                attr_id_row = await conn.fetchrow(
                    """
                    SELECT attribute_id
                    FROM   attribute_master
                    WHERE  attribute_code = $1
                      AND  entity_id     = $2
                      AND  tenant_id     = $3
                    """,
                    attr_code, entity_id, tenant_id,
                )
                if not attr_id_row:
                    continue

                attr_id  = attr_id_row["attribute_id"]
                # LAW 9: agg_func validated against allowlist — never interpolated raw
                agg_func = "SUM" if metric_type == "SUM" else "AVG"

                # Build optional sub-filter (parameterised — never f-string interpolated)
                filter_clause = ""
                params: list = [attr_id, tenant_id]

                for attr_filter_code, attr_filter_val in (filter_obj or {}).items():
                    sub_attr_row = await conn.fetchrow(
                        """
                        SELECT attribute_id
                        FROM   attribute_master
                        WHERE  attribute_code = $1
                          AND  entity_id     = $2
                          AND  tenant_id     = $3
                        """,
                        attr_filter_code, entity_id, tenant_id,
                    )
                    if sub_attr_row:
                        filter_clause += (
                            f" AND record_id IN ("
                            f"SELECT record_id FROM entity_attribute_values"
                            f" WHERE attribute_id = ${len(params) + 1}"
                            f"   AND value_text   = ${len(params) + 2})"
                        )
                        params.extend([sub_attr_row["attribute_id"], attr_filter_val])

                # value_number is the correct column for numeric attributes (LAW 2)
                val = await conn.fetchval(
                    f"""
                    SELECT {agg_func}(value_number)
                    FROM   entity_attribute_values
                    WHERE  attribute_id = $1 AND tenant_id = $2{filter_clause}
                    """,
                    *params,
                )
                metric_value = float(val) if val is not None else 0.0

            results.append({
                "code":  w["widget_code"],
                "label": w["display_name"],
                "value": metric_value,
                "type":  metric_type,
                "icon":  w["icon_name"],
                "color": w["color_scheme"],
            })

        return results

    except HTTPException:
        raise
    except Exception:
        logger.error("Dashboard metrics aggregation failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to aggregate dashboard intelligence.",
        )
