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

With the API running locally, create a short-lived partner key and send a sample booking:

```bash
./.venv/bin/python scripts/demo_booking.py seed
./.venv/bin/python scripts/demo_booking.py sync --api-key <printed-key>
```

The sample booking includes a passenger, flight segment, and seat assignment.
- Use HTTPS and restrict `CORS_ORIGINS`.
- Keep the R2 bucket private and use short-lived download URLs.
- Add rate limiting at the edge or API gateway.
- Do not log API keys, passwords, ticket numbers, or raw booking payloads.
