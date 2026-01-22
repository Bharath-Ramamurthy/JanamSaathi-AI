# app/ws/handlers/assess.py
from datetime import datetime
from typing import Dict, Any, Optional, List
import asyncio
import logging
from decimal import Decimal

import sqlalchemy as sa
from fastapi import WebSocket

from sqlalchemy.orm import Session

from ws.socket_manager import SocketManager
from core.database import SessionLocal
from utils.profile_utils import find_profile_by_id
from utils.chat_utils import get_chat
from utils.report_utils import get_report, create_report, update_report
from services.horoscope import horoscope_score
from services.text_sentiment import analyze_text
from models.chat import ChatMessage  # Use correct model
from utils.helpers import ordered_pair, to_decimal  # Ensures consistent (user1,user2) ordering and conversion

logger = logging.getLogger(__name__)


async def handle_assess(
    websocket: WebSocket,
    user_id: str,
    request_id: str,
    payload: Dict[str, Any],
    meta: Dict[str, Any],
    ctx: Dict[str, Any],
) -> None:
    """
    Assess compatibility between two users. Sends intermediate 'stage' messages
    followed by a final result.

    Flow:
    - fetch chat history (non-blocking)
    - analyze sentiment (AI)
    - try update_report(score)
      - if report does not exist -> compute horoscope, create_report with horoscope, then update_report(score)
    - final result payload contains compatibility_score and horoscope_score
    """
    manager = SocketManager.instance()
    partner_id = payload.get("partner_id")
    topic = payload.get("topic", "general")

    if not partner_id:
        await manager.safe_send_json(websocket, {
            "type": "assess", "request_id": request_id,
            "payload": {"stage": "error", "message": "Missing partner_id"}
        })
        return

    # Acknowledge start
    await manager.safe_send_json(websocket, {
        "type": "ack", "request_id": request_id,
        "payload": {"status": "started", "ts": datetime.utcnow().isoformat()}
    })

    try:
        # -------------------------
        # 1) Fetch chat history from DB (non-blocking)
        # -------------------------
        await manager.safe_send_json(websocket, {
            "type": "assess", "request_id": request_id,
            "payload": {"stage": "Fetching_chat_history", "message": "Fetching chat history"}
        })

        def _fetch_chats(u1: int, u2: int, t: str) -> List[ChatMessage]:
            db = SessionLocal()
            try:
        
                messages = get_chat(db,u1,u2,t)
                
                if messages is None:
                    return []
                    
                for m in messages: print(m.__dict__)

                return messages
            finally:
                db.close()

        loop = asyncio.get_running_loop()
        msgs: List[ChatMessage] = await loop.run_in_executor(
            None, _fetch_chats, int(user_id), int(partner_id), topic
        )

        if msgs is []:
            await manager.safe_send_json(websocket, {"type": "assess", "request_id": request_id,"payload": {"stage": "fetched_chat_history", "message": "Failed to fetch chat messages"}})
        
        else:
            await manager.safe_send_json(websocket, {"type": "assess", "request_id": request_id,"payload": {"stage": "fetched_chat_history","message": "Fetching chat messages complete" }})

        # -------------------------
        # 2) Analyze sentiment with AI
        # -------------------------
        await manager.safe_send_json(websocket, {
            "type": "assess", "request_id": request_id,
            "payload": {"stage": "analysing_sentiment", "message": "Analyzing messages"}
        })

        text_corpus = " ".join(msg_obj["text"] for m in msgs if m.messages for msg_obj in m.messages if isinstance(msg_obj, dict) and msg_obj.get("text"))
        compatibility_score_raw = analyze_text(text_corpus, topic) 
        await manager.safe_send_json(websocket, {
            "type": "assess", "request_id": request_id,
            "payload": {"stage": "generated_score", "compatibility_score": compatibility_score_raw}
        })

     
        # Ensure compatibility_score is a float numeric value for DB update calls
        try:
            compatibility_score_value = to_decimal(compatibility_score_raw)
        except Exception as exc:
            logger.warning(f"Failed to parse compatibility score '{compatibility_score_raw}': {exc}")
            # fallback: treat as 0.0 to avoid crashing; you may prefer to return error instead
            compatibility_score_value = 0.0

        # -------------------------
        # 3) Attempt to update report with the compatibility score
        # -------------------------
        await manager.safe_send_json(websocket, {
            "type": "assess", "request_id": request_id,
            "payload": {"stage": "updating_report", "message": "Updating the report"}
        })

        def _update(u1: int, u2: int, score: float):
            db = SessionLocal()
            try:
                 updated_report = update_report(db, u1, u2, float(score))
                 
                 db.commit()
                 
                 return updated_report
            finally:
                db.close()

        updated_report = None
        try:
            updated_report = await loop.run_in_executor(
                None, _update, int(user_id), int(partner_id), compatibility_score_value
            )
        except Exception as exc:
            logger.exception(f"Error while attempting update_report: {exc}")
            updated_report = {"error": str(exc)}

        # Check if report did not exist per update_report's contract
        if updated_report is None or updated_report.get("status") == "fail":
            # Report is missing -> compute horoscope then create report, then update again.

            # 4a) Fetch horoscope (profiles + horoscope)
            await manager.safe_send_json(websocket, {
                "type": "assess", "request_id": request_id,
                "payload": {"stage": "fetching_horoscope", "message": "Fetching horoscope score"}
            })

            def _compute_horoscope(u1: int, u2: int) -> Optional[Decimal]:
                db = SessionLocal()
                try:
                    u1_obj = find_profile_by_id(db, u1)
                    u2_obj = find_profile_by_id(db, u2)
                    
                    if not (u1_obj and u2_obj):
                        
                        return None
    
                    try:
                        hv = horoscope_score(u1_obj, u2_obj)
                    except Exception as e:
                        logger.exception(f"horoscope_score failed: {e}")
                        hv = None
                       
                    if hv is None:                        
                         return None
                            
                    return to_decimal(hv)
                       

                finally:
                    db.close()

            hor_val_dec: Optional[Decimal] = None
            try:
                hor_val_dec = await loop.run_in_executor(None, _compute_horoscope, int(user_id), int(partner_id))
            except Exception as exc:
                logger.exception(f"Failed to compute horoscope: {exc}")
                hor_val_dec = None

        
            # 4b) Create report with horoscope_val (may be None)
            await manager.safe_send_json(websocket, {
                "type": "assess", "request_id": request_id,
                "payload": {"stage": "creating_report", "message": "Creating report"}
            })

            def _create(u1: int, u2: int, hor_val):
                db = SessionLocal()
                try:
                    # create_report accepts horoscope_val optionally; pass Decimal or None
                    
                    created_report = create_report(db, u1, u2, horoscope_val=hor_val)
                    
                    db.commit()
                    return created_report
                finally:
                    db.close()

            
            created_report = None
            try:

                created_report = await loop.run_in_executor(
                    None, _create, int(user_id), int(partner_id), hor_val_dec
                )
            except Exception as exc:
                logger.exception(f"Failed to create report: {exc}")
                created_report = {"error": str(exc)}
                
                

            await manager.safe_send_json(websocket, {"type": "assess", "request_id": request_id,"payload": {"stage": "created_report", "report": created_report}})

            # Inform creation completed
            await manager.safe_send_json(websocket, {
                "type": "assess", "request_id": request_id,
                "payload": {"stage": "creating_report_completed", "message": "Creating report completed"}
            })

            # 4c) Now update newly created report with compatibility score
            await manager.safe_send_json(websocket, {
                "type": "assess", "request_id": request_id,
                "payload": {"stage": "updating_report", "message": "Updating the report (after creation)"}
            })


            updated_report_after_create = None
            try:
                updated_report_after_create = await loop.run_in_executor(
                    None, _update, int(user_id), int(partner_id), compatibility_score_value
                )
            except Exception as exc:
                logger.exception(f"Failed to update report after creation: {exc}")
                updated_report_after_create = {"error": str(exc)}

            await manager.safe_send_json(websocket, {
                "type": "assess", "request_id": request_id,
                "payload": {"stage": "updated_report", "report": updated_report_after_create}
            })

            if updated_report_after_create and updated_report_after_create.get("status") =="success":
                await manager.safe_send_json(websocket, {
                    "type": "assess", "request_id": request_id,
                    "payload": {"stage": "report_updation_complete", "message": "Report updation complete"}
                })
            # set final_report for response building
            final_report = updated_report_after_create or created_report

        else:
            # initial update succeeded
            await manager.safe_send_json(websocket, {
                "type": "assess", "request_id": request_id,
                "payload": {"stage": "updated_report", "report": updated_report}
            })
            await manager.safe_send_json(websocket, {
                "type": "assess", "request_id": request_id,
                "payload": {"stage": "report_updation_complete", "message": "Report updation complete"}
            })
            final_report = updated_report

    
        await manager.safe_send_json(websocket, {"type": "assess", "request_id": request_id,"payload": {"status": "done"}})


    except Exception as exc:
        logger.exception(f"Unhandled error in handle_assess: {exc}")
        await manager.safe_send_json(websocket, {
            "type": "assess", "request_id": request_id,
            "payload": {"stage": "error", "message": str(exc)}
        })
