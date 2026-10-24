import os
from dataclasses import dataclass, field
from functools import lru_cache


@dataclass
class Settings:
    app_name: str = "Aircraft Communication Edge"
    environment: str = "development"
    secret_key: str = "change-me"
    database_path: str = "./communication.db"
    mqtt_host: str = "localhost"
    mqtt_port: int = 1883
    mqtt_username: str = ""
    mqtt_password: str = ""
    mqtt_enabled: bool = False
    flight_id: str = "demo-flight"
    flight_number: str = "DEMO001"
    aircraft_identifier: str = "DEMO-AIRCRAFT"
    crew_pairing_code: str = "CREW-DEMO"
    demo_seed: bool = False
    access_token_expire_minutes: int = 720
    cors_origins: list[str] = field(default_factory=lambda: [
        "http://localhost:3000",
        "http://localhost:5000",
        "http://localhost:5001",
        "http://localhost:8080",
        "http://127.0.0.1:5000",
        "http://127.0.0.1:5001",
        "http://127.0.0.1:8080",
    ])

    def __post_init__(self) -> None:
        if os.path.exists(".env"):
            with open(".env", encoding="utf-8") as file:
                for line in file:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        os.environ.setdefault(key.strip(), value.strip())
        string_fields = ("app_name", "environment", "secret_key", "database_path", "mqtt_host", "mqtt_username", "mqtt_password", "flight_id", "flight_number", "aircraft_identifier", "crew_pairing_code")
        for name in string_fields:
            env_name = name.upper()
            if env_name in os.environ and os.environ[env_name]:
                setattr(self, name, os.environ[env_name])
        if os.environ.get("MQTT_PORT"):
            self.mqtt_port = int(os.environ["MQTT_PORT"])
        if os.environ.get("ACCESS_TOKEN_EXPIRE_MINUTES"):
            self.access_token_expire_minutes = int(os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"])
        if "MQTT_ENABLED" in os.environ:
            self.mqtt_enabled = os.environ["MQTT_ENABLED"].lower() in {"1", "true", "yes", "on"}
        if "DEMO_SEED" in os.environ:
            self.demo_seed = os.environ["DEMO_SEED"].lower() in {"1", "true", "yes", "on"}
        if os.environ.get("CORS_ORIGINS"):
            self.cors_origins = [item.strip() for item in os.environ["CORS_ORIGINS"].split(",") if item.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
