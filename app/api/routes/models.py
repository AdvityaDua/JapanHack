from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select

from app.api.dependencies import DB, get_current_user
from app.core.config import settings
from app.db.models import TranslationModel, User
from app.schemas.model import DownloadURLResponse, ModelResponse
from app.services.r2_storage import r2_storage

router = APIRouter(prefix="/api/v1/models", tags=["translation models"])


@router.get("", response_model=list[ModelResponse])
def list_models(db: DB, source_language: str | None = Query(default=None), target_language: str | None = Query(default=None), platform: str | None = Query(default=None), _user: User = Depends(get_current_user)):
    query = select(TranslationModel).where(TranslationModel.status == "active")
    if source_language:
        query = query.where(TranslationModel.source_language == source_language)
    if target_language:
        query = query.where(TranslationModel.target_language == target_language)
    if platform:
        query = query.where(TranslationModel.platform.in_([platform, "all"]))
    return db.scalars(query.order_by(TranslationModel.created_at.desc())).all()


@router.post("/{model_id}/download-url", response_model=DownloadURLResponse)
def download_url(model_id: str, db: DB, _user: User = Depends(get_current_user)):
    model = db.get(TranslationModel, model_id)
    if not model or model.status != "active":
        raise HTTPException(status_code=404, detail="Model not found")
    try:
        url = r2_storage.create_download_url(model.r2_object_key)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return DownloadURLResponse(model_id=model.id, download_url=url, expires_in_seconds=settings.model_download_url_expire_seconds, sha256_checksum=model.sha256_checksum)
