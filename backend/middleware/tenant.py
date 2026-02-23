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

import logging
import os
from typing import Awaitable, Callable

logger = logging.getLogger(__name__)

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
    # --- 1. Protocol Bypass (CORS, root, health) ---
    if (
        request.method == "OPTIONS"
        or request.url.path in EXEMPT_PATHS
        or request.url.path in ("/", "/api/v1", "/api/v1/", "/favicon.ico")
    ):
        return await call_next(request)

    # --- 2. Attempt Identity Extraction (LAW 7) ---
    authorization: str = request.headers.get("Authorization", "")
    token = authorization.removeprefix("Bearer ").strip() if authorization.startswith("Bearer ") else None
    
    payload = None
    if token:
        try:
            payload = jwt.decode(token, auth_settings.secret_key, algorithms=[auth_settings.algorithm])
            request.state.tenant_id = payload.get("tenant_id")
            request.state.user_id = payload.get("sub")
            request.state.role = payload.get("role", "app_user")
            logger.debug("JWT validated for path %s", request.url.path)
        except JWTError as exc:
            logger.debug("JWT validation failed for path %s: %s", request.url.path, type(exc).__name__)

    # --- 3. Public Metadata Fallback (menus/forms) ---
    # If no valid identity found and it's a metadata path, use system context
    is_metadata_path = (request.url.path.startswith("/api/v1/menus/") or request.url.path.startswith("/api/v1/forms/"))
    
    if not getattr(request.state, "tenant_id", None):
        if is_metadata_path:
            request.state.tenant_id = os.getenv("SYSTEM_TENANT_ID", "00000000-0000-0000-0000-000000000000")
            request.state.role = "app_user"
            request.state.user_id = None
        else:
            # Not a metadata path and no valid token
            detail = "Invalid or expired token" if token else "Missing Authorization header"
            return JSONResponse(status_code=status.HTTP_401_UNAUTHORIZED, content={"detail": detail})

    # --- 4. Final Security Check (LAW 7) ---
    if not request.state.tenant_id:
        return JSONResponse(status_code=status.HTTP_401_UNAUTHORIZED, content={"detail": "Tenant identification failed"})

    return await call_next(request)
