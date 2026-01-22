from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List

from schemas import ConversationItem
from utils.chat_utils import fetch_conversations
from .deps import get_db, get_user_id

router = APIRouter(tags=["Conversations"])


@router.get("/fetch_conversations", response_model=List[ConversationItem])
def fetch_conversations_route(
    user_id: str = Depends(get_user_id),
    db: Session = Depends(get_db),
):
    """
    Fetch recent conversations for the logged-in user.
    Returns a list of ConversationItem objects.
    """
    user_id_int = int(user_id)
    raw_list = fetch_conversations(db, user_id_int)
    return [ConversationItem.from_raw(item) for item in raw_list]
