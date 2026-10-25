# Cabin–Passenger Communication Backend

This backend is intended to run on an aircraft-local server and provide a communication layer between passenger mobile apps and cabin-crew devices.

For the two-phone local demo, MQTT can remain disabled. The passenger and crew apps communicate through HTTP and WebSockets while SQLite stores the requests locally.

```bash
cd communication_backend
/Users/advityadua/.platformio/penv/bin/python -m pip install -r requirements.txt
/Users/advityadua/.platformio/penv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Use the laptop's LAN IP from the phones, for example `http://192.168.1.20:8000`, not `localhost`. MQTT is enabled only when `MQTT_ENABLED=true`.

Set `CREW_PAIRING_CODE` in the communication backend environment and use the same value when pairing the crew app. The default `CREW-DEMO` value is intended only for local development.

For a backend-backed demo queue, set `DEMO_SEED=true`. On startup the backend inserts seven deterministic passenger requests into SQLite, including pending, in-progress, and completed records. The seed is idempotent, so restarting the server does not duplicate them. The Flutter crew dashboard starts empty and only displays these records after pairing with the backend.

```bash
cd communication_backend
cp .env.example .env
uv run --with fastapi --with uvicorn --with paho-mqtt --with websockets uvicorn app.main:app --host 0.0.0.0 --port 8001
```

The backend should not depend on internet connectivity during the flight. It should continue working over the aircraft's local Wi-Fi network and synchronize with the cloud backend when connectivity returns.

## Aircraft model cache

The edge server can distribute large speech and translation bundles over the
aircraft Wi-Fi network. Copy the model files into `models/{model-id}/`, create
`models/manifest.json` from `models/manifest.example.json`, and start the edge
server normally. Paired passenger devices can then call `GET /api/v1/models`
and download declared files from `GET /api/v1/models/{model_id}/{file_name}`.
Downloads support HTTP ranges, so the passenger app can resume after a brief
Wi-Fi interruption. Model files and the real manifest are intentionally
ignored by Git because they can be hundreds of megabytes or larger.

## Core use case

```text
Passenger mobile app
        ↓ local aircraft network
Aircraft communication backend
        ↓
Cabin crew tablet/display
```

A passenger should be able to send a clear, structured request such as:

- Assistance needed
- Water
- Food or beverage
- Medical assistance
- Language assistance
- Wheelchair or mobility support
- Seat issue
- Feeling unwell
- Cannot hear or understand announcement
- Custom text or translated voice request

The crew should see the request with enough context to respond, but without requiring unnecessary personal information.

## Architecture options

### Option A — Local FastAPI server with WebSockets

The aircraft hosts a small FastAPI server. Passenger apps and crew tablets connect over the aircraft Wi-Fi network. WebSockets deliver new requests and status updates in real time.

```text
Passenger app ──WebSocket/HTTP──> FastAPI edge server <──WebSocket/HTTP── Crew tablet
                                      │
                                      └── local SQLite/PostgreSQL-compatible store
```

Advantages:

- Easiest to build and demonstrate
- Fits the existing FastAPI ecosystem
- Real-time updates are straightforward
- Simple request/response model
- Easy Swagger documentation
- Works well for a hackathon prototype

Limitations:

- Clients must reconnect after Wi-Fi interruptions
- The server must manage connection state
- Scaling to many aircraft would require a cloud control plane later

Best for: the first working prototype.

### Option B — MQTT-based event communication

The aircraft hosts an MQTT broker. Passenger apps publish requests, and crew devices subscribe to relevant topics.

Example topics:

```text
flight/{flight_id}/requests
flight/{flight_id}/crew-updates
flight/{flight_id}/announcements
device/{device_id}/status
```

Advantages:

- Designed for unreliable networks and intermittent clients
- Lightweight for mobile and embedded devices
- Built-in publish/subscribe model
- Quality-of-service levels support delivery guarantees
- Good fit for future sensors or seat hardware

Limitations:

- Requires an MQTT broker and topic authorization
- More infrastructure and operational complexity
- Request history and permissions still need an application backend
- Browser/mobile debugging is less direct than HTTP/WebSockets

Best for: a production-like aircraft edge system or future IoT integration.

### Option C — HTTP sync with local request queue

Passenger apps submit requests through normal HTTP. The local backend stores them, and crew devices periodically poll or sync for updates.

```text
Passenger app ──HTTP POST──> Local server/database
Crew tablet  ──HTTP GET───> Local server/database
```

Advantages:

- Simplest implementation and debugging
- Works well with offline-first mobile clients
- Requests survive app and network restarts
- Easy to test using curl or Swagger
- No persistent socket management

Limitations:

- Not instantly real-time unless polling is frequent
- More battery and network usage from polling
- Crew updates may be delayed by the polling interval

Best for: a highly reliable MVP where a delay of a few seconds is acceptable.

