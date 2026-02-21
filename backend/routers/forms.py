"""
routers/forms.py — Declarative form metadata router.

LAW 11 : New modules = data, not tables.
LAW 9  : Reports/Forms are metadata-driven.
"""

from __future__ import annotations

import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from db import db_conn, asyncpg

router = APIRouter(prefix="/forms", tags=["forms"])

@router.get("/{form_code}")
async def get_form_metadata(
    form_code: str,
    conn: asyncpg.Connection = Depends(db_conn),
) -> dict:
    """
    Returns the full structure of a form: sections and fields.
    """
    # 1. Fetch form master
    form = await conn.fetchrow(
        "SELECT * FROM form_master WHERE form_code = $1 AND is_active = TRUE",
        form_code,
    )
    if not form:
        raise HTTPException(status_code=404, detail=f"Form '{form_code}' not found")

    form_id = form["form_id"]

    # 2. Fetch sections
    sections = await conn.fetch(
        "SELECT * FROM form_sections WHERE form_id = $1 ORDER BY sort_order",
        form_id,
    )

    # 3. Fetch fields for each section
    # We join with attribute_master to get data_type and validation_rule
    results = []
    for section in sections:
        fields = await conn.fetch(
            """
            SELECT ff.*, am.attribute_code, am.data_type, am.validation_rule as base_validation
            FROM   form_fields ff
            JOIN   attribute_master am ON am.attribute_id = ff.attribute_id
            WHERE  ff.section_id = $1
            ORDER BY ff.sort_order
            """,
            section["section_id"],
        )
        
        results.append({
            "section": dict(section),
            "fields": [dict(f) for f in fields]
        })

    return {
        "form": dict(form),
        "structure": results
    }
