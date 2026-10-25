from fastapi import APIRouter, Depends
from sqlalchemy import select

from app.api.dependencies import DB, get_current_user
from app.db.models import PushDevice, User
from app.schemas.notifications import PushDeviceRegistration, PushDeviceResponse

router = APIRouter(prefix="/api/v1/notifications", tags=["notifications"])


@router.post("/devices", response_model=PushDeviceResponse)
def register_device(payload: PushDeviceRegistration, db: DB, user: User = Depends(get_current_user)):
    device = db.scalar(select(PushDevice).where(PushDevice.user_id == user.id, PushDevice.device_id == payload.device_id))
    token_owner = db.scalar(select(PushDevice).where(PushDevice.token == payload.token))
    if token_owner and token_owner.user_id != user.id:
        # FCM tokens can be reassigned after reinstall/account changes. Keep
        # the old row for auditability but free the token for its new owner.
        token_owner.token = f"revoked:{token_owner.id}"
        token_owner.enabled = False
    if device is None:
        device = PushDevice(user_id=user.id, **payload.model_dump())
        db.add(device)
    else:
        for field, value in payload.model_dump().items():
            setattr(device, field, value)
        device.enabled = True
    db.commit()
    db.refresh(device)
    return device


@router.delete("/devices/{device_id}", status_code=204)
def unregister_device(device_id: str, db: DB, user: User = Depends(get_current_user)):
    device = db.scalar(select(PushDevice).where(PushDevice.user_id == user.id, PushDevice.device_id == device_id))
    if device:
        device.enabled = False
        db.commit()
