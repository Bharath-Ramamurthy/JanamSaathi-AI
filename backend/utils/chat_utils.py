# app/utils/chat_utils.py

from sqlalchemy.orm import Session
from sqlalchemy import and_
import sqlalchemy as sa
from datetime import datetime
from typing import List, Dict, Any

from .helpers import ordered_pair
from models.chat import ChatMessage
from utils.profile_utils import find_profile_by_id
from schemas import ConversationItem


def create_or_update_chat(
    db: Session,
    user1_id: int,
    user2_id: int,
    topic: str,
    messages: List[Dict[str, str]],
):
    """
    Create a new chat or update existing one for a couple and topic.
    - If chat exists → append new messages to JSON list
    - Else create new chat with provided messages
    """
    u1, u2 = ordered_pair(user1_id, user2_id)

    chat = (
        db.query(ChatMessage)
        .filter(
            and_(
                ChatMessage.user1_id == u1,
                ChatMessage.user2_id == u2,
                ChatMessage.topic == topic,
            )
        )
        .first()
    )

    if chat:
        existing = chat.messages or []
        existing.extend(messages)
        chat.messages = existing
        chat.updated_at = datetime.utcnow()
    else:
        chat = ChatMessage(
            user1_id=u1,
            user2_id=u2,
            topic=topic,
            messages=messages,
        )
        db.add(chat)

    db.commit()
    db.refresh(chat)
    return chat


def get_chat(db: Session, user1_id: int, user2_id: int, topic: str) -> ChatMessage | None:
    """Retrieve chat for given couple and topic."""
    u1, u2 = ordered_pair(user1_id, user2_id)
    messages = db.query(ChatMessage).filter(and_(ChatMessage.user1_id == u1, ChatMessage.user2_id == u2,ChatMessage.topic == topic,)).all() 
    return messages
    


def clear_chat(db: Session, user1_id: int, user2_id: int, topic: str):
    """Clear chat messages but keep row."""
    chat = get_chat(db, user1_id, user2_id, topic)
    if chat:
        chat.messages = []
        chat.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(chat)
    return chat


def persist_messages_bulk(
    db: Session,
    sender_id: int,
    receiver_id: int,
    topic: str,
    messages: List[Dict[str, str]],
):
    """
    Insert or update a chat conversation with multiple messages:
    - If (user1, user2, topic) exists → append all messages to JSON list
    - Else create new conversation row with messages
    """
    u1, u2 = sorted([sender_id,  receiver_id])  # ensure consistency

    conversation = (
        db.query(ChatMessage)
        .filter(
            sa.text("LEAST(user1_id, user2_id) = :u1"),
            sa.text("GREATEST(user1_id, user2_id) = :u2"),
            sa.func.lower(ChatMessage.topic) == topic.lower(),
        )
        .params(u1=u1, u2=u2)
        .first()
    )

    new_msgs = []
    for msg in messages:
        new_msgs.append({
            "sender": msg.get("sender", sender_id),
            "text": msg.get("text", ""),
            "timestamp": msg.get("timestamp") or datetime.utcnow().isoformat(),
        })

    if conversation:
        msgs = conversation.messages or []
        msgs.extend(new_msgs)
        conversation.messages = msgs
        conversation.updated_at = datetime.utcnow()
    else:
        conversation = ChatMessage(
            user1_id=u1,
            user2_id=u2,
            topic=topic,
            messages=new_msgs,
        )
        db.add(conversation)

    db.commit()
    db.refresh(conversation)
    return conversation




def fetch_conversations(db: Session, user_id: int) -> List[Dict[str, Any]]:
    """
    Fetch and deduplicate recent conversations for a given user.
    Returns a list of dicts compatible with ConversationItem.from_raw().
    """
    conversations = (
        db.query(ChatMessage)
        .filter((ChatMessage.user1_id == user_id) | (ChatMessage.user2_id == user_id))
        .order_by(ChatMessage.updated_at.desc())
        .all()
    )

    # Deduplicate by user pair
    pair_map = {}
    for conv in conversations:
        pair_key = tuple(sorted([conv.user1_id, conv.user2_id]))
        if pair_key not in pair_map:
            pair_map[pair_key] = conv

    results: List[Dict[str, Any]] = []
    for conv in pair_map.values():
        other_user_id = conv.user1_id if conv.user2_id == user_id else conv.user2_id
        profile = find_profile_by_id(db, other_user_id)
        if profile:
            results.append({
              "id": other_user_id,
              "name": profile.user_name,
              "avatar_url": profile.photo_url,
              "topic": conv.topic,
            })

    return results