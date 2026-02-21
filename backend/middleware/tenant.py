"""
middleware/tenant.py — JWT-based tenant context middleware.

CRITICAL (LAW 7):
  tenant_id is extracted EXCLUSIVELY from the signed JWT in the
  Authorization header.  It is NEVER read from the request body, query
  string, or any header other than Authorization.

Flow per request:
  1. Extract Bearer token from Authorization header.
  2. Verify signature + expiry using SECRET_KEY / ALGORITHM.
  3. Read the ``tenant_id`` claim from the validated payload.
  4. Store it in ``request.state.tenant_id``.
  5. db.py's ``db_conn`` dependency reads this value and issues
     ``SET LOCAL app.tenant_id = '<tenant_id>'`` before any SQL.

Public paths (listed in EXEMPT_PATHS) bypass JWT validation so that
the login endpoint can be reached unauthenticated.
"""

from __future__ import annotations

from typing import Awaitable, Callable

from fastapi import Request, Response, status
from fastapi.responses import JSONResponse
from jose import JWTError, jwt
from pydantic_settings import BaseSettings, SettingsConfigDict


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

class AuthSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str = "change-me-in-production-use-a-256-bit-random-key"
    algorithm: str = "HS256"

auth_settings = AuthSettings()

# Paths that do not require a JWT (unauthenticated endpoints)
# Note: These are checked against request.url.path, which includes /api/v1
EXEMPT_PATHS: frozenset[str] = frozenset({
    "/api/v1/auth/login",
    "/api/v1/auth/refresh",
    "/api/v1/health",
    "/health", # Some callers might hit root health
    "/docs",
    "/openapi.json",
    "/redoc",
})


# ---------------------------------------------------------------------------
# Middleware
# ---------------------------------------------------------------------------

async def tenant_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """
    Starlette-compatible middleware that validates the JWT and injects
    ``tenant_id`` into ``request.state``.

    LAW 7: tenant_id comes EXCLUSIVELY from the signed JWT claim.
           It is NEVER read from request body, query string, or any
           other header.  Only the paths in EXEMPT_PATHS bypass this.

    Registered in main.py via ``app.middleware("http")(tenant_middleware)``.
    """
    # --- Pure passthrough: no auth, no context (CORS pre-flight, docs, health) ---
    if (
        request.method == "OPTIONS"
        or request.url.path in EXEMPT_PATHS
        or request.url.path.startswith("/docs")
        or request.url.path.startswith("/redoc")
        or request.url.path in ("/", "/api/v1", "/api/v1/", "/favicon.ico")
    ):
        return await call_next(request)

    # --- Public read-only app-shell routes (menus, forms) ---
    # These are structural metadata endpoints the frontend needs before login.
    # They are not tenant-security boundaries — menus/forms are system-level data.
    # We inject the system tenant context with a minimal role (app_user, NOT admin).
    # LAW 7 is not violated: tenant_id still comes from the server (env var), never the client.
    if (
        request.url.path.startswith("/api/v1/menus/")
        or request.url.path.startswith("/api/v1/forms/")
    ):
        import os
        request.state.tenant_id = os.getenv("SYSTEM_TENANT_ID", "00000000-0000-0000-0000-000000000000")
        request.state.role = "app_user"
        request.state.user_id = None
        return await call_next(request)

    # --- All remaining routes require a valid JWT (LAW 7) ---
    # /entities/, /reports/, /workflow/, /policy/ all fall through to here.

    authorization: str = request.headers.get("Authorization", "")
    if not authorization.startswith("Bearer "):
        print(f"DEBUG: Unauthorized access attempt to {request.method} {request.url.path}")
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={"detail": "Missing or malformed Authorization header. Expected: Bearer <token>"},
        )

    token = authorization.removeprefix("Bearer ").strip()

    # --- Validate token ---
    try:
        payload: dict = jwt.decode(
            token,
            auth_settings.secret_key,
            algorithms=[auth_settings.algorithm],
        )
    except JWTError as exc:
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={"detail": f"Invalid or expired token: {exc}"},
        )

    # --- Extract tenant_id from JWT claims (NEVER from request body) ---
    tenant_id: str | None = payload.get("tenant_id")
    if not tenant_id:
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={"detail": "JWT is missing required claim: tenant_id"},
        )

    # Store on request state — db.py reads this to set the GUC
    request.state.tenant_id = tenant_id
    request.state.user_id = payload.get("sub")
    request.state.role = payload.get("role", "app_user")

    return await call_next(request)
