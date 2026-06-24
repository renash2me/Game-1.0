from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Database
    database_url: str
    postgres_user: str = "aethermoor"
    postgres_password: str
    postgres_db: str = "aethermoor"

    # Redis
    redis_url: str = "redis://redis-game:6379"

    # JWT
    jwt_secret: str
    jwt_expire_hours: int = 24

    # Server
    server_host: str = "localhost"
    game_api_port: int = 8000
    game_ws_port: int = 8001

    # Admin
    admin_token: str = "changeme"

    # Environment
    environment: str = "production"
    debug: bool = False


settings = Settings()
