import asyncio
import json


class ConnectionManager:
    def __init__(self) -> None:
        self.passengers: dict[str, set] = {}
        self.crew: dict[str, set] = {}
        self.loop: asyncio.AbstractEventLoop | None = None

    def set_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        self.loop = loop

    async def connect(self, websocket, flight_id: str, audience: str, device_id: str) -> None:
        await websocket.accept()
        group = self.crew if audience == "crew" else self.passengers
        group.setdefault(f"{flight_id}:{device_id}", set()).add(websocket)

    def disconnect(self, websocket, flight_id: str, audience: str, device_id: str) -> None:
        group = self.crew if audience == "crew" else self.passengers
        group.get(f"{flight_id}:{device_id}", set()).discard(websocket)

    async def send(self, websocket, event: dict) -> None:
        await websocket.send_text(json.dumps(event))

    def broadcast(self, flight_id: str, event: dict, passenger_device_id: str | None = None) -> None:
        if not self.loop:
            return
        targets = set()
        for sockets in self.crew.values():
            targets.update(sockets)
        if passenger_device_id:
            targets.update(self.passengers.get(f"{flight_id}:{passenger_device_id}", set()))
        for websocket in targets:
            asyncio.run_coroutine_threadsafe(self.send(websocket, event), self.loop)

    def broadcast_passengers(self, flight_id: str, event: dict, passenger_device_id: str | None = None) -> None:
        if not self.loop:
            return
        if passenger_device_id:
            targets = set(self.passengers.get(f"{flight_id}:{passenger_device_id}", set()))
        else:
            targets = {socket for key, sockets in self.passengers.items() if key.startswith(f"{flight_id}:") for socket in sockets}
        for websocket in targets:
            asyncio.run_coroutine_threadsafe(self.send(websocket, event), self.loop)


manager = ConnectionManager()
