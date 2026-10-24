# Hushit Crew Tablet Dashboard — UI Description

## Purpose

A tablet-first cabin-crew dashboard for monitoring and responding to passenger assistance requests during a flight. The screen must make urgent requests obvious, keep the selected passenger's context visible, and support fast status updates with minimal interaction.

## Visual direction

- Light, calm aviation operations interface.
- Primary brand color: vivid airline red for active navigation, primary actions, urgent state, and selected request.
- Supporting colors: amber for pending/in-progress attention, green for completed/healthy, blue for informational state.
- White surfaces on a very light gray background.
- Thin borders, restrained shadows, and medium corner radii.
- Dark navy text for high contrast.
- Font may be a platform-safe sans-serif; the hierarchy matters more than the exact typeface.

## Tablet layout

The reference is a landscape tablet dashboard with three horizontal zones:

1. **Top flight bar**
   - Hushit logo and tagline on the left.
   - Flight number, route, status, time, and aircraft thumbnail in the center.
   - Aircraft network, internet, connected-device count, and crew profile on the right.

2. **Persistent left navigation rail**
   - Overview (selected).
   - Live Requests with a red unread badge.
   - Conversations.
   - Cabin Map.
   - Announcements.
   - Passenger Preferences.
   - Exit-row Checks.
   - Quiet-seat Check-ins.
   - System Status.
   - Help card anchored near the bottom.

3. **Main dashboard canvas**
   - Four summary cards: pending, in progress, completed, and passengers needing attention.
   - Main content row:
     - Live Requests list.
     - Request Details panel for the selected request.
     - Passenger Information panel.
   - Bottom row:
     - Cabin Seat Map with color-coded request states.
     - Quick Actions for announcements, announcements list, exit-row checks, and quiet-seat check-ins.

## Interaction model

- The first pending/urgent request is selected on load when available.
- Selecting a request updates the details and passenger panels.
- Status actions are explicit and large: Acknowledge, Mark In Progress, Mark Completed.
- Status changes optimistically update the list and are sent to the aircraft backend with an idempotency key.
- WebSocket events update the queue in real time; reconnects fall back to HTTP queue refresh.
- Filters support All, New, In Progress, and Completed.
- Urgent requests use both a red label/icon and text, never color alone.
- A compact toast/banner communicates network errors and successful status changes.

## Backend integration

Base URL is configurable for local tablet testing, for example `http://192.168.1.20:8001`.

- Pair crew device: `POST /api/v1/devices/pair` with `device_type=crew` and `pairing_code`.
- Load queue: `GET /api/v1/crew/requests`.
- Update status: `PATCH /api/v1/crew/requests/{request_id}/status`.
- Live updates: `ws://<host>/api/v1/ws/crew/{device_id}?token=<device_token>`.
- Replay missed events after reconnect: `GET /api/v1/events?after_sequence=<sequence>`.

## Demo boundary

The first Flutter screen implements the Overview, Live Requests, Request Details, passenger context, status actions, and a visual seat map. Announcements, voice calls, preferences editing, and full cabin-map navigation are represented as clear placeholders or quick-action affordances until their backend contracts are added.
