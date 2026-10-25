from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse

from app.config import settings
from app.messaging import MQTTBus
from app.realtime import manager
from app.schemas import AnnouncementBody, CreateRequestBody, CrewMessageBody, EventResponse, PairDeviceRequest, PairDeviceResponse, PassengerActionBody, RequestResponse, SeatResponse, SessionResponse, UpdateStatusBody
from app.service import cancel_passenger_request, create_announcement, create_crew_message, create_passenger_message, create_request, pair_device, row_to_request, row_to_seat, submit_passenger_action, update_status, verify_device_token
from app.store import store
from app.model_store import get_model_file, public_catalog


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

    @router.get("/models")
    def model_catalog(device: dict = Depends(token_device)):
        """List model bundles staged on this aircraft edge server."""
        return public_catalog()

    @router.get("/models/{model_id}/{file_name:path}")
    def model_file(model_id: str, file_name: str, request: Request, device: dict = Depends(token_device)):
        """Stream a staged model file and support HTTP Range for resumable downloads."""
        _, file_meta, path = get_model_file(model_id, file_name)
        size = path.stat().st_size
        start, end = 0, size - 1
        range_header = request.headers.get("range")
        if range_header:
            if not range_header.startswith("bytes=") or "," in range_header:
                raise HTTPException(status_code=416, detail="Only one byte range is supported")
            raw_start, raw_end = (range_header.removeprefix("bytes=").split("-", 1) + [""])[:2]
            try:
                if raw_start:
                    start = int(raw_start)
                    end = int(raw_end) if raw_end else size - 1
                else:
                    suffix = int(raw_end)
                    start = max(size - suffix, 0)
                    end = size - 1
            except ValueError as exc:
                raise HTTPException(status_code=416, detail="Invalid byte range") from exc
            if start < 0 or start >= size or end < start:
                raise HTTPException(status_code=416, detail="Invalid byte range")
            end = min(end, size - 1)

        length = end - start + 1

        def chunks():
            with path.open("rb") as stream:
                stream.seek(start)
                remaining = length
                while remaining:
                    chunk = stream.read(min(1024 * 1024, remaining))
                    if not chunk:
                        break
                    remaining -= len(chunk)
                    yield chunk

        headers = {
            "Accept-Ranges": "bytes",
            "Content-Length": str(length),
            "Content-Disposition": f'attachment; filename="{path.name}"',
        }
        if file_meta.get("sha256"):
            headers["X-Model-SHA256"] = str(file_meta["sha256"])
        if range_header:
            headers["Content-Range"] = f"bytes {start}-{end}/{size}"
        return StreamingResponse(chunks(), status_code=206 if range_header else 200, media_type="application/octet-stream", headers=headers)

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

    @router.patch("/passenger/requests/{request_id}/cancel", response_model=RequestResponse)
    def passenger_cancel(request_id: str, payload: UpdateStatusBody, device: dict = Depends(token_device)):
        if device["device_type"] != "passenger":
            raise HTTPException(status_code=403, detail="Passenger device required")
        return cancel_passenger_request(request_id, payload.idempotency_key, device, bus)

    @router.post("/passenger/requests/{request_id}/messages")
    def passenger_message(request_id: str, payload: CrewMessageBody, device: dict = Depends(token_device)):
        if device["device_type"] != "passenger":
            raise HTTPException(status_code=403, detail="Passenger device required")
        return create_passenger_message(request_id, payload, device, bus)

    @router.post("/passenger/actions")
    def passenger_action(payload: PassengerActionBody, device: dict = Depends(token_device)):
        if device["device_type"] != "passenger":
            raise HTTPException(status_code=403, detail="Passenger device required")
        return submit_passenger_action(payload, device, bus)

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

    @router.post("/crew/requests/{request_id}/messages")
    def crew_message(request_id: str, payload: CrewMessageBody, device: dict = Depends(token_device)):
        if device["device_type"] != "crew":
            raise HTTPException(status_code=403, detail="Crew device required")
        return create_crew_message(request_id, payload, device, bus)

    @router.post("/crew/announcements")
    def crew_announcement(payload: AnnouncementBody, device: dict = Depends(token_device)):
        if device["device_type"] != "crew":
            raise HTTPException(status_code=403, detail="Crew device required")
        return create_announcement(payload, device, bus)

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
