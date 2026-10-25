import base64
import hashlib
import hmac
import json
import time

from fastapi import HTTPException

from app.config import settings
from app.domain import now_iso, new_id, validate_transition
from app.messaging import MQTTBus, publish_pending
from app.realtime import manager
from app.schemas import AnnouncementBody, CreateRequestBody, CrewMessageBody, PairDeviceRequest, PassengerActionBody, UpdateStatusBody
from app.store import store


def issue_device_token(device_id: str, flight_id: str, device_type: str) -> str:
    payload = f"{device_id}|{flight_id}|{device_type}|{int(time.time()) + settings.access_token_expire_minutes * 60}"
    signature = hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return base64.urlsafe_b64encode(f"{payload}|{signature}".encode()).decode()


def verify_device_token(token: str, expected_type: str | None = None) -> dict:
    try:
        decoded = base64.urlsafe_b64decode(token.encode()).decode().split("|")
        device_id, flight_id, device_type, expires, signature = decoded
        payload = "|".join(decoded[:-1])
        expected = hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(signature, expected) or int(expires) < int(time.time()):
            raise ValueError
        if expected_type and device_type != expected_type:
            raise ValueError
        device = store.get_device(device_id)
        if not device or device["flight_id"] != flight_id or device["device_type"] != device_type:
            raise ValueError
        return {"device_id": device_id, "flight_id": flight_id, "device_type": device_type}
    except (ValueError, TypeError, UnicodeDecodeError, IndexError) as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired device token") from exc


def row_to_request(row) -> dict:
    return {"id": row["id"], "flight_id": row["flight_id"], "passenger_device_id": row["passenger_device_id"], "seat_token": row["seat_token"], "seat_number": row["seat_number"], "passenger_language": row["passenger_language"], "category": row["category"], "message": row["message"], "urgency": row["urgency"], "status": row["status"], "assigned_crew_device_id": row["assigned_crew_device_id"], "created_at": row["created_at"], "updated_at": row["updated_at"]}


def row_to_seat(row) -> dict:
    return {"flight_id": row["flight_id"], "seat_number": row["seat_number"], "row_number": row["row_number"], "seat_column": row["seat_column"], "seat_order": row["seat_order"], "cabin_class": row["cabin_class"], "seat_type": row["seat_type"], "occupancy_status": row["occupancy_status"], "request_id": row["request_id"], "request_category": row["request_category"], "request_status": row["request_status"], "request_urgency": row["request_urgency"]}


def pair_device(payload: PairDeviceRequest) -> dict:
    if payload.device_type == "crew" and not hmac.compare_digest(payload.pairing_code or "", settings.crew_pairing_code):
        raise HTTPException(status_code=403, detail="Invalid crew pairing code")
    device_id = new_id()
    seat_token = new_id()[:12] if payload.device_type == "passenger" else None
    device_token = issue_device_token(device_id, settings.flight_id, payload.device_type)
    now = now_iso()
    store.save_device({"id": device_id, "flight_id": settings.flight_id, "device_type": payload.device_type, "display_name": payload.display_name, "seat_number": payload.seat_number, "seat_token": seat_token, "token_hash": hashlib.sha256(device_token.encode()).hexdigest(), "status": "active", "last_seen_at": now})
    return {"device_id": device_id, "device_token": device_token, "flight_id": settings.flight_id, "device_type": payload.device_type, "seat_token": seat_token}


def create_request(payload: CreateRequestBody, device: dict, bus: MQTTBus) -> dict:
    stored_device = store.get_device(device["device_id"])
    if not stored_device or not stored_device["seat_token"] or not hmac.compare_digest(stored_device["seat_token"], payload.seat_token):
        raise HTTPException(status_code=403, detail="Seat token does not belong to this device")
    existing = store.get_idempotent(f"create:{device['device_id']}", payload.idempotency_key)
    if existing:
        return existing
    request_id = new_id()
    now = now_iso()
    request = {"id": request_id, "flight_id": device["flight_id"], "passenger_device_id": device["device_id"], "seat_token": payload.seat_token, "seat_number": stored_device["seat_number"], "passenger_language": payload.passenger_language, "category": payload.category, "message": payload.message, "urgency": payload.urgency, "status": "created", "assigned_crew_device_id": None, "created_at": now, "updated_at": now}
    event = {"event_id": new_id(), "event_type": "request.created", "event_version": 1, "flight_id": device["flight_id"], "aggregate_id": request_id, "producer": "passenger-device", "device_id": device["device_id"], "occurred_at": now, "payload": request}
    topic = f"flight/{device['flight_id']}/events/request-created"
    store.create_request(request, event, topic, now)
    store.save_idempotent(f"create:{device['device_id']}", payload.idempotency_key, request, now)
    publish_pending(bus)
    manager.broadcast(device["flight_id"], event, passenger_device_id=device["device_id"])
    return request


