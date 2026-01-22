# app/ws/handlers/report.py
from datetime import datetime
from typing import Dict, Any, Optional
import asyncio
import logging
from decimal import Decimal

from fastapi import WebSocket
from core.database import SessionLocal
from ws.socket_manager import SocketManager
from utils.report_utils import get_report, create_report, update_report
from services.horoscope import horoscope_score
from utils.profile_utils import find_profile_by_id
from utils.helpers import to_decimal

logger = logging.getLogger(__name__)

async def handle_report(
    websocket: WebSocket,
    user_id: str,
    request_id: str,
    payload: Dict[str, Any],
    meta: Dict[str, Any],
    ctx: Dict[str, Any],
) -> None:
    """
    View or update a compatibility report. Sends intermediate stages and final result.

    Behavior:
    - If a report with a compatibility_score exists -> return it (same as before).
    - If not -> compute horoscope, create report (with horoscope), then optionally update with provided AI score.
    """
    manager = SocketManager.instance()

    # Helper to send stage messages
    async def send_stage(stage: str, extra: Optional[Dict[str, Any]] = None):
        msg = {
            "type": "report",
            "request_id": request_id,
            "payload": {"stage": stage, "ts": datetime.utcnow().isoformat()}
        }
        if extra:
            msg["payload"].update(extra)
        await manager.safe_send_json(websocket, msg)

    # Helper for final result
    async def send_final(result: Dict[str, Any]):
        msg = {
            "type": "report",
            "request_id": request_id,
            "payload": {
                "status": "done", "result": result, "ts": datetime.utcnow().isoformat()
            }
        }
        await manager.safe_send_json(websocket, msg)

    # Extract partner ID
    partner = payload.get("partner_id") or payload.get("partner") or payload.get("to")
    if not partner:
        await manager.safe_send_json(websocket, {
            "type": "report", "request_id": request_id,
            "payload": {"stage": "error", "message": "missing_partner_id"}
        })
        return

    # Acknowledge start
    await manager.safe_send_json(websocket, {
        "type": "ack", "request_id": request_id,
        "payload": {"status": "started", "ts": datetime.utcnow().isoformat()}
    })

    # Normalize IDs
    try:
        u1 = int(user_id)
    except (ValueError, TypeError):
        u1 = user_id
    try:
        u2 = int(partner)
    except (ValueError, TypeError):
        u2 = partner

    loop = asyncio.get_running_loop()
    try:
        # 1) Check if report exists
        await send_stage("checking_report_exists", {"message": "Checking existing report"})
        await asyncio.sleep(1)

        def _get_report(a, b):
            db = SessionLocal()
            try:
                return get_report(db, a, b)
            finally:
                db.close()

        try:
            existing = await loop.run_in_executor(None, _get_report, u1, u2)
        except Exception as exc:
            logger.error(f"Error fetching report: {exc}")
            existing = None

        # If a valid report with a compatibility_score exists, return it
        if existing and existing.get("status")=="success" and existing.get("compatibility_score"):
            await send_stage("fetching_report", {"message": "Report found"})
            await asyncio.sleep(0.5)  # brief pause for UI
            result = {
                "compatibility_score": existing.get("compatibility_score"),
                "horoscope_score": existing.get("horoscope_score"),
                "raw": existing
            }
            await send_final(result)
            return

        # If report not found or missing compatibility_score -> compute horoscope then create report
        await send_stage("computing_horoscope_value", {"message": "Computing horoscope value"})
        await asyncio.sleep(0.5) 

        def _compute_horoscope(a, b) -> Optional[Decimal]:
            db = SessionLocal()
            try:
                u1_obj = find_profile_by_id(db, a)
                u2_obj = find_profile_by_id(db, b)
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
            hor_val_dec = await loop.run_in_executor(None, _compute_horoscope, u1, u2)
        except Exception as exc:
            logger.exception(f"Failed to compute horoscope: {exc}")
            hor_val_dec = None

        # --- CHANGED LINES START ---
        # Inform about horoscope result — send stage ONLY if computing a new horoscope
        if existing is None:
            if hor_val_dec is not None:
                await send_stage("Horoscope socre generated")
            else:
                await send_stage("Horoscope score generation failed")
        # --- CHANGED LINES END ---

        # 2) Create report with the computed horoscope value (may be None)
        await send_stage("creating_report", {"message": "Creating report"})
        await asyncio.sleep(0.5) 

        def _create(a, b, hor_val):
            db = SessionLocal()
            try:
                return create_report(db, a, b, horoscope_val=hor_val)
            finally:
                db.close()

        try:
            created = await loop.run_in_executor(None, _create, u1, u2, hor_val_dec)
        except Exception as exc:
            logger.error(f"create_report failed: {exc}")
            await manager.safe_send_json(websocket, {
                "type": "report", "request_id": request_id,
                "payload": {"stage": "error", "message": f"create_report_failed: {exc}"}
            })
            return

        if created.get("status") =="fail":
          await send_stage("report_creation_failed")
         
        else:
          await asyncio.sleep(0.5) 
          await send_stage("created_report", {"report": created})   
                    
        
        await asyncio.sleep(0.5)

        # Inform creation completed
        await send_stage("creating_report_completed", {"message": "Creating report completed"})

        # 3) Fetch latest and return
        def _fetch_latest(a, b):
            db = SessionLocal()
            try:
                return get_report(db, a, b)
            finally:
                db.close()

        try:
            latest = await loop.run_in_executor(None, _fetch_latest, u1, u2)
        except Exception as exc:
            logger.error(f"Failed to fetch latest report: {exc}")
            latest = current_report or {}

        final_result = {
            "compatibility_score": latest.get("compatibility_score"),
            "horoscope_score": latest.get("horoscope_score"),
            "raw": latest
        }
        await asyncio.sleep(0.2) 
        await send_final(final_result)
        return

    except Exception as exc:
        logger.exception(f"Unhandled error in handle_report: {exc}")
        await manager.safe_send_json(websocket, {
            "type": "report", "request_id": request_id,
            "payload": {"stage": "error", "message": str(exc)}
        })
        return
