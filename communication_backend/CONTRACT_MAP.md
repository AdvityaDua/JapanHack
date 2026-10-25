# Flutter Contract Map

This document is the contract between the Flutter passenger/crew apps and the aircraft communication backend.

## Base URLs

HTTP:

```text
http://aircraft-gateway.local:8000
```

WebSocket:

```text
ws://aircraft-gateway.local:8000/api/v1/ws/{audience}/{device_id}?token={device_token}
```

MQTT:

```text
mqtt://aircraft-gateway.local:1883
```

The app should discover the aircraft gateway address from the aircraft Wi-Fi captive portal, a QR code, or a configured local hostname. Do not hard-code an IP address in production.

## Pairing contract

The app first pairs its device with the active flight session.

### Request

```http
POST /api/v1/devices/pair
Content-Type: application/json
```

Passenger:

```json
{
  "device_type": "passenger",
  "display_name": "Passenger phone",
  "seat_number": "32A"
}
```

Crew:

```json
{
  "device_type": "crew",
  "display_name": "Crew tablet 1",
  "pairing_code": "CREW-DEMO"
}
```

### Response

```json
{
  "device_id": "device-uuid",
  "device_token": "short-lived-token",
  "flight_id": "demo-flight",
  "device_type": "passenger",
  "seat_token": "seat-token"
}
```

Store `device_token` only in Flutter secure storage. Store `device_id`, `flight_id`, and `seat_token` alongside it.

## HTTP authentication

Send the device token on every HTTP request:

```http
Authorization: Bearer {device_token}
```

The current MVP also accepts:

```http
X-Device-Token: {device_token}
```

## Passenger HTTP API

### Create request

```http
POST /api/v1/passenger/requests
Authorization: Bearer {device_token}
Content-Type: application/json
```

```json
{
  "device_id": "device-uuid",
  "seat_token": "seat-token",
  "category": "water",
  "message": "Water please",
  "urgency": "normal",
  "idempotency_key": "flutter-uuid-1"
}
```

Response:

```json
{
  "id": "request-uuid",
  "flight_id": "demo-flight",
  "passenger_device_id": "device-uuid",
  "seat_token": "seat-token",
  "seat_number": "32A",
  "category": "water",
  "message": "Water please",
  "urgency": "normal",
  "status": "created",
  "assigned_crew_device_id": null,
  "created_at": "2026-10-24T10:30:00Z",
  "updated_at": "2026-10-24T10:30:00Z"
}
```

### Retrieve one request

```http
GET /api/v1/passenger/requests/{request_id}
Authorization: Bearer {device_token}
```

### Passenger actions

Passenger UI actions use the HTTP/event protocol; they are not sent as legacy
WebSocket commands.

```http
PATCH /api/v1/passenger/requests/{request_id}/cancel
POST /api/v1/passenger/requests/{request_id}/messages
POST /api/v1/passenger/actions
Authorization: Bearer {device_token}
```

`/passenger/actions` accepts an `action`, optional `request_id`, arbitrary
JSON `payload`, and an `idempotency_key`. Actions such as
`announcement_acknowledged`, `exit_row_answer`, `quiet_seat_checkin_answer`,
`message_confirmed`, `message_cancelled`, and `profile_updated` are persisted
as `passenger.action_submitted` events for the crew application.

## Crew HTTP API

### Request queue

```http
GET /api/v1/crew/requests

GET /api/v1/crew/seat-map

Returns the aircraft's ordered seat map. Each seat includes its cabin class,
seat type, occupancy state, and the latest active communication request mapped
to that seat when one exists. The crew device token is required.

```json
{
  "seat_number": "24A",
  "row_number": 24,
  "seat_column": "A",
  "cabin_class": "economy",
  "seat_type": "window",
  "occupancy_status": "available",
  "request_status": "created",
  "request_category": "water"
}
```
Authorization: Bearer {crew_device_token}
```

Optional filter:

```text
GET /api/v1/crew/requests?status=created,acknowledged,in_progress,escalated
```

### Update request status

```http
PATCH /api/v1/crew/requests/{request_id}/status
Authorization: Bearer {crew_device_token}
Content-Type: application/json
```

```json
{
  "status": "acknowledged",
  "crew_device_id": "crew-device-uuid",
  "note": "Crew member notified",
  "idempotency_key": "flutter-uuid-2"
}
```

Valid states:

```text
created → acknowledged → in_progress → fulfilled
created → cancelled
created → expired
acknowledged → escalated
in_progress → escalated
```

### Crew message

```http
POST /api/v1/crew/requests/{request_id}/messages
Authorization: Bearer {crew_device_token}
Content-Type: application/json
```

