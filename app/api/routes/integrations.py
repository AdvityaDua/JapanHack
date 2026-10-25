from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.api.dependencies import DB, require_partner_client
from app.db.models import APIClient, Booking, BookingPassenger, BookingSegment, IdempotencyRecord, SeatAssignment, User, UserPreference
from app.schemas.booking import BookingResponse, BookingSyncRequest
from app.services.push import send_user_notification

router = APIRouter(prefix="/api/v1/integrations", tags=["partner integrations"])


@router.post("/bookings", response_model=BookingResponse, status_code=201)
def sync_booking(payload: BookingSyncRequest, db: DB, client: APIClient = Depends(require_partner_client), idempotency_key: str | None = Header(default=None)):
    if "bookings:write" not in client.scopes.split(","):
        raise HTTPException(status_code=403, detail="Missing bookings:write scope")
    if not idempotency_key:
        raise HTTPException(status_code=400, detail="Idempotency-Key header is required")
    prior_request = db.scalar(select(IdempotencyRecord).where(IdempotencyRecord.api_client_id == client.id, IdempotencyRecord.idempotency_key == idempotency_key))
    if prior_request and prior_request.booking_id:
        existing = db.scalar(select(Booking).options(selectinload(Booking.segments).selectinload(BookingSegment.seat_assignments)).where(Booking.id == prior_request.booking_id))
        if existing:
            return existing
    user = None
    new_user = False
    if payload.external_user_id:
        user = db.scalar(select(User).where(User.external_user_id == payload.external_user_id))
    if not user and payload.email:
        user = db.scalar(select(User).where(User.email == payload.email.lower()))
    if not user:
        if not payload.email:
            raise HTTPException(status_code=400, detail="email is required for a new user")
        user = User(email=payload.email.lower(), external_user_id=payload.external_user_id, display_name=payload.display_name, preferred_language=payload.preferred_language, password_hash="external-auth")
        db.add(user)
        db.flush()
        new_user = True
    if user.preferences is None:
        user.preferences = UserPreference(spoken_language=user.preferred_language, display_language=user.preferred_language)
    booking = db.scalar(select(Booking).options(selectinload(Booking.segments).selectinload(BookingSegment.seat_assignments)).where(Booking.api_client_id == client.id, Booking.external_order_id == payload.external_order_id))
    if booking:
        booking.booking_status = payload.booking_status
        booking.external_booking_reference = payload.external_booking_reference
        booking.raw_metadata = payload.raw_metadata
        db.commit()
        db.refresh(booking)
        return booking
    booking = Booking(user_id=user.id, api_client_id=client.id, external_order_id=payload.external_order_id, external_booking_reference=payload.external_booking_reference, booking_status=payload.booking_status, source_system=payload.source_system, raw_metadata=payload.raw_metadata)
    booking.passengers = [BookingPassenger(**item.model_dump()) for item in payload.passengers]
    booking.segments = [BookingSegment(**item.model_dump()) for item in payload.segments]
    db.add(booking)
    db.flush()
    passengers_by_external_id = {item.external_passenger_id: item for item in booking.passengers}
    segments_by_external_id = {item.external_segment_id: item for item in booking.segments}
    for seat in payload.seats:
        passenger = passengers_by_external_id.get(seat.external_passenger_id)
        segment = segments_by_external_id.get(seat.external_segment_id)
        if passenger and segment:
            db.add(SeatAssignment(booking_segment_id=segment.id, booking_passenger_id=passenger.id, seat_number=seat.seat_number, cabin_class=seat.cabin_class, boarding_group=seat.boarding_group, seat_status=seat.seat_status))
    db.add(IdempotencyRecord(api_client_id=client.id, idempotency_key=idempotency_key, booking_id=booking.id))
    db.commit()
    db.refresh(booking)
    send_user_notification(
        db,
        user.id,
        title="Flight booking confirmed",
        body=f"Your booking {booking.external_booking_reference or booking.external_order_id} is ready. Set your Hashi preferences before flying.",
        data={"type": "booking.confirmed", "booking_id": str(booking.id)},
    )
    if new_user:
        send_user_notification(
            db,
            user.id,
            title="Complete your Hashi preferences",
            body="Choose your language and accessibility preferences for a smoother flight.",
            data={"type": "preferences.required"},
        )
    return booking
