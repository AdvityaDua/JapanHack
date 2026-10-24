from uuid import UUID

from pydantic import BaseModel, Field


class PreferenceUpdate(BaseModel):
    spoken_language: str = Field(min_length=2, max_length=20)
    display_language: str = Field(min_length=2, max_length=20)
    translation_mode: str = Field(min_length=2, max_length=30)
    voice_input_enabled: bool = True
    text_to_speech_enabled: bool = True
    font_scale: int = Field(default=100, ge=80, le=200)
    high_contrast_enabled: bool = False
    senior_mode_enabled: bool = False
    hearing_assistance_enabled: bool = False


class PreferenceResponse(PreferenceUpdate):
    id: UUID
    user_id: UUID

    model_config = {"from_attributes": True}
