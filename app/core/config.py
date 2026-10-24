from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "JAL Offline Translation Backend"
    environment: str = "development"
    debug: bool = True
    secret_key: str = ""
    database_url: str = ""
    r2_account_id: str = ""
    r2_access_key_id: str = Field(default="", validation_alias="R2_ACCESS_ID")
    r2_secret_access_key: str = Field(default="", validation_alias="R2_ACCESS_KEY")
    r2_bucket_name: str = ""
    r2_endpoint_url: str = Field(default="", validation_alias="R2_URL")
    r2_public_base_url: str = ""
    cors_origins: list[str] = ["http://localhost:3000"]
    access_token_expire_minutes: int = 1440
    model_download_url_expire_seconds: int = 900
    max_model_size_bytes: int = 1_073_741_824

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, value: str | list[str]) -> list[str]:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
