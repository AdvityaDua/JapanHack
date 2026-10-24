from fastapi import APIRouter, Depends

from app.api.dependencies import DB, get_current_user
from app.db.models import User, UserPreference
from app.schemas.preferences import PreferenceResponse, PreferenceUpdate

router = APIRouter(prefix="/api/v1/preferences", tags=["preferences"])


def get_or_create_preferences(db, user: User) -> UserPreference:
    preferences = user.preferences
    if preferences is None:
        preferences = UserPreference(
            user_id=user.id,
            spoken_language=user.preferred_language,
            display_language=user.preferred_language,
        )
        db.add(preferences)
        db.commit()
        db.refresh(preferences)
    return preferences


@router.get("", response_model=PreferenceResponse)
def get_preferences(db: DB, user: User = Depends(get_current_user)):
    return get_or_create_preferences(db, user)


@router.put("", response_model=PreferenceResponse)
def update_preferences(payload: PreferenceUpdate, db: DB, user: User = Depends(get_current_user)):
    preferences = get_or_create_preferences(db, user)
    for field, value in payload.model_dump().items():
        setattr(preferences, field, value)
    user.preferred_language = payload.display_language
    db.commit()
    db.refresh(preferences)
    return preferences
