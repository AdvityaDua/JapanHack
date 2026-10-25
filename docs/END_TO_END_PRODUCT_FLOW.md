# HASHI — End-to-End Product and Technology Flow

## 1. Product summary

HASHI is an airline communication assistant for passengers who may not be comfortable with spoken English, have difficulty with regional accents, or need accessible communication during a flight.

The product combines three ideas:

1. A cloud-backed passenger account containing identity, language and accessibility preferences, bookings and seat details.
2. A passenger application with offline-first translation models, visual request cards, local speech recognition, translation and text-to-speech.
3. A small aircraft-local communication backend that connects passenger devices and the cabin crew dashboard over the aircraft Wi-Fi network.

The passenger's preferred language is the target language. Crew members can use their comfortable language; the passenger device performs the final translation locally, so the crew device stays lightweight and one announcement can be rendered differently for each passenger.

## 2. The complete journey

```text
Passenger books
      ↓
Central API syncs booking, flight and seat to passenger account
      ↓
Passenger chooses language and accessibility preferences
      ↓
Passenger downloads translation models before travel
      ↓
Passenger boards and joins aircraft-local HASHI backend
      ↓
Passenger sends cards, text or voice requests
      ↓
Crew receives a live, seat-aware queue and responds
      ↓
Passenger device translates crew announcements/messages locally
      ↓
After landing, offline translation and airport assistance remain available
```

## 3. Onboarding and pre-flight flow

### Step 1 — Account creation and sign-in

The passenger signs in to the central FastAPI backend. The account is the source of truth for personal information, preferred language, accessibility needs and communication settings.

The app does not ask the passenger to type a seat manually. Seat information comes from the synchronized booking.

### Step 2 — Booking synchronization

An airline or partner booking system calls the open booking integration endpoint using an API key and an idempotency key. The backend creates or updates:

- Passenger account
- Booking reference and ticket details
- Flight segment, route, departure and arrival data
- Seat assignment
- Passenger-to-flight relationship

The same booking can be safely submitted again because the idempotency key prevents duplicate records. The passenger sees the booking in the personal account and the app derives the seat from it.

Demo booking synchronization is available through `scripts/demo_booking.py`, which calls the real integration endpoint rather than inserting fake records into the Flutter UI.

### Step 3 — Preferences

The passenger chooses a preferred language and can configure needs such as:

- Text size
- Read messages aloud
- Text and voice communication
- Visual request cards
- Senior-friendly presentation
- Hearing, speech, mobility or medical assistance needs

These preferences are stored centrally when the passenger is online and cached locally for use during the flight.

### Step 4 — Model readiness

Before travel, the app checks whether the local speech and translation models are available. The passenger is shown which model bundle is missing and is directed to download it on Wi-Fi.

The system currently supports local model bundles for:

- Voice activity detection
- Whisper Tiny speech recognition
- Multilingual speech recognition for Indian and Southeast Asian languages
- Translation assets used by the passenger-side translation pipeline

The central backend can distribute models through Cloudflare R2. The aircraft edge backend can also distribute the same bundles locally, allowing a passenger who did not download them before boarding to retrieve them over the aircraft network without internet access.

## 4. Boarding and aircraft-local onboarding

After boarding, the passenger app discovers the aircraft edge backend using the configured local address, mDNS/hostname fallbacks, QR pairing or the local demo address. For the current mobile demo, the backend is exposed through `127.0.0.1:8001` using ADB port forwarding.

The passenger presents a booking grant and device ID. The edge server validates the grant, confirms the flight and seat, and creates a paired passenger device session. The seat is accepted from the booking/boarding response, not typed into the app.

The edge server then provides:

- A local session token
- Flight and seat context
- Passenger preferences needed by the crew dashboard
- WebSocket event connectivity
- Access to the local model catalogue and files

## 5. In-flight passenger flow

### A. Visual request cards

