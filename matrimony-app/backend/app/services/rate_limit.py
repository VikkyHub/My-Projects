from redis.asyncio import Redis


async def hit(redis: Redis, key: str, limit: int, window_seconds: int) -> bool:
    """Fixed-window counter. Returns True if this hit is allowed."""
    pipe = redis.pipeline()
    pipe.incr(key)
    pipe.expire(key, window_seconds, nx=True)
    count, _ = await pipe.execute()
    return int(count) <= limit
