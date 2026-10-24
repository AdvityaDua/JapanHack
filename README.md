# JAL Offline Translation Backend

FastAPI backend for user profiles, preferences, airline booking synchronization, and offline translation model delivery.

## Local setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open the API documentation at http://localhost:8000/docs.

With no `DATABASE_URL`, development uses `local.db`. For Neon, set the pooled PostgreSQL URL in `.env`. R2 download URLs require the R2 variables to be populated.

## Implemented API surface

- `GET /health`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/users/me`
- `GET /api/v1/users/me/bookings`
- `GET /api/v1/users/me/bookings/{booking_id}`
- `POST /api/v1/integrations/bookings`
- `GET /api/v1/models`
- `POST /api/v1/models/{model_id}/download-url`

Partner booking writes require `X-API-Key` and `Idempotency-Key` headers. API clients and keys should be created through an admin workflow or seed script before integration.

## Production checklist

- Set a strong `SECRET_KEY`.
- Keep `CORS_ORIGINS` as a JSON array, for example `["https://app.example.com"]`.
- R2 uses `R2_TOEKN`, `R2_ACCESS_ID`, `R2_ACCESS_KEY`, `R2_URL`, `R2_BUCKET_NAME`, and `R2_PUBLIC_BASE_URL`, matching the populated project `.env`.
- Use Neon PostgreSQL and run Alembic migrations.
- Set `ENVIRONMENT=production`.

## Demo booking sync

With the API running locally, synchronize a ticket to the existing demo user. The
script uses the real partner booking endpoint, so the booking appears in that
user's `GET /api/v1/users/me/bookings` response. Re-running the command with the
same order ID updates the same demo booking instead of creating another one.

```bash
./.venv/bin/python scripts/demo_booking.py demo \
  --email demo.passenger@example.com \
  --external-user-id demo-passenger-001
```

Use the email of the user already registered in the database. You can customize
the seat or booking reference for the demo:

```bash
./.venv/bin/python scripts/demo_booking.py demo \
  --email passenger@example.com \
  --seat 24A \
  --booking-reference JAL-DEMO-001
```

The sample booking includes a passenger, flight segment, and seat assignment.
The `seed` and `sync` commands remain available when you want to inspect or
provide the partner API key manually.
- Use HTTPS and restrict `CORS_ORIGINS`.
- Keep the R2 bucket private and use short-lived download URLs.
- Add rate limiting at the edge or API gateway.
- Do not log API keys, passwords, ticket numbers, or raw booking payloads.
