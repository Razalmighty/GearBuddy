#!/usr/bin/env python3
"""Extract static BLU mechanics candidates from a LandSandBoat checkout.

The result is comparison evidence only. It is intentionally incompatible with
the reviewed runtime mechanics registry and cannot promote a Horizon row.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]

NUMERIC_FIELDS = {
    "numHits": "hit_count",
    "ftp0": "ftp_0",
    "ftp1500": "ftp_1500",
    "ftp3000": "ftp_3000",
    "ftpAzure": "ftp_azure_lore",
    "baseDamageCap": "base_damage_cap",
    "attackMult": "attack_multiplier",
    "dStatMultiplier": "dstat_multiplier",
    "constant": "constant",
}
SYMBOLIC_FIELDS = {
    "dStat": "dstat",
    "tpModifier": "tp_modifier",
    "attackType": "attack_type",
    "damageType": "damage_type",
}
WSC_PATTERN = re.compile(r"^([a-z]+)_wsc$")
ASSIGNMENT_PATTERN = re.compile(
    r"^\s*params\.([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.+?)(?:\s*--.*)?$",
    re.MULTILINE,
)
NUMBER_PATTERN = re.compile(r"^-?(?:\d+(?:\.\d*)?|\.\d+)$")
SYMBOL_PATTERN = re.compile(r"^xi\.(?:mod|spells\.blue\.tpMod|attackType|damageType)\.([A-Z0-9_]+)$")


def normalize_name(value: str) -> str:
    return " ".join(re.sub(r"[^a-z0-9]+", " ", value.lower()).split())


def source_revision(checkout: Path) -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=checkout, check=True,
            capture_output=True, text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def parse_value(raw: str) -> int | float | str | None:
    value = raw.strip()
    if NUMBER_PATTERN.fullmatch(value):
        number = float(value)
        return int(number) if number.is_integer() else number
    symbol = SYMBOL_PATTERN.fullmatch(value)
    return symbol.group(1).lower() if symbol else None


def extract_file(path: Path, action_lookup: dict[str, dict[str, Any]]) -> dict[str, Any] | None:
    raw = path.read_bytes()
    text = raw.decode("utf-8")
    key = normalize_name(path.stem)
    action = action_lookup.get(key)
    if action is None:
        return None

    values: dict[str, Any] = {}
    ignored: list[str] = []
    for field, raw_value in ASSIGNMENT_PATTERN.findall(text):
        target = NUMERIC_FIELDS.get(field)
        wsc = WSC_PATTERN.fullmatch(field)
        if wsc:
            target = f"wsc.{wsc.group(1)}"
        elif field in SYMBOLIC_FIELDS:
            target = SYMBOLIC_FIELDS[field]
        if target is None:
            continue
        value = parse_value(raw_value)
        if value is None:
            ignored.append(field)
        else:
            values[target] = value

    if not values and not ignored:
        return None
    return {
        "action_id": action["id"],
        "action_name": action["name"],
        "source_file": path.name,
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "verification": "Comparison only",
        "candidate_values": dict(sorted(values.items())),
        "ignored_dynamic_fields": sorted(set(ignored)),
    }


def extract(checkout: Path, actions_path: Path) -> dict[str, Any]:
    scripts = checkout / "scripts" / "actions" / "spells" / "blue"
    if not scripts.is_dir():
        raise ValueError(f"LandSandBoat BLU script directory not found: {scripts}")
    actions = json.loads(actions_path.read_text(encoding="utf-8"))["actions"]
    lookup = {normalize_name(row["name"]): row for row in actions}
    rows = [extract_file(path, lookup) for path in sorted(scripts.glob("*.lua"))]
    candidates = [row for row in rows if row is not None]
    matched_ids = {row["action_id"] for row in candidates}
    return {
        "schema_version": 1,
        "source_type": "LandSandBoat comparison",
        "source_revision": source_revision(checkout),
        "server_scope": "comparison_only_not_HorizonXI",
        "promotion_policy": "manual_per_outcome_review_required",
        "candidate_actions": candidates,
        "summary": {
            "source_files": len(list(scripts.glob("*.lua"))),
            "matched_actions": len(matched_ids),
            "unmatched_verified_actions": [
                {"id": row["id"], "name": row["name"]}
                for row in actions
                if row["verification"] == "Verified" and row["id"] not in matched_ids
            ],
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkout", type=Path, required=True)
    parser.add_argument("--actions", type=Path, default=ROOT / "data" / "actions_source.json")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    try:
        payload = extract(args.checkout.resolve(), args.actions.resolve())
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        parser.error(str(exc))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload["summary"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