The passenger can select a large, language-aware card such as water, blanket, food, assistance or medical help. This is useful for seniors, passengers with limited English proficiency, passengers in a noisy cabin and passengers who cannot comfortably speak.

The card becomes a durable request on the edge backend. It contains the passenger device, flight, seat, request type, language, urgency and idempotency key.

### B. Text communication

The passenger can type a message in their preferred language. The edge backend sends it to the crew queue. The crew can acknowledge, mark it in progress or complete it. Status changes are delivered back to the passenger in real time.

### C. Voice communication

The passenger's device captures speech and runs speech recognition locally. The recognized text is translated for the crew side and displayed or spoken on the crew device.

When the crew replies, the crew's words are sent as an event to the passenger device. The passenger device translates the message into the passenger's preferred language and uses local text-to-speech when enabled.

This means the same crew sentence can be translated independently on different passenger devices:

```text
Crew English sentence
       ├── Passenger A → Punjabi audio/text
       ├── Passenger B → Hindi audio/text
       └── Passenger C → Japanese audio/text
```

### D. Crew announcements

An announcement is flight-scoped, not passenger-scoped. The crew sends it once to the edge backend with the flight ID and source language. Every paired passenger device in that flight receives the announcement event.

Each passenger device then translates the announcement locally into its own preferred language and can read it aloud. This avoids sending multiple language versions from the crew tablet and keeps the cabin workflow simple.

### E. Safety and assistance events

The same event mechanism supports:

- Exit-row checks
- Quiet-seat check-ins
- Assistance confirmations
- Passenger acknowledgement of announcements
- Crew messages requiring a passenger response

## 6. In-flight crew flow

The crew Flutter dashboard is designed as a tablet-first interface. It consumes live edge-backend data rather than hard-coded request rows.

The dashboard presents:

- Pending, in-progress and completed request counts
- Live requests grouped by seat and priority
- Request details and translated conversation
- Passenger language and accessibility preferences
- Aircraft seat map with request status mapped to seats
- Crew announcements
- Quick actions such as announcement creation and queue refresh

Crew actions update the durable request status through the edge API. All connected passenger and crew clients receive the corresponding event.

## 7. Post-flight flow

After landing, the passenger can continue using the app without network access for supported features:

- Offline translation
- Camera/OCR translation of airport signs
- Text-to-speech in the preferred language
- Saved communication cards and accessibility preferences

The application can later synchronize pending account changes, telemetry that is safe to retain, updated preferences and the completed trip state when internet connectivity returns.

## 8. Backend architecture

### Central backend

- FastAPI for HTTP APIs
- PostgreSQL on Neon for accounts, preferences, bookings, flights, seats and device registrations
- Alembic for schema migrations
- Cloudflare R2 for large offline model objects and download URLs
- Firebase Admin SDK / FCM for passenger push notifications when internet is available
- API-key protected partner booking integration
- Idempotency keys for booking and event safety

Important central API areas:

- Authentication and current passenger account
- Preferences
- User bookings
- Partner booking synchronization
- Model catalogue and signed download URLs
- Push notification device registration

### Aircraft edge backend

- FastAPI for local commands and queries
- SQLite for the local flight/request/session store
- WebSockets for low-latency live updates to Flutter clients
- MQTT adapter available for future broker-driven integrations
- Local model catalogue and range-enabled model file downloads
- Pairing and seat-aware passenger sessions
- Flight-scoped announcements and passenger-scoped messages

For the hackathon demo, HTTP plus WebSockets is the primary path. MQTT is optional and can be enabled when the aircraft deployment has a broker. This keeps the demo easy to run while preserving an event-driven integration boundary.

### Flutter passenger app

- Flutter/Dart mobile application
- Central REST client for account, booking and preferences
- Aircraft REST/WebSocket client for local communication
- Secure device/session credentials
- Offline model store and resumable downloads
- Local speech recognition and translation pipeline
- Local text-to-speech
- Firebase notification registration for passenger devices when online

