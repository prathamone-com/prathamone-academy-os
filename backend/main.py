"""
main.py — FastAPI application entry point.

PrathamOne Academy OS — Kernel API Server
==========================================
Author    : Jawahar R Mallah
Role      : Founder & Technical Architect
Web       : https://aiTDL.com | https://pratham1.com
Version   : Author_Metadata_v1.0
Copyright : © 2026 Jawahar R Mallah. All rights reserved.
----------------------------------------------------------

RULES.md compliance:
  LAW 7 : tenant_id is NEVER accepted from the client. It is extracted only
           from the signed JWT in middleware/tenant.py and stored in
           request.state.tenant_id.
  LAW 8 : Audit tables are INSERT-ONLY. The DB role + RLS enforce this;
           the application never issues UPDATE/DELETE on audit tables.

Startup sequence:
  1. lifespan context manager initialises and tears down the asyncpg pool.
  2. TenantMiddleware is registered — it validates JWTs and populates
     request.state.tenant_id before any route handler runs.
  3. All routers are mounted under /api/v1/.
"""

import os
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from db import init_pool, close_pool
from middleware.tenant import tenant_middleware
from routers import auth, entities, workflow, policy, reports, forms, menus, fees, dashboard, attendance


# ---------------------------------------------------------------------------
# Lifespan (startup / shutdown)
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Initialise DB connection pool on startup; drain it on shutdown."""
    await init_pool()
    yield
    await close_pool()


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

app = FastAPI(
    title="PrathamOne Academy OS — API",
    description=(
        "Kernel API for the PrathamOne Academy OS. "
        "All access is tenant-scoped via JWT + PostgreSQL RLS. "
        "tenant_id is NEVER accepted from the client."
    ),
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# ---------------------------------------------------------------------------
# Middleware
# ---------------------------------------------------------------------------

# CORS — restrict origins in production via environment variable
origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:5173").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Tenant isolation middleware — must run AFTER CORS, BEFORE route handlers.
# Validates JWT and sets request.state.tenant_id from the 'tenant_id' claim.
# tenant_id is NEVER read from the request body (LAW 7).
app.middleware("http")(tenant_middleware)

# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------

API_PREFIX = "/api/v1"

app.include_router(auth.router,     prefix=API_PREFIX)
app.include_router(entities.router, prefix=API_PREFIX)
app.include_router(workflow.router, prefix=API_PREFIX)
app.include_router(policy.router,   prefix=API_PREFIX)
app.include_router(reports.router,  prefix=API_PREFIX)
app.include_router(forms.router,    prefix=API_PREFIX)
app.include_router(menus.router,    prefix=API_PREFIX)
app.include_router(fees.router,     prefix=API_PREFIX)
app.include_router(dashboard.router,prefix=API_PREFIX)
app.include_router(attendance.router,prefix=API_PREFIX)


# ---------------------------------------------------------------------------
# Health check (unauthenticated — listed in EXEMPT_PATHS in tenant.py)
# ---------------------------------------------------------------------------

@app.get("/health", tags=["ops"], summary="Health check")
async def health() -> dict:
    return {"status": "ok", "service": "prathamone-academy-os"}


# ---------------------------------------------------------------------------
# Run with: uvicorn main:app --reload --port 8000
# ---------------------------------------------------------------------------
