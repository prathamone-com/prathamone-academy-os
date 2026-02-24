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
    Includes entity_code from entity_master so the frontend can POST without
    hardcoding any entity identifiers (LAW UI-7).
    """
    # 1. Fetch form master + entity_code from entity_master join
    form = await conn.fetchrow(
        """
        SELECT fm.*, em.entity_code
        FROM   form_master fm
        JOIN   entity_master em ON em.entity_id = fm.entity_id
                                AND em.tenant_id = fm.tenant_id
        WHERE  fm.form_code = $1
          AND  fm.is_active = TRUE
        """,
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

    # 3. Fetch fields for each section, including attribute label + validation_rule
    results = []
    for section in sections:
        fields = await conn.fetch(
            """
            SELECT
                ff.*,
                am.attribute_code,
                am.display_label    AS attr_display_label,
                am.data_type,
                am.validation_rule  AS base_validation,
                am.is_required      AS attr_required
            FROM   form_fields ff
            JOIN   attribute_master am ON am.attribute_id = ff.attribute_id
                                      AND am.tenant_id    = ff.tenant_id
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

