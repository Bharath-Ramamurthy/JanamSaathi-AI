# core/database.py


from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, scoped_session, declarative_base
from core.config import settings


DATABASE_URL = (
    f"postgresql://{settings.DB_USER}:{settings.DB_PASS}"
    f"@{settings.DB_HOST}:{settings.DB_PORT}/{settings.DB_NAME}"
)

# Engine
#engine = create_engine(DATABASE_URL, echo=settings.DEBUG,  connect_args={'options': '-c client_encoding=utf8'})
engine = create_engine(
    DATABASE_URL,
    echo=settings.DEBUG,
    pool_pre_ping=True,                 # auto-reconnects dropped connections
    connect_args={'options': '-c client_encoding=utf8'}
)


# Session factory
SessionLocal = scoped_session(
    sessionmaker(autocommit=False, autoflush=False, bind=engine)
)

# Base class for ORM models
Base = declarative_base()

# --- DB Session Dependency ---
def get_db():
    """Provide a transactional database session."""
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
