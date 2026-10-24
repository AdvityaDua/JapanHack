from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import CHAR, JSON, Boolean, DateTime, ForeignKey, Integer, String, Text, TypeDecorator, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base

class UUIDType(TypeDecorator):
    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "postgresql":
            return dialect.type_descriptor(PGUUID(as_uuid=True))
        return dialect.type_descriptor(CHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return value if dialect.name == "postgresql" else str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return value if dialect.name == "postgresql" else str(value)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class User(TimestampMixin, Base):
    __tablename__ = "users"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    external_user_id: Mapped[str | None] = mapped_column(String(255), unique=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(255))
    preferred_language: Mapped[str] = mapped_column(String(20), default="en")
    password_hash: Mapped[str] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(30), default="active")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    preferences = relationship("UserPreference", back_populates="user", uselist=False, cascade="all, delete-orphan")
    bookings = relationship("Booking", back_populates="user")


class UserPreference(TimestampMixin, Base):
    __tablename__ = "user_preferences"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    spoken_language: Mapped[str] = mapped_column(String(20), default="en")
    display_language: Mapped[str] = mapped_column(String(20), default="en")
    translation_mode: Mapped[str] = mapped_column(String(30), default="conversation")
    voice_input_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    text_to_speech_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    font_scale: Mapped[int] = mapped_column(Integer, default=100)
    high_contrast_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    senior_mode_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    hearing_assistance_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    user = relationship("User", back_populates="preferences")


class AirlinePartner(TimestampMixin, Base):
    __tablename__ = "airline_partners"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    name: Mapped[str] = mapped_column(String(255))
    iata_code: Mapped[str | None] = mapped_column(String(3))
    icao_code: Mapped[str | None] = mapped_column(String(4))
    status: Mapped[str] = mapped_column(String(30), default="active")


class APIClient(TimestampMixin, Base):
    __tablename__ = "api_clients"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    organization_name: Mapped[str] = mapped_column(String(255))
    client_id: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    airline_partner_id: Mapped[UUID | None] = mapped_column(ForeignKey("airline_partners.id"))
    status: Mapped[str] = mapped_column(String(30), default="active")
    scopes: Mapped[str] = mapped_column(String(500), default="bookings:write,bookings:read")


class APIKey(Base):
    __tablename__ = "api_keys"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    api_client_id: Mapped[UUID] = mapped_column(ForeignKey("api_clients.id", ondelete="CASCADE"))
    key_prefix: Mapped[str] = mapped_column(String(16))
    key_hash: Mapped[str] = mapped_column(String(128), unique=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    __table_args__ = (UniqueConstraint("api_client_id", "idempotency_key", name="uq_idempotency_client_key"),)
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    api_client_id: Mapped[UUID] = mapped_column(ForeignKey("api_clients.id", ondelete="CASCADE"))
    idempotency_key: Mapped[str] = mapped_column(String(255))
    booking_id: Mapped[UUID | None] = mapped_column(ForeignKey("bookings.id", ondelete="SET NULL"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Booking(TimestampMixin, Base):
    __tablename__ = "bookings"
    __table_args__ = (UniqueConstraint("api_client_id", "external_order_id", name="uq_booking_external_order"),)
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), index=True)
    api_client_id: Mapped[UUID] = mapped_column(ForeignKey("api_clients.id"), index=True)
    external_order_id: Mapped[str] = mapped_column(String(255))
    external_booking_reference: Mapped[str | None] = mapped_column(String(100))
    booking_status: Mapped[str] = mapped_column(String(30), default="confirmed")
    source_system: Mapped[str | None] = mapped_column(String(100))
    raw_metadata: Mapped[dict | None] = mapped_column(JSON)
    user = relationship("User", back_populates="bookings")
    passengers = relationship("BookingPassenger", back_populates="booking", cascade="all, delete-orphan")
    segments = relationship("BookingSegment", back_populates="booking", cascade="all, delete-orphan")


class BookingPassenger(Base):
    __tablename__ = "booking_passengers"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    booking_id: Mapped[UUID] = mapped_column(ForeignKey("bookings.id", ondelete="CASCADE"))
    user_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    external_passenger_id: Mapped[str | None] = mapped_column(String(100))
    given_name: Mapped[str] = mapped_column(String(100))
    family_name: Mapped[str] = mapped_column(String(100))
    passenger_type: Mapped[str] = mapped_column(String(30), default="adult")
    booking = relationship("Booking", back_populates="passengers")


class BookingSegment(Base):
    __tablename__ = "booking_segments"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    booking_id: Mapped[UUID] = mapped_column(ForeignKey("bookings.id", ondelete="CASCADE"))
    external_segment_id: Mapped[str | None] = mapped_column(String(100))
    flight_number: Mapped[str] = mapped_column(String(20))
    airline_code: Mapped[str] = mapped_column(String(3))
    departure_airport: Mapped[str] = mapped_column(String(5))
    arrival_airport: Mapped[str] = mapped_column(String(5))
    departure_time: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    arrival_time: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    segment_status: Mapped[str] = mapped_column(String(30), default="confirmed")
    booking = relationship("Booking", back_populates="segments")
    seat_assignments = relationship("SeatAssignment", back_populates="booking_segment", cascade="all, delete-orphan")


class SeatAssignment(Base):
    __tablename__ = "seat_assignments"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    booking_segment_id: Mapped[UUID] = mapped_column(ForeignKey("booking_segments.id", ondelete="CASCADE"))
    booking_passenger_id: Mapped[UUID] = mapped_column(ForeignKey("booking_passengers.id", ondelete="CASCADE"))
    seat_number: Mapped[str | None] = mapped_column(String(10))
    cabin_class: Mapped[str | None] = mapped_column(String(30))
    boarding_group: Mapped[str | None] = mapped_column(String(10))
    seat_status: Mapped[str] = mapped_column(String(30), default="confirmed")
    booking_segment = relationship("BookingSegment", back_populates="seat_assignments")


class Ticket(Base):
    __tablename__ = "tickets"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=lambda: str(uuid4()))
    booking_id: Mapped[UUID] = mapped_column(ForeignKey("bookings.id", ondelete="CASCADE"))
    booking_passenger_id: Mapped[UUID] = mapped_column(ForeignKey("booking_passengers.id", ondelete="CASCADE"))
    ticket_number_hash: Mapped[str | None] = mapped_column(String(128))
    ticket_number_last4: Mapped[str | None] = mapped_column(String(4))
    ticket_status: Mapped[str] = mapped_column(String(30), default="issued")


class TranslationModel(TimestampMixin, Base):
    __tablename__ = "translation_models"
    id: Mapped[UUID] = mapped_column(UUIDType, primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(255))
    version: Mapped[str] = mapped_column(String(50))
    source_language: Mapped[str] = mapped_column(String(20), index=True)
    target_language: Mapped[str] = mapped_column(String(20), index=True)
    model_type: Mapped[str] = mapped_column(String(50), default="translation")
    platform: Mapped[str] = mapped_column(String(30), default="all")
    file_size_bytes: Mapped[int] = mapped_column(Integer)
    r2_object_key: Mapped[str] = mapped_column(String(1024), unique=True)
    sha256_checksum: Mapped[str] = mapped_column(String(64))
    minimum_app_version: Mapped[str | None] = mapped_column(String(50))
    status: Mapped[str] = mapped_column(String(30), default="draft")
