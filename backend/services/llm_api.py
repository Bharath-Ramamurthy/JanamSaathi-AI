# services/llm_api.py
import logging
from openai import OpenAI
from core.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

class LLMService:
    """
    Wrapper for OpenAI/OpenRouter chat completion API.
    """
    def __init__(self):
        self.client = OpenAI(base_url=settings.LLM_BASE_URL,
                             api_key=settings.OPENROUTER_API_KEY)
        self.model = settings.LLM_MODEL

    def send_query(self, prompt: str) -> str:
        """
        Send a chat completion request. Returns response text or error message.
        """
        try:
            completion = self.client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
            )
            return completion.choices[0].message.content
        except Exception as exc:
            logger.error(f"LLM API error: {exc}")
            return "Sorry, something went wrong generating a response."

if __name__ == "__main__":
    # Example usage (for local testing)
    llm = LLMService()
    reply = llm.send_query("What is the meaning of life?")
    print("Response:", reply)