```json
{
  "text": "I will bring water shortly.",
  "translated_text": null,
  "idempotency_key": "flutter-message-uuid"
}
```

The passenger receives a `message.created` WebSocket event targeted to the
passenger device that created the request.

### Crew announcement

```http
POST /api/v1/crew/announcements
Authorization: Bearer {crew_device_token}
Content-Type: application/json
```

```json
{
  "text": "Please remain seated.",
  "target_device_id": null,
  "kind": "info",
  "icon": "Megaphone",
  "idempotency_key": "flutter-announcement-uuid"
}
```

`target_device_id` can target one passenger; `null` broadcasts to every
passenger connected to the active flight. The passenger receives an
`announcement.created` event and can translate it locally.

## WebSocket contract

### Passenger connection

```text
GET /api/v1/ws/passenger/{device_id}?token={device_token}
```

Passenger receives only events relevant to its own device.

### Crew connection

```text
GET /api/v1/ws/crew/{device_id}?token={crew_device_token}
```

Crew receives all request events for the active flight.

### Event message

```json
{
  "event_id": "event-uuid",
  "event_type": "request.created",
  "event_version": 1,
  "flight_id": "demo-flight",
  "aggregate_id": "request-uuid",
  "producer": "passenger-device",
  "device_id": "device-uuid",
  "occurred_at": "2026-10-24T10:30:00Z",
  "sequence": 42,
  "payload": {
    "id": "request-uuid",
    "category": "water",
    "status": "created"
  }
}
```

The Flutter WebSocket client should send a small heartbeat text message, such as `ping`, every 20–30 seconds. The server currently keeps the connection alive by waiting for client messages.

## MQTT contract

Use MQTT when Flutter connects directly to the aircraft broker.

Passenger command topics:

```text
flight/{flight_id}/passenger/{device_id}/commands/request-create
flight/{flight_id}/passenger/{device_id}/commands/request-cancel
```

Crew command topics:

```text
flight/{flight_id}/crew/{device_id}/commands/request-status
```

Backend event topics:

```text
flight/{flight_id}/events/request-created
flight/{flight_id}/events/request-status-changed
```

MQTT payloads use the same event envelope as WebSockets. Flutter should use QoS 1 for request commands and status commands. The client must generate a unique `event_id` and `idempotency_key` for every command.

## Flutter implementation sequence

1. Discover the aircraft gateway address.
2. Call `/api/v1/session/current`.
3. Pair the device using `/api/v1/devices/pair`.
4. Save the device token in `flutter_secure_storage`.
5. Open the WebSocket using the saved token.
6. Load existing passenger requests or the crew queue through HTTP.
7. Use WebSocket events for live updates.
8. On WebSocket failure, reconnect with exponential backoff.
9. After reconnect, call `/api/v1/events?after_sequence={last_sequence}`.
10. Retry writes using the same idempotency key, never a new key.

## Flutter models

Suggested Dart models:

```dart
enum RequestStatus {
  created,
  acknowledged,
  inProgress,
  fulfilled,
  cancelled,
  expired,
  escalated,
}

class CommunicationRequest {
  final String id;
  final String category;
  final String? message;
  final String urgency;
  final RequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CommunicationRequest({
    required this.id,
    required this.category,
    required this.message,
    required this.urgency,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
}

class CommunicationEvent {
  final String eventId;
  final String eventType;
  final int sequence;
  final Map<String, dynamic> payload;

  const CommunicationEvent({
    required this.eventId,
    required this.eventType,
    required this.sequence,
    required this.payload,
  });
}
```

## Flutter repository boundary

Keep transport details out of widgets:

```text
CommunicationRepository
  ├── pairDevice()
  ├── createRequest()
  ├── getRequest()
  ├── getCrewQueue()
  ├── updateRequestStatus()
  ├── connectEvents()
  └── replayEvents(afterSequence)
```

Recommended layers in Flutter:

```text
UI widgets
    ↓
Riverpod/Bloc controller
    ↓
CommunicationRepository
    ├── HTTP client
    ├── WebSocket client
    ├── MQTT client (optional direct mode)
    └── secure local token storage
```

The UI should render from a local request state store and update it from HTTP responses and incoming events.

## Current implementation scope

Implemented in this directory:

- FastAPI application
- SQLite local persistence
- Flight session bootstrap
- Passenger and crew pairing
- Device token authentication
- Passenger request creation
- Crew queue retrieval
- Crew status transitions
- WebSocket event delivery
- MQTT command/event adapter
- Inbox duplicate protection
- Outbox persistence and retry loop
- Flutter contract documentation

The next production-hardening steps are broker ACLs, non-demo crew pairing, encrypted local storage, cloud synchronization, and end-to-end tests with a real MQTT broker.
