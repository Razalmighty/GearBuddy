#!/usr/bin/env python3
"""Normalize an English Ashita v4 IItem export into a catalog base.

The output is deliberately evidence-only. It contains no verification state;
`merge_catalog_sources.py` assigns every untouched row `ID Verified`, so client
resource data cannot silently become optimizer-eligible.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import date
from pathlib import Path
from typing import Any


class AshitaNormalizeError(ValueError):
    """Raised when an Ashita resource export violates the input contract."""


EQUIPPABLE_FLAG = 0x800
KNOWN_SLOT_MASK = 0xFFFF
RESOURCE_SCHEMA = "Ashita v4 IItem"

# Ashita and LuAshitacast use one-based equipment-slot indices. Ear and ring
# sides collapse to catalog compatibility classes; the runtime expands those
# classes back to Ear1/Ear2 and Ring1/Ring2 while enforcing instance identity.
SLOT_BITS = (
    (0, "Main"),
    (1, "Sub"),
    (2, "Range"),
    (3, "Ammo"),
    (4, "Head"),
    (5, "Body"),
    (6, "Hands"),
    (7, "Legs"),
    (8, "Feet"),
    (9, "Neck"),
    (10, "Waist"),
    (11, "Ear"),
    (12, "Ear"),
    (13, "Ring"),
    (14, "Ring"),
    (15, "Back"),
)

JOB_BITS = (
    (1, "WAR"), (2, "MNK"), (3, "WHM"), (4, "BLM"),
    (5, "RDM"), (6, "THF"), (7, "PLD"), (8, "DRK"),
    (9, "BST"), (10, "BRD"), (11, "RNG"), (12, "SAM"),
    (13, "NIN"), (14, "DRG"), (15, "SMN"), (16, "BLU"),
    (17, "COR"), (18, "PUP"), (19, "DNC"), (20, "SCH"),
    (21, "GEO"), (22, "RUN"),
)
KNOWN_JOB_MASK = sum(1 << job_id for job_id, _ in JOB_BITS)
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AshitaNormalizeError(message)


def integer(row: dict[str, Any], field: str, label: str) -> int:
    value = row.get(field)
    require(
        isinstance(value, int) and not isinstance(value, bool) and value >= 0,
        f"{label} {field} must be a nonnegative integer.",
    )
    return value


def optional_integer(row: dict[str, Any], field: str, label: str) -> int | None:
    if field not in row or row[field] is None:
        return None
    return integer(row, field, label)


def decode_slots(mask: int) -> list[str]:
    require(mask & ~KNOWN_SLOT_MASK == 0, f"Unsupported Ashita slot bits: 0x{mask:X}")
    result: list[str] = []
    for bit, name in SLOT_BITS:
        if mask & (1 << bit) and name not in result:
            result.append(name)
    return result


def decode_jobs(mask: int) -> list[str]:
    return [name for job_id, name in JOB_BITS if mask & (1 << job_id)]


def _validate_header(payload: dict[str, Any], input_sha256: str) -> None:
    require(payload.get("schema_version") == 1, "Unsupported Ashita export schema version.")
    require(payload.get("resource_schema") == RESOURCE_SCHEMA, "Unexpected resource schema.")
    require(payload.get("language") == "English", "Ashita export language must be English.")
    require(
        isinstance(payload.get("source_id"), str) and payload["source_id"].strip(),
        "Ashita export source_id is required.",
    )
    extracted_on = payload.get("extracted_on")
    require(isinstance(extracted_on, str), "Ashita export extracted_on is required.")
    try:
        date.fromisoformat(extracted_on)
    except (TypeError, ValueError) as exc:
        raise AshitaNormalizeError("Ashita export extracted_on must be an ISO date.") from exc
    require(SHA256_PATTERN.fullmatch(input_sha256) is not None, "Input SHA-256 is invalid.")
    require(isinstance(payload.get("items"), list), "Ashita export items must be a list.")


def _resource_evidence(row: dict[str, Any], label: str) -> dict[str, Any]:
    result: dict[str, Any] = {
        "flags": integer(row, "Flags", label),
        "slots_mask": integer(row, "Slots", label),
        "jobs_mask": integer(row, "Jobs", label),
        "raw_description": row["Description"],
    }
    for source_field, target_field in (
        ("Type", "type"),
        ("ResourceId", "resource_id"),
        ("ItemLevel", "item_level"),
        ("SuperiorLevel", "superior_level"),
        ("Skill", "skill"),
        ("DPS", "dps"),
    ):
        value = optional_integer(row, source_field, label)
        if value is not None:
            result[target_field] = value
    return result


def normalize_export(
    payload: dict[str, Any],
    *,
    input_sha256: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Return a schema-v2 base catalog and deterministic audit report."""
    require(isinstance(payload, dict), "Ashita export must be a JSON object.")
    _validate_header(payload, input_sha256)

    normalized: list[dict[str, Any]] = []
    seen: set[int] = set()
    skipped_not_equippable = 0
    skipped_no_slot = 0
    empty_job_masks = 0
    unknown_job_masks = 0
    multi_slot_items = 0

    for position, row in enumerate(payload["items"], start=1):
        require(isinstance(row, dict), f"Ashita row {position} must be an object.")
        label = f"Ashita row {position}"
        item_id = integer(row, "Id", label)
        require(item_id > 0, f"{label} Id must be positive.")
        require(item_id not in seen, f"Duplicate Ashita item ID: {item_id}")
        seen.add(item_id)

        flags = integer(row, "Flags", label)
        slots_mask = integer(row, "Slots", label)
        jobs_mask = integer(row, "Jobs", label)
        level = integer(row, "Level", label)
        damage = integer(row, "Damage", label)
        delay = integer(row, "Delay", label)

        if flags & EQUIPPABLE_FLAG == 0:
            skipped_not_equippable += 1
            continue
        if slots_mask == 0:
            skipped_no_slot += 1
            continue

        name = row.get("Name")
        description = row.get("Description")
        require(isinstance(name, str) and name.strip(), f"Item {item_id} lacks an English name.")
        require(isinstance(description, str), f"Item {item_id} lacks an English description string.")

        slots = decode_slots(slots_mask)
        require(slots, f"Item {item_id} has no supported equipment slot.")
        jobs = decode_jobs(jobs_mask)
        unknown_job_bits = jobs_mask & ~KNOWN_JOB_MASK
        if not jobs:
            empty_job_masks += 1
        if unknown_job_bits:
            unknown_job_masks += 1
        if len(slots) > 1:
            multi_slot_items += 1

        stats: dict[str, int] = {}
        if damage > 0:
            stats["damage"] = damage
        if delay > 0:
            stats["delay"] = delay

        evidence = _resource_evidence(row, f"Item {item_id}")
        if unknown_job_bits:
            evidence["unknown_jobs_mask"] = unknown_job_bits

        normalized.append({
            "id": item_id,
            "name": name.strip(),
            "slots": slots,
            "required_level": level,
            "jobs": jobs,
            "stats": stats,
            "resource_evidence": evidence,
        })

    normalized.sort(key=lambda row: row["id"])
    base = {
        "schema_version": 2,
        "source_id": payload["source_id"],
        "source_type": RESOURCE_SCHEMA,
        "extracted_on": payload["extracted_on"],
        "language": payload["language"],
        "input_sha256": input_sha256,
        "items": normalized,
    }
    if isinstance(payload.get("resource_version"), str) and payload["resource_version"].strip():
        base["resource_version"] = payload["resource_version"].strip()

    report = {
        "input_rows": len(payload["items"]),
        "normalized_equipment_rows": len(normalized),
        "skipped_not_equippable": skipped_not_equippable,
        "skipped_no_slot": skipped_no_slot,
        "empty_known_job_masks": empty_job_masks,
        "rows_with_unknown_job_bits": unknown_job_masks,
        "multi_catalog_slot_items": multi_slot_items,
        "input_sha256": input_sha256,
    }
    return base, report


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--base-out", type=Path, required=True)
    parser.add_argument("--report-out", type=Path, required=True)
    args = parser.parse_args()

    raw = args.input.read_bytes()
    try:
        payload = json.loads(raw.decode("utf-8"))
        base, report = normalize_export(
            payload,
            input_sha256=hashlib.sha256(raw).hexdigest(),
        )
    except (UnicodeDecodeError, json.JSONDecodeError, AshitaNormalizeError) as exc:
        parser.error(str(exc))

    write_json(args.base_out, base)
    write_json(args.report_out, report)
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
