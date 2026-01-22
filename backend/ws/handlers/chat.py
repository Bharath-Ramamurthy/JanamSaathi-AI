# app/ws/handlers/chat.py
from datetime import datetime
from typing import Dict, Any
import logging
from sqlalchemy.dialects.postgresql import JSONB
from fastapi import WebSocket
from ws.socket_manager import SocketManager
from core.redis import save_message_to_cache  # Redis cache helper

logger = logging.getLogger(__name__)

def _canonical_room_id(a: str, b: str) -> str:
    """Return a canonical room ID for two user IDs."""
    try:
        ai, bi = int(a), int(b)
        return f"{min(ai, bi)}_{max(ai, bi)}"
    except (ValueError, TypeError):
        pair = sorted([str(a), str(b)])
        return f"{pair[0]}_{pair[1]}"

async def handle_chat(
    websocket: WebSocket,
    user_id: str,
    request_id: str,
    payload: Dict[str, Any],
    meta: Dict[str, Any],
    ctx: Dict[str, Any],
) -> None:
    """
    Chat message handler. Persists to Redis and broadcasts to the room.
    DB flush happens only on WebSocket disconnect.
    """
    manager = SocketManager.instance()
    sender = str(ctx.get("user_id") or payload.get("sender") or "")
    if not sender:
        await manager.safe_send_json(websocket, {
            "type": "error", "request_id": request_id,
            "payload": {"message": "missing_sender"}
        })
        return

    text = (payload.get("text") or "").strip()
    if not text:
        await manager.safe_send_json(websocket, {
            "type": "ack", "request_id": request_id,
            "payload": {"status": "empty", "message": "empty_text"}
        })
        return

    topic = payload.get("topic") or payload.get("topic_name") or "general"
    room_id = payload.get("room_id")

    # derive receiver / to_id
    to_id = payload.get("to") or payload.get("receiver") or payload.get("recipient") or None

    if not room_id:
        if to_id:
            room_id = _canonical_room_id(sender, str(to_id))
        else:
            room_id = payload.get("room") or meta.get("room_id")
    if not room_id:
        await manager.safe_send_json(websocket, {
            "type": "error", "request_id": request_id,
            "payload": {"message": "missing_room_or_to"}
        })
        return

    msg_obj = {
        "sender": sender,
        "receiver": str(to_id) if to_id is not None else None,
        "text": text,
        "topic": topic,
        "ts": datetime.utcnow().isoformat(),
    }

    # Persist to Redis (best-effort)
    try:
        await save_message_to_cache(room_id, msg_obj)
    except Exception as exc:
        logger.error(f"Redis save failed for room {room_id}: {exc}")
        await manager.safe_send_json(websocket, {
            "type": "error", "request_id": request_id,
            "payload": {"message": "redis_save_failed", "detail": str(exc)}
        })

    # Add sender to room
    try:
        await manager.add_user_to_room(sender, room_id)
        if to_id:
           await manager.add_user_to_room(str(to_id), room_id) 
    except Exception as exc:
        logger.warning(f"Failed to add user {sender} to room {room_id}: {exc}")

    # Acknowledge the sender
    try:
        await manager.safe_send_json(websocket, {
            "type": "ack", "request_id": request_id,
            "payload": {"status": "received", "ts": msg_obj["ts"]}
        })
    except Exception as exc:
        logger.error(f"Failed to send ack to sender {sender}: {exc}")

    # Broadcast to the room
    broadcast_payload = {
        "type": "chat",
        "request_id": request_id,
        "payload": {
            "room_id": room_id,
            "sender": msg_obj["sender"],
            "receiver": msg_obj["receiver"],  # added
            "text": msg_obj["text"],
            "topic": msg_obj["topic"],
            "ts": msg_obj["ts"]
        }
    }
    try:
        await manager.broadcast_to_room(room_id, broadcast_payload, exclude_user=sender)
    except Exception as exc:
        logger.error(f"Broadcast failed in room {room_id}: {exc}")
        await manager.safe_send_json(websocket, {
            "type": "error", "request_id": request_id,
            "payload": {"message": "broadcast_failed", "detail": str(exc)}
        })
