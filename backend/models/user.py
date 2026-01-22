
# app/db_models/user.py
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.sql import func
from core.database import Base

class User(Base):
    __tablename__ = "users"
    id = sa.Column(sa.BigInteger, primary_key=True, index=True)
    password = sa.Column(sa.String(255), nullable=False)
    user_name = sa.Column(sa.String(200), nullable=False, index=True)
    email_id = sa.Column(sa.String(50), unique=True, index=True)
    gender = sa.Column(sa.String(50))
    dob = sa.Column(sa.String(50))
    place_of_birth = sa.Column(sa.String(150))
    education = sa.Column(sa.String(150))
    salary = sa.Column(sa.String(50))
    religion = sa.Column(sa.String(80), index=True)
    caste = sa.Column(sa.String(80), index=True)
    color = sa.Column(sa.String(50))
    photo_url = sa.Column(sa.String(255))
    preferences = sa.Column(JSONB, nullable=False, server_default=sa.text("'{}'::jsonb"))
