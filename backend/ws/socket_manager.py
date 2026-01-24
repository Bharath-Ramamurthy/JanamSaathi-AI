# ws/socket_manager.py
import asyncio
import json
import logging
import time
from typing import Callable, Awaitable, Dict, Any, Set, Optional, Iterable
from fastapi import WebSocket
from sqlalchemy.orm import Session
from core.redis import get_messages_from_cache, clear_room_cache
from utils.chat_utils import persist_messages_bulk
from core.config import get_settings
from utils.helpers import db_call 

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

Handler = Callable[[WebSocket, str, str, dict, dict, dict], Awaitable[None]]
settings = get_settings()


class SocketManager:
    """
    Singleton WebSocket manager that tracks connections and rooms.
    Supports multiple sockets per user, room membership, safe message dispatch,
    and bulk flush of chat messages from Redis to DB on disconnect.
    Automatically starts a ping loop when the singleton is created.
    """
    _instance: Optional["SocketManager"] = None

    def __init__(self) -> None:
        self._user_ws: Dict[str, Set[WebSocket]] = {}
        self._ws_user: Dict[WebSocket, str] = {}
        self._rooms: Dict[str, Set[str]] = {}
        self._handlers: Dict[str, Handler] = {}
        self._lock = asyncio.Lock()

        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = asyncio.get_event_loop()

        try:
            self._ping_task = loop.create_task(self._ping_loop())
            logger.info("SocketManager ping loop started")
        except Exception as exc:
            logger.warning("Failed to start ping loop automatically: %s", exc)
            self._ping_task = None

    @classmethod
    def instance(cls) -> "SocketManager":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    # ---------------- Connection lifecycle ----------------
    async def register_connection(self, user_id: str, websocket: WebSocket) -> None:
        async with self._lock:
            self._user_ws.setdefault(user_id, set()).add(websocket)
            self._ws_user[websocket] = user_id
            logger.info(f"WebSocket registered for user {user_id}")

    async def unregister_connection(self, websocket: WebSocket) -> Optional[str]:
        async with self._lock:
            user_id = self._ws_user.pop(websocket, None)
            rooms_to_flush = []
            if user_id:
                conns = self._user_ws.get(user_id)
                if conns:
                    conns.discard(websocket)
                    if not conns:
                        self._user_ws.pop(user_id, None)

                for room_id, members in list(self._rooms.items()):
                    if user_id in members:
                        members.discard(user_id)
                        rooms_to_flush.append(room_id)
                        if not members:
                            self._rooms.pop(room_id, None)
                logger.info(f"WebSocket for user {user_id} unregistered")

        for room_id in rooms_to_flush:
             await self._flush_room_cache_to_db(room_id)

        return user_id

    async def close_user_connections(self, user_id: str) -> None:
        async with self._lock:
            conns = list(self._user_ws.get(user_id, []))
        for ws in conns:
            try:
                await ws.close()
            except Exception as exc:
                logger.error(f"Error closing ws for user {user_id}: {exc}")
            await self.unregister_connection(ws)

    # ---------------- Room management ----------------
    async def add_user_to_room(self, user_id: str, room_id: str) -> None:
        async with self._lock:
            self._rooms.setdefault(room_id, set()).add(user_id)

    async def remove_user_from_room(self, user_id: str, room_id: str) -> None:
        async with self._lock:
            members = self._rooms.get(room_id)
            if members and user_id in members:
                members.discard(user_id)
                if not members:
                    self._rooms.pop(room_id, None)

    def room_members(self, room_id: str) -> Set[str]:
        return set(self._rooms.get(room_id, set()))

    # ---------------- Handler registry & dispatch ----------------
    def register_handler(self, msg_type: str, handler: Handler) -> None:
        self._handlers[msg_type] = handler

    def unregister_handler(self, msg_type: str) -> None:
        self._handlers.pop(msg_type, None)

    async def dispatch_raw(self, websocket: WebSocket, raw_text: str, ctx: dict) -> None:
        try:
            if "token_exp" in ctx and ctx["token_exp"] is not None and int(time.time()) > int(ctx["token_exp"]):
                logger.info(f"Closing ws for user {ctx.get('user_id')} due to expired token")
                await self.safe_send_json(websocket, {
                    "type": "error", "request_id": None, "payload": {"message": "token_expired"}
                })
                await websocket.close(code=4403)
                return
        except Exception:
            pass

        try:
            msg = json.loads(raw_text)
        except json.JSONDecodeError:
            await self.safe_send_json(websocket, {
                "type": "error", "request_id": None, "payload": {"message": "invalid_json"}
            })
            return

        msg_type = msg.get("type")
        request_id = msg.get("request_id", "") or ""
        payload = msg.get("payload", {}) or {}
        meta = msg.get("meta", {}) or {}
        handler = self._handlers.get(msg_type)

        if not handler:
            await self.safe_send_json(websocket, {
                "type": "error", "request_id": request_id,
                "payload": {"message": f"unknown_type:{msg_type}"}
            })
            return

        user_id = ctx.get("user_id", "")

        async def _run_handler():
            try:
                await handler(websocket, user_id, request_id, payload, meta, ctx)
            except Exception as exc:
                logger.exception(f"Handler error for msg_type {msg_type}: {exc}")
                try:
                    await self.safe_send_json(websocket, {
                        "type": msg_type, "request_id": request_id,
                        "payload": {"stage": "error", "message": str(exc)}
                    })
                except Exception:
                    pass

        asyncio.create_task(_run_handler())

    # ---------------- Safe send helpers ----------------
    async def safe_send_json(self, websocket: WebSocket, obj: dict) -> None:
        try:
            await websocket.send_json(obj)
        except Exception as exc:
            logger.error(f"send_json failed: {exc}. Closing websocket.")
            try:
                await websocket.close()
            except Exception:
                pass
            await self.unregister_connection(websocket)

    async def send_json_to_user(self, user_id: str, obj: dict) -> int:
        async with self._lock:
            conns = list(self._user_ws.get(user_id, set()))
        sent = 0
        for ws in conns:
            try:
                await ws.send_json(obj)
                sent += 1
            except Exception as exc:
                logger.error(f"Broadcast send failed for user {user_id}: {exc}")
                try:
                    await ws.close()
                except Exception:
                    pass
                await self.unregister_connection(ws)
        return sent

    async def broadcast_to_room(self, room_id: str, obj: dict, exclude_user: str = None) -> int:
        members = self.room_members(room_id)
        sent = 0
        for uid in list(members):
          if exclude_user and str(uid) == str(exclude_user):
            continue
          sent += await self.send_json_to_user(uid, obj)
        return sent

    # ---------------- Utilities ----------------
    def get_user_ids(self) -> Iterable[str]:
        return list(self._user_ws.keys())

    async def get_user_websockets(self, user_id: str) -> Set[WebSocket]:
        async with self._lock:
            return set(self._user_ws.get(user_id, set()))

    async def ping_all(self) -> None:
        async with self._lock:
            all_conns = [ws for conns in self._user_ws.values() for ws in conns]
        for ws in all_conns:
            try:
                await ws.send_text("__ping__")
            except Exception as exc:
                logger.warning(f"Ping failed: {exc}")
                try:
                    await ws.close()
                except Exception:
                    pass
                await self.unregister_connection(ws)

    async def _ping_loop(self) -> None:
        while True:
            try:
                await self.ping_all()
            except Exception as exc:
                logger.error(f"Ping loop error: {exc}")
            await asyncio.sleep(settings.WS_PING_INTERVAL)

    # ---------------- Redis flush to DB ----------------
    async def _flush_room_cache_to_db(self, room_id: str):
        """Flush cached messages from Redis to DB in bulk"""
        try:
            messages = await get_messages_from_cache(room_id)
            if not messages:
                return

            # Extract participants reliably (keep as strings)
            participants: Set[str] = set()
            for msg in messages:
                if msg.get("sender"):
                    participants.add(str(msg["sender"]))
                if msg.get("receiver"):
                    participants.add(str(msg["receiver"]))

            # Fallback: derive participants from room_id if needed
            if len(participants) < 2 and "_" in room_id:
                parts = room_id.split("_")
                for p in parts[:2]:
                    participants.add(str(p))

            if len(participants) >= 2:
                u1_str, u2_str = sorted(list(participants))[:2]
                try:
                    u1, u2 = int(u1_str), int(u2_str)
                except ValueError:
                    logger.warning(f"Non-numeric participant IDs in room {room_id}, skipping flush.")
                    return
            else:
                logger.warning(f"Could not determine both participants for room {room_id}, skipping flush.")
                return

            topic = messages[0].get("topic", "general")

          
            # ✅ Persist first
            await asyncio.to_thread(db_call, persist_messages_bulk, u1, u2, topic, messages)

            # ✅ Only clear cache after DB write succeeded
            await clear_room_cache(room_id)

            logger.info(f"Flushed {len(messages)} messages from {room_id} to DB")

        except Exception as exc:
            logger.exception(f"Error flushing Redis cache to DB for room {room_id}: {exc}")
