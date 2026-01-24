from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime

from datetime import datetime

class Preferences(BaseModel):
    living_arrangement: Optional[str] = None
    cultural_practices: Optional[str] = None
    preferred_food: Optional[str] = None
    parents_involvement: Optional[str] = None
    home_vibe: Optional[str] = None

    model_config = {
        "from_attributes": True
    }


class LoginRequest(BaseModel):
    email_id: str
    password: str


class SignupRequest(BaseModel):
    user_name: str
    email_id: str
    password: str  # Use 'password' consistently across backend
    gender: str
    dob: str
    place_of_birth: str
    education: str
    salary: str
    religion: str
    caste: str
    color: Optional[str] = None
    preferences: Preferences = Field(default_factory=Preferences)
    photo_url: Optional[str] = None

    model_config = {
        "from_attributes": True
    }
        

class UserOut(BaseModel):
    id: int
    user_name: str
    email_id: Optional[str] = None
    gender: Optional[str] = None
    dob: Optional[str] = None
    place_of_birth: Optional[str] = None
    education: Optional[str] = None
    salary: Optional[str] = None
    religion: Optional[str] = None
    caste: Optional[str] = None
    color: Optional[str] = None
    photo_url: Optional[str] = None
    preferences: Optional[dict] = None


    model_config = {
        "from_attributes": True
    } 
