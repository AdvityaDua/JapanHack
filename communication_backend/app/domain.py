from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from uuid import UUID, uuid4


class RequestStatus(StrEnum):
    CREATED = "created"
    ACKNOWLEDGED = "acknowledged"
    IN_PROGRESS = "in_progress"
    FULFILLED = "fulfilled"
    CANCELLED = "cancelled"
    EXPIRED = "expired"
    ESCALATED = "escalated"


class RequestCategory(StrEnum):
    ASSISTANCE = "assistance"
    WATER = "water"
    FOOD = "food"
    MEDICAL = "medical"
    LANGUAGE = "language_assistance"
    MOBILITY = "mobility"
    SEAT = "seat_issue"
    ANNOUNCEMENT = "announcement_help"
    CUSTOM = "custom"


VALID_TRANSITIONS: dict[RequestStatus, set[RequestStatus]] = {
    RequestStatus.CREATED: {RequestStatus.ACKNOWLEDGED, RequestStatus.CANCELLED, RequestStatus.EXPIRED},
    RequestStatus.ACKNOWLEDGED: {RequestStatus.IN_PROGRESS, RequestStatus.CANCELLED, RequestStatus.ESCALATED},
    RequestStatus.IN_PROGRESS: {RequestStatus.FULFILLED, RequestStatus.CANCELLED, RequestStatus.ESCALATED},
    RequestStatus.ESCALATED: {RequestStatus.ACKNOWLEDGED, RequestStatus.IN_PROGRESS, RequestStatus.FULFILLED},
    RequestStatus.FULFILLED: set(),
    RequestStatus.CANCELLED: set(),
    RequestStatus.EXPIRED: set(),
}


@dataclass(frozen=True)
class CommunicationRequest:
    id: str
    flight_id: str
    passenger_device_id: str
    seat_token: str
    category: str
    message: str | None
    urgency: str
    status: str
    assigned_crew_device_id: str | None
    created_at: str
    updated_at: str


def new_id() -> str:
    return str(uuid4())


def now_iso() -> str:
    return datetime.now(UTC).isoformat()


def validate_transition(current: str, target: str) -> None:
    try:
        allowed = VALID_TRANSITIONS[RequestStatus(current)]
    except ValueError as exc:
        raise ValueError(f"Unknown current status: {current}") from exc
    if RequestStatus(target) not in allowed:
        raise ValueError(f"Invalid request transition: {current} -> {target}")
