from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import auth, bookings, health, integrations, models, notifications, preferences, users
from app.core.config import settings
from app.db import models as _models
from app.db.session import Base, engine



@asynccontextmanager
async def lifespan(_app: FastAPI):
    create_local_tables()
    yield


app = FastAPI(title=settings.app_name, version="0.1.0", debug=settings.debug, lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.include_router(health.router)
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(bookings.router)
app.include_router(integrations.router)
app.include_router(models.router)
app.include_router(preferences.router)
app.include_router(notifications.router)


def create_local_tables() -> None:
    if settings.environment == "development" and not settings.database_url:
        Base.metadata.create_all(bind=engine)
