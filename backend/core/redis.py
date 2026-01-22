import redis.asyncio as redis
import json
from typing import List

# Create Redis connection pool
redis_client = redis.from_url(
    "redis://localhost:6379", 
    decode_responses=True
)

async def save_message_to_cache(room_id: str, message: dict):
    """
    Save a chat message into Redis list for the given room.
    """
    await redis_client.rpush(f"chat:{room_id}", json.dumps(message))

async def get_messages_from_cache(room_id: str) -> List[dict]:
    """
    Get all cached chat messages for a room.
    """
    messages = await redis_client.lrange(f"chat:{room_id}", 0, -1)
    return [json.loads(msg) for msg in messages]

async def clear_room_cache(room_id: str):
    """
    Delete cached messages for a room.
    """
    await redis_client.delete(f"chat:{room_id}")
