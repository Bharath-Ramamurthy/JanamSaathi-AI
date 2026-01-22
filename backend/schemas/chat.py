# app/schemas/conversation.py
from typing import Optional, Union
from pydantic import BaseModel, Field
from datetime import datetime


class ConversationItem(BaseModel):
    """
    Represents a single chat conversation entry.
    Used to serialize normalized data for the frontend.
    """
    id: Union[int, str] = Field(..., description="User unique id")
    user_name: str = Field(..., description="User display name")
    avatar_url: Optional[str] = Field(None, description="Avatar / image URL")
    topic: Optional[str] = Field(None, description="Conversation topic")

    @classmethod
    def from_raw(cls, raw: dict):
        """
        Normalize raw dict fields from backend or DB.
        """
        return cls(
            id=raw.get("user_id") or raw.get("id") or raw.get("userId"),
            user_name=raw.get("user_name") or raw.get("name") or raw.get("full_name"),
            avatar_url=raw.get("avatar_url") or raw.get("photo_url") or raw.get("image") or raw.get("avatar"),
            topic=raw.get("topic") or raw.get("conversation_topic") or raw.get("last_topic"),
        )
