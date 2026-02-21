"""
engines/report_engine.py — Declarative report execution engine.

RULES.md:
  LAW 9 : Reports are metadata, never raw SQL. This engine builds the query.
  LAW 8 : Executions are immutable audit events. Logged to report_execution_log.
  LAW 6/7 : Tenant isolation enforced via RLS and session context.

Logic Flow:
  1. Fetch report_master and check report_role_access.
  2. Fetch dimensions, measures, and filters metadata.
  3. Build a parameterized SQL query Joining entity_records + attribute_values.
  4. Apply aggregations (COUNT, SUM, AVG, etc.) per measure.
  5. Enforce safety LIMIT (max_rows).
  6. Execute and return results.
  7. Log execution; if exported, log to security_event_log.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from typing import Any

import asyncpg


class ReportEngine:
    """
    Constructs and executes reports based on declarative metadata.
    No raw SQL is stored in the database or accepted from the user.
    """

    def __init__(self, conn: asyncpg.Connection) -> None:
        self._conn = conn

    async def run(
        self,
        *,
        report_code: str,
        filters: dict[str, Any],
        actor_id: str | None,
        role: str,
        export: bool = False,
        execution_mode: str = "INTERACTIVE",
    ) -> dict:
        """
        Main entry point for report execution.
        """
        # --- 1. Load Metadata & Check Permissions ---
        report = await self._conn.fetchrow(
            """
            SELECT rm.*, er.entity_code as primary_entity_code
            FROM   report_master rm
            JOIN   entity_master er ON er.entity_id = rm.primary_entity_id
            WHERE  rm.report_code = $1
              AND  rm.is_active = TRUE
            LIMIT  1
            """,
            report_code,
        )

        if not report:
            raise ValueError(f"Report '{report_code}' not found or inactive.")

        report_id = report["report_id"]

        # Permission check
        access = await self._conn.fetchrow(
            """
            SELECT can_view, can_export, max_rows_override
            FROM   report_role_access
            WHERE  report_id = $1 AND role_code = $2
            """,
            report_id, role,
        )

        if not access or not access["can_view"]:
            # Log failure to report_execution_log
             await self._log_execution(
                report_id=report_id, actor_id=actor_id, role=role,
                mode=execution_mode, filters=filters, error_code="FORBIDDEN",
                error_message=f"Role '{role}' does not have access to this report."
            )
             raise PermissionError(f"Access denied for role '{role}'")

        if export and not (report["is_exportable"] and access["can_export"]):
            raise PermissionError(f"Export not allowed for report '{report_code}' by role '{role}'")

        # --- 2. Load Dimensions, Measures, Filters ---
        dimensions = await self._conn.fetch(
            "SELECT * FROM report_dimensions WHERE report_id = $1 AND is_active = TRUE ORDER BY sort_order",
            report_id
        )
        measures = await self._conn.fetch(
            "SELECT * FROM report_measures WHERE report_id = $1 AND is_active = TRUE ORDER BY sort_order",
            report_id
        )
        report_filters = await self._conn.fetch(
            "SELECT * FROM report_filters WHERE report_id = $1 AND is_active = TRUE",
            report_id
        )

        # --- 3. Build SQL Query ---
        query_parts = await self._build_sql(
            report=report,
            dimensions=dimensions,
            measures=measures,
            report_filters=report_filters,
            user_filters=filters,
            max_rows=access["max_rows_override"] or report["max_rows"]
        )

        sql = query_parts["sql"]
        params = query_parts["params"]

        # --- 4. Execute ---
        import time
        start_time = time.perf_counter()
        try:
            results = await self._conn.fetch(sql, *params)
            duration_ms = int((time.perf_counter() - start_time) * 1000)

            # --- 5. Log Execution ---
            execution_id = await self._log_execution(
                report_id=report_id,
                actor_id=actor_id,
                role=role,
                mode=execution_mode,
                filters=filters,
                row_count=len(results),
                duration_ms=duration_ms,
                was_exported=export,
                export_format="JSON" if export else None, # Defaulting to JSON for engine level
                query_hash=hashlib.sha256(sql.encode()).hexdigest()
            )

            if export:
                await self._log_security_event(
                    actor_id=actor_id,
                    event_type="REPORT_EXPORT",
                    resource_path=f"reports/{report_code}/export",
                    data={"report_id": str(report_id), "execution_id": str(execution_id)}
                )

            return {
                "report_id": str(report_id),
                "execution_id": str(execution_id),
                "data": [dict(r) for r in results],
                "duration_ms": duration_ms,
                "truncated": len(results) >= (access["max_rows_override"] or report["max_rows"])
            }

        except Exception as e:
             await self._log_execution(
                report_id=report_id, actor_id=actor_id, role=role,
                mode=execution_mode, filters=filters, error_code="SQL_ERROR",
                error_message=str(e)
            )
             raise

    async def _build_sql(self, report, dimensions, measures, report_filters, user_filters, max_rows) -> dict[str, Any]:
        """
        Constructs a fully parameterized SQL string from declarative metadata.

        Rules compliance:
          LAW 9 : No raw SQL — all query structure is derived from metadata rows.
          LAW 6 : Every EAV JOIN scopes to both entity_record_id AND tenant_id.
          SECURITY: All UUID values use $N placeholders — never f-string interpolated.
        """
        params: list[Any] = []

        def add_param(val: Any) -> str:
            """Append val to params list and return the $N placeholder."""
            params.append(val)
            return f"${len(params)}"

        # Tracks attribute_id -> alias to deduplicate LEFT JOINs
        attr_joins: dict = {}   # attribute_id -> alias
        # Accumulates extra param placeholders needed when adding JOINs
        join_params: list[str] = []  # parallel to attr_joins: stores the $N for each attr_id

        def get_attr_alias(attr_id) -> str:
            if attr_id not in attr_joins:
                alias = f"av_{len(attr_joins) + 1}"
                attr_joins[attr_id] = alias
                join_params.append(add_param(attr_id))  # $N placeholder for attribute_id
            return attr_joins[attr_id]

        select_cols: list[str] = []
        group_cols:  list[str] = []

        # --- Process Dimensions ---
        for dim in dimensions:
            if dim["dimension_source"] == "ATTRIBUTE":
                alias = get_attr_alias(dim["attribute_id"])
                attr_meta = await self._conn.fetchrow(
                    """
                    SELECT data_type, attribute_code
                    FROM   attribute_master
                    WHERE  attribute_id = $1
                      AND  tenant_id    = current_setting('app.tenant_id', true)::uuid
                    """,
                    dim["attribute_id"],
                )
                val_col = self._get_val_col(attr_meta["data_type"])
                col_sql = f"{alias}.{val_col}"
                select_cols.append(f'{col_sql} AS "{dim["display_label"]}"')
                group_cols.append(col_sql)
            elif dim["dimension_source"] == "DATE_TRUNC":
                pass  # date_trunc bucketing — extend as needed

        # --- Process Measures ---
        for meas in measures:
            fn = meas["aggregate_fn"]
            if meas["measure_source"] == "RECORD_COUNT":
                select_cols.append(f'COUNT(*) AS "{meas["display_label"]}"')
            elif meas["measure_source"] == "ATTRIBUTE":
                alias = get_attr_alias(meas["attribute_id"])
                attr_meta = await self._conn.fetchrow(
                    """
                    SELECT data_type
                    FROM   attribute_master
                    WHERE  attribute_id = $1
                      AND  tenant_id    = current_setting('app.tenant_id', true)::uuid
                    """,
                    meas["attribute_id"],
                )
                val_col = self._get_val_col(attr_meta["data_type"])
                select_cols.append(f'{fn}({alias}.{val_col}) AS "{meas["display_label"]}"')

        # --- FROM clause ---
        from_clause = "entity_records er"

        # --- EAV LEFT JOINs (LAW 6: scoped to entity_record_id AND tenant_id) ---
        # join_params[i] holds the $N placeholder for the i-th attr_id parameter.
        # We rebuild the mapping here because the $N indices are already locked in params[].
        joins: list[str] = []
        for i, (attr_id, alias) in enumerate(attr_joins.items()):
            attr_placeholder = join_params[i]   # already in params[]
            joins.append(
                f"LEFT JOIN entity_attribute_values {alias}"
                f" ON {alias}.entity_record_id = er.record_id"
                f" AND {alias}.tenant_id        = er.tenant_id"
                f" AND {alias}.attribute_id     = {attr_placeholder}"
            )

        # --- WHERE clause ---
        # Scope to the report's primary entity using a parameterized placeholder (LAW 6).
        entity_id_placeholder = add_param(report["primary_entity_id"])
        where_clauses: list[str] = [f"er.entity_id = {entity_id_placeholder}"]

        # --- Static and user-facing filters ---
        for flt in report_filters:
            if flt["filter_source"] == "ATTRIBUTE":
                alias = get_attr_alias(flt["attribute_id"])
                attr_meta = await self._conn.fetchrow(
                    """
                    SELECT data_type, attribute_code
                    FROM   attribute_master
                    WHERE  attribute_id = $1
                      AND  tenant_id    = current_setting('app.tenant_id', true)::uuid
                    """,
                    flt["attribute_id"],
                )
                val_col = self._get_val_col(attr_meta["data_type"])
                val = (
                    user_filters.get(attr_meta["attribute_code"])
                    if flt["is_user_facing"]
                    else flt["static_value"]
                )
                if val is not None:
                    op  = self._map_operator(flt["operator"])
                    ph  = add_param(val)
                    where_clauses.append(f"{alias}.{val_col} {op} {ph}")

        # --- Assemble ---
        sql = (
            f"SELECT {', '.join(select_cols)}"
            f" FROM {from_clause}"
            f" {' '.join(joins)}"
            f" WHERE {' AND '.join(where_clauses)}"
        )
        if group_cols:
            sql += f" GROUP BY {', '.join(group_cols)}"
        sql += f" LIMIT {int(max_rows)}"   # max_rows is always an int from DB — cast to be safe

        return {"sql": sql, "params": params}

    def _get_val_col(self, data_type: str) -> str:
        """Map attribute_master.data_type to the correct EAV column name."""
        if data_type == "numeric":  return "value_numeric"   # was wrong: 'number'/'value_number'
        if data_type == "boolean":  return "value_bool"
        if data_type == "json":     return "value_json"
        return "value_text"   # text, uuid, date, datetime

    def _map_operator(self, op: str) -> str:
        mapping = {
            "eq": "=", "ne": "!=", "lt": "<", "lte": "<=", "gt": ">", "gte": ">=",
            "contains": "ILIKE", "starts_with": "ILIKE"
        }
        return mapping.get(op, "=")

    async def _log_execution(self, **kwargs):
        tenant_id = await self._conn.fetchval("SELECT current_setting('app.tenant_id', true)::uuid")
        
        # Construct applied_filters snapshot
        applied_filters = {}
        for k, v in kwargs.get("filters", {}).items():
            applied_filters[k] = v

        log_id = await self._conn.fetchval(
            """
            INSERT INTO report_execution_log
            (tenant_id, report_id, actor_id, actor_role_code, execution_mode, 
             applied_filters, row_count, was_exported, export_format, 
             execution_duration_ms, query_hash, error_code, error_message)
            VALUES ($1, $2, $3::uuid, $4, $5, $6::jsonb, $7, $8, $9, $10, $11, $12, $13)
            RETURNING execution_id
            """,
            tenant_id, kwargs.get("report_id"), kwargs.get("actor_id"), 
            kwargs.get("role"), kwargs.get("mode", "INTERACTIVE"),
            json.dumps(applied_filters), kwargs.get("row_count", 0), 
            kwargs.get("was_exported", False), kwargs.get("export_format"),
            kwargs.get("duration_ms"), kwargs.get("query_hash"), 
            kwargs.get("error_code"), kwargs.get("error_message")
        )
        return log_id

    async def _log_security_event(self, **kwargs):
        tenant_id = await self._conn.fetchval("SELECT current_setting('app.tenant_id', true)::uuid")
        await self._conn.execute(
            """
            INSERT INTO security_event_log
            (tenant_id, event_type, actor_id, resource_path, event_data)
            VALUES ($1, $2, $3::uuid, $4, $5::jsonb)
            """,
            tenant_id, kwargs.get("event_type"), kwargs.get("actor_id"),
            kwargs.get("resource_path"), json.dumps(kwargs.get("data", {}))
        )

    async def get_cache_key(self, tenant_id: str, report_id: str, filters: dict) -> str:
        """
        Computes the cache key as per requirements:
        tenant_id:report_id:filters_hash:policy_version:settings_version
        """
        filters_hash = hashlib.sha256(json.dumps(filters, sort_keys=True).encode()).hexdigest()
        
        # Policy version: latest updated_at across all policies
        policy_version = await self._conn.fetchval("SELECT COALESCE(MAX(updated_at), '1970-01-01')::text FROM policy_master")
        
        # Settings version: latest version_number across relevant settings
        settings_version = await self._conn.fetchval("SELECT COALESCE(MAX(version_number), 0) FROM system_settings")
        
        return f"{tenant_id}:{report_id}:{filters_hash}:{policy_version}:{settings_version}"
