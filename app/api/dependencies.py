from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import decode_access_token, hash_api_key
from app.db.models import APIClient, APIKey, User
from app.db.session import get_db

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")
DB = Annotated[Session, Depends(get_db)]


def get_current_user(token: Annotated[str, Depends(oauth2_scheme)], db: DB) -> User:
    user_id = decode_access_token(token)
    try:
        user = db.get(User, UUID(user_id)) if user_id else None
    except (ValueError, TypeError):
        user = None
    if not user or user.status != "active":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")
    return user


def require_partner_client(x_api_key: Annotated[str | None, Header()] = None, db: DB = None) -> APIClient:
    if not x_api_key:
        raise HTTPException(status_code=401, detail="X-API-Key header is required")
    api_key = db.scalar(select(APIKey).where(APIKey.key_hash == hash_api_key(x_api_key)))
    if not api_key or api_key.revoked_at or (api_key.expires_at and api_key.expires_at < datetime.now(UTC)):
        raise HTTPException(status_code=401, detail="Invalid or expired API key")
    client = db.get(APIClient, api_key.api_client_id)
    if not client or client.status != "active":
        raise HTTPException(status_code=403, detail="API client is inactive")
    api_key.last_used_at = datetime.now(UTC)
    db.commit()
    return client
