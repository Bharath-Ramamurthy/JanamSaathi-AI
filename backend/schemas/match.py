from typing import List
from pydantic import BaseModel
from .user import UserOut # recommended_profiles will contain full Signup objects


class MatchRequest(BaseModel):
    user_id: str
    
    model_config = {
        "from_attributes": True
    }


class MatchResponse(BaseModel):
    recommended_profiles: List[UserOut]

    model_config = {
        "from_attributes": True
    }
