from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class SessionResponse(BaseModel):
    id: str
    flight_number: str
    aircraft_identifier: str
    status: str


class PairDeviceRequest(BaseModel):
    device_type: Literal["passenger", "crew"]
    display_name: str | None = None
    seat_number: str | None = None
    pairing_code: str | None = None


class PairDeviceResponse(BaseModel):
    device_id: str
    device_token: str
    flight_id: str
    device_type: str
    seat_token: str | None = None


class CreateRequestBody(BaseModel):
    device_id: str
    seat_token: str = Field(min_length=1, max_length=80)
    category: str
    message: str | None = Field(default=None, max_length=500)
    passenger_language: str = Field(default="English", min_length=1, max_length=80)
    urgency: Literal["normal", "high", "urgent"] = "normal"
    idempotency_key: str = Field(min_length=8, max_length=160)


class UpdateStatusBody(BaseModel):
    status: str
    crew_device_id: str | None = None
    note: str | None = Field(default=None, max_length=500)
    idempotency_key: str = Field(min_length=8, max_length=160)


class RequestResponse(BaseModel):
    id: str
    flight_id: str
    passenger_device_id: str
    seat_token: str
    seat_number: str | None = None
    passenger_language: str = "English"
    category: str
    message: str | None
    urgency: str
    status: str
    assigned_crew_device_id: str | None
    created_at: datetime
    updated_at: datetime


class EventResponse(BaseModel):
    event_id: str
    event_type: str
    aggregate_id: str
    sequence: int
    occurred_at: datetime
    payload: dict
