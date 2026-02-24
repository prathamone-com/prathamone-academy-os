"""
routers/attendance.py — Bulk attendance marking.

RULES.md:
  LAW 1 : ATTENDANCE_RECORD is a first-class Sovereign Entity. Each record
          is created via the kernel function, not raw INSERT.
  LAW 3 : Workflow transitions are metadata-driven rows — no hard-coded status logic.
  LAW 8 : The kernel function + execute_workflow_transition emit audit events
          on every create/transition (INSERT-ONLY).
  LAW 9 : Computed stats (percentage) are calculated live at query time.
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import date
from typing import Optional

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel

from db import db_conn

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/attendance", tags=["attendance"])

# Fallback actor for system-initiated operations (no authenticated user)
_SYSTEM_ACTOR_ID: uuid.UUID = uuid.UUID("00000000-0000-0000-0000-000000000001")


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class AttendanceEntry(BaseModel):
    student_id: uuid.UUID
    status: str           # PRESENT | ABSENT | LATE | EXCUSED
    remarks: Optional[str] = None


class BulkAttendanceRequest(BaseModel):
    attendance_date: date
    entries: list[AttendanceEntry]


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post(
    "/bulk",
    status_code=status.HTTP_201_CREATED,
    summary="Bulk mark attendance for multiple students",
)
async def mark_bulk_attendance(
    req: BulkAttendanceRequest,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
):
    """
    Creates ATTENDANCE_RECORD entities for multiple students.
    Each entry is a first-class Sovereign Entity (LAW 1).
    Workflow transitions are metadata-driven (LAW 3).
    Audit events are emitted by the kernel functions (LAW 8).
    """
    # 1. Verify entity registration
    entity_exists = await conn.fetchval(
        "SELECT 1 FROM entity_master WHERE entity_code = 'ATTENDANCE_RECORD'"
    )
    if not entity_exists:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="ATTENDANCE_RECORD entity not registered in registry.",
        )

    # 2. Resolve Actor (LAW 7: user_id from JWT only — never from request body)
    user_id_str = getattr(request.state, "user_id", None)
    actor_id: uuid.UUID = (
        uuid.UUID(user_id_str) if user_id_str else _SYSTEM_ACTOR_ID
    )

    # 3. Process each entry
    results: list[str] = []
    for entry in req.entries:
        attributes = [
            {"attribute_code": "student_record_id", "value": str(entry.student_id)},
            {"attribute_code": "attendance_date",   "value": req.attendance_date.isoformat()},
            {"attribute_code": "status",            "value": entry.status},
        ]
        if entry.remarks:
            attributes.append({"attribute_code": "remarks", "value": entry.remarks})

        try:
            # Call kernel function — creates entity_record + EAV rows atomically (LAW 1, LAW 8)
            record_id = await conn.fetchval(
                "SELECT create_entity_record('ATTENDANCE_RECORD', $1::jsonb, $2::uuid)",
                json.dumps(attributes),
                actor_id,
            )

            # Workflow: NULL → DRAFT (LAW 3: transitions from workflow_transitions table)
            await conn.execute(
                "SELECT execute_workflow_transition('ATTENDANCE_RECORD', $1::uuid, 'DRAFT', $2::uuid)",
                record_id, actor_id,
            )
            # Workflow: DRAFT → MARKED (LAW 3)
            await conn.execute(
                "SELECT execute_workflow_transition('ATTENDANCE_RECORD', $1::uuid, 'MARKED', $2::uuid)",
                record_id, actor_id,
            )

            results.append(str(record_id))

        except Exception:
            logger.error(
                "Failed to mark attendance for student %s",
                entry.student_id, exc_info=True,
            )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Attendance marking failed for student {entry.student_id}. See server logs.",
            )

    return {"status": "success", "count": len(results), "record_ids": results}


@router.get("/stats/{student_id}", summary="Attendance percentage for a student (LAW 9)")
async def get_student_stats(
    student_id: uuid.UUID,
    conn: asyncpg.Connection = Depends(db_conn),
):
    """
    Computes attendance percentage live at query time — never cached (LAW 9).
    """
    stats = await conn.fetchrow(
        """
        WITH attendance_data AS (
            SELECT eav_status.value_text AS status
            FROM entity_records           er
            JOIN entity_master            em  ON em.entity_id = er.entity_id
            JOIN entity_attribute_values  eav_sid
                 ON eav_sid.record_id = er.record_id
                AND eav_sid.attribute_id = (
                        SELECT attribute_id
                        FROM   attribute_master
                        WHERE  attribute_code = 'student_record_id'
                          AND  entity_id      = em.entity_id
                    )
            JOIN entity_attribute_values  eav_status
                 ON eav_status.record_id = er.record_id
                AND eav_status.attribute_id = (
                        SELECT attribute_id
                        FROM   attribute_master
                        WHERE  attribute_code = 'status'
                          AND  entity_id      = em.entity_id
                    )
            WHERE em.entity_code    = 'ATTENDANCE_RECORD'
              AND eav_sid.value_text = $1::text
        )
        SELECT
            COUNT(*) AS total_days,
            COUNT(*) FILTER (WHERE status = 'PRESENT') AS present_days,
            COUNT(*) FILTER (WHERE status = 'ABSENT')  AS absent_days,
            ROUND(
                (COUNT(*) FILTER (WHERE status = 'PRESENT'))::numeric
                / NULLIF(COUNT(*), 0) * 100,
                2
            ) AS percentage
        FROM attendance_data
        """,
        str(student_id),
    )

    if not stats or stats["total_days"] == 0:
        return {"student_id": student_id, "total_days": 0, "percentage": 0}

    return {
        "student_id":   student_id,
        "total_days":   stats["total_days"],
        "present_days": stats["present_days"],
        "absent_days":  stats["absent_days"],
        "percentage":   float(stats["percentage"]),
    }
