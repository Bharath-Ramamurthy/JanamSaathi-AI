# app/db_models/chat.py
import sqlalchemy as sa
from sqlalchemy.sql import func
from core.database import Base
from sqlalchemy.dialects.postgresql import JSONB

class ChatMessage(Base):
    __tablename__ = "chat"
    id = sa.Column(sa.BigInteger, primary_key=True, autoincrement=True)
    user1_id = sa.Column(sa.BigInteger, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    user2_id = sa.Column(sa.BigInteger, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    topic = sa.Column(sa.String(200), nullable=True)
    messages = sa.Column(JSONB, default=[])
    created_at = sa.Column(sa.TIMESTAMP(timezone=True), server_default=func.now())
    updated_at = sa.Column(sa.TIMESTAMP(timezone=True), server_default=func.now(), onupdate=func.now())
    __table_args__ = (
        sa.Index("ix_chat", sa.text("LEAST(user1_id, user2_id)"), sa.text("GREATEST(user1_id, user2_id)"), sa.text("lower(topic)"), unique=True),
    )
