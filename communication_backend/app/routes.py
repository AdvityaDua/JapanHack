from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, Query, WebSocket, WebSocketDisconnect

from app.config import settings
from app.messaging import MQTTBus
from app.realtime import manager
from app.schemas import CreateRequestBody, EventResponse, PairDeviceRequest, PairDeviceResponse, RequestResponse, SeatResponse, SessionResponse, UpdateStatusBody
from app.service import create_request, pair_device, row_to_request, row_to_seat, update_status, verify_device_token
from app.store import store


def token_device(authorization: Annotated[str | None, Header()] = None, device_token: Annotated[str | None, Header()] = None) -> dict:
    raw = device_token or (authorization.removeprefix("Bearer ") if authorization else None)
    if not raw:
        raise HTTPException(status_code=401, detail="Device token is required")
    return verify_device_token(raw)


def make_router(bus: MQTTBus) -> APIRouter:
    router = APIRouter(prefix="/api/v1", tags=["communication"])

    @router.get("/session/current", response_model=SessionResponse)
    def current_session():
        row = store.get_session(settings.flight_id)
        if not row:
            raise HTTPException(status_code=404, detail="No active flight session")
        return dict(row)

    @router.post("/devices/pair", response_model=PairDeviceResponse)
    def pair(payload: PairDeviceRequest):
        return pair_device(payload)

    @router.post("/passenger/requests", response_model=RequestResponse, status_code=201)
    def passenger_request(payload: CreateRequestBody, device: dict = Depends(token_device)):
        if device["device_type"] != "passenger":
            raise HTTPException(status_code=403, detail="Passenger device required")
        return create_request(payload, device, bus)

    @router.get("/passenger/requests/{request_id}", response_model=RequestResponse)
    def passenger_request_detail(request_id: str, device: dict = Depends(token_device)):
        row = store.get_request(request_id)
        if not row or row["passenger_device_id"] != device["device_id"]:
            raise HTTPException(status_code=404, detail="Request not found")
        return row_to_request(row)

    @router.get("/crew/requests", response_model=list[RequestResponse])
    def crew_requests(status: str | None = Query(default=None), device: dict = Depends(token_device)):
        if device["device_type"] != "crew":
            raise HTTPException(status_code=403, detail="Crew device required")
        statuses = status.split(",") if status else None
        return [row_to_request(row) for row in store.list_requests(device["flight_id"], statuses)]

    @router.get("/crew/seat-map", response_model=list[SeatResponse])
    def crew_seat_map(device: dict = Depends(token_device)):
        if device["device_type"] != "crew":
            raise HTTPException(status_code=403, detail="Crew device required")
        return [row_to_seat(row) for row in store.list_seats(device["flight_id"])]

    @router.patch("/crew/requests/{request_id}/status", response_model=RequestResponse)
    def crew_status(request_id: str, payload: UpdateStatusBody, device: dict = Depends(token_device)):
        if device["device_type"] != "crew":
            raise HTTPException(status_code=403, detail="Crew device required")
        return update_status(request_id, payload, device, bus)

    @router.get("/events", response_model=list[EventResponse])
    def replay_events(after_sequence: int = Query(default=0, ge=0), device: dict = Depends(token_device)):
        rows = store.replay_events(device["flight_id"], after_sequence)
        return [{"event_id": row["event_id"], "event_type": row["event_type"], "aggregate_id": row["request_id"], "sequence": row["sequence"], "occurred_at": row["occurred_at"], "payload": __import__("json").loads(row["payload"])} for row in rows]

    @router.websocket("/ws/{audience}/{device_id}")
    async def websocket_endpoint(websocket: WebSocket, audience: str, device_id: str, token: str, flight_id: str = settings.flight_id):
        device = verify_device_token(token, "crew" if audience == "crew" else "passenger")
        if device["device_id"] != device_id or device["flight_id"] != flight_id:
            await websocket.close(code=1008)
            return
        await manager.connect(websocket, flight_id, audience, device_id)
        try:
            while True:
                await websocket.receive_text()
        except WebSocketDisconnect:
            manager.disconnect(websocket, flight_id, audience, device_id)

    return router