def update_status(request_id: str, payload: UpdateStatusBody, device: dict, bus: MQTTBus) -> dict:
    existing = store.get_idempotent(f"status:{request_id}", payload.idempotency_key)
    if existing:
        return existing
    current = store.get_request(request_id)
    if not current or current["flight_id"] != device["flight_id"]:
        raise HTTPException(status_code=404, detail="Request not found")
    try:
        validate_transition(current["status"], payload.status)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    now = now_iso()
    event = {"event_id": new_id(), "event_type": "request.status_changed", "event_version": 1, "flight_id": device["flight_id"], "aggregate_id": request_id, "producer": "crew-device", "device_id": device["device_id"], "occurred_at": now, "payload": {"status": payload.status, "note": payload.note, "crew_device_id": payload.crew_device_id}}
    row = store.transition_request(request_id, payload.status, payload.crew_device_id, event, f"flight/{device['flight_id']}/events/request-status-changed", now)
    response = row_to_request(row)
    store.save_idempotent(f"status:{request_id}", payload.idempotency_key, response, now)
    publish_pending(bus)
    manager.broadcast(device["flight_id"], event, passenger_device_id=current["passenger_device_id"])
    return response


def cancel_passenger_request(request_id: str, idempotency_key: str, device: dict, bus: MQTTBus) -> dict:
    scope = f"passenger-status:{device['device_id']}:{request_id}"
    existing = store.get_idempotent(scope, idempotency_key)
    if existing:
        return existing
    current = store.get_request(request_id)
    if not current or current["flight_id"] != device["flight_id"] or current["passenger_device_id"] != device["device_id"]:
        raise HTTPException(status_code=404, detail="Request not found")
    try:
        validate_transition(current["status"], "cancelled")
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    now = now_iso()
    event = {"event_id": new_id(), "event_type": "request.status_changed", "event_version": 1, "flight_id": device["flight_id"], "aggregate_id": request_id, "producer": "passenger-device", "device_id": device["device_id"], "occurred_at": now, "payload": {"status": "cancelled", "note": "Cancelled by passenger", "crew_device_id": None}}
    row = store.transition_request(request_id, "cancelled", None, event, f"flight/{device['flight_id']}/events/request-status-changed", now)
    response = row_to_request(row)
    store.save_idempotent(scope, idempotency_key, response, now)
    publish_pending(bus)
    manager.broadcast(device["flight_id"], event, passenger_device_id=device["device_id"])
    return response


def create_crew_message(request_id: str, payload: CrewMessageBody, device: dict, bus: MQTTBus) -> dict:
    existing = store.get_idempotent(f"message:{request_id}", payload.idempotency_key)
    if existing:
        return existing
    request = store.get_request(request_id)
    if not request or request["flight_id"] != device["flight_id"]:
        raise HTTPException(status_code=404, detail="Request not found")
    now = now_iso()
    message = {"id": new_id(), "request_id": request_id, "from": "crew", "original": payload.text, "translated": payload.translated_text, "source_language": payload.source_language, "status": "sent", "lane": "machine"}
    event = {"event_id": new_id(), "event_type": "message.created", "event_version": 1, "flight_id": device["flight_id"], "aggregate_id": request_id, "producer": "crew-device", "device_id": device["device_id"], "occurred_at": now, "payload": message}
    store.append_event(event, f"flight/{device['flight_id']}/events/message-created", now)
    store.save_idempotent(f"message:{request_id}", payload.idempotency_key, message, now)
    publish_pending(bus)
    manager.broadcast(device["flight_id"], event, passenger_device_id=request["passenger_device_id"])
    return message


