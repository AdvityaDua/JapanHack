from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.api.dependencies import DB, get_current_user
from app.db.models import Booking, BookingSegment, User
from app.schemas.booking import BookingResponse

router = APIRouter(prefix="/api/v1/users/me/bookings", tags=["bookings"])


@router.get("", response_model=list[BookingResponse])
def list_bookings(db: DB, user: User = Depends(get_current_user)):
    return db.scalars(select(Booking).options(selectinload(Booking.segments).selectinload(BookingSegment.seat_assignments)).where(Booking.user_id == user.id).order_by(Booking.created_at.desc())).all()


@router.get("/{booking_id}", response_model=BookingResponse)
def get_booking(booking_id: str, db: DB, user: User = Depends(get_current_user)):
    booking = db.scalar(select(Booking).options(selectinload(Booking.segments).selectinload(BookingSegment.seat_assignments)).where(Booking.id == booking_id, Booking.user_id == user.id))
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    return booking
