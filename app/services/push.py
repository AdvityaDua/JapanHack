from __future__ import annotations

from sqlalchemy import select

from app.core.config import settings
from app.db.models import PushDevice

_firebase_app = None


def send_user_notification(db, user_id, *, title: str, body: str, data: dict[str, str] | None = None) -> int:
    """Best-effort FCM delivery; returns the number of accepted messages."""
    if not settings.firebase_credentials_path:
        return 0
    try:
        import firebase_admin
        from firebase_admin import credentials, messaging
    except ImportError:
        return 0

    global _firebase_app
    try:
        if _firebase_app is None:
            try:
                _firebase_app = firebase_admin.get_app()
            except ValueError:
                options = {"projectId": settings.firebase_project_id} if settings.firebase_project_id else None
                _firebase_app = firebase_admin.initialize_app(credentials.Certificate(settings.firebase_credentials_path), options=options)
        tokens = db.scalars(select(PushDevice.token).where(PushDevice.user_id == user_id, PushDevice.enabled.is_(True))).all()
        accepted = 0
        for token in tokens:
            try:
                messaging.send(messaging.Message(notification=messaging.Notification(title=title, body=body), data=data or {}, token=token), app=_firebase_app)
                accepted += 1
            except Exception:
                # Stale tokens are harmless; the next app launch registers the current token.
                continue
        return accepted
    except Exception:
        return 0
