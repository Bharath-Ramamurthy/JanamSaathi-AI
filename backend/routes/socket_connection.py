# routes/socket_connection.py
from typing import Optional
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query

from ws.socket_manager import SocketManager
from .deps import get_user_id, get_exp_token

router = APIRouter()
manager = SocketManager.instance()
logger = logging.getLogger("app.routes.socket_connection")
logger.setLevel(logging.INFO)


def _extract_token_from_headers(websocket: WebSocket) -> Optional[str]:
    """
    Return raw token string or None.
    Accepts:
      - Authorization: Bearer <token>
      - authorization: Bearer <token>
    """
    auth_header = websocket.headers.get("authorization") or websocket.headers.get("Authorization")
    if not auth_header or not isinstance(auth_header, str):
        return None
    parts = auth_header.split(" ", 1)
    if len(parts) == 1:
        # header contains only token
        return parts[0].strip()
    scheme, token = parts
    if scheme.lower() == "bearer":
        return token.strip()
    # not a bearer token
    return None


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket, token: Optional[str] = Query(None)):
    """
    WebSocket endpoint that authenticates a user using a bearer token supplied either
    as ?token=<token> or via an Authorization header. On success the connection is
    accepted and registered with SocketManager; incoming messages are dispatched.
    """
    

    # 1) Extract token (prefer query param, fall back to header)
    raw_token = None
    if token:
        # token may already be "Bearer <token>" or raw token
        if isinstance(token, str) and token.lower().startswith("bearer "):
            raw_token = token.split(" ", 1)[1].strip()
        else:
            raw_token = token.strip()
    else:
        raw_token = _extract_token_from_headers(websocket)

    if not raw_token:
        logger.debug("WebSocket connection attempt without token; rejecting")
        try:
            await websocket.close(code=4403)
        except Exception:
            logger.debug("Failed to close unauthorized websocket", exc_info=True)
        return

    # normalize to header form expected by deps functions
    auth_header_value = f"Bearer {raw_token}"

    user_id: Optional[str] = None
    token_exp: Optional[int] = None

    # 2) Validate token (these are async dependency helpers)
    try:
        # get_user_id / get_exp_token will raise HTTPException on invalid token
        user_id = await get_user_id(authorization=auth_header_value)
        token_exp = await get_exp_token(authorization=auth_header_value)
    except Exception as exc:
        # Authentication failed — close socket and return
        logger.info("WebSocket authentication failed: %s", exc)
        try:
            await websocket.close(code=4403)
        except Exception:
            logger.debug("Failed to close websocket after auth failure", exc_info=True)
        return

    user_id = str(user_id)
    logger.info("WebSocket authenticated for user_id=%s", user_id)

    # 3) Accept and register the connection
    try:
        await websocket.accept()
    except Exception as exc:
        logger.exception("Failed to accept websocket for user %s: %s", user_id, exc)
        try:
            await websocket.close(code=1011)
        except Exception:
            pass
        return

    try:
        await manager.register_connection(user_id, websocket)
    except Exception as exc:
        logger.exception("Failed to register websocket for user %s: %s", user_id, exc)
        try:
            await websocket.close(code=1011)
        except Exception:
            pass
        return

    # Build context for handlers — token_exp is an integer unix timestamp (as returned by deps)
    ctx = {"user_id": user_id, "claims": None, "token_exp": token_exp}

    # 4) Read loop and dispatch
    try:
        while True:
            raw_text = await websocket.receive_text()
            if raw_text is None:
                continue
            # dispatch_raw is async; manager will handle exceptions in handler execution
            await manager.dispatch_raw(websocket, raw_text, ctx)
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected for user %s", user_id)
        try:
            await manager.unregister_connection(websocket)
        except Exception:
            logger.exception("Error during unregister on disconnect for user %s", user_id)
    except Exception as exc:
        logger.exception("Unexpected websocket error for user %s: %s", user_id, exc)
        try:
            await manager.unregister_connection(websocket)
        except Exception:
            logger.exception("Error during unregister after unexpected exception for user %s", user_id)
        try:
            await websocket.close(code=1011)
        except Exception:
            pass
    finally:
        # Ensure we clean up if something else slipped through
        try:
            await manager.unregister_connection(websocket)
        except Exception:
            # already attempted above; keep silence
            pass
