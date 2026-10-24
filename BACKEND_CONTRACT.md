# JAL Translation Platform Backend Contract

This document defines the HTTP contract for the main cloud backend in `/Volumes/Data/Hacks/JapanHack/app`.

The backend is responsible for:

- Passenger accounts
- Passenger preferences
- Airline booking synchronization
- Flight, passenger, segment, and seat data
- Offline translation-model metadata
- Secure Cloudflare R2 download URLs

The aircraft communication service is a separate local backend documented in:

[communication_backend/CONTRACT_MAP.md](./communication_backend/CONTRACT_MAP.md)

## Environments

Development:

```text
http://localhost:8000
```

Production should use HTTPS and a versioned host such as:

```text
https://api.example.com
```

## API conventions

Base path:

```text
/api/v1
```

Content type:

```http
Content-Type: application/json
```

IDs are UUIDs. Timestamps use ISO 8601 UTC strings:

```text
2026-10-24T10:30:00Z
```

## Authentication

Passenger endpoints use a bearer token:

```http
Authorization: Bearer {access_token}
```

Partner booking endpoints use an API key:

```http
X-API-Key: {partner_api_key}
Idempotency-Key: {unique_request_key}
```

API keys belong to an API client and are scoped to operations such as:

```text
bookings:write
bookings:read
users:read
```

## Health

### Request

```http
GET /health
```

### Response

```json
{
  "status": "ok"
}
```

## Passenger authentication

### Register

```http
POST /api/v1/auth/register
```

```json
{
  "email": "passenger@example.com",
  "password": "strong-password",
  "display_name": "Asha Kumar",
  "preferred_language": "hi"
}
```

Response:

```json
{
  "id": "user-uuid",
  "email": "passenger@example.com",
  "display_name": "Asha Kumar",
  "preferred_language": "hi"
}
```

### Login

```http
POST /api/v1/auth/login
```

```json
{
  "email": "passenger@example.com",
  "password": "strong-password"
}
```

Response:

```json
{
  "access_token": "jwt-token",
  "token_type": "bearer"
}
```

### Current user

```http
GET /api/v1/users/me
Authorization: Bearer {access_token}
```

Response:

```json
{
  "id": "user-uuid",
  "email": "passenger@example.com",
  "display_name": "Asha Kumar",
  "preferred_language": "hi"
}
```

## Preferences contract

### Get preferences

