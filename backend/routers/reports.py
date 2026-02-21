"""
routers/reports.py — Declarative report execution.

LAW 9: Reports are declarative metadata. No raw SQL in feature code.
       The report engine reads dimension/measure/filter metadata from the
       report_* tables and constructs a safe, parameterised query at runtime.
"""

from __future__ import annotations

import uuid
from typing import Any

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from db import db_conn
from engines.report_engine import ReportEngine

router = APIRouter(prefix="/reports", tags=["reports"])


class ReportRunRequest(BaseModel):
    report_code: str
    filters: dict[str, Any] = {}
    export: bool = False


class ReportRunResponse(BaseModel):
    report_code: str
    columns: list[str]
    rows: list[dict]
    row_count: int
    execution_id: uuid.UUID


@router.post("/run", response_model=ReportRunResponse, summary="Execute a declarative report")
async def run_report(
    body: ReportRunRequest,
    conn: asyncpg.Connection = Depends(db_conn),
) -> ReportRunResponse:
    """
    Execute a report definition stored in report_master.

    The report engine:
      1. Loads report_master, report_dimensions, report_measures, report_filters.
      2. Builds a parameterised query from metadata — NO raw SQL from clients.
      3. Executes the query under the current tenant context (RLS enforced).
      4. Appends an immutable row to report_execution_log.
      5. Returns columns + row data.

    LAW 9 is enforced: the caller sends filter values (scalars), never SQL.
    """
    engine = ReportEngine(conn)
    return await engine.run(
        report_code=body.report_code,
        filters=body.filters,
        export=body.export,
    )


@router.get("/", summary="List available reports")
async def list_reports(
    conn: asyncpg.Connection = Depends(db_conn),
) -> list[dict]:
    """Return all report definitions visible to the current tenant (incl. system templates)."""
    rows = await conn.fetch(
        """
        SELECT report_code, display_name, description, is_active
        FROM   report_master
        WHERE  is_active = true
        ORDER  BY display_name
        """
    )
    return [dict(r) for r in rows]


@router.get("/{report_code}", summary="Describe a report definition")
async def describe_report(
    report_code: str,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """Return full metadata for a report: dimensions, measures, and filters."""
    report = await conn.fetchrow(
        "SELECT * FROM report_master WHERE report_code = $1 AND is_active = true",
        report_code,
    )
    if not report:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found")

    report_id = report["report_id"]
    dimensions = await conn.fetch(
        "SELECT * FROM report_dimensions WHERE report_id = $1 ORDER BY sort_order",
        report_id,
    )
    measures = await conn.fetch(
        "SELECT * FROM report_measures WHERE report_id = $1 ORDER BY sort_order",
        report_id,
    )
    filters = await conn.fetch(
        "SELECT * FROM report_filters WHERE report_id = $1 ORDER BY sort_order",
        report_id,
    )

    return {
        "report": dict(report),
        "dimensions": [dict(d) for d in dimensions],
        "measures": [dict(m) for m in measures],
        "filters": [dict(f) for f in filters],
    }
