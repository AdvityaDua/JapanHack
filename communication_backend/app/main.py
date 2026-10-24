import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.domain import now_iso
from app.messaging import MQTTBus
from app.realtime import manager
from app.routes import make_router
from app.service import handle_mqtt_command
from app.store import store
from app.demo_seed import seed_demo_data, seed_demo_seat_map

logging.basicConfig(level=logging.INFO)


def command_handler(topic: str, payload: dict) -> None:
    handle_mqtt_command(topic, payload, bus)


bus = MQTTBus(command_handler)


@asynccontextmanager
async def lifespan(app: FastAPI):
    store.init()
    store.seed_session({"id": settings.flight_id, "flight_number": settings.flight_number, "aircraft_identifier": settings.aircraft_identifier, "status": "boarding", "started_at": now_iso()})
    if settings.demo_seed:
        seed_demo_seat_map()
        seed_demo_data()
    manager.set_loop(asyncio.get_running_loop())
    bus.start()
    yield
    bus.stop()


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.include_router(make_router(bus))


@app.get("/health", tags=["health"])
def health():
    return {"status": "ok", "flight_id": settings.flight_id, "mqtt_enabled": bus.enabled}


@app.get("/ready", tags=["health"])
def ready():
    return {"status": "ready", "flight_id": settings.flight_id}
