#!/usr/bin/env python3
"""Merge bulk client item data with reviewed Horizon overrides.

Bulk rows enter as identity-only candidates. Only an explicit reviewed override
can promote a row to Verified, and every changed value must carry a resolution.
This keeps large imports useful without allowing retail/client drift to affect
runtime optimization silently.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any


class CatalogMergeError(ValueError):
    """Raised when catalog evidence is incomplete or internally inconsistent."""


DECISIONS = {
    "verify": ("Verified", "high"),
    "partial": ("Partial", "medium"),
    "exclude": ("Pending", "high"),
}
VALID_SLOTS = {
    "Main", "Sub", "Range", "Ammo", "Head", "Body", "Hands", "Legs",
    "Feet", "Neck", "Waist", "Ear", "Ring", "Back",
}
VALID_JOBS = {
    "WAR", "MNK", "WHM", "BLM", "RDM", "THF", "PLD", "DRK",
    "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "SMN", "BLU",
    "COR", "PUP", "DNC", "SCH", "GEO", "RUN",
}
COPY_FIELDS = (
    "id", "name", "slots", "required_level", "jobs", "weapon_type", "stats",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CatalogMergeError(message)


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(payload, dict), f"{path} must contain a JSON object.")
    return payload


def _normalized_slots(row: dict[str, Any], label: str) -> list[str]:
    slots = row.get("slots")
    if slots is None and row.get("slot") is not None:
        slots = [row["slot"]]
    require(isinstance(slots, list) and slots, f"{label} must have at least one slot.")
    require(all(isinstance(slot, str) for slot in slots), f"{label} has an invalid slot.")
    require(len(slots) == len(set(slots)), f"{label} repeats a slot.")
    require(all(slot in VALID_SLOTS for slot in slots), f"{label} has an unsupported slot.")
    return list(slots)


def _validate_item_fields(row: dict[str, Any], label: str) -> None:
    require(isinstance(row.get("name"), str) and row["name"].strip(), f"{label} lacks a name.")
    _normalized_slots(row, label)
    level = row.get("required_level")
    require(
        level is None or (
            isinstance(level, int) and not isinstance(level, bool) and level >= 0
        ),
        f"{label} required_level is invalid.",
    )
    jobs = row.get("jobs")
    require(isinstance(jobs, list), f"{label} jobs must be a list.")
    require(all(isinstance(job, str) for job in jobs), f"{label} has an invalid job.")
    require(len(jobs) == len(set(jobs)), f"{label} repeats a job.")
    require(all(job in VALID_JOBS for job in jobs), f"{label} has an unsupported job.")
    stats = row.get("stats")
    require(isinstance(stats, dict), f"{label} stats must be an object.")
    for stat, value in stats.items():
        require(isinstance(stat, str) and stat, f"{label} has an invalid stat name.")
        require(
            isinstance(value, (int, float)) and not isinstance(value, bool),
            f"{label} stat {stat} must be numeric.",
        )
    weapon_type = row.get("weapon_type")
    require(
        weapon_type is None or (isinstance(weapon_type, str) and weapon_type.strip()),
        f"{label} weapon_type is invalid.",
    )


def _validate_base(payload: dict[str, Any]) -> None:
    schema_version = payload.get("schema_version")
    require(schema_version in {1, 2}, "Unsupported base schema version.")
    require(isinstance(payload.get("source_id"), str) and payload["source_id"].strip(), "Base source_id is required.")
    require(isinstance(payload.get("extracted_on"), str) and payload["extracted_on"].strip(), "Base extracted_on is required.")
    require(isinstance(payload.get("items"), list), "Base items must be a list.")
    seen: set[int] = set()
    for row in payload["items"]:
        require(isinstance(row, dict), "Base item rows must be objects.")
        require(
            isinstance(row.get("id"), int)
            and not isinstance(row["id"], bool)
            and row["id"] > 0,
            "Base item ID is invalid.",
        )
        require(row["id"] not in seen, f"Duplicate base item ID: {row['id']}")
        seen.add(row["id"])
        if schema_version == 2:
            require("slots" in row and "slot" not in row, f"Item {row['id']} must use schema-v2 slots.")
        _validate_item_fields(row, f"Item {row['id']}")


def _validate_overrides(payload: dict[str, Any], base_ids: set[int]) -> None:
    require(payload.get("schema_version") == 1, "Unsupported override schema version.")
    require(payload.get("server_scope") == "HorizonXI", "Overrides must target HorizonXI.")
    require(isinstance(payload.get("items"), list), "Override items must be a list.")
    seen: set[int] = set()
    for row in payload["items"]:
        require(isinstance(row, dict), "Override rows must be objects.")
        item_id = row.get("id")
        require(isinstance(item_id, int) and item_id in base_ids, f"Override references unknown item: {item_id}")
        require(item_id not in seen, f"Duplicate override item ID: {item_id}")
        seen.add(item_id)
        require(row.get("decision") in DECISIONS, f"Item {item_id} has an invalid decision.")
        require(isinstance(row.get("source_id"), str), f"Item {item_id} override source_id is required.")
        require(isinstance(row.get("last_verified"), str), f"Item {item_id} last_verified is required.")
        require(isinstance(row.get("set", {}), dict), f"Item {item_id} set must be an object.")
        require(isinstance(row.get("remove_stats", []), list), f"Item {item_id} remove_stats must be a list.")
        require(isinstance(row.get("resolutions", {}), dict), f"Item {item_id} resolutions must be an object.")
        require(isinstance(row.get("effects", []), list), f"Item {item_id} effects must be a list.")


def _record_conflict(
    conflicts: list[dict[str, Any]],
    field: str,
    base_value: Any,
    horizon_value: Any,
    resolution: str | None,
    selected_value: Any,
    verified: bool,
) -> None:
    if base_value == horizon_value:
        return
    if verified:
        require(
            isinstance(resolution, str) and resolution.strip(),
            f"Verified override changes {field} without a resolution.",
        )
    conflicts.append({
        "field": field,
        "base_value": base_value,
        "horizon_value": horizon_value,
        "status": "resolved" if resolution else "unresolved",
        "selected_value": selected_value,
        "resolution": resolution,
    })


def _apply_override(item: dict[str, Any], override: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    result = copy.deepcopy(item)
    decision = override["decision"]
    verification, default_confidence = DECISIONS[decision]
    verified = decision == "verify"
    resolutions = override.get("resolutions", {})
    conflicts: list[dict[str, Any]] = []

    for field, value in override.get("set", {}).items():
        require(field in COPY_FIELDS[1:] or field == "horizon_change", f"Unsupported override field: {field}")
        if field == "stats":
            require(isinstance(value, dict), f"Item {item['id']} stats override must be an object.")
            for stat, stat_value in value.items():
                path = f"stats.{stat}"
                base_value = result["stats"].get(stat)
                _record_conflict(
                    conflicts, path, base_value, stat_value,
                    resolutions.get(path), stat_value, verified,
                )
                result["stats"][stat] = stat_value
        else:
            base_value = result.get(field)
            _record_conflict(
                conflicts, field, base_value, value,
                resolutions.get(field), value, verified,
            )
            result[field] = copy.deepcopy(value)

    for stat in override.get("remove_stats", []):
        require(isinstance(stat, str) and stat, f"Item {item['id']} has an invalid removed stat.")
        if stat in result["stats"]:
            path = f"stats.{stat}"
            _record_conflict(
                conflicts, path, result["stats"][stat], None,
                resolutions.get(path), None, verified,
            )
            del result["stats"][stat]

    result.update({
        "verification": verification,
        "confidence": override.get("confidence", default_confidence),
        "source_id": override["source_id"],
        "source_ids": list(dict.fromkeys([override["source_id"], item["source_id"]])),
        "horizon_change": override.get("set", {}).get("horizon_change", bool(conflicts)),
        "last_verified": override["last_verified"],
        "notes": override.get("notes"),
    })
    if conflicts:
        result["source_conflicts"] = conflicts
    if decision == "exclude":
        result["horizon_excluded"] = True

    _validate_item_fields(result, f"Item {item['id']}")

    if verified:
        require(
            isinstance(result.get("required_level"), int)
            and not isinstance(result["required_level"], bool)
            and result["required_level"] >= 1,
            f"Verified item {item['id']} lacks a level.",
        )
        require(bool(result.get("jobs")), f"Verified item {item['id']} lacks jobs.")
    return result, override.get("effects", [])


def merge_catalog(
    base: dict[str, Any],
    overrides: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    """Return catalog, effects, and an audit report without writing files."""
    _validate_base(base)
    base_ids = {row["id"] for row in base["items"]}
    _validate_overrides(overrides, base_ids)
    override_by_id = {row["id"]: row for row in overrides["items"]}

    items: list[dict[str, Any]] = []
    effects: list[dict[str, Any]] = []
    for source_row in sorted(base["items"], key=lambda row: row["id"]):
        row = {field: copy.deepcopy(source_row.get(field)) for field in COPY_FIELDS if field in source_row}
        row["slots"] = _normalized_slots(source_row, f"Item {source_row['id']}")
        row.update({
            "verification": "ID Verified",
            "confidence": "low",
            "source_id": base["source_id"],
            "source_ids": [base["source_id"]],
            "horizon_change": None,
            "last_verified": base["extracted_on"],
            "notes": "Bulk client/resource candidate; Horizon availability and stats are not yet reviewed.",
        })
        override = override_by_id.get(row["id"])
        if override is not None:
            row, item_effects = _apply_override(row, override)
            for effect in item_effects:
                merged_effect = copy.deepcopy(effect)
                merged_effect["item_id"] = row["id"]
                effects.append(merged_effect)
        items.append(row)

    effect_ids = [effect.get("id") for effect in effects]
    require(all(isinstance(value, str) and value for value in effect_ids), "Every effect requires a stable ID.")
    require(len(effect_ids) == len(set(effect_ids)), "Duplicate effect IDs in overrides.")

    catalog = {
        "schema_version": 2,
        "data_version": overrides.get("data_version", 1),
        "generated_from": overrides.get("generated_from", "bulk base + Horizon overrides"),
        "items": items,
    }
    effect_payload = {
        "schema_version": 1,
        "data_version": overrides.get("data_version", 1),
        "effects": effects,
    }
    report = {
        "base_items": len(items),
        "reviewed_items": len(override_by_id),
        "verified_items": sum(row["verification"] == "Verified" for row in items),
        "partial_items": sum(row["verification"] == "Partial" for row in items),
        "excluded_items": sum(row.get("horizon_excluded") is True for row in items),
        "identity_only_items": sum(row["verification"] == "ID Verified" for row in items),
        "resolved_conflicts": sum(
            conflict["status"] == "resolved"
            for row in items for conflict in row.get("source_conflicts", [])
        ),
        "unresolved_conflicts": sum(
            conflict["status"] == "unresolved"
            for row in items for conflict in row.get("source_conflicts", [])
        ),
        "effects": len(effects),
    }
    return catalog, effect_payload, report


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--overrides", type=Path, required=True)
    parser.add_argument("--catalog-out", type=Path, required=True)
    parser.add_argument("--effects-out", type=Path, required=True)
    parser.add_argument("--report-out", type=Path, required=True)
    args = parser.parse_args()

    catalog, effects, report = merge_catalog(
        load_json(args.base), load_json(args.overrides)
    )
    write_json(args.catalog_out, catalog)
    write_json(args.effects_out, effects)
    write_json(args.report_out, report)
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
