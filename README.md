# HASHI 橋 — Every Language. One Journey.

HASHI is an offline-first airline communication platform for passengers and cabin crew. It helps passengers communicate essential needs and understand crew messages when spoken English, regional accents, cabin noise or limited language proficiency create a barrier.

The hackathon prototype combines a central cloud backend, an aircraft-local communication backend, a passenger Flutter app and a crew tablet dashboard.

## Product journey

```text
Passenger books → account and preferences sync → models become ready
       → passenger boards → local aircraft communication → post-flight assistance
```

Passengers can use large visual request cards, text or voice. Crew members receive a live, seat-aware queue. Flight-wide announcements are sent once and translated locally on each passenger device into that passenger's preferred language.

The complete presentation-ready flow is documented in [docs/END_TO_END_PRODUCT_FLOW.md](docs/END_TO_END_PRODUCT_FLOW.md).

## Architecture

```text
Airline / Internet
        │
Central FastAPI API ── PostgreSQL/Neon ── Cloudflare R2 ── FCM
        │ pre-flight synchronization
Aircraft Wi-Fi
        │
Aircraft edge FastAPI ── SQLite ── WebSockets ── optional MQTT
        ├── Passenger Flutter app + local models + TTS
        └── Crew Flutter tablet + live queue + seat map
```

### Central backend (`app/`)

- Passenger authentication, profiles and accessibility preferences.
- Flight, passenger, segment, booking and seat data.
- Partner booking synchronization with API-key authentication.
- Idempotent writes using `Idempotency-Key`.
- PostgreSQL/Neon in shared environments and SQLite fallback locally.
- Alembic migrations.
- Cloudflare R2 model metadata and short-lived download URLs.
- Firebase Cloud Messaging device registration and online notifications.

### Aircraft edge backend (`communication_backend/`)

- FastAPI commands and queries on the aircraft-local server.
- SQLite persistence for the local flight/request queue.
- WebSockets for real-time passenger and crew updates.
- Optional MQTT adapter for future cabin hardware and broker-driven events.
- Pairing, seat-aware sessions, passenger requests and flight-wide announcements.
- Range-enabled model downloads with resume support.

### Flutter applications

- `flutter-app_Hashi/`: passenger app with booking sync, model readiness, visual cards, local speech recognition, translation and text-to-speech.
- `crew_flutter/`: tablet-first crew dashboard with live requests, passenger preferences, seat map, statuses and announcements.

The current hackathon demo uses HTTP plus WebSockets as the primary edge path. MQTT can remain disabled.

## Local setup

```bash
cp .env.example .env
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Open the API documentation at http://localhost:8000/docs.

With no `DATABASE_URL`, development uses `local.db`. For Neon, set the pooled PostgreSQL URL in `.env`. R2 download URLs require the R2 variables to be populated.

For Windows PowerShell:

```powershell
Copy-Item .env.example .env
uv venv
.\.venv\Scripts\Activate.ps1
uv pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Aircraft communication backend

```bash
cd communication_backend
cp .env.example .env
uv run --with fastapi --with uvicorn --with paho-mqtt --with websockets \
  uvicorn app.main:app --host 0.0.0.0 --port 8001
```

For Android testing through ADB:

```bash
adb reverse tcp:8001 tcp:8001
```

The passenger app then uses `http://127.0.0.1:8001`. A second device on the same Wi-Fi should use the host laptop's LAN address. MQTT is disabled by default for the two-phone demo.

### Flutter apps

```bash
cd flutter-app_Hashi
flutter pub get
flutter run -d chrome

cd ../crew_flutter
flutter pub get
flutter run -d chrome
```

## Implemented API surface

