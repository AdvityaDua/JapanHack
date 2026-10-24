import pytest

pytest.importorskip("sqlalchemy")
pytest.importorskip("jose")
pytest.importorskip("passlib")

from fastapi.testclient import TestClient


@pytest.fixture()
def backend(tmp_path, monkeypatch):
    import app.core.config as config
    import app.db.session as session
    import app.db.models as models
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    test_engine = create_engine(f"sqlite:///{tmp_path / 'main.db'}", connect_args={"check_same_thread": False})
    session.engine = test_engine
    session.SessionLocal = sessionmaker(bind=test_engine, autoflush=False, autocommit=False)
    models.Base.metadata.create_all(bind=test_engine)
    config.settings.secret_key = "test-secret"
    config.settings.database_url = f"sqlite:///{tmp_path / 'main.db'}"
    import app.main as main
    with TestClient(main.app) as client:
        yield client, session, models


def register_and_login(client):
    registration = client.post("/api/v1/auth/register", json={"email": "passenger@example.com", "password": "password-123", "display_name": "Passenger", "preferred_language": "hi"})
    assert registration.status_code == 201, registration.text
    login = client.post("/api/v1/auth/login", json={"email": "passenger@example.com", "password": "password-123"})
    assert login.status_code == 200
    return login.json()["access_token"]


def test_health_registration_login_and_profile(backend):
    client, _, _ = backend
    assert client.get("/health").json() == {"status": "ok"}
    token = register_and_login(client)
    profile = client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {token}"})
    assert profile.status_code == 200
    assert profile.json()["email"] == "passenger@example.com"


def test_authentication_edge_cases(backend):
    client, _, _ = backend
    assert client.post("/api/v1/auth/register", json={"email": "bad", "password": "short"}).status_code == 422
    register_and_login(client)
    assert client.post("/api/v1/auth/register", json={"email": "passenger@example.com", "password": "password-123"}).status_code == 409
    assert client.post("/api/v1/auth/login", json={"email": "passenger@example.com", "password": "wrong-password"}).status_code == 401
    assert client.get("/api/v1/users/me").status_code == 401
    assert client.get("/api/v1/users/me", headers={"Authorization": "Bearer malformed"}).status_code == 401


def test_user_has_no_bookings_initially(backend):
    client, _, _ = backend
    token = register_and_login(client)
    response = client.get("/api/v1/users/me/bookings", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json() == []


def test_preferences_are_read_and_updated(backend):
    client, _, _ = backend
    token = register_and_login(client)
    headers = {"Authorization": f"Bearer {token}"}
    initial = client.get("/api/v1/preferences", headers=headers)
    assert initial.status_code == 200
    assert initial.json()["spoken_language"] == "hi"

    updated = client.put(
        "/api/v1/preferences",
        headers=headers,
        json={
            "spoken_language": "hi",
            "display_language": "ja",
            "translation_mode": "conversation",
            "voice_input_enabled": False,
            "text_to_speech_enabled": True,
            "font_scale": 120,
            "high_contrast_enabled": True,
            "senior_mode_enabled": True,
            "hearing_assistance_enabled": False,
        },
    )
    assert updated.status_code == 200
    assert updated.json()["display_language"] == "ja"
    assert client.get("/api/v1/users/me", headers=headers).json()["preferred_language"] == "ja"


def test_preferences_require_authentication_and_validate_font_scale(backend):
    client, _, _ = backend
    assert client.get("/api/v1/preferences").status_code == 401
    token = register_and_login(client)
    response = client.put(
        "/api/v1/preferences",
        headers={"Authorization": f"Bearer {token}"},
        json={"spoken_language": "en", "display_language": "en", "translation_mode": "conversation", "font_scale": 300},
    )
    assert response.status_code == 422


def test_partner_booking_requires_api_key_and_idempotency_header(backend):
    client, session, models = backend
    assert client.post("/api/v1/integrations/bookings", json={"external_order_id": "ORDER-1", "email": "p@example.com"}).status_code == 401

    db = session.SessionLocal()
    client_record = models.APIClient(organization_name="Demo Airline", client_id="demo-client")
    db.add(client_record)
    db.flush()
    from app.core.security import hash_api_key
    db.add(models.APIKey(api_client_id=client_record.id, key_prefix="test", key_hash=hash_api_key("partner-secret")))
    db.commit()
    db.close()

    headers = {"X-API-Key": "partner-secret"}
    response = client.post("/api/v1/integrations/bookings", headers=headers, json={"external_order_id": "ORDER-1", "email": "p@example.com"})
    assert response.status_code == 400


def test_partner_booking_is_idempotent_by_external_order(backend):
    client, session, models = backend
    registration = client.post("/api/v1/auth/register", json={"email": "p@example.com", "password": "password-123"})
    assert registration.status_code == 201
    user_token = client.post("/api/v1/auth/login", json={"email": "p@example.com", "password": "password-123"}).json()["access_token"]
    db = session.SessionLocal()
    client_record = models.APIClient(organization_name="Demo Airline", client_id="demo-client")
    db.add(client_record)
    db.flush()
    from app.core.security import hash_api_key
    db.add(models.APIKey(api_client_id=client_record.id, key_prefix="test", key_hash=hash_api_key("partner-secret")))
    db.commit()
    db.close()

    headers = {"X-API-Key": "partner-secret", "Idempotency-Key": "booking-event-1"}
    payload = {"external_order_id": "ORDER-1", "email": "p@example.com", "external_user_id": "airline-user-1", "passengers": [{"external_passenger_id": "pax-1", "given_name": "Asha", "family_name": "Kumar"}], "segments": [{"external_segment_id": "seg-1", "flight_number": "JL707", "airline_code": "JL", "departure_airport": "NRT", "arrival_airport": "DEL", "departure_time": "2026-11-15T10:30:00Z", "arrival_time": "2026-11-15T17:00:00Z"}], "seats": [{"external_passenger_id": "pax-1", "external_segment_id": "seg-1", "seat_number": "32A", "cabin_class": "economy"}]}
    first = client.post("/api/v1/integrations/bookings", headers=headers, json=payload)
    second = client.post("/api/v1/integrations/bookings", headers=headers, json=payload)
    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    assert first.json()["segments"][0]["seat_assignments"][0]["seat_number"] == "32A"

    bookings = client.get("/api/v1/users/me/bookings", headers={"Authorization": f"Bearer {user_token}"})
    assert bookings.status_code == 200


def test_models_are_empty_without_seed_data(backend):
    client, _, _ = backend
    token = register_and_login(client)
    response = client.get("/api/v1/models", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json() == []