### Option D — Hybrid edge communication layer

Use HTTP for durable commands and WebSockets for live updates.

```text
Passenger app ──HTTP POST──────────────> Edge backend/database
Passenger app <──WebSocket notification── Edge backend
Crew tablet  <──WebSocket live queue──── Edge backend
Crew tablet  ──HTTP PATCH status────────> Edge backend/database
```

Advantages:

- Durable requests do not depend on an open socket
- Crew receives real-time updates
- Reconnection is straightforward
- Best balance of reliability and user experience
- Easy migration from a prototype to a production edge service

Limitations:

- More code than HTTP-only
- Requires careful duplicate-event handling
- WebSocket connection lifecycle still needs to be managed

Best for: the recommended implementation.

## Recommended approach

Start with Option D: a local FastAPI edge backend using:

- HTTP for creating and updating requests
- WebSockets for live queue updates
- SQLite for the aircraft-local MVP database
- A synchronization adapter for the cloud backend when online
- UUIDs and idempotency keys for every request

This gives us durable communication even when a device briefly disconnects, while still allowing the crew dashboard to update immediately.

MQTT can be added later if the system expands to seat hardware, cabin sensors, or multiple edge services.

## Suggested request lifecycle

```text
created → acknowledged → in_progress → fulfilled
                                  ↘ cancelled
```

Each request should contain:

- Request ID
- Flight/session ID
- Passenger device ID
- Seat number or seat token
- Request category
- Optional translated text
- Optional urgency
- Created timestamp
- Current status
- Assigned crew member/device
- Last updated timestamp

Avoid sending full passenger profile data to every crew device. The crew interface should receive only the information needed to fulfill the request.

## Initial data model

### `flight_sessions`

Represents the active aircraft session.

```text
id
flight_number
aircraft_identifier
departure_airport
arrival_airport
status
started_at
ended_at
```

### `devices`

Represents passenger phones, crew tablets, and the edge server.

```text
id
device_type
display_name
seat_number nullable
last_seen_at
status
```

### `communication_requests`

```text
id
flight_session_id
passenger_device_id
seat_number nullable
category
message
translated_message nullable
urgency
status
assigned_crew_device_id nullable
created_at
updated_at
```

### `request_events`

```text
id
request_id
event_type
actor_device_id
payload
created_at
```

This event history makes status changes auditable and allows disconnected devices to catch up.

## Passenger API

```text
POST /api/v1/edge/session/join
GET  /api/v1/edge/session/current

POST /api/v1/edge/requests
GET  /api/v1/edge/requests/{request_id}
POST /api/v1/edge/requests/{request_id}/cancel

WS   /api/v1/edge/ws/passenger
```

## Crew API

```text
POST /api/v1/edge/crew/devices/register
GET  /api/v1/edge/crew/requests
GET  /api/v1/crew/seat-map
GET  /api/v1/edge/crew/requests/{request_id}
PATCH /api/v1/edge/crew/requests/{request_id}/status
POST /api/v1/edge/crew/requests/{request_id}/assign

WS   /api/v1/edge/ws/crew
```

## Reliability requirements

- Every write accepts an idempotency key
- Requests are persisted before notifications are sent
- WebSocket clients receive events with sequence numbers
- Clients reconnect and request events after their last sequence number
- Status updates are append-only events plus a current status projection
- The crew tablet can acknowledge a request even if the passenger disconnects
- A request should visibly expire or be transferred at the end of the flight
- The server should expose a health endpoint and active-device count

## Security requirements

- The aircraft backend should use a per-flight session key
- Passenger devices should receive a short-lived device token after joining
- Crew devices should require a stronger crew token or PIN-based pairing
- Passenger devices must not list other passengers' requests
- Crew devices should only access the current flight session
- Rate-limit custom messages and request creation
- Do not store raw microphone recordings by default
- Avoid exposing full passenger personal information on crew screens
- Log security events without logging secrets or sensitive message content

## Open decisions before implementation

1. Should passengers identify themselves by seat number, QR code, booking token, or app login?
2. Should crew see the passenger's name, or only seat number and request?
3. Should requests be anonymous to the crew for sensitive assistance categories?
4. Is a few-second delay acceptable, or is instant delivery required?
5. Will the aircraft provide a local Wi-Fi network reachable by passenger phones?
6. Should crew be able to send translated replies back to passengers?
7. What happens to urgent medical requests if the crew tablet is offline?

## Proposed first implementation

Implement Option D with the following narrow MVP:

1. Flight-session creation and device pairing
2. Passenger request creation using category, seat token, and optional text
3. Crew request queue
4. WebSocket notifications
5. Request acknowledgement and status updates
6. Reconnect and event replay
7. SQLite persistence
8. Mock cloud synchronization endpoint

Do not add voice streaming, mesh networking, or full passenger profiles until the basic request lifecycle is validated.
