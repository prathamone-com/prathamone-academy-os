"""
routers/auth.py — Login and JWT generation.

The JWT payload embeds tenant_id so that all downstream middleware and
database sessions can enforce tenant isolation without trusting the client.

LAW 7: tenant_id is set server-side only.  The login endpoint looks up
the tenant that owns the authenticating user from the database — the client
never sends a tenant_id.

LAW 5: No PII (usernames, tenant IDs, user IDs) is written to standard
output. Use the module logger at DEBUG level; output is controlled by
the LOG_LEVEL environment variable and never always-on in production.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Annotated

import asyncpg
import bcrypt as _bcrypt
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from jose import jwt
from pydantic import BaseModel

from db import db_conn
from middleware.tenant import auth_settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])

def _verify_password(plain: str, hashed: str) -> bool:
    """Verify a password against a bcrypt hash."""
    try:
        return _bcrypt.checkpw(plain.encode(), hashed.encode())
    except Exception:
        return False

ACCESS_TOKEN_EXPIRE_MINUTES = 60
REFRESH_TOKEN_EXPIRE_DAYS = 7


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_token(
    data: dict,
    expires_delta: timedelta,
) -> str:
    payload = data.copy()
    payload["exp"] = datetime.now(timezone.utc) + expires_delta
    return jwt.encode(
        payload,
        auth_settings.secret_key,
        algorithm=auth_settings.algorithm,
    )


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/login", response_model=TokenResponse, summary="Authenticate and receive JWT")
async def login(
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
    conn: asyncpg.Connection = Depends(db_conn),
) -> TokenResponse:
    """
    Authenticate a user by username + password.

    The server looks up the user record, verifies the password hash, and
    then reads the tenant_id from the database row.  The tenant_id is
    embedded in the JWT — it is NEVER supplied by the client.
    """
    # Fetch user + tenant_id server-side (tenant_id is never from client)
    logger.debug("Login attempt received")
    row = await conn.fetchrow(
        """
        SELECT
            er.record_id,
            er.tenant_id,
            eav_pwd.value_text  AS password_hash,
            (
                SELECT eav.value_text
                FROM entity_attribute_values eav
                JOIN attribute_master am
                    ON am.attribute_id = eav.attribute_id
                   AND am.tenant_id    = eav.tenant_id
                   AND am.attribute_code = 'role_name'
                WHERE eav.record_id = er.record_id
                  AND eav.tenant_id = er.tenant_id
                LIMIT 1
            ) AS role
        FROM entity_records er
        JOIN entity_master em
            ON em.entity_id   = er.entity_id
           AND em.tenant_id   = er.tenant_id
           AND em.entity_code = 'user'
        JOIN entity_attribute_values eav_pwd
            ON eav_pwd.record_id = er.record_id
           AND eav_pwd.tenant_id = er.tenant_id
        JOIN attribute_master am_pwd
            ON am_pwd.attribute_id   = eav_pwd.attribute_id
           AND am_pwd.tenant_id      = er.tenant_id
           AND am_pwd.attribute_code = 'password_hash'
        WHERE EXISTS (
            SELECT 1
            FROM entity_attribute_values u
            JOIN attribute_master am_u
                ON am_u.attribute_id   = u.attribute_id
               AND am_u.tenant_id      = u.tenant_id
               AND am_u.attribute_code = 'username'
            WHERE u.record_id  = er.record_id
              AND u.tenant_id  = er.tenant_id
              AND u.value_text = $1
        )
        LIMIT 1
        """,
        form_data.username,
    )

    if row is None or not _verify_password(form_data.password, row["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
        )

    tenant_id = str(row["tenant_id"])
    user_id = str(row["record_id"])
    role = row["role"] or "app_user"

    logger.debug("Login successful, issuing tokens (role=%s)", role)
    # Build tokens with tenant_id embedded — client never chooses this value
    access_token = _create_token(
        {"sub": user_id, "tenant_id": tenant_id, "role": role, "type": "access"},
        timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    refresh_token = _create_token(
        {"sub": user_id, "tenant_id": tenant_id, "type": "refresh"},
        timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
    )

    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/refresh", response_model=TokenResponse, summary="Exchange refresh token for new access token")
async def refresh(
    body: RefreshRequest,
    conn: asyncpg.Connection = Depends(db_conn),
) -> TokenResponse:
    """
    Issue a new access token using a valid refresh token.

    LAW 2 (Tenant Sovereignty): The user's real role is re-queried from the
    database during refresh — it is NEVER hardcoded or inferred.  This ensures
    that role changes (e.g., promotion, demotion) take effect on next refresh.
    """
    from jose import JWTError
    try:
        payload = jwt.decode(
            body.refresh_token,
            auth_settings.secret_key,
            algorithms=[auth_settings.algorithm],
        )
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

    if payload.get("type") != "refresh":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Not a refresh token")

    # Re-query the user's current role from the database (LAW 2 — never hardcode role).
    # The role may have changed since the refresh token was issued.
    user_id = payload["sub"]
    tenant_id = payload["tenant_id"]

    role_row = await conn.fetchrow(
        """
        SELECT eav.value_text AS role
        FROM   entity_attribute_values eav
        JOIN   attribute_master am ON am.attribute_id   = eav.attribute_id
                                   AND am.tenant_id      = eav.tenant_id
                                   AND am.attribute_code = 'role_name'
        WHERE  eav.record_id = $1::uuid
          AND  eav.tenant_id = $2::uuid
        LIMIT 1
        """,
        user_id,
        tenant_id,
    )
    role = (role_row["role"] if role_row else None) or "app_user"

    access_token = _create_token(
        {"sub": user_id, "tenant_id": tenant_id, "role": role, "type": "access"},
        timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    new_refresh = _create_token(
        {"sub": user_id, "tenant_id": tenant_id, "type": "refresh"},
        timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
    )
    return TokenResponse(access_token=access_token, refresh_token=new_refresh)
