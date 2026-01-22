import re
import logging
from typing import Dict, Optional
from services.llm_api import LLMService
from models import User

logger = logging.getLogger(__name__)
llm = LLMService()

def horoscope_score(
    user1_data: User,
    user2_data: User
) -> str:
    """
    Query an LLM to compute horoscope compatibility.
    Returns 'XX.XX %' or 'Invalid result'.
    """

    prompt = (
        "Based on the following birth details, calculate compatibility as a single numeric percentage. "
        "ONLY RETURN the number in the format XX.XX% (example: 57.32%). "
        "Do NOT include any text, explanation, tables, or markdown.\n"
        f"Person 1: DOB {user1_data.dob}, Place {user1_data.place_of_birth}\n"
        f"Person 2: DOB {user2_data.dob}, Place {user2_data.place_of_birth}"
    )
   
    try:
        result = llm.send_query(prompt).strip()
    except Exception as exc:
        logger.error(f"LLM query failed in horoscope_score: {exc}")
        return "Invalid result"


    match = re.search(r"(\d+(?:\.\d+)?)\s*%?", result)
    if match:
        value = float(match.group(1))
        if 0 <= value <= 100:
            return f"{value:.2f} %"
    return "Invalid result"

