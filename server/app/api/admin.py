import json
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import settings
from app.data import loader

router = APIRouter(prefix="/admin/api", tags=["admin"])
_bearer = HTTPBearer()
_DATA_DIR = Path(__file__).parent.parent / "data"

_FILES = {
    "items":    "items.json",
    "monsters": "monsters.json",
    "maps":     "maps.json",
    "cards":    "cards.json",
    "skills":   "skills.json",
    "quests":   "quests.json",
    "formulas": "formulas.json",
}


def _auth(creds: HTTPAuthorizationCredentials = Depends(_bearer)):
    if creds.credentials != settings.admin_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token inválido")


def _read(catalog: str) -> list:
    path = _DATA_DIR / _FILES[catalog]
    return json.loads(path.read_text(encoding="utf-8"))


def _write(catalog: str, data: list) -> None:
    path = _DATA_DIR / _FILES[catalog]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    loader.load_all()


# ── List ──────────────────────────────────────────────────────────────────────

@router.get("/{catalog}")
def list_catalog(catalog: str, _=Depends(_auth)) -> list[Any]:
    if catalog not in _FILES:
        raise HTTPException(status_code=404, detail="Catálogo não encontrado")
    return _read(catalog)


# ── Create ────────────────────────────────────────────────────────────────────

@router.post("/{catalog}", status_code=201)
def create_entry(catalog: str, body: dict, _=Depends(_auth)) -> dict:
    if catalog not in _FILES:
        raise HTTPException(status_code=404, detail="Catálogo não encontrado")
    if "id" not in body or not body["id"]:
        raise HTTPException(status_code=400, detail="Campo 'id' obrigatório")

    data = _read(catalog)
    if any(e["id"] == body["id"] for e in data):
        raise HTTPException(status_code=409, detail=f"ID '{body['id']}' já existe")

    data.append(body)
    _write(catalog, data)
    return body


# ── Update ────────────────────────────────────────────────────────────────────

@router.put("/{catalog}/{entry_id}")
def update_entry(catalog: str, entry_id: str, body: dict, _=Depends(_auth)) -> dict:
    if catalog not in _FILES:
        raise HTTPException(status_code=404, detail="Catálogo não encontrado")

    data = _read(catalog)
    idx = next((i for i, e in enumerate(data) if e["id"] == entry_id), None)
    if idx is None:
        raise HTTPException(status_code=404, detail=f"'{entry_id}' não encontrado")

    body["id"] = entry_id
    data[idx] = body
    _write(catalog, data)
    return body


# ── Delete ────────────────────────────────────────────────────────────────────

@router.delete("/{catalog}/{entry_id}", status_code=204)
def delete_entry(catalog: str, entry_id: str, _=Depends(_auth)) -> None:
    if catalog not in _FILES:
        raise HTTPException(status_code=404, detail="Catálogo não encontrado")

    data = _read(catalog)
    new_data = [e for e in data if e["id"] != entry_id]
    if len(new_data) == len(data):
        raise HTTPException(status_code=404, detail=f"'{entry_id}' não encontrado")

    _write(catalog, new_data)


# ── Reload manual ─────────────────────────────────────────────────────────────

@router.post("/reload", status_code=200)
def reload_catalogs(_=Depends(_auth)) -> dict:
    loader.load_all()
    return {"ok": True}
