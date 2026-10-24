import importlib
import json

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client(tmp_path, monkeypatch):
    import app.config as config
    import app.store as store_module

    monkeypatch.setattr(config.settings, "database_path", str(tmp_path / "test.db"))
    store_module.store.path = config.settings.database_path
    store_module.store.init()
    import app.main as main
    importlib.reload(main)
    with TestClient(main.app) as test_client:
        yield test_client


def pair(client, device_type, **extra):
    response = client.post("/api/v1/devices/pair", json={"device_type": device_type, **extra})
    assert response.status_code == 200, response.text
    return response.json()


def test_health_and_current_session(client):
    assert client.get("/health").json()["status"] == "ok"
    response = client.get("/api/v1/session/current")
    assert response.status_code == 200
    assert response.json()["status"] == "boarding"


def test_passenger_request_reaches_crew_queue(client):
    passenger = pair(client, "passenger", seat_number="32A")
    crew = pair(client, "crew", display_name="Crew 1", pairing_code="CREW-DEMO")

    created = client.post(
        "/api/v1/passenger/requests",
        headers={"Authorization": f"Bearer {passenger['device_token']}"},
        json={"device_id": passenger["device_id"], "seat_token": passenger["seat_token"], "category": "water", "message": "Water please", "urgency": "normal", "idempotency_key": "request-key-1"},
    )
    assert created.status_code == 201
    request_id = created.json()["id"]

    queue = client.get("/api/v1/crew/requests", headers={"Authorization": f"Bearer {crew['device_token']}"})
    assert queue.status_code == 200
    assert queue.json()[0]["id"] == request_id
    assert queue.json()[0]["seat_number"] == "32A"
    assert queue.json()[0]["status"] == "created"


def test_idempotency_returns_same_request(client):
    passenger = pair(client, "passenger", seat_number="12B")
    headers = {"Authorization": f"Bearer {passenger['device_token']}"}
    body = {"device_id": passenger["device_id"], "seat_token": passenger["seat_token"], "category": "food", "urgency": "normal", "idempotency_key": "same-request-key"}
    first = client.post("/api/v1/passenger/requests", headers=headers, json=body)
    second = client.post("/api/v1/passenger/requests", headers=headers, json=body)
    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] == second.json()["id"]


def test_passenger_cannot_forge_another_seat_token(client):
    passenger = pair(client, "passenger", seat_number="12B")
    headers = {"Authorization": f"Bearer {passenger['device_token']}"}
    response = client.post(
        "/api/v1/passenger/requests",
        headers=headers,
        json={"device_id": passenger["device_id"], "seat_token": "wrong-seat-token", "category": "water", "idempotency_key": "forged-seat-key"},
    )
    assert response.status_code == 403


def test_invalid_status_transition_is_rejected(client):
    passenger = pair(client, "passenger", seat_number="14C")
    crew = pair(client, "crew", display_name="Crew 2", pairing_code="CREW-DEMO")
    request = client.post(
        "/api/v1/passenger/requests",
        headers={"Authorization": f"Bearer {passenger['device_token']}"},
        json={"device_id": passenger["device_id"], "seat_token": passenger["seat_token"], "category": "assistance", "urgency": "urgent", "idempotency_key": "urgent-request-key"},
    ).json()
    response = client.patch(
        f"/api/v1/crew/requests/{request['id']}/status",
        headers={"Authorization": f"Bearer {crew['device_token']}"},
        json={"status": "fulfilled", "crew_device_id": crew["device_id"], "idempotency_key": "bad-transition-key"},
    )
    assert response.status_code == 409


def test_only_owner_can_read_passenger_request(client):
    owner = pair(client, "passenger", seat_number="18A")
    other = pair(client, "passenger", seat_number="18B")
    request = client.post(
        "/api/v1/passenger/requests",
        headers={"Authorization": f"Bearer {owner['device_token']}"},
        json={"device_id": owner["device_id"], "seat_token": owner["seat_token"], "category": "language_assistance", "idempotency_key": "private-request-key"},
    ).json()
    response = client.get(f"/api/v1/passenger/requests/{request['id']}", headers={"Authorization": f"Bearer {other['device_token']}"})
    assert response.status_code == 404


def test_missing_or_wrong_pairing_is_rejected(client):
    assert client.get("/api/v1/crew/requests").status_code == 401
    assert client.post("/api/v1/devices/pair", json={"device_type": "crew", "pairing_code": "wrong"}).status_code == 403


def test_event_replay_returns_request_created_event(client):
    passenger = pair(client, "passenger", seat_number="20D")
    response = client.post(
        "/api/v1/passenger/requests",
        headers={"Authorization": f"Bearer {passenger['device_token']}"},
        json={"device_id": passenger["device_id"], "seat_token": passenger["seat_token"], "category": "medical", "urgency": "urgent", "idempotency_key": "replay-request-key"},
    )
    assert response.status_code == 201
    replay = client.get("/api/v1/events?after_sequence=0", headers={"Authorization": f"Bearer {passenger['device_token']}"})
    assert replay.status_code == 200
    assert replay.json()[0]["event_type"] == "request.created"