def create_passenger_message(request_id: str, payload: CrewMessageBody, device: dict, bus: MQTTBus) -> dict:
    existing = store.get_idempotent(f"passenger-message:{device['device_id']}:{request_id}", payload.idempotency_key)
    if existing:
        return existing
    request = store.get_request(request_id)
    if not request or request["flight_id"] != device["flight_id"] or request["passenger_device_id"] != device["device_id"]:
        raise HTTPException(status_code=404, detail="Request not found")
    now = now_iso()
    message = {"id": new_id(), "request_id": request_id, "from": "passenger", "original": payload.text, "translated": payload.translated_text, "source_language": payload.source_language, "status": "sent", "lane": "machine"}
    event = {"event_id": new_id(), "event_type": "message.created", "event_version": 1, "flight_id": device["flight_id"], "aggregate_id": request_id, "producer": "passenger-device", "device_id": device["device_id"], "occurred_at": now, "payload": message}
    store.append_event(event, f"flight/{device['flight_id']}/events/message-created", now)
    store.save_idempotent(f"passenger-message:{device['device_id']}:{request_id}", payload.idempotency_key, message, now)
    publish_pending(bus)
    manager.broadcast(device["flight_id"], event)
    return message


def submit_passenger_action(payload: PassengerActionBody, device: dict, bus: MQTTBus) -> dict:
    scope = f"passenger-action:{device['device_id']}"
    existing = store.get_idempotent(scope, payload.idempotency_key)
    if existing:
        return existing
    if payload.request_id:
        request = store.get_request(payload.request_id)
        if not request or request["flight_id"] != device["flight_id"] or request["passenger_device_id"] != device["device_id"]:
            raise HTTPException(status_code=404, detail="Request not found")
    now = now_iso()
    action = {"id": new_id(), "action": payload.action, "request_id": payload.request_id, "payload": payload.payload, "device_id": device["device_id"]}
    event = {"event_id": new_id(), "event_type": "passenger.action_submitted", "event_version": 1, "flight_id": device["flight_id"], "aggregate_id": payload.request_id or device["device_id"], "producer": "passenger-device", "device_id": device["device_id"], "occurred_at": now, "payload": action}
    store.append_event(event, f"flight/{device['flight_id']}/events/passenger-action-submitted", now)
    store.save_idempotent(scope, payload.idempotency_key, action, now)
    publish_pending(bus)
    manager.broadcast(device["flight_id"], event)
    return action


def create_announcement(payload: AnnouncementBody, device: dict, bus: MQTTBus) -> dict:
    existing = store.get_idempotent(f"announcement:{device['device_id']}", payload.idempotency_key)
    if existing:
        return existing
    now = now_iso()
    announcement_id = new_id()
    announcement = {
        "id": announcement_id,
        "phrase": None,
        "custom": payload.text,
        # Keep the source text under its own language for older clients; new
        # passenger clients translate `custom` locally into their preference.
        "texts": {payload.source_language: payload.text},
        "source_language": payload.source_language,
        "kind": payload.kind,
        "icon": payload.icon,
        "target_device_id": payload.target_device_id,
    }
    event = {"event_id": new_id(), "event_type": "announcement.created", "event_version": 1, "flight_id": device["flight_id"], "aggregate_id": announcement_id, "producer": "crew-device", "device_id": device["device_id"], "occurred_at": now, "payload": announcement}
    store.append_event(event, f"flight/{device['flight_id']}/events/announcement-created", now)
    store.save_idempotent(f"announcement:{device['device_id']}", payload.idempotency_key, announcement, now)
    publish_pending(bus)
    manager.broadcast_passengers(device["flight_id"], event, passenger_device_id=payload.target_device_id)
    return announcement


def handle_mqtt_command(topic: str, payload: dict, bus: MQTTBus) -> None:
    command = topic.rsplit("/", 1)[-1]
    device = {"device_id": payload.get("device_id", "mqtt-device"), "flight_id": payload.get("flight_id", settings.flight_id), "device_type": "passenger" if "/passenger/" in topic else "crew"}
    if command == "request-create":
        body = CreateRequestBody(**payload["payload"])
        create_request(body, device, bus)
    elif command == "request-status":
        body = UpdateStatusBody(**payload["payload"])
        update_status(payload["aggregate_id"], body, device, bus)
