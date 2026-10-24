"""Deterministic local demo data for the aircraft-edge prototype."""

import hashlib
from datetime import UTC, datetime, timedelta

from app.config import settings
from app.domain import new_id
from app.service import issue_device_token
from app.store import store


DEMO_REQUESTS = (
    ("24A", "Tamil", "water", "Thanneer vendum.", "normal", "created", 2),
    ("18C", "Hindi", "blanket", "Could I have a blanket?", "normal", "in_progress", 8),
    ("12F", "Punjabi", "food", "Is this vegetarian?", "normal", "created", 14),
    ("31B", "Bengali", "assistance", "I need help, please.", "urgent", "created", 21),
    ("7A", "English", "food", "Juice please.", "normal", "fulfilled", 28),
    ("21D", "Marathi", "pillow", "One pillow, please.", "normal", "fulfilled", 39),
    ("14C", "Telugu", "assistance", "I need assistance.", "normal", "fulfilled", 52),
)


def seed_demo_seat_map() -> int:
    """Create a realistic 30-row 2-4-2 aircraft layout once."""
    columns = ("A", "B", "C", "D", "E", "F", "G", "H")
    inserted = 0
    occupied = {"3C", "5F", "9B", "16G", "22D"}
    for row_number in range(1, 31):
        for seat_order, column in enumerate(columns):
            seat_number = f"{row_number}{column}"
            seat_type = "window" if column in {"A", "H"} else "aisle" if column in {"B", "C", "F", "G"} else "middle"
            before = store.list_seats(settings.flight_id)
            if any(row["seat_number"] == seat_number for row in before):
                continue
            store.save_seat({"flight_id": settings.flight_id, "seat_number": seat_number, "row_number": row_number, "seat_column": column, "seat_order": seat_order, "cabin_class": "business" if row_number <= 4 else "economy", "seat_type": seat_type, "occupancy_status": "occupied" if seat_number in occupied else "available"})
            inserted += 1
    return inserted


def seed_demo_data() -> int:
    """Insert demo passenger devices and requests once; return new request count."""
    inserted = 0
    now = datetime.now(UTC)
    for seat, language, category, message, urgency, status, age_minutes in DEMO_REQUESTS:
        request_id = f"demo-{seat.lower()}"
        if store.get_request(request_id):
            continue
        device_id = f"demo-passenger-{seat.lower()}"
        seat_token = f"demo-seat-token-{seat.lower()}"
        if not store.get_device(device_id):
            demo_token = issue_device_token(device_id, settings.flight_id, "passenger")
            store.save_device({"id": device_id, "flight_id": settings.flight_id, "device_type": "passenger", "display_name": f"Passenger {seat}", "seat_number": seat, "seat_token": seat_token, "token_hash": hashlib.sha256(demo_token.encode()).hexdigest(), "status": "active", "last_seen_at": now.isoformat()})
        created_at = (now - timedelta(minutes=age_minutes)).isoformat()
        request = {"id": request_id, "flight_id": settings.flight_id, "passenger_device_id": device_id, "seat_token": seat_token, "seat_number": seat, "passenger_language": language, "category": category, "message": message, "urgency": urgency, "status": status, "assigned_crew_device_id": None, "created_at": created_at, "updated_at": created_at}
        event = {"event_id": new_id(), "event_type": "request.created", "event_version": 1, "flight_id": settings.flight_id, "aggregate_id": request_id, "producer": "demo-seed", "device_id": device_id, "occurred_at": created_at, "payload": request}
        store.create_request(request, event, f"flight/{settings.flight_id}/events/request-created", created_at)
        inserted += 1
    return inserted
