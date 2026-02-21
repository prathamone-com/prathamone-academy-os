"""
routers/auth.py — Login and JWT generation.

The JWT payload embeds tenant_id so that all downstream middleware and
database sessions can enforce tenant isolation without trusting the client.

LAW 7: tenant_id is set server-side only.  The login endpoint looks up
the tenant that owns the authenticating user from the database — the client
never sends a tenant_id.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Annotated

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from jose import jwt
from passlib.context import CryptContext
from pydantic import BaseModel

from db import db_conn
from middleware.tenant import auth_settings

router = APIRouter(prefix="/auth", tags=["auth"])
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

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
    row = await conn.fetchrow(
        """
        SELECT
            er.record_id,
            er.tenant_id,
            eav_pwd.value_text  AS password_hash,
            eav_role.value_text AS role
        FROM entity_records er
        JOIN entity_attribute_values eav_pwd
            ON eav_pwd.entity_record_id = er.record_id
           AND eav_pwd.tenant_id = er.tenant_id
           AND eav_pwd.attribute_code = 'password_hash'
        LEFT JOIN entity_attribute_values eav_role
            ON eav_role.entity_record_id = er.record_id
           AND eav_role.tenant_id = er.tenant_id
           AND eav_role.attribute_code = 'role_name'
        WHERE er.entity_code = 'user'
          AND er.tenant_id = er.tenant_id  -- RLS filters by session GUC
          AND EXISTS (
              SELECT 1 FROM entity_attribute_values u
              WHERE u.entity_record_id = er.record_id
                AND u.tenant_id = er.tenant_id
                AND u.attribute_code = 'username'
                AND u.value_text = $1
          )
        LIMIT 1
        """,
        form_data.username,
    )

    if row is None or not pwd_context.verify(form_data.password, row["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
        )

    tenant_id = str(row["tenant_id"])
    user_id = str(row["record_id"])
    role = row["role"] or "app_user"

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
async def refresh(body: RefreshRequest) -> TokenResponse:
    """Issue a new access token using a valid refresh token."""
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

    access_token = _create_token(
        {"sub": payload["sub"], "tenant_id": payload["tenant_id"], "role": "app_user", "type": "access"},
        timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    new_refresh = _create_token(
        {"sub": payload["sub"], "tenant_id": payload["tenant_id"], "type": "refresh"},
        timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
    )
    return TokenResponse(access_token=access_token, refresh_token=new_refresh)
