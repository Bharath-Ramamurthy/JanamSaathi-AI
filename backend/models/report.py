# app/db_models/report.py
import sqlalchemy as sa
from sqlalchemy.sql import func
from core.database import Base

class Report(Base):
    __tablename__ = "report"
    id = sa.Column(sa.BigInteger, primary_key=True, autoincrement=True)
    user1_id = sa.Column(sa.BigInteger, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    user2_id = sa.Column(sa.BigInteger, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    horoscope_score = sa.Column(sa.Numeric(5, 2), nullable=True)
    sentiment_sum = sa.Column(sa.Numeric(10, 2), default=0)
    sentiment_count = sa.Column(sa.Integer, default=0)
    sentiment_avg = sa.Column(sa.Numeric(5, 2), nullable=True)
    last_sentiment_at = sa.Column(sa.TIMESTAMP(timezone=True), nullable=True)
    created_at = sa.Column(sa.TIMESTAMP(timezone=True), server_default=func.now())
    updated_at = sa.Column(sa.TIMESTAMP(timezone=True), server_default=func.now(), onupdate=func.now())
    __table_args__ = (
        sa.Index("ix_report", sa.text("LEAST(user1_id, user2_id)"), sa.text("GREATEST(user1_id, user2_id)"), unique=True),
    )
