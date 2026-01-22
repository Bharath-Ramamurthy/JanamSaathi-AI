# routes/deps.py
from typing import Optional, Generator
from fastapi import Depends, HTTPException, Header, status
from sqlalchemy.orm import Session
from core.database import get_db as _get_db
from core.security import decode_token

# re-export DB dependency
def get_db() -> Generator[Session, None, None]:
    yield from _get_db()

# --- Extract User ID from Token ---
async def get_user_id(
    authorization: Optional[str] = Header(None),
    db: Session = Depends(get_db),
) -> str:

    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Authorization header missing"
        )

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid auth scheme"
        )

    payload = decode_token(token)
    if payload.get("type") != "access_token":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token is not an access token"
        )

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token missing subject"
        )

    return user_id


async def get_exp_token(
    authorization: Optional[str] = Header(None),
    db: Session = Depends(get_db),
) -> Optional[int]:
    """
    Return the token expiry (exp) integer from a valid access token.
    Returns None if authorization missing/invalid (raises HTTPException on invalid token).
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Authorization header missing"
        )

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid auth scheme"
        )

    payload = decode_token(token)
    if payload.get("type") != "access_token":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token is not an access token"
        )

    token_exp = payload.get("exp")
    if token_exp is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token missing expiry"
        )

    return int(token_exp)


async def get_user_id_from_refresh(
    authorization: Optional[str] = Header(None),
    db: Session = Depends(get_db),
) -> str:
    if not authorization:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authorization header missing")

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid auth scheme")

    payload = decode_token(token)
    if payload.get("type") != "refresh_token":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token is not a refresh token")

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token missing subject")

    return user_id
