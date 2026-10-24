from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class PassengerIn(BaseModel):
    external_passenger_id: str | None = None
    given_name: str
    family_name: str
    passenger_type: str = "adult"


class SegmentIn(BaseModel):
    external_segment_id: str | None = None
    flight_number: str
    airline_code: str
    departure_airport: str
    arrival_airport: str
    departure_time: datetime
    arrival_time: datetime
    segment_status: str = "confirmed"


class SeatIn(BaseModel):
    external_passenger_id: str
    external_segment_id: str
    seat_number: str | None = None
    cabin_class: str | None = None
    boarding_group: str | None = None
    seat_status: str = "confirmed"


class BookingSyncRequest(BaseModel):
    external_user_id: str | None = None
    email: str | None = None
    display_name: str | None = None
    preferred_language: str = "en"
    external_order_id: str
    external_booking_reference: str | None = None
    booking_status: str = "confirmed"
    source_system: str | None = None
    passengers: list[PassengerIn] = Field(default_factory=list)
    segments: list[SegmentIn] = Field(default_factory=list)
    seats: list[SeatIn] = Field(default_factory=list)
    raw_metadata: dict | None = None


class SeatAssignmentResponse(BaseModel):
    id: UUID
    booking_segment_id: UUID
    booking_passenger_id: UUID
    seat_number: str | None
    cabin_class: str | None
    boarding_group: str | None
    seat_status: str
    model_config = {"from_attributes": True}


class SegmentResponse(BaseModel):
    id: UUID
    flight_number: str
    airline_code: str
    departure_airport: str
    arrival_airport: str
    departure_time: datetime
    arrival_time: datetime
    segment_status: str
    seat_assignments: list[SeatAssignmentResponse] = []
    model_config = {"from_attributes": True}


class BookingResponse(BaseModel):
    id: UUID
    user_id: UUID
    external_order_id: str
    external_booking_reference: str | None
    booking_status: str
    segments: list[SegmentResponse] = []
    model_config = {"from_attributes": True}
