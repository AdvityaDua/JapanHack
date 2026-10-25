from pydantic import BaseModel, Field


class PushDeviceRegistration(BaseModel):
    device_id: str = Field(min_length=1, max_length=255)
    token: str = Field(min_length=20, max_length=4096)
    platform: str = Field(default="android", min_length=2, max_length=30)
    app_id: str | None = Field(default=None, max_length=255)


class PushDeviceResponse(PushDeviceRegistration):
    enabled: bool
