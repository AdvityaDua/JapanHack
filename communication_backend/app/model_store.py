"""Read-only catalogue and safe local-file access for aircraft model bundles."""

from __future__ import annotations

import json
from pathlib import Path

from fastapi import HTTPException

from app.config import settings


def _manifest_path() -> Path:
    return Path(settings.model_manifest_path).expanduser().resolve()


def load_manifest() -> dict:
    path = _manifest_path()
    if not path.exists():
        return {"version": 1, "models": []}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=503, detail="Model manifest is unavailable") from exc
    if not isinstance(value, dict) or not isinstance(value.get("models", []), list):
        raise HTTPException(status_code=503, detail="Model manifest is invalid")
    return value


def get_model(model_id: str) -> dict:
    for model in load_manifest()["models"]:
        if isinstance(model, dict) and model.get("id") == model_id:
            return model
    raise HTTPException(status_code=404, detail="Model not found")


def get_model_file(model_id: str, file_name: str) -> tuple[dict, dict, Path]:
    model = get_model(model_id)
    files = model.get("files", [])
    file_meta = next((item for item in files if isinstance(item, dict) and item.get("name") == file_name), None)
    if file_meta is None:
        raise HTTPException(status_code=404, detail="Model file not found")
    if not file_name or Path(file_name).name != file_name:
        raise HTTPException(status_code=400, detail="Invalid model file name")
    root = Path(settings.model_directory).expanduser().resolve() / model_id
    path = (root / file_name).resolve()
    if root not in path.parents:
        raise HTTPException(status_code=400, detail="Invalid model file path")
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Model file is not installed on the aircraft server")
    return model, file_meta, path


def public_catalog() -> dict:
    result = []
    for model in load_manifest()["models"]:
        if not isinstance(model, dict) or not isinstance(model.get("id"), str):
            continue
        files = []
        available = True
        for file_meta in model.get("files", []):
            if not isinstance(file_meta, dict) or not isinstance(file_meta.get("name"), str):
                continue
            path = Path(settings.model_directory).expanduser().resolve() / model["id"] / file_meta["name"]
            installed = path.is_file()
            available = available and installed
            files.append({**file_meta, "available": installed})
        result.append({**model, "files": files, "available": available})
    return {"version": load_manifest().get("version", 1), "flight_id": settings.flight_id, "models": result}
