# utils/helpers.py
import logging
from decimal import Decimal, InvalidOperation
from typing import Optional, Tuple, Callable, Any
from core.database import SessionLocal

# Define logger for this module
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def ordered_pair(user1_id: int, user2_id: int) -> Tuple[int, int]:
    """Return a consistent (min, max) ordering of two user IDs."""
    return (min(int(user1_id), int(user2_id)), max(int(user1_id), int(user2_id)))

def to_decimal(v) -> Optional[Decimal]:
   
    """Convert a value to Decimal; return None if not numeric."""
    
    
    if v is None:
        return None
    s = str(v).strip()
    if s.endswith("%"):
        s = s[:-1].strip()
    try:
        return Decimal(s)
    except Exception:
        # log or ignore
        logger.warning(f"Cannot convert {v!r} to Decimal, returning None")
        return None

def format_decimal(d: Optional[Decimal]) -> str:
    """Format Decimal to string with 2 decimal places, or 'None' if missing."""
    if d is None:
        return "None"
    return f"{Decimal(d).quantize(Decimal('0.01'))}"

            
def db_call(fn: Callable[..., Any], *args, **kwargs) -> Any:
    """
    Centralized helper to open a DB session, call `fn(db, ...)`, and close session.
    Safe to use in run_in_executor.
    Ensures rollback and logs any DB errors.
    """
    db = SessionLocal()
    try:
        return fn(db, *args, **kwargs)
    except Exception as exc:
        try:
            db.rollback()
        except Exception:
            logger.exception("Rollback failed in db_call")
        logger.exception(f"DB call failed in {fn.__name__}: {exc}")
        raise
    finally:
        try:
            db.close()
        except Exception:
            logger.exception("Error closing DB session in db_call")
