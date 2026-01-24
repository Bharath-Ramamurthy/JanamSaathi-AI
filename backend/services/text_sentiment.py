# services/text_sentiment.py
from services.llm_api import LLMService
import re

llm = LLMService()

def analyze_text(text: str, topic: str) -> str:
    """
    Analyze a conversation using the Gottman Method to determine compatibility score.
    Returns the score as "XX.XX %" or "Invalid result".
    """
    prompt = f"""
You are a relationship analysis expert using the Gottman Method to evaluate a couple's conversation.
Assess the following chat conversation between two people and determine a single
compatibility score in percentage format (XX.X%), based on these markers:

Relationship Assessment Markers (Gottman Method)
- Positive Interactions: Compliments, appreciation, humor, empathy, agreement
- Negative Interactions: Criticism, sarcasm, dismissive tone, contempt
- Defensiveness: Denying responsibility, counter-attacking
- Stonewalling: Silence, avoiding answers, disengaging
- Trust Indicators: Expressions of reliability or safety (“I can count on you”)
- Shared Meaning: Alignment on goals/future (“We both want…”)
- Conflict Resolution: Calmly expressing feelings, using "I" statements, compromise
- Emotional Intimacy: Vulnerability, sharing fears or dreams
- Humor & Playfulness: Light teasing, shared jokes, laughter

Important Instructions:
- Evaluate the tone, patterns, and content of the conversation.
- ONLY RETURN the number in the format XX.XX% (example: 57.32%). Do NOT include any text, explanation, tables, or markdown.\n"

Conversation topic: {topic}
Conversation: {text}
"""
    result = llm.send_query(prompt).strip()
    match = re.search(r"(\d+(?:\.\d+)?)\s*%?", result)
    if match:
        value = float(match.group(1))
        if 0 <= value <= 100:
            return f"{value:.2f} %"
    return "Invalid result"
