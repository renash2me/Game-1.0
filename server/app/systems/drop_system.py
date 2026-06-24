import random
import uuid
from dataclasses import dataclass, field


@dataclass
class Drop:
    drop_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    item_id: str = ""
    quantity: int = 1
    cards: list = field(default_factory=list)

    def to_dict(self, x: float, y: float) -> dict:
        return {
            "drop_id": self.drop_id,
            "item_id": self.item_id,
            "quantity": self.quantity,
            "cards": self.cards,
            "x": x,
            "y": y,
        }


def roll_drops(monster_data: dict) -> list[Drop]:
    """
    Rola as chances de drop de um monstro.
    Cartas têm chance de 0.01% (0.0001) — cada drop é rolado independentemente.
    """
    drops: list[Drop] = []
    for entry in monster_data.get("drops", []):
        if random.random() < entry["chance"]:
            drops.append(Drop(item_id=entry["item_id"], quantity=1))
    return drops
