import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Request
from db import db_conn

router = APIRouter(prefix="/menus", tags=["menus"])

@router.get("/{menu_code}")
async def get_menu(
    menu_code: str,
    request: Request,
    conn: asyncpg.Connection = Depends(db_conn),
) -> list[dict]:
    """
    Returns a flattened, role-filtered list of menu items.
    """
    # For demo purposes, if no JWT is present, default to 'ADMIN' to see all items.
    # In production, this would be 'app_user' or would require a token.
    role = getattr(request.state, "role", "ADMIN")
    # 1. Fetch menu items
    # Note: We filter by role client-side OR here. Better here for security.
    rows = await conn.fetch(
        """
        SELECT mi.*
        FROM   menu_items mi
        JOIN   menu_master mm ON mm.menu_id = mi.menu_id
        WHERE  mm.menu_code = $1
          AND  mi.is_active = TRUE
          AND  (mi.required_roles = '{}' OR $2 = ANY(mi.required_roles))
        ORDER BY mi.parent_item_id NULLS FIRST, mi.sort_order
        """,
        menu_code, role,
    )
    
    if not rows and not await conn.fetchval("SELECT 1 FROM menu_master WHERE menu_code = $1", menu_code):
        raise HTTPException(status_code=404, detail=f"Menu '{menu_code}' not found")

    return [dict(r) for r in rows]
