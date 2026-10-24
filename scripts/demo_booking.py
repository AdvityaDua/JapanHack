"""Seed a partner API key and/or send a sample booking to the local API.

Examples:
    .venv/bin/python scripts/demo_booking.py seed
    .venv/bin/python scripts/demo_booking.py sync --api-key <printed-key>
"""

import argparse
import json
import sys
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.request import Request, urlopen

# Make `python scripts/demo_booking.py ...` work from the repository root.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.security import generate_api_key, hash_api_key
from app.db.models import APIClient, APIKey
from app.db.session import Base, SessionLocal, engine


def seed_partner() -> None:
    Base.metadata.create_all(bind=engine)
    api_key = generate_api_key()
    with SessionLocal() as db:
        client = APIClient(
            organization_name="Demo Airline",
            client_id=f"demo-client-{uuid.uuid4().hex[:8]}",
            scopes="bookings:write,bookings:read",
        )
        db.add(client)
        db.flush()
        db.add(
            APIKey(
                api_client_id=client.id,
                key_prefix=api_key[:12],
                key_hash=hash_api_key(api_key),
                expires_at=datetime.now(UTC) + timedelta(hours=2),
            )
        )
        db.commit()
        print(f"Partner client: {client.client_id}")
        print(f"Partner API key: {api_key}")


def sync_booking(base_url: str, api_key: str) -> None:
    payload = {
        "external_user_id": "demo-passenger-001",
        "email": "demo.passenger@example.com",
        "display_name": "Demo Passenger",
        "preferred_language": "hi",
        "external_order_id": f"DEMO-ORDER-{uuid.uuid4().hex[:8].upper()}",
        "external_booking_reference": "DEMO123",
        "booking_status": "confirmed",
        "source_system": "demo-booking-script",
        "passengers": [{"external_passenger_id": "demo-pax-001", "given_name": "Demo", "family_name": "Passenger", "passenger_type": "adult"}],
        "segments": [{"external_segment_id": "demo-segment-001", "flight_number": "JL707", "airline_code": "JL", "departure_airport": "NRT", "arrival_airport": "DEL", "departure_time": "2026-11-15T10:30:00Z", "arrival_time": "2026-11-15T17:00:00Z", "segment_status": "confirmed"}],
        "seats": [{"external_passenger_id": "demo-pax-001", "external_segment_id": "demo-segment-001", "seat_number": "32A", "cabin_class": "economy", "boarding_group": "B", "seat_status": "confirmed"}],
    }
    request = Request(
        f"{base_url.rstrip('/')}/api/v1/integrations/bookings",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "X-API-Key": api_key, "Idempotency-Key": f"demo-sync-{uuid.uuid4()}"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=15) as response:
            print(json.dumps(json.load(response), indent=2))
    except Exception as exc:
        print(f"Booking sync failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("seed", help="create a short-lived demo partner API key")
    sync_parser = subparsers.add_parser("sync", help="send a sample booking to the API")
    sync_parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    sync_parser.add_argument("--api-key", required=True)
    args = parser.parse_args()
    if args.command == "seed":
        seed_partner()
    else:
        sync_booking(args.base_url, args.api_key)


if __name__ == "__main__":
    main()
