from typing import List, Dict
from pydantic import BaseModel, Field


class AssessRequest(BaseModel):
    partner_id: str
    topic: str
    messages: List[Dict[str, str]]  # [{"sender": "user1", "text": "Hello"}]
    
    model_config = {
        "from_attributes": True
    }


class ReportResponse(BaseModel):
    horoscope_score: float
    compatibility_score: float

    model_config = {
        "from_attributes": True
    }


class ViewReportRequest(BaseModel):
    partner_id: str
    
    model_config = {
        "from_attributes": True
    }


class UpdateReportRequest(BaseModel):
    partner_id: str
    sentiment_score: float
    
    model_config = {
        "from_attributes": True
    }
