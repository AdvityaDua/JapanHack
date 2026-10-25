import importlib
import json

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client(tmp_path, monkeypatch):
    import app.config as config
    import app.store as store_module

    monkeypatch.setattr(config.settings, "database_path", str(tmp_path / "test.db"))
    monkeypatch.setattr(config.settings, "demo_seed", False)
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


def test_aircraft_model_catalogue_and_resumable_download(client, tmp_path, monkeypatch):
    import json
    import app.config as config

    model_root = tmp_path / "models"
    model_dir = model_root / "demo-model"
    model_dir.mkdir(parents=True)
    payload = b"0123456789"
    (model_dir / "model.bin").write_bytes(payload)
    (model_root / "manifest.json").write_text(
        json.dumps({
            "version": 2,
            "models": [{
                "id": "demo-model",
                "version": "1",
                "files": [{"name": "model.bin", "size_bytes": len(payload), "sha256": "demo"}],
            }],
        }),
        encoding="utf-8",
    )
    monkeypatch.setattr(config.settings, "model_directory", str(model_root))
    monkeypatch.setattr(config.settings, "model_manifest_path", str(model_root / "manifest.json"))
    passenger = pair(client, "passenger", seat_number="24A")
    headers = {"Authorization": f"Bearer {passenger['device_token']}"}

    catalogue = client.get("/api/v1/models", headers=headers)
    assert catalogue.status_code == 200
    assert catalogue.json()["models"][0]["available"] is True

    partial = client.get("/api/v1/models/demo-model/model.bin", headers={**headers, "Range": "bytes=3-6"})
    assert partial.status_code == 206
    assert partial.content == b"3456"
    assert partial.headers["content-range"] == "bytes 3-6/10"


def test_aircraft_model_download_requires_pairing_and_rejects_undeclared_files(client):
    assert client.get("/api/v1/models").status_code == 401
    passenger = pair(client, "passenger", seat_number="24B")
    headers = {"Authorization": f"Bearer {passenger['device_token']}"}
    assert client.get("/api/v1/models/unknown/model.bin", headers=headers).status_code == 404


def test_crew_seat_map_returns_aircraft_layout(client):
    from app.demo_seed import seed_demo_seat_map

    seed_demo_seat_map()
    crew = pair(client, "crew", display_name="Crew 1", pairing_code="CREW-DEMO")
    response = client.get(
        "/api/v1/crew/seat-map",
        headers={"Authorization": f"Bearer {crew['device_token']}"},
    )
    assert response.status_code == 200
    seats = response.json()
    assert len(seats) == 240
    assert seats[0]["seat_number"] == "1A"
    assert seats[0]["cabin_class"] == "business"


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


def test_crew_message_and_announcement_are_replayable(client):
    passenger = pair(client, "passenger", seat_number="24C")
    crew = pair(client, "crew", display_name="Crew 1", pairing_code="CREW-DEMO")
    request = client.post(
        "/api/v1/passenger/requests",
        headers={"Authorization": f"Bearer {passenger['device_token']}"},
        json={"device_id": passenger["device_id"], "seat_token": passenger["seat_token"], "category": "water", "idempotency_key": "message-request-key"},
    ).json()

    message = client.post(
        f"/api/v1/crew/requests/{request['id']}/messages",
        headers={"Authorization": f"Bearer {crew['device_token']}"},
        json={"text": "I will bring water shortly.", "idempotency_key": "crew-message-key"},
    )
    assert message.status_code == 200
    assert message.json()["from"] == "crew"

    announcement = client.post(
        "/api/v1/crew/announcements",
        headers={"Authorization": f"Bearer {crew['device_token']}"},
        json={"text": "Please remain seated.", "idempotency_key": "announcement-key"},
    )
    assert announcement.status_code == 200

    replay = client.get("/api/v1/events?after_sequence=0", headers={"Authorization": f"Bearer {passenger['device_token']}"})
    assert [event["event_type"] for event in replay.json()] == ["request.created", "message.created", "announcement.created"]


def test_passenger_new_protocol_actions_and_cancel(client):
    passenger = pair(client, "passenger", seat_number="31B")
    crew = pair(client, "crew", display_name="Crew 1", pairing_code="CREW-DEMO")
    passenger_headers = {"Authorization": f"Bearer {passenger['device_token']}"}
    crew_headers = {"Authorization": f"Bearer {crew['device_token']}"}
    request = client.post(
        "/api/v1/passenger/requests",
        headers=passenger_headers,
        json={"device_id": passenger["device_id"], "seat_token": passenger["seat_token"], "category": "assistance", "idempotency_key": "passenger-request-1"},
    ).json()

    action = client.post(
        "/api/v1/passenger/actions",
        headers=passenger_headers,
        json={"action": "exit_row_answer", "payload": {"willing": True}, "idempotency_key": "passenger-action-1"},
    )
    assert action.status_code == 200
    assert action.json()["action"] == "exit_row_answer"

    message = client.post(
        f"/api/v1/passenger/requests/{request['id']}/messages",
        headers=passenger_headers,
        json={"text": "I need help, please.", "idempotency_key": "passenger-message-1"},
    )
    assert message.status_code == 200
    assert message.json()["from"] == "passenger"

    cancelled = client.patch(
        f"/api/v1/passenger/requests/{request['id']}/cancel",
        headers=passenger_headers,
        json={"status": "cancelled", "idempotency_key": "passenger-cancel-1"},
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == "cancelled"

    crew_events = client.get("/api/v1/events?after_sequence=0", headers=crew_headers)
    assert [event["event_type"] for event in crew_events.json()] == [
        "request.created",
        "passenger.action_submitted",
        "message.created",
        "request.status_changed",
    ]


def test_passenger_cannot_cancel_another_passengers_request(client):
    owner = pair(client, "passenger", seat_number="12A")
    other = pair(client, "passenger", seat_number="12B")
    request = client.post(
        "/api/v1/passenger/requests",
        headers={"Authorization": f"Bearer {owner['device_token']}"},
        json={"device_id": owner["device_id"], "seat_token": owner["seat_token"], "category": "water", "idempotency_key": "owner-request-1"},
    ).json()
    response = client.patch(
        f"/api/v1/passenger/requests/{request['id']}/cancel",
        headers={"Authorization": f"Bearer {other['device_token']}"},
        json={"status": "cancelled", "idempotency_key": "other-cancel-1"},
    )
    assert response.status_code == 404
