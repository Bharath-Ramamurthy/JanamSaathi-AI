# app/utils/report_utils.py

from typing import Optional, Union, Dict
from datetime import datetime
from decimal import Decimal

from sqlalchemy.orm import Session
from models import Report, User
from .profile_utils import find_profile_by_id
from services.horoscope import horoscope_score
from .helpers import ordered_pair, to_decimal, format_decimal


def create_report(
    session: Session,
    user1_id: int,
    user2_id: int,
    horoscope_val: Optional[Decimal] = None,
) -> Dict[str, str]:
    """
    Create a report for user1 and user2 if missing.
    - If report already exists -> return {"status": "already_exists", ... scores ...}
    - If not exists -> create it using `horoscope_val` if provided, otherwise attempt to compute
      horoscope_score(user1_obj, user2_obj) as before. Returns {"status": "success", ...}.
    Notes:
      - Accepts User objects or integer IDs for user1/user2.
      - Initializes horoscope_score (if available), sentiment_sum=0, sentiment_count=0, sentiment_avg=None.
    """

    u1, u2 = ordered_pair(user1_id, user2_id)
    
    report = None

    report = session.query(Report).filter(Report.user1_id == u1, Report.user2_id == u2).first()
 
    if report is not None:
        return {"status": "fail", "error": "Report already exists"}


    report = Report(
        user1_id=u1,
        user2_id=u2,
        horoscope_score=horoscope_val,
        sentiment_sum=Decimal("0"),
        sentiment_count=0,
        sentiment_avg=None,
        last_sentiment_at=None,
    )
    session.add(report)
    session.commit() 


    return {
        "status": "success",
        "horoscope_score": format_decimal(report.horoscope_score) if report.horoscope_score is not None else "None",
        "compatibility_score": "No data available",
    }


def get_report(session: Session, user1_id: int, user2_id: int) -> Dict[str, str]:
    """
    Return report for pair (order-agnostic).
    - If report not found -> return {"error": "Report not found"}.
    - If found -> return same format as before.
    """
    u1, u2 = ordered_pair(user1_id, user2_id)
    report = session.query(Report).filter(Report.user1_id == u1, Report.user2_id == u2).first()
    
    if report is None:
             return {"status": "fail", "error": "Report does not exist"}


    return { "status": "success",
        "horoscope_score": format_decimal(report.horoscope_score) if report.horoscope_score is not None else "None",
        "compatibility_score": "No data available" if not report.sentiment_count else format_decimal(report.sentiment_avg),
    }


def update_report(session: Session, user1_id: int, user2_id: int, new_score: Decimal) -> Dict[str, str]:
    """
    Add a new sentiment score and update running sum/count/avg.
    - If report does not exist -> return {"error": "Report does not exist"}.
    - If exists -> perform the update and return {"status": "success", ...scores...}.
    """
    u1, u2 = ordered_pair(user1_id, user2_id)

    report = session.query(Report).filter(Report.user1_id == u1, Report.user2_id == u2).first()
    if report is None:
        return {"status": "fail", "error": "Report does not exist"}


    new_score_dec = to_decimal(new_score)

    current_sum = report.sentiment_sum or Decimal("0")
    current_count = report.sentiment_count or 0

    new_sum = current_sum + new_score_dec
    new_count = current_count + 1
    new_avg = (new_sum / Decimal(new_count)).quantize(Decimal("0.01"))

    report.sentiment_sum = new_sum
    report.sentiment_count = new_count
    report.sentiment_avg = new_avg
    report.last_sentiment_at = datetime.utcnow()


    return {
        "status": "success",
        "horoscope_score": format_decimal(report.horoscope_score) if report.horoscope_score is not None else "None",
        "compatibility_score": format_decimal(report.sentiment_avg) if report.sentiment_count else "No data available",
    }
