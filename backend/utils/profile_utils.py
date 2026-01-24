# utils/profile_utils.py

from typing import Optional, Dict, Any, List, Union
from fastapi import HTTPException
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from routes.deps import get_db
from schemas import UserOut, SignupRequest
from models import User


def load_profiles(session: Session, limit: int = 100) -> List[UserOut]:
    """
    Load up to `limit` user records and return them as Pydantic UserOut objects.
    The session lifecycle is managed by FastAPI's get_db().
    """
    if session is None:
        raise ValueError("session is required")

    # sanitize limit (avoid huge queries)
    limit = max(1, min(limit, 1000))

    rows = session.query(User).limit(limit).all()
    return [UserOut.model_validate(r) for r in rows]


def add_profile(session: Session = None, profile: Union[SignupRequest, dict] = None) -> Dict[str, Any]:
    """
    Create a new user from a SignupRequest or dict.

    - Validates input via SignupRequest if a dict was passed.
    - Removes non-ORM fields like confirm_password or token.
    - Preserves `preferences` since the User model supports JSONB.
    - Catches IntegrityError for uniqueness issues (like duplicate email).
    - Uses session.flush() to assign DB-generated id and refresh() to load values.

    IMPORTANT: Do NOT close the session here; get_db() manages lifecycle.
    """

    if session is None:
        raise ValueError("session is required")

    if profile is None:
        raise HTTPException(status_code=400, detail="profile required")

    # validate/normalize input
    validated = profile if hasattr(profile, "dict") else SignupRequest(**profile)
    p = validated.dict()

    # Remove fields not part of User ORM model
    p.pop("confirm_password", None)
    p.pop("token", None)

    # Ensure password exists
    if not p.get("password"):
        raise HTTPException(status_code=400, detail="Password required")

    # Create ORM object and add to session
    user = User(**p)
    session.add(user)

    try:
        session.flush()    # flush so DB assigns PK
        session.refresh(user)
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(status_code=400, detail="Email already exists") from exc

    return {
        "status": "success",
        "id": user.id,
        "user_name": user.user_name,
    }


def find_profile_by_id(session: Session = None, id: Union[int, str] = None) -> Optional[User]:
    """
    Return the User ORM object for the given id, or None if not found.
    IMPORTANT: do NOT close the session here — caller manages lifecycle.
    """
    if session is None:
        raise ValueError("session is required")

    if id is None:
        return None

    return session.query(User).filter(User.id == int(id)).first()


def find_profile_by_email_id(session: Session = None, email_id: Optional[str] = None) -> Optional[User]:
    """
    Return the User ORM object for the given email_id, or None if not found.
    IMPORTANT: do NOT close the session here — caller manages lifecycle.
    """
    if session is None:
        raise ValueError("session is required")

    if not email_id:
        return None

    return session.query(User).filter(User.email_id == email_id).one_or_none()
