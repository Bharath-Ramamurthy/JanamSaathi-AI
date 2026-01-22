# core/config.py

from pydantic_settings import BaseSettings
from pydantic import Field
from functools import lru_cache


class Settings(BaseSettings):

    PROJECT_NAME: str = Field("GenAI Matchmaking App", description="Project name")
    VERSION: str = Field("1.0.0", description="App version")
    API_PREFIX: str = Field("/api", description="API base prefix")
    DEBUG: bool = True

    # --- Server ---
    #HOST: str = Field("127.0.0.1", description="Backend host")
    #PORT: int = Field(8000, description="Backend port")

    BACKEND_HOST: str = "127.0.0.1"
    BACKEND_PORT: int = 8000

    # --- Database ---
    DB_USER: str
    DB_PASS: str
    DB_HOST: str
    DB_PORT: int
    DB_NAME: str
    DATABASE_URL: str | None = None  # optional, can build dynamically

    # --- AI / LLM Keys ---
    OPENAI_API_KEY: str
    LLM_MODEL: str
    LLM_BASE_URL: str
    HUGGINGFACE_HUB_TOKEN: str
    OPENROUTER_API_KEY: str

    # --- Data directory ---
    DATA_DIR: str = "./data"

    # --- Security ---
    JWT_SECRET: str
    JWT_ALGORITHM: str
    ACCESS_EXPIRE_MINUTES: int = Field(15, description="JWT access token expiry in minutes")
    REFRESH_EXPIRE_DAYS: int = Field(30, description="JWT refresh token expiry in days")
    
    WS_PING_INTERVAL: int

    class Config:
        env_file = ".env"
        case_sensitive = True

    def build_database_url(self) -> str:
        """Build the full Postgres DB URL from individual components, if DATABASE_URL not set"""
        if self.DATABASE_URL:
            return self.DATABASE_URL
        return (
            f"postgresql://{self.DB_USER}:{self.DB_PASS}"
            f"@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}"
        )


@lru_cache()
def get_settings() -> Settings:
    """Return cached Settings instance to avoid reloading .env multiple times"""
    return Settings()


# Global instance for convenience
settings = get_settings()
