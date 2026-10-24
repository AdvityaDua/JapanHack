from uuid import UUID

from pydantic import BaseModel


class ModelResponse(BaseModel):
    id: UUID
    name: str
    version: str
    source_language: str
    target_language: str
    model_type: str
    platform: str
    file_size_bytes: int
    sha256_checksum: str
    minimum_app_version: str | None
    status: str
    model_config = {"from_attributes": True}


class DownloadURLResponse(BaseModel):
    model_id: UUID
    download_url: str
    expires_in_seconds: int
    sha256_checksum: str
