import json
from pathlib import Path

import structlog

logger = structlog.get_logger()

_DATA_DIR = Path(__file__).parent

_items: dict = {}
_cards: dict = {}
_monsters: dict = {}
_maps: dict = {}
_skills: dict = {}
_quests: dict = {}
_classes: dict = {}


def _load(filename: str) -> list:
    path = _DATA_DIR / filename
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_all() -> None:
    global _items, _cards, _monsters, _maps, _skills, _quests, _classes

    _items = {entry["id"]: entry for entry in _load("items.json")}
    _cards = {entry["id"]: entry for entry in _load("cards.json")}
    _monsters = {entry["id"]: entry for entry in _load("monsters.json")}
    _maps = {entry["id"]: entry for entry in _load("maps.json")}
    _skills = {entry["id"]: entry for entry in _load("skills.json")}
    _quests = {entry["id"]: entry for entry in _load("quests.json")}
    _classes = {entry["id"]: entry for entry in _load("classes.json")}

    logger.info(
        "catalogs_loaded",
        items=len(_items),
        cards=len(_cards),
        monsters=len(_monsters),
        maps=len(_maps),
        skills=len(_skills),
        quests=len(_quests),
        classes=len(_classes),
    )


def get_items() -> dict: return _items
def get_cards() -> dict: return _cards
def get_monsters() -> dict: return _monsters
def get_maps() -> dict: return _maps
def get_skills() -> dict: return _skills
def get_quests() -> dict: return _quests
def get_classes() -> dict: return _classes
