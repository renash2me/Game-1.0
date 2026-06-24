import redis.asyncio as redis

from app.config import settings

_pool: redis.ConnectionPool | None = None


def get_redis_pool() -> redis.ConnectionPool:
    global _pool
    if _pool is None:
        _pool = redis.ConnectionPool.from_url(
            settings.redis_url,
            decode_responses=True,
            max_connections=50,
        )
    return _pool


def get_redis() -> redis.Redis:
    return redis.Redis(connection_pool=get_redis_pool())
