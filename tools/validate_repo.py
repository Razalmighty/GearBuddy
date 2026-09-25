#!/usr/bin/env python3
"""Static safety, provenance, and repository validation for GearBuddy."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"

REQUIRED = [
    "gearbuddy.lua",
    "core/app.lua",
    "core/context.lua",
    "core/inventory_index.lua",
    "core/item_legality.lua",
    "core/candidate.lua",
    "core/gear_pins.lua",
    "core/policy.lua",
    "core/resolver.lua",
    "core/score.lua",
    "core/action_mechanics.lua",
    "core/self_test.lua",
    "ui/console.lua",
    "ui/hud.lua",
    "data/catalog_source.json",
    "data/effects_source.json",
    "data/actions_source.json",
    "data/mechanics_source.json",
    "data/policies_source.json",
    "tools/normalize_ashita_items.py",
    "tools/merge_catalog_sources.py",
    "docs/APPROVAL_TEST_PLAN.md",
    "docs/CATALOG_PIPELINE.md",
    ".github/workflows/validate.yml",
    ".github/ISSUE_TEMPLATE/bug_report.yml",
    ".github/ISSUE_TEMPLATE/approval_finding.yml",
    ".github/pull_request_template.md",
    ".gitattributes",
    "LICENSE",
    "README.md",
]

FORBIDDEN_RUNTIME_TOKENS = [
    "AddOutgoingPacket",
    "InjectPacket",
    "QueueCommand",
    "'packet_out'",
    '"packet_out"',
]

VERIFICATION_STATES = {
    "Verified",
    "Verified text; magnitude unknown",
    "Partial",
    "ID Verified",
    "Pending",
}
CONFIDENCE_LEVELS = {"high", "medium", "low", "unknown"}
ACTION_CATEGORIES = {
    "physical",
    "magical",
    "debuff",
    "healing",
    "breath",
    "buff",
    "drain",
    "dispel",
    "status",
}
HORIZON_ACTION_STATES = {
    "Documented", "Horizon change", "Era excluded", "Verify source",
    "Wiki conflict",
}
ACTION_STAT_NAMES = {
    "str", "dex", "vit", "agi", "int", "mnd", "chr", "defense",
}
MECHANIC_OUTCOMES = {"landing", "potency", "duration", "utility"}
MECHANIC_STATUSES = {
    "unknown", "not_applicable", "qualitative", "verified_numeric",
}
MECHANIC_DRIVER_KINDS = {"stat", "state", "model", "property"}
CATALOG_SLOTS = {
    "Main", "Sub", "Range", "Ammo", "Head", "Body", "Hands", "Legs",
    "Feet", "Neck", "Waist", "Ear", "Ring", "Back",
}
CATALOG_JOBS = {
    "WAR", "MNK", "WHM", "BLM", "RDM", "THF", "PLD", "DRK",
    "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "SMN", "BLU",
    "COR", "PUP", "DNC", "SCH", "GEO", "RUN",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def load(name: str) -> dict:
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def validate_confidence(row: dict, label: str) -> None:
    if row.get("confidence") not in CONFIDENCE_LEVELS:
        fail(f"{label} lacks a valid confidence level.")
    if row.get("verification") not in VERIFICATION_STATES:
        fail(f"{label} lacks a valid verification state.")


def validate_actions(
    actions: dict,
    source_ids: set[str],
    policies: dict,
) -> tuple[int, int]:
    if actions.get("schema_version") != 1:
        fail("Action metadata schema version is unsupported.")
    if not isinstance(actions.get("data_version"), int) or actions["data_version"] < 1:
        fail("Action metadata data_version is invalid.")
    if actions.get("server_scope") != "HorizonXI":
        fail("Action metadata must declare HorizonXI server scope.")
    rows = actions.get("actions")
    if not isinstance(rows, list):
        fail("Action metadata actions must be a list.")

    ids: set[int] = set()
    names: set[str] = set()
    lookup_names: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            fail("Action metadata row is not an object.")
        required = (
            "id", "name", "job", "category", "context", "required_level",
            "skill", "element", "hit_count", "wsc", "accuracy_model",
            "flags", "horizon_override", "source_id", "source_ids",
            "last_verified", "confidence", "verification", "horizon_type",
            "horizon_verification", "horizon_spell_page", "dominant_stats",
            "tracker_priority", "best_use", "era_notes", "job_trait",
        )
        missing = [key for key in required if key not in row]
        if missing:
            fail(f"Action metadata row is missing: {', '.join(missing)}")
        action_id = row["id"]
        if isinstance(action_id, bool) or not isinstance(action_id, int) or action_id < 1:
            fail("Action metadata IDs must be positive integers.")
        if action_id in ids:
            fail(f"Duplicate action ID: {action_id}")
        ids.add(action_id)
        name = row["name"]
        if not isinstance(name, str) or not name.strip():
            fail(f"Action {action_id} lacks a readable name.")
        name_key = " ".join(name.lower().split())
        if name_key in names:
            fail(f"Duplicate action name: {name}")
        names.add(name_key)
        if name_key in lookup_names:
            fail(f"Duplicate action lookup name: {name}")
        lookup_names.add(name_key)
        if not isinstance(row["job"], str) or not row["job"].strip():
            fail(f"Action {action_id} lacks a legal job.")
        job = row["job"].upper()
        if job not in policies["jobs"]:
            fail(f"Action {action_id} references an unsupported job.")
        if row["category"] not in ACTION_CATEGORIES:
            fail(f"Action {action_id} has an invalid category.")
        if not isinstance(row["context"], str) or not row["context"].strip():
            fail(f"Action {action_id} lacks a policy context.")
        if row["context"] not in policies["jobs"][job]["contexts"]:
            fail(f"Action {action_id} references a missing policy context.")
        level = row["required_level"]
        if isinstance(level, bool) or not isinstance(level, int) or level < 1:
            fail(f"Action {action_id} has an invalid required level.")
        if row["source_id"] not in source_ids:
            fail(f"Action {action_id} lacks a valid source.")
        action_sources = row["source_ids"]
        if not isinstance(action_sources, list) or not action_sources:
            fail(f"Action {action_id} lacks its evidence chain.")
        if len(action_sources) != len(set(action_sources)):
            fail(f"Action {action_id} repeats a source ID.")
        if row["source_id"] not in action_sources:
            fail(f"Action {action_id} primary source is absent from source_ids.")
        if any(source_id not in source_ids for source_id in action_sources):
            fail(f"Action {action_id} contains an unknown source ID.")
        if not isinstance(row["last_verified"], str) or not row["last_verified"].strip():
            fail(f"Action {action_id} lacks a verification date.")
        validate_confidence(row, f"Action {action_id}")
        if row["verification"] == "Verified" and row["confidence"] == "unknown":
            fail(f"Verified action metadata cannot use unknown confidence: {action_id}")
        if not isinstance(row["skill"], str) or not row["skill"].strip():
            fail(f"Action {action_id} lacks a skill.")
        if not isinstance(row["element"], str) or not row["element"].strip():
            fail(f"Action {action_id} lacks an explicit element classification.")
        if not isinstance(row["accuracy_model"], str) or not row["accuracy_model"].strip():
            fail(f"Action {action_id} lacks an accuracy model.")
        if not isinstance(row["flags"], dict):
            fail(f"Action {action_id} flags must be an object.")
        if row["horizon_override"] is not None and not isinstance(row["horizon_override"], dict):
            fail(f"Action {action_id} Horizon override must be null or an object.")
        horizon_state = row["horizon_verification"]
        if horizon_state not in HORIZON_ACTION_STATES:
            fail(f"Action {action_id} has an invalid Horizon verification state.")
        if not isinstance(row["horizon_type"], str) or not row["horizon_type"].strip():
            fail(f"Action {action_id} lacks a Horizon spell type.")
        horizon_page = row["horizon_spell_page"]
        if not isinstance(horizon_page, str) or not horizon_page.startswith(
            "https://horizonffxi.wiki/"
        ):
            fail(f"Action {action_id} lacks a Horizon evidence page.")
        for key in ("tracker_priority", "best_use", "era_notes", "job_trait"):
            if not isinstance(row[key], str) or not row[key].strip():
                fail(f"Action {action_id} lacks tracker field {key}.")
        if horizon_state == "Horizon change":
            override = row["horizon_override"]
            if not isinstance(override, dict):
                fail(f"Action {action_id} lacks its Horizon override record.")
            if override.get("field") != "required_level":
                fail(f"Action {action_id} has an unsupported Horizon override field.")
            if override.get("horizon_value") != level:
                fail(f"Action {action_id} Horizon override disagrees with required_level.")
            retail_level = override.get("retail_value")
            if isinstance(retail_level, bool) or not isinstance(retail_level, int):
                fail(f"Action {action_id} lacks a retail comparison level.")
        elif row["horizon_override"] is not None:
            fail(f"Action {action_id} has an unflagged Horizon override.")
        if horizon_state in {"Documented", "Horizon change"}:
            if row["verification"] != "Verified":
                fail(f"Action {action_id} has documented Horizon evidence but is not Verified.")
        elif row["verification"] == "Verified":
            fail(f"Action {action_id} cannot be Verified while Horizon evidence is unresolved.")
        if horizon_state == "Era excluded" and row["verification"] != "Pending":
            fail(f"Era-excluded action {action_id} must remain Pending.")
        conflicts = row.get("source_conflicts", [])
        if not isinstance(conflicts, list):
            fail(f"Action {action_id} source_conflicts must be a list.")
        for conflict in conflicts:
            if not isinstance(conflict, dict) or not isinstance(conflict.get("field"), str):
                fail(f"Action {action_id} has an invalid source conflict.")
            if conflict.get("status") not in {"resolved", "unresolved", "unresolved_era_excluded"}:
                fail(f"Action {action_id} source conflict lacks a valid status.")
            if not isinstance(conflict.get("resolution"), str) or not conflict["resolution"].strip():
                fail(f"Action {action_id} source conflict lacks a resolution note.")
            if conflict["status"] == "resolved" and "selected_value" not in conflict:
                fail(f"Action {action_id} resolved conflict lacks a selected value.")
            if "client_resource_value" not in conflict:
                fail(f"Action {action_id} source conflict lacks its client comparison.")
        if horizon_state == "Wiki conflict" and not conflicts:
            fail(f"Action {action_id} lacks details for its wiki conflict.")
        hit_count = row["hit_count"]
        if isinstance(hit_count, bool) or not isinstance(hit_count, int) or hit_count < 1:
            fail(f"Action {action_id} has an invalid hit count.")
        wsc = row["wsc"]
        if not isinstance(wsc, dict):
            fail(f"Action {action_id} WSC must be an object.")
        for stat, coefficient in wsc.items():
            if not isinstance(stat, str) or not stat.strip():
                fail(f"Action {action_id} has an invalid WSC stat.")
            if isinstance(coefficient, bool) or not isinstance(coefficient, (int, float)) or coefficient < 0:
                fail(f"Action {action_id} has an invalid WSC coefficient.")
        dominant_stats = row["dominant_stats"]
        if not isinstance(dominant_stats, list):
            fail(f"Action {action_id} dominant_stats must be a list.")
        if len(dominant_stats) != len(set(dominant_stats)):
            fail(f"Action {action_id} repeats a qualitative stat focus.")
        if any(stat not in ACTION_STAT_NAMES for stat in dominant_stats):
            fail(f"Action {action_id} has an invalid qualitative stat focus.")
        aliases = row.get("aliases", [])
        if not isinstance(aliases, list):
            fail(f"Action {action_id} aliases must be a list.")
        alias_keys: list[str] = []
        for alias in aliases:
            if not isinstance(alias, str) or not alias.strip():
                fail(f"Action {action_id} has an invalid alias.")
            alias_keys.append(" ".join(alias.lower().split()))
        if len(alias_keys) != len(set(alias_keys)):
            fail(f"Action {action_id} repeats an alias.")
        if name_key in alias_keys:
            fail(f"Action {action_id} aliases its own primary name.")
        for alias_key in alias_keys:
            if alias_key in lookup_names:
                fail(f"Action {action_id} has a duplicate lookup alias.")
            lookup_names.add(alias_key)
        nonnegative_numbers = (
            "element_id", "blue_points", "mp_cost", "cast_time",
            "recast_seconds", "duration_seconds", "target_mask",
        )
        for key in nonnegative_numbers:
            if key not in row:
                continue
            value = row[key]
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
                fail(f"Action {action_id} has an invalid {key} value.")
    return len(rows), sum(row["verification"] == "Verified" for row in rows)


def validate_mechanics(
    mechanics: dict,
    source_ids: set[str],
    action_ids: set[int],
) -> int:
    if mechanics.get("schema_version") != 1:
        fail("Action mechanics schema version is unsupported.")
    if not isinstance(mechanics.get("data_version"), int) or mechanics["data_version"] < 1:
        fail("Action mechanics data_version is invalid.")
    if mechanics.get("server_scope") != "HorizonXI":
        fail("Action mechanics must declare HorizonXI server scope.")
    outcome_types = mechanics.get("outcome_types")
    if not isinstance(outcome_types, list) or set(outcome_types) != MECHANIC_OUTCOMES:
        fail("Action mechanics must declare the complete outcome contract.")
    if len(outcome_types) != len(set(outcome_types)):
        fail("Action mechanics repeats an outcome type.")
    rows = mechanics.get("mechanics")
    if not isinstance(rows, list):
        fail("Action mechanics rows must be a list.")

    seen: set[int] = set()
    for row in rows:
        if not isinstance(row, dict):
            fail("Action mechanics row is not an object.")
        action_id = row.get("action_id")
        if isinstance(action_id, bool) or not isinstance(action_id, int):
            fail("Action mechanics IDs must be integers.")
        if action_id not in action_ids:
            fail(f"Action mechanics references an unknown action: {action_id}")
        if action_id in seen:
            fail(f"Duplicate action mechanics row: {action_id}")
        seen.add(action_id)
        validate_confidence(row, f"Action mechanics {action_id}")
        if row["verification"] not in {"Verified", "Partial"}:
            fail(f"Action mechanics {action_id} has an invalid runtime state.")
        evidence = row.get("source_ids")
        if not isinstance(evidence, list) or not evidence:
            fail(f"Action mechanics {action_id} lacks its evidence chain.")
        if len(evidence) != len(set(evidence)):
            fail(f"Action mechanics {action_id} repeats a source ID.")
        if any(source_id not in source_ids for source_id in evidence):
            fail(f"Action mechanics {action_id} contains an unknown source ID.")
        if not isinstance(row.get("notes"), str) or not row["notes"].strip():
            fail(f"Action mechanics {action_id} lacks scope notes.")
        if not isinstance(row.get("last_verified"), str) or not row["last_verified"].strip():
            fail(f"Action mechanics {action_id} lacks a verification date.")

        outcomes = row.get("outcomes")
        if not isinstance(outcomes, list):
            fail(f"Action mechanics {action_id} outcomes must be a list.")
        found_types: set[str] = set()
        for outcome in outcomes:
            if not isinstance(outcome, dict):
                fail(f"Action mechanics {action_id} has an invalid outcome.")
            kind = outcome.get("type")
            if kind not in MECHANIC_OUTCOMES:
                fail(f"Action mechanics {action_id} has an invalid outcome type.")
            if kind in found_types:
                fail(f"Action mechanics {action_id} repeats outcome {kind}.")
            found_types.add(kind)
            status = outcome.get("status")
            if status not in MECHANIC_STATUSES:
                fail(f"Action mechanics {action_id}/{kind} has an invalid status.")
            drivers = outcome.get("drivers")
            if not isinstance(drivers, list):
                fail(f"Action mechanics {action_id}/{kind} drivers must be a list.")
            if status in {"unknown", "not_applicable"} and drivers:
                fail(f"Unknown mechanics cannot assert drivers: {action_id}/{kind}")
            if status == "verified_numeric":
                if row["verification"] != "Verified" or not isinstance(outcome.get("formula"), dict):
                    fail(f"Numeric mechanics require verified formula evidence: {action_id}/{kind}")
            elif "formula" in outcome:
                fail(f"Nonnumeric mechanics cannot contain a formula: {action_id}/{kind}")
            for driver in drivers:
                if not isinstance(driver, dict):
                    fail(f"Action mechanics {action_id}/{kind} has an invalid driver.")
                if driver.get("kind") not in MECHANIC_DRIVER_KINDS:
                    fail(f"Action mechanics {action_id}/{kind} has an invalid driver kind.")
                for key in ("key", "role"):
                    if not isinstance(driver.get(key), str) or not driver[key].strip():
                        fail(f"Action mechanics {action_id}/{kind} driver lacks {key}.")
                if any(key in driver for key in ("coefficient", "multiplier", "value", "weight")):
                    fail(f"Qualitative driver encodes an unverified number: {action_id}/{kind}")
            if not isinstance(outcome.get("notes"), str) or not outcome["notes"].strip():
                fail(f"Action mechanics {action_id}/{kind} lacks notes.")
        if found_types != MECHANIC_OUTCOMES:
            fail(f"Action mechanics {action_id} lacks an explicit outcome.")
    return len(rows)


def validate_data() -> tuple[int, int, int, int, int, int]:
    catalog = load("catalog_source.json")
    effects = load("effects_source.json")
    actions = load("actions_source.json")
    mechanics = load("mechanics_source.json")
    sources = load("sources.json")
    policies = load("policies_source.json")

    if catalog.get("schema_version") != 2:
        fail("Catalog schema version is unsupported.")
    if not isinstance(catalog.get("data_version"), int) or catalog["data_version"] < 2:
        fail("Catalog data_version is invalid.")
    items = catalog["items"]
    item_ids = [item["id"] for item in items]
    if len(item_ids) != len(set(item_ids)):
        fail("Catalog contains duplicate item IDs.")

    source_ids = {source["id"] for source in sources["sources"]}
    verified = [item for item in items if item["verification"] == "Verified"]
    for item in items:
        for key in ("id", "name", "slots", "required_level", "jobs", "stats", "source_id", "last_verified", "confidence", "verification"):
            if key not in item:
                fail(f"Catalog row is missing {key}: {item.get('name', item.get('id', '?'))}")
        if "slot" in item:
            fail(f"Catalog row uses legacy slot field: {item['name']}")
        if isinstance(item["id"], bool) or not isinstance(item["id"], int) or item["id"] < 1:
            fail(f"Catalog row has an invalid ID: {item.get('name', '?')}")
        if not isinstance(item["name"], str) or not item["name"].strip():
            fail(f"Catalog row has an invalid name: {item['id']}")
        slots = item["slots"]
        if not isinstance(slots, list) or not slots:
            fail(f"Catalog row lacks slot compatibility: {item['name']}")
        if not all(isinstance(slot, str) for slot in slots):
            fail(f"Catalog row has an invalid slot: {item['name']}")
        if len(slots) != len(set(slots)):
            fail(f"Catalog row repeats a slot: {item['name']}")
        if any(slot not in CATALOG_SLOTS for slot in slots):
            fail(f"Catalog row has an unsupported slot: {item['name']}")
        level = item["required_level"]
        if level is not None and (
            isinstance(level, bool) or not isinstance(level, int) or level < 0
        ):
            fail(f"Catalog row has an invalid required level: {item['name']}")
        jobs = item["jobs"]
        if not isinstance(jobs, list) or not all(isinstance(job, str) for job in jobs):
            fail(f"Catalog row has invalid jobs: {item['name']}")
        if len(jobs) != len(set(jobs)):
            fail(f"Catalog row repeats a job: {item['name']}")
        if any(job not in CATALOG_JOBS for job in jobs):
            fail(f"Catalog row has an unsupported job: {item['name']}")
        stats = item["stats"]
        if not isinstance(stats, dict):
            fail(f"Catalog row stats must be an object: {item['name']}")
        for stat, value in stats.items():
            if not isinstance(stat, str) or not stat:
                fail(f"Catalog row has an invalid stat name: {item['name']}")
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                fail(f"Catalog row has a nonnumeric stat: {item['name']}/{stat}")
        validate_confidence(item, f"Catalog item {item['id']}")
    for item in verified:
        if item.get("source_id") not in source_ids:
            fail(f"Verified item lacks a valid source: {item['name']}")
        if not isinstance(item.get("required_level"), int) or item["required_level"] < 1 or not item.get("jobs"):
            fail(f"Verified item lacks eligibility data: {item['name']}")

    effects_seen: set[str] = set()
    for effect in effects["effects"]:
        if effect["id"] in effects_seen:
            fail(f"Duplicate effect ID: {effect['id']}")
        effects_seen.add(effect["id"])
        if effect["item_id"] not in item_ids:
            fail(f"Orphan effect: {effect['id']}")
        for key in ("category", "source_id", "confidence", "verification"):
            if key not in effect:
                fail(f"Effect is missing {key}: {effect['id']}")
        validate_confidence(effect, f"Effect {effect['id']}")
        if effect.get("source_id") not in source_ids:
            fail(f"Effect lacks a valid source: {effect['id']}")
        if effect["verification"] != "Verified" and effect.get("value") == 0:
            fail(f"Unknown effect magnitude encoded as zero: {effect['id']}")

    for job, job_data in policies["jobs"].items():
        contexts = job_data["contexts"]
        if job_data["default_context"] not in contexts:
            fail(f"{job} default context is missing.")
        for key, policy in contexts.items():
            stats = [objective["stat"] for objective in policy["objectives"]]
            if len(stats) != len(set(stats)):
                fail(f"{job}/{key} repeats an objective.")
            if not stats:
                fail(f"{job}/{key} has no objectives.")

    action_count, verified_action_count = validate_actions(actions, source_ids, policies)
    mechanic_count = validate_mechanics(
        mechanics,
        source_ids,
        {row["id"] for row in actions["actions"]},
    )
    return (
        len(items), len(verified), len(effects["effects"]),
        action_count, verified_action_count, mechanic_count,
    )


def validate_runtime() -> int:
    for relative in REQUIRED:
        if not (ROOT / relative).is_file():
            fail(f"Missing required file: {relative}")

    lua_files = [
        path
        for path in ROOT.rglob("*.lua")
        if "data" not in path.relative_to(ROOT).parts
    ]
    combined = "\n".join(path.read_text(encoding="utf-8") for path in lua_files)
    for token in FORBIDDEN_RUNTIME_TOKENS:
        if token in combined:
            fail(f"Read-only runtime contains forbidden token: {token}")

    entrypoint = (ROOT / "gearbuddy.lua").read_text(encoding="utf-8")
    for event in ("load", "unload", "packet_in", "command", "d3d_present"):
        if f"'{event}'" not in entrypoint and f'"{event}"' not in entrypoint:
            fail(f"Entrypoint does not register {event}.")

    ui_text = "\n".join(
        path.read_text(encoding="utf-8") for path in (ROOT / "ui").glob("*.lua")
    )
    if "GetContainerItem" in ui_text:
        fail("UI code must not scan inventory.")

    self_test_text = (ROOT / "core" / "self_test.lua").read_text(encoding="utf-8")
    for token in ("GetContainerCountMax", "GetContainerItem"):
        if token in self_test_text:
            fail(f"Self-test must observe the cache instead of scanning: {token}")

    defaults = (ROOT / "config" / "defaults.lua").read_text(encoding="utf-8")
    for slot in ("Main", "Sub", "Range"):
        if slot not in defaults:
            fail(f"Default weapon lock is missing {slot}.")

    workflow = (ROOT / ".github" / "workflows" / "validate.yml").read_text(
        encoding="utf-8"
    )
    for marker in (
        "permissions:",
        "contents: read",
        "lua5.1 tests/runtime_smoke.lua",
        "tools/build_release.py",
        "tools/verify_release.py",
    ):
        if marker not in workflow:
            fail(f"GitHub validation workflow is missing: {marker}")

    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    version_markers = {
        "gearbuddy.lua": f'addon.version = "{version}";',
        "config/defaults.lua": f'version = "{version}"',
        "core/app.lua": f'v{version} loaded in READ-ONLY mode',
        "ui/console.lua": f'GearBuddy v{version}',
        "README.md": f'`{version}` build',
    }
    for relative, marker in version_markers.items():
        text = (ROOT / relative).read_text(encoding="utf-8")
        if marker not in text:
            fail(f"Version marker is stale: {relative}")
    return len(lua_files)


def main() -> int:
    try:
        subprocess.run(
            [sys.executable, str(ROOT / "tools" / "generate_data.py"), "--check"],
            cwd=ROOT,
            check=True,
        )
        (
            item_count, verified_count, effect_count,
            action_count, verified_action_count, mechanic_count,
        ) = validate_data()
        lua_count = validate_runtime()
        texlua = shutil.which("texlua")
        if texlua:
            lua_files = sorted(str(path) for path in ROOT.rglob("*.lua"))
            subprocess.run(
                [texlua, str(ROOT / "tools" / "check_lua_syntax.lua"), *lua_files],
                cwd=ROOT,
                check=True,
            )
    except (AssertionError, KeyError, OSError, subprocess.CalledProcessError) as exc:
        print(f"Validation failed: {exc}", file=sys.stderr)
        return 1

    print(
        "Validation passed: "
        f"{item_count} catalog rows, {verified_count} fully verified rows, "
        f"{effect_count} effects, {action_count} action rows, "
        f"{verified_action_count} verified runtime actions, "
        f"{mechanic_count} qualitative mechanics rows, "
        f"{lua_count} runtime Lua files."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