- `GET /health`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/users/me`
- `GET /api/v1/users/me/bookings`
- `GET /api/v1/users/me/bookings/{booking_id}`
- `POST /api/v1/integrations/bookings`
- `POST /api/v1/notifications/devices`
- `DELETE /api/v1/notifications/devices/{device_id}`
- `GET /api/v1/models`
- `POST /api/v1/models/{model_id}/download-url`

Partner booking writes require `X-API-Key` and `Idempotency-Key` headers. API clients and keys should be created through an admin workflow or seed script before integration.

The aircraft API, WebSocket event envelope and optional MQTT topics are documented in [communication_backend/CONTRACT_MAP.md](communication_backend/CONTRACT_MAP.md).

## Demo flow

1. Start the central backend on port `8000`.
2. Apply migrations with `alembic upgrade head`.
3. Create or use the demo passenger account.
4. Run `scripts/demo_booking.py` to synchronize a ticket and seat through the booking API.
5. Start the aircraft backend on port `8001`.
6. Start the passenger and crew Flutter apps.
7. Pair both apps with the local edge backend.
8. Send a passenger card request and show it in the crew queue.
9. Update the request status and show the passenger-side live update.
10. Broadcast an announcement and demonstrate local translation on the passenger device.

To synchronize a demo ticket through the real partner booking endpoint:

```bash
./.venv/bin/python scripts/demo_booking.py demo \
  --email demo.passenger@example.com \
  --external-user-id demo-passenger-001
```

Customize the seat or booking reference when needed:

```bash
./.venv/bin/python scripts/demo_booking.py demo \
  --email demo.passenger@example.com \
  --booking-reference JAL-DEMO-001 \
  --seat 24A
```

The email must belong to a user already registered in the central database. Reusing the same order/idempotency value updates the booking instead of creating a duplicate.

## Repository layout

```text
app/                         Central FastAPI backend
alembic/                     Central database migrations
communication_backend/       Aircraft-local FastAPI edge service
crew_flutter/                Crew tablet Flutter app
flutter-app_Hashi/           Passenger Flutter app
scripts/demo_booking.py      Demo booking synchronization
docs/                        Product flow and UI documentation
BACKEND_CONTRACT.md          Central API contract
TESTING.md                   Test and validation notes
```

## Firebase push notifications

The passenger Android app registers its FCM token at
`POST /api/v1/notifications/devices`. When a partner booking is created, the
backend sends a booking-confirmed notification and, for a newly created user,
a reminder to complete preferences.

The Android client requires a local `google-services.json` file for Firebase
builds. It is intentionally ignored by Git. Keep the Firebase Admin
service-account JSON outside Git and set these backend variables in `.env`:

```dotenv
FIREBASE_CREDENTIALS_PATH=/absolute/path/to/japan-hack-firebase-adminsdk.json
FIREBASE_PROJECT_ID=japan-hack
```

The service account is only used by the FastAPI process to send FCM messages; it
must never be placed in the Flutter app or committed to the repository.

## Model distribution

There are two model paths:

1. **Central path:** the central API exposes model metadata and creates short-lived R2 download URLs.
2. **Aircraft path:** the edge server serves model files over cabin Wi-Fi, including HTTP ranges for resumable downloads.

Large model binaries and the real manifest are intentionally excluded from Git.
Provision them on the edge server:

```bash
cd communication_backend
cp models/manifest.example.json models/manifest.json
# Copy model files into models/{model-id}/ according to the manifest
```

See [communication_backend/models/README.md](communication_backend/models/README.md).

## Security and production notes

This is a hackathon prototype. Before production airline deployment:

- Rotate any credential that has ever been exposed.
- Use HTTPS and restrict `CORS_ORIGINS`.
- Keep R2 private and use short-lived download URLs.
- Replace demo pairing codes with per-flight provisioning and device certificates.
- Add rate limiting, audit logging, encrypted edge storage and data-retention rules.
- Add MQTT ACLs if MQTT is enabled.
- Do not log API keys, passwords, ticket numbers or raw booking payloads.

## Documentation map

- [End-to-end product flow](docs/END_TO_END_PRODUCT_FLOW.md)
- [Central API contract](BACKEND_CONTRACT.md)
- [Aircraft edge contract](communication_backend/CONTRACT_MAP.md)
- [Aircraft edge implementation plan](communication_backend/IMPLEMENTATION_PLAN.md)
- [Crew tablet UI specification](docs/CREW_TABLET_UI_SPEC.md)
- [Passenger backend integration](flutter-app_Hashi/BACKEND_INTEGRATION.md)
- [Testing notes](TESTING.md)

## Status

The current target is a local, demonstrable end-to-end flow between a passenger
phone, an aircraft-local backend and a crew tablet. Production deployment would
require airline-system integration, device provisioning, monitoring, security
hardening and real-device cabin testing.
