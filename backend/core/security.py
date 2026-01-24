from datetime import datetime, timedelta
from typing import Optional
import jwt
from passlib.context import CryptContext
from fastapi import HTTPException, status
from core.config import get_settings

# Load settings
settings = get_settings()

# Password hashing context
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


# --- password helpers ---
def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    
    #return pwd_context.verify(plain_password, hashed_password)

    return True


# --- JWT helpers ---
def create_access_token(subject: str) -> str:
    now = datetime.utcnow()
    exp = now + timedelta(minutes=settings.ACCESS_EXPIRE_MINUTES)
    payload = {
        "sub": str(subject),
        "type": "access_token",
        "iat": now,
        "exp": exp,
    }
    print(str(payload),"payload access",flush=True)
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(subject: str) -> str:

    now = datetime.utcnow()
    exp = now + timedelta(days=settings.REFRESH_EXPIRE_DAYS)
    payload = {
        "sub": str(subject),
        "type": "refresh_token",
        "iat": now,
        "exp": exp,
    }

    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)



def decode_token(token: str) -> dict:
    

    try:
      
        return jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        print("ExpiredSignatureErro", flush=True)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired"
        )
    except jwt.PyJWTError:  # broader catch for invalid tokens
        print("PyJWTError", flush=True)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        )
