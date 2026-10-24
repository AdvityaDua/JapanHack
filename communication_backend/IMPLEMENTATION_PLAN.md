# Aircraft Communication Backend Implementation Plan

## Goal

Provide a flight-local, event-driven communication layer that lets passengers send structured requests to cabin crew and receive status updates without requiring internet connectivity.

## Runtime topology

```text
Flutter passenger app ──HTTP/WebSocket──┐
                                        │
Flutter crew app ──────HTTP/WebSocket───┼── FastAPI edge service
                                        │       │
Flutter MQTT mode ─────MQTT────────────┘       ├── SQLite
                                                ├── inbox/outbox
                                                └── MQTT client
                                                        │
                                                 Mosquitto broker
                                                        │
                                                Cloud sync adapter
```

FastAPI and MQTT are complementary:

- FastAPI is the external application adapter and diagnostics surface.
- MQTT is the local event transport.
- SQLite is the source of truth during the flight.
- WebSockets deliver events to Flutter without requiring Flutter to implement MQTT first.
- MQTT direct mode can be enabled when the app needs a fully event-native path.

## Current implementation

The MVP currently includes:

- Local SQLite schema creation
- Active flight-session bootstrap
- Passenger and crew device pairing
- Short-lived HMAC device tokens
- Passenger request creation
- Crew request queue
- Crew status transitions
- WebSocket event delivery
- MQTT command adapter
- Inbox duplicate protection
- Transactional request event and outbox writes
- Outbox publishing loop
- HTTP event replay by sequence number
- Flutter contract map

## Implementation phases

### Phase 1: Local flight session

At process startup:

1. Initialize SQLite.
2. Create the active flight session if it does not exist.
3. Start the MQTT client if `MQTT_ENABLED=true`.
4. Start the outbox publisher loop.
5. Expose `/health` and `/ready`.

The session is identified by `FLIGHT_ID`. In production, the aircraft operation system should provide this value rather than using the demo default.

### Phase 2: Device pairing

Passenger or crew app calls:

```text
POST /api/v1/devices/pair
```

The backend returns a device ID and short-lived token. The device token is scoped to:

- One flight
- One device
- One device type

Crew pairing currently uses `CREW-DEMO` as a placeholder. Replace this with an aircraft-generated pairing code or QR flow before deployment.

### Phase 3: Request creation

The passenger app can create a request over HTTP:

```text
POST /api/v1/passenger/requests
```

Or publish an MQTT command:

```text
flight/{flight_id}/passenger/{device_id}/commands/request-create
```

The application flow is:

```text
Validate token and payload
        ↓
Check idempotency key
        ↓
Create communication request
        ↓
Append request.created event
        ↓
Append MQTT outbox message
        ↓
Commit SQLite transaction
        ↓
Publish event
        ↓
Notify WebSocket subscribers
```

The database write occurs before notification delivery so a temporary MQTT or WebSocket failure does not lose the request.

### Phase 4: Crew handling

The crew app loads the current queue through:

```text
GET /api/v1/crew/requests
```

It then receives live events through:

```text
WS /api/v1/ws/crew/{device_id}?token={device_token}
```

Crew status changes use:

```text
PATCH /api/v1/crew/requests/{request_id}/status
```

The domain transition validator rejects invalid changes, such as fulfilling a request that has never been acknowledged.

### Phase 5: Reconnection and replay

Flutter stores the highest received event sequence per flight locally.

After reconnecting:

1. Reconnect the WebSocket.
2. Call `/api/v1/events?after_sequence={last_sequence}`.
3. Apply events in sequence order.
4. Ignore already-applied event IDs.
5. Resume live WebSocket updates.

The app should use HTTP responses as the immediate write result and WebSocket events as state synchronization.

### Phase 6: MQTT deployment

For local development:

```bash
docker compose up --build
```

For a single-process local prototype:

```bash
MQTT_ENABLED=false uvicorn app.main:app --reload
```

For aircraft deployment:

1. Run Mosquitto on the aircraft edge server.
2. Disable anonymous access.
3. Create per-flight or per-device credentials.
4. Apply topic ACLs.
5. Run the FastAPI service with `MQTT_ENABLED=true`.
6. Store the SQLite database on persistent local storage.
7. Back up or export the database at flight close.

### Phase 7: Cloud synchronization

Add a `CloudSyncPort` and adapter that sends completed local events to the existing cloud backend.

The adapter should:

- Read only unpublished synchronization events.
- Use the original `event_id` as the idempotency key.
- Retry with exponential backoff.
- Mark events synchronized only after a successful cloud response.
- Never block passenger or crew operations.

Cloud synchronization is eventually consistent and should be treated as optional while airborne.

## Flutter integration architecture

Use a repository boundary in Flutter:

```text
Passenger/Crew screens
        ↓
Riverpod, Bloc, or equivalent controller
        ↓
CommunicationRepository
        ├── EdgeHttpClient
        ├── EdgeWebSocketClient
        ├── EdgeMqttClient (optional)
        ├── SecureTokenStore
        └── LocalEventStore
```

The UI should not know whether an update arrived through HTTP, WebSocket, or MQTT.

Recommended repository methods:

```dart
Future<PairingResult> pairDevice(PairDeviceInput input);
Future<CommunicationRequest> createRequest(CreateRequestInput input);
Future<CommunicationRequest> getRequest(String requestId);
Future<List<CommunicationRequest>> getCrewQueue();
Future<CommunicationRequest> updateStatus(String requestId, UpdateStatusInput input);
Stream<CommunicationEvent> watchEvents();
Future<List<CommunicationEvent>> replayEvents(int afterSequence);
```

## Flutter state rules

### Passenger app

- Show a request immediately after the HTTP request succeeds.
- Render `created` as “Sent to crew”.
- Render `acknowledged` as “Crew notified”.
- Render `in_progress` as “Crew is helping”.
- Render `fulfilled` as “Completed”.
- Allow cancellation only in `created` or `acknowledged`.
- Disable duplicate submission while the same idempotency key is pending.

### Crew app

- Sort active requests by urgency, then creation time.
- Highlight medical and urgent requests.
- Preserve the queue locally during temporary disconnects.
- Confirm status changes from the server response.
- Use the event stream for updates from other crew devices.

## Contract source of truth

The integration contract is documented in:

[CONTRACT_MAP.md](./CONTRACT_MAP.md)

The generated FastAPI OpenAPI document is available at runtime at:

```text
/openapi.json
/docs
```

## Production hardening before aircraft deployment

- Replace demo crew pairing code.
- Disable anonymous MQTT access.
- Configure MQTT topic ACLs.
- Use TLS or the aircraft platform's protected local network.
- Encrypt the SQLite volume.
- Add request expiry and flight-close cleanup.
- Add rate limiting.
- Add database backup and power-loss recovery testing.
- Add structured audit logs.
- Add cloud sync and conflict handling.
- Add end-to-end tests against Mosquitto.
- Verify the aircraft Wi-Fi network supports device-to-edge routing.
