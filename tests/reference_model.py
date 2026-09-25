"""Small host-side reference model for deterministic policy contract tests."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"


def load(name: str) -> dict:
    return json.loads((DATA / name).read_text(encoding="utf-8"))


CATALOG = load("catalog_source.json")
EFFECTS = load("effects_source.json")
ACTIONS = load("actions_source.json")
MECHANICS = load("mechanics_source.json")
POLICIES = load("policies_source.json")


def item_slots(item: dict) -> list[str]:
    """Return schema-v2 slot compatibility with a migration fallback."""
    if isinstance(item.get("slots"), list):
        return item["slots"]
    return [item["slot"]]


def item_effects(item_id: int, context: str) -> tuple[dict[str, float], set[str]]:
    stats: dict[str, float] = {}
    tags: set[str] = set()
    for effect in EFFECTS["effects"]:
        if effect["item_id"] != item_id or context not in effect["applies_to"]:
            continue
        if effect.get("tag") and effect.get("verified_text"):
            tags.add(effect["tag"])
        if (
            effect.get("stat")
            and isinstance(effect.get("value"), (int, float))
            and effect["verification"] == "Verified"
        ):
            stats[effect["stat"]] = stats.get(effect["stat"], 0) + effect["value"]
    return stats, tags


def candidate_key(item: dict, context: str, policy: dict) -> tuple:
    effect_stats, tags = item_effects(item["id"], context)
    stats = dict(item["stats"])
    for stat, value in effect_stats.items():
        stats[stat] = stats.get(stat, 0) + value
    required = sum(tag in tags for tag in policy.get("required_tags", []))
    values: list[float | int] = [required]
    for objective in policy["objectives"]:
        value = stats.get(objective["stat"], 0)
        if "cap" in objective:
            value = min(value, objective["cap"])
        if "target" in objective:
            value = min(value, objective["target"])
        if objective["direction"] == "min":
            value = -value
        values.append(value)
    values.append(-item["id"])
    return tuple(values)


def resolve(owned: list[int], job: str, level: int, context: str) -> dict[str, dict]:
    policy = POLICIES["jobs"][job]["contexts"][context]
    eligible = [
        item
        for item in CATALOG["items"]
        if item["id"] in owned
        and item["verification"] == "Verified"
        and item["required_level"] <= level
        and job in item["jobs"]
        and not any(
            slot in {"Main", "Sub", "Range", "Ammo"}
            for slot in item_slots(item)
        )
    ]
    by_slot: dict[str, list[dict]] = {}
    for item in eligible:
        for slot in item_slots(item):
            by_slot.setdefault(slot, []).append(item)
    return {
        slot: max(items, key=lambda item: candidate_key(item, context, policy))
        for slot, items in by_slot.items()
    }