### Flutter crew dashboard

- Tablet-first Flutter dashboard
- Live edge-backend connection status
- Real-time request queue
- Seat map and passenger detail views
- Request state actions
- Announcement composition and broadcast

## 9. Why this technology choice

### FastAPI

FastAPI is lightweight, typed through Pydantic schemas, quick to iterate during a hackathon and suitable for both the central API and the aircraft edge service.

### PostgreSQL/Neon

PostgreSQL provides relational consistency for passengers, bookings, flights, seats and preferences. Neon gives the demo a managed database without requiring a separate database server.

### SQLite on the aircraft

The aircraft edge should remain operational even when there is no internet. SQLite is appropriate for a small local flight-scoped dataset and avoids a heavy database dependency on the aircraft server.

### WebSockets

WebSockets provide immediate request and status updates without the crew refreshing the dashboard. They are also straightforward for Flutter and easy to debug locally.

### MQTT

MQTT is retained as an event adapter for future cabin hardware, sensors or multiple edge services. It is not required for the current two-device demo.

### Local models

Speech recognition, translation and text-to-speech on the passenger device reduce latency, preserve privacy and allow the core communication experience to continue when cabin internet is unavailable.

### Cloudflare R2 and aircraft model cache

R2 is cost-effective object storage for 30 MB–1 GB model files. The aircraft cache creates a second distribution path: passengers can download models over the aircraft network even without internet.

### Firebase Cloud Messaging

FCM provides familiar online push notifications for booking confirmation, missing-preference reminders and other pre-flight updates. It is not the mechanism for critical in-flight communication; in-flight communication uses the aircraft-local edge event channel.

## 10. Demo script for the presentation

1. Sign in as the demo passenger.
2. Show the upcoming booking and seat loaded from the backend.
3. Update the passenger's preferred language and accessibility preferences.
4. Show model readiness and the local model catalogue.
5. Run `scripts/demo_booking.py` or call the partner booking endpoint to demonstrate booking synchronization.
6. Start the aircraft communication backend.
7. Pair the passenger and crew applications with the same local flight.
8. Send a passenger request card and show it appear in the crew queue.
9. Acknowledge it, mark it in progress and complete it; show live status changes.
10. Send a crew announcement and show it delivered to all passenger clients.
11. Demonstrate that each passenger device translates the same announcement into its own preferred language.
12. Demonstrate voice/text exchange and local read-aloud.
13. Open the seat map and show request status mapped to the passenger's seat.
14. Close with offline model distribution and post-flight OCR/translation.

## 11. Current demo scope and honest limitations

Included in the hackathon prototype:

- Central account, preference and booking data
- Open API booking synchronization
- Demo booking script
- Passenger-side model readiness and download flow
- Aircraft-local FastAPI communication backend
- WebSocket live updates
- Optional MQTT adapter
- Passenger requests and crew status updates
- Flight-wide announcements
- Passenger-preferred-language translation boundary
- Crew tablet dashboard
- Local model distribution from the aircraft edge server

Intentionally simplified for the demo:

- Booking data is simulated through the integration script rather than a real airline reservation system.
- Crew authentication and aircraft provisioning are demo-level pairing flows.
- The edge database is local SQLite rather than a replicated production flight data store.
- Push notifications depend on internet availability; local WebSocket events handle in-flight communication.
- The downloaded model binaries are kept out of Git and must be provisioned separately on the edge server.

## 12. Repository entry points

- Central backend: `app/`
- Aircraft communication backend: `communication_backend/`
- Passenger app: `flutter-app_Hashi/`
- Crew dashboard: `crew_flutter/`
- Demo booking simulator: `scripts/demo_booking.py`
- Central API documentation: `README.md`
- Edge API contract: `communication_backend/CONTRACT_MAP.md`
- Edge model catalogue instructions: `communication_backend/models/README.md`
