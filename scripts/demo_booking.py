"""Seed a partner API key and/or send a sample booking to the local API.

Examples:
    .venv/bin/python scripts/demo_booking.py seed
    .venv/bin/python scripts/demo_booking.py sync --api-key <printed-key>
    .venv/bin/python scripts/demo_booking.py demo --email passenger@example.com
"""

import argparse
import json
import os
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.request import Request, urlopen

from sqlalchemy import select

# Make `python scripts/demo_booking.py ...` work from the repository root.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.security import generate_api_key, hash_api_key
from app.db.models import APIClient, APIKey
from app.db.session import Base, SessionLocal, engine


def seed_partner() -> str:
    Base.metadata.create_all(bind=engine)
    api_key = generate_api_key()
    with SessionLocal() as db:
        client = db.scalar(select(APIClient).where(APIClient.client_id == "demo-client"))
        if not client:
            client = APIClient(
                organization_name="Demo Airline",
                client_id="demo-client",
                scopes="bookings:write,bookings:read",
            )
            db.add(client)
            db.flush()
        db.add(
            APIKey(
                api_client_id=client.id,
                key_prefix=api_key[:12],
                key_hash=hash_api_key(api_key),
                expires_at=datetime.now(timezone.utc) + timedelta(hours=2),
            )
        )
        db.commit()
        print(f"Partner client: {client.client_id}")
        print(f"Partner API key: {api_key}")
        return api_key


def sync_booking(
    base_url: str,
    api_key: str,
    *,
    email: str,
    external_user_id: str,
    order_id: str,
    booking_reference: str,
    seat_number: str,
    language: str,
) -> None:
    payload = {
        "external_user_id": external_user_id,
        "email": email,
        "display_name": "Demo Passenger",
        "preferred_language": language,
        "external_order_id": order_id,
        "external_booking_reference": booking_reference,
        "booking_status": "confirmed",
        "source_system": "demo-booking-script",
        "passengers": [{"external_passenger_id": "demo-pax-001", "given_name": "Demo", "family_name": "Passenger", "passenger_type": "adult"}],
        "segments": [{"external_segment_id": "demo-segment-001", "flight_number": "JL707", "airline_code": "JL", "departure_airport": "NRT", "arrival_airport": "DEL", "departure_time": "2026-11-15T10:30:00Z", "arrival_time": "2026-11-15T17:00:00Z", "segment_status": "confirmed"}],
        "seats": [{"external_passenger_id": "demo-pax-001", "external_segment_id": "demo-segment-001", "seat_number": seat_number, "cabin_class": "economy", "boarding_group": "B", "seat_status": "confirmed"}],
    }
    request = Request(
        f"{base_url.rstrip('/')}/api/v1/integrations/bookings",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "X-API-Key": api_key, "Idempotency-Key": f"demo-sync-{uuid.uuid4()}"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=15) as response:
            result = json.load(response)
            print("Booking synchronized successfully")
            print(f"User: {email} ({external_user_id})")
            print(f"Booking ID: {result['id']}")
            print(f"Booking reference: {result['external_booking_reference']}")
            for segment in result.get("segments", []):
                print(
                    f"Flight: {segment['airline_code']}{segment['flight_number']} "
                    f"{segment['departure_airport']} → {segment['arrival_airport']}"
                )
                for seat in segment.get("seat_assignments", []):
                    print(f"Seat: {seat['seat_number']} ({seat['cabin_class']})")
    except Exception as exc:
        print(f"Booking sync failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("seed", help="create a short-lived demo partner API key")
    sync_parser = subparsers.add_parser("sync", help="send or update a sample booking")
    sync_parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    sync_parser.add_argument("--api-key", required=True)
    add_demo_options(sync_parser)
    demo_parser = subparsers.add_parser(
        "demo",
        help="create a short-lived partner key and synchronize one demo booking",
    )
    demo_parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    add_demo_options(demo_parser)
    args = parser.parse_args()
    if args.command == "seed":
        seed_partner()
    elif args.command == "demo":
        api_key = seed_partner()
        sync_booking(args.base_url, api_key, **booking_options(args))
    else:
        sync_booking(args.base_url, args.api_key, **booking_options(args))


def add_demo_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--email",
        default=os.getenv("DEMO_USER_EMAIL", "demo.passenger@example.com"),
        help="email of the existing user to receive the booking",
    )
    parser.add_argument(
        "--external-user-id",
        default=os.getenv("DEMO_EXTERNAL_USER_ID", "demo-passenger-001"),
    )
    parser.add_argument("--order-id", default="DEMO-ORDER-001")
    parser.add_argument("--booking-reference", default="DEMO123")
    parser.add_argument("--seat", default="32A")
    parser.add_argument("--language", default="hi")


def booking_options(args: argparse.Namespace) -> dict[str, str]:
    return {
        "email": args.email.lower(),
        "external_user_id": args.external_user_id,
        "order_id": args.order_id,
        "booking_reference": args.booking_reference,
        "seat_number": args.seat,
        "language": args.language,
    }


if __name__ == "__main__":
    main()
