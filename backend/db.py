"""
db.py — PostgreSQL connection pool and per-session tenant context.

CRITICAL (LAW 7):
  tenant_id is NEVER accepted from the frontend or request body.
  It is extracted from the validated JWT by middleware/tenant.py and stored
  in request.state.tenant_id.  This module then issues:

      SET LOCAL app.tenant_id = '<tenant_id>';

  inside every acquired connection before any application SQL runs.
  The RLS policies in db/rls_policies.sql read this GUC to filter rows.   
"""

from __future__ import annotations

import asyncpg
from contextlib import asynccontextmanager
from typing import AsyncGenerator, Optional
from fastapi import Request
from pydantic_settings import BaseSettings, SettingsConfigDict


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

class DBSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://postgres:password@localhost:5432/prathamone"
    db_min_size: int = 2
    db_max_size: int = 10

db_settings = DBSettings()

# ---------------------------------------------------------------------------
# Global pool (initialised in lifespan)
# ---------------------------------------------------------------------------

_pool: Optional[asyncpg.Pool] = None


async def init_pool() -> None:
    """Create the asyncpg connection pool. Called once at application startup."""
    global _pool
    _pool = await asyncpg.create_pool(
        dsn=db_settings.database_url,
        min_size=db_settings.db_min_size,
        max_size=db_settings.db_max_size,
        command_timeout=30,
    )


async def close_pool() -> None:
    """Drain and close the pool. Called at application shutdown."""
    global _pool
    if _pool:
        await _pool.close()
        _pool = None


# ---------------------------------------------------------------------------
# Connection with tenant context
# ---------------------------------------------------------------------------

@asynccontextmanager
async def get_connection(
    tenant_id: Optional[str] = None,
) -> AsyncGenerator[asyncpg.Connection, None]:
    """
    Acquire a pooled connection and set the session-local GUC
    ``app.tenant_id`` if a tenant context is provided.

    If ``tenant_id`` is None, the GUC is not set, meaning RLS policies
    referencing it will resolve to NULL.
    """
    assert _pool is not None, "Pool not initialised — call init_pool() first"

    async with _pool.acquire() as conn:
        # Open an explicit transaction so SET LOCAL takes effect.
        async with conn.transaction():
            if tenant_id:
                # LAW 7: inject tenant context server-side only.
                await conn.execute(
                    "SELECT set_config('app.tenant_id', $1, true)",
                    str(tenant_id),
                )
            yield conn


# ---------------------------------------------------------------------------
# FastAPI dependency
# ---------------------------------------------------------------------------

async def db_conn(request: Request) -> AsyncGenerator[asyncpg.Connection, None]:
    """
    FastAPI dependency that yields a tenant-scoped database connection.

    If ``request.state.tenant_id`` is present (set by TenantMiddleware),
    the connection is scoped to that tenant. Otherwise, it is unscoped
    (tenant_id=None), which is appropriate for public/system endpoints.
    """
    tenant_id: Optional[str] = getattr(request.state, "tenant_id", None)
    
    async with get_connection(tenant_id) as conn:
        yield conn