GET /api/v1/preferences
Authorization: Bearer {access_token}
```

### Update preferences

```http
PUT /api/v1/preferences
Authorization: Bearer {access_token}
Content-Type: application/json
```

Expected preference payload:

```json
{
  "spoken_language": "hi",
  "display_language": "hi",
  "translation_mode": "conversation",
  "voice_input_enabled": true,
  "text_to_speech_enabled": true,
  "font_scale": 120,
  "high_contrast_enabled": false,
  "senior_mode_enabled": true,
  "hearing_assistance_enabled": false
}
```

`font_scale` must be between 80 and 200. Updating `display_language` also updates the user's profile language.

## Passenger bookings

### List the user’s bookings

```http
GET /api/v1/users/me/bookings
Authorization: Bearer {access_token}
```

### Get one booking

```http
GET /api/v1/users/me/bookings/{booking_id}
Authorization: Bearer {access_token}
```

Response shape:

```json
{
  "id": "booking-uuid",
  "user_id": "user-uuid",
  "external_order_id": "ORDER-123",
  "external_booking_reference": "ABC123",
  "booking_status": "confirmed",
  "segments": [
    {
      "id": "segment-uuid",
      "flight_number": "JL707",
      "airline_code": "JL",
      "departure_airport": "NRT",
      "arrival_airport": "DEL",
      "departure_time": "2026-11-15T10:30:00Z",
      "arrival_time": "2026-11-15T17:00:00Z",
      "segment_status": "confirmed",
      "seat_assignments": [
        {
          "id": "seat-assignment-uuid",
          "booking_segment_id": "segment-uuid",
          "booking_passenger_id": "passenger-uuid",
          "seat_number": "32A",
          "cabin_class": "economy",
          "boarding_group": "B",
          "seat_status": "confirmed"
        }
      ]
    }
  ]
}
```

## Airline partner booking synchronization

Partner systems send booking data to the cloud backend. The endpoint creates or updates the passenger and booking aggregate.

### Synchronize a booking

```http
POST /api/v1/integrations/bookings
X-API-Key: {partner_api_key}
Idempotency-Key: partner-event-uuid
```

```json
{
  "external_user_id": "airline-user-123",
  "email": "passenger@example.com",
  "display_name": "Asha Kumar",
  "preferred_language": "hi",
  "external_order_id": "ORDER-123",
  "external_booking_reference": "ABC123",
  "booking_status": "confirmed",
  "source_system": "airline-pnr",
  "passengers": [
    {
      "external_passenger_id": "PAX-1",
      "given_name": "Asha",
      "family_name": "Kumar",
      "passenger_type": "adult"
    }
  ],
  "segments": [
    {
      "external_segment_id": "SEG-1",
      "flight_number": "JL707",
      "airline_code": "JL",
      "departure_airport": "NRT",
      "arrival_airport": "DEL",
      "departure_time": "2026-11-15T10:30:00Z",
      "arrival_time": "2026-11-15T17:00:00Z",
      "segment_status": "confirmed"
    }
  ],
  "raw_metadata": {}
}
```

Response:

```json
{
  "id": "booking-uuid",
  "user_id": "user-uuid",
  "external_order_id": "ORDER-123",
  "external_booking_reference": "ABC123",
  "booking_status": "confirmed",
  "segments": []
}
```

Supported booking statuses should include:

```text
confirmed
changed
cancelled
rebooked
completed
```

The endpoint must remain idempotent for retries from airline systems.

Seat-assignment synchronization is part of the target contract, but the current cloud endpoint does not yet accept or return seat assignments. Add it only after the corresponding `seat_assignments` schema and migration are implemented.

## Translation model catalog

### List active models

```http
GET /api/v1/models
Authorization: Bearer {access_token}
```

Optional filters:

```text
GET /api/v1/models?source_language=ja&target_language=hi&platform=android
```

Response:

```json
[
  {
    "id": "model-uuid",
    "name": "Japanese Hindi Offline Translator",
    "version": "1.0.0",
    "source_language": "ja",
    "target_language": "hi",
    "model_type": "translation",
    "platform": "android",
    "file_size_bytes": 45000000,
    "sha256_checksum": "checksum",
    "minimum_app_version": "1.0.0",
    "status": "active"
  }
]
```

### Request a secure download URL

```http
POST /api/v1/models/{model_id}/download-url
Authorization: Bearer {access_token}
```

Response:

```json
{
  "model_id": "model-uuid",
  "download_url": "https://r2-presigned-url",
  "expires_in_seconds": 900,
  "sha256_checksum": "checksum"
}
```

Flutter should download the model directly from R2 and verify the SHA-256 checksum locally.

## Error contract

All errors should use FastAPI’s standard shape:

```json
{
  "detail": "Human-readable error message"
}
```

Common status codes:

```text
400 Invalid request or missing idempotency key
401 Missing or invalid authentication
403 Insufficient scope or permission
404 Resource not found
409 Duplicate or conflicting resource
422 Validation error
429 Rate limit exceeded
503 External service unavailable
```

## Flutter integration flow

```text
Register or authenticate passenger
        ↓
Store JWT securely
        ↓
GET /users/me
        ↓
GET /users/me/bookings
        ↓
GET /models with route/language filters
        ↓
POST /models/{id}/download-url
        ↓
Download model directly from R2
        ↓
Verify checksum
        ↓
Use local offline model during flight
```

## Relationship with the aircraft communication backend

Before boarding or while connected to cloud services:

```text
Main cloud backend
  ├── user identity
  ├── booking and seat details
  ├── language preferences
  └── model catalog

Aircraft communication backend
  ├── active flight session
  ├── passenger device pairing
  ├── crew request queue
  └── local event delivery
```

The aircraft backend should receive only the minimum flight/session context required for the active flight:

```json
{
  "flight_id": "flight-session-uuid",
  "flight_number": "JL707",
  "passenger_device_id": "device-uuid",
  "seat_token": "seat-token",
  "language_preferences": ["hi", "en", "ja"]
}
```

Do not copy the complete passenger profile or full booking record to every crew device.

## Versioning rules

- Keep `/api/v1` stable during the hackathon.
- Add fields in a backward-compatible way.
- Do not rename existing fields without a new API version.
- Include `model version` and `event version` in downloadable model and event contracts.
- Preserve external airline IDs exactly as received.
- Use idempotency keys for all partner writes.

## Implementation status

Currently implemented in the main backend:

- Health endpoint
- Passenger registration
- Passenger login
- Current-user endpoint
- User booking retrieval
- Partner booking synchronization
- Translation model listing
- R2 presigned download URL generation

Next contract-aligned additions:

- Preferences endpoints
- Admin API-client provisioning
- Seat and ticket response expansion
- Booking update event endpoint
- Model download completion tracking
- Cloud-to-aircraft flight-session handoff
