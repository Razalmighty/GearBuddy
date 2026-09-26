#!/usr/bin/env python3
"""Report catalog and action-mechanics coverage without promoting any data."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"


def load(name: str) -> dict[str, Any]:
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def sorted_counts(values: list[str]) -> dict[str, int]:
    return dict(sorted(Counter(values).items()))


def find_candidate_conflicts(
    rows: list[dict[str, Any]], subject_key: str
) -> list[dict[str, Any]]:
    """Return fields with two or more distinct source assertions."""
    assertions: dict[tuple[str, str], dict[str, list[str]]] = {}
    for row in rows:
        subject = str(row[subject_key]).strip().lower()
        for field, value in row.get("values", {}).items():
            key = (subject, field)
            rendered = json.dumps(value, sort_keys=True, separators=(",", ":"))
            assertions.setdefault(key, {}).setdefault(rendered, []).append(
                row["evidence_id"]
            )
    return [
        {
            "subject": subject,
            "field": field,
            "assertions": values,
        }
        for (subject, field), values in sorted(assertions.items())
        if len(values) > 1
    ]


def build_report() -> dict[str, Any]:
    catalog = load("catalog_source.json")
    effects = load("effects_source.json")
    actions = load("actions_source.json")
    mechanics = load("mechanics_source.json")
    contributors = load("contributors_source.json")
    equipment_candidates = load("equipment_candidates_source.json")
    mechanics_candidates = load("mechanics_candidates_source.json")

    items = catalog["items"]
    action_rows = actions["actions"]
    mechanic_rows = mechanics["mechanics"]
    mechanics_by_action = {row["action_id"]: row for row in mechanic_rows}

    catalog_verification = sorted_counts([row["verification"] for row in items])
    effect_verification = sorted_counts([row["verification"] for row in effects["effects"]])
    action_verification = sorted_counts([row["verification"] for row in action_rows])
    slot_counts = Counter()
    job_counts = Counter()
    stat_counts = Counter()
    for row in items:
        slot_counts.update(row["slots"])
        job_counts.update(row["jobs"])
        stat_counts.update(row["stats"].keys())

    outcome_status = {
        outcome: Counter()
        for outcome in mechanics["outcome_types"]
    }
    numeric_outcomes = 0
    for row in mechanic_rows:
        for outcome in row["outcomes"]:
            outcome_status[outcome["type"]][outcome["status"]] += 1
            numeric_outcomes += outcome["status"] == "verified_numeric"

    verified_actions = [row for row in action_rows if row["verification"] == "Verified"]
    missing_mechanics = [
        {"id": row["id"], "name": row["name"], "context": row["context"]}
        for row in verified_actions
        if row["id"] not in mechanics_by_action
    ]
    unverified_items = [
        {"id": row["id"], "name": row["name"], "verification": row["verification"]}
        for row in items
        if row["verification"] != "Verified"
    ]

    gear_conflicts = find_candidate_conflicts(
        equipment_candidates["candidates"], "name"
    )
    mechanics_conflicts = find_candidate_conflicts(
        mechanics_candidates["evidence_sets"], "action_name"
    )

    return {
        "report_schema_version": 1,
        "server_scope": "HorizonXI",
        "catalog": {
            "schema_version": catalog["schema_version"],
            "data_version": catalog["data_version"],
            "total_items": len(items),
            "verification": catalog_verification,
            "optimizer_eligible_items": catalog_verification.get("Verified", 0),
            "items_with_numeric_stats": sum(bool(row["stats"]) for row in items),
            "items_with_effect_records": len({row["item_id"] for row in effects["effects"]}),
            "slot_rows": dict(sorted(slot_counts.items())),
            "job_rows": dict(sorted(job_counts.items())),
            "stat_rows": dict(sorted(stat_counts.items())),
            "review_queue": unverified_items,
        },
        "effects": {
            "schema_version": effects["schema_version"],
            "data_version": effects["data_version"],
            "total_effects": len(effects["effects"]),
            "verification": effect_verification,
            "numeric_effects": sum(
                isinstance(row.get("value"), (int, float))
                and not isinstance(row.get("value"), bool)
                for row in effects["effects"]
            ),
        },
        "actions": {
            "schema_version": actions["schema_version"],
            "data_version": actions["data_version"],
            "total_actions": len(action_rows),
            "verification": action_verification,
            "categories": sorted_counts([row["category"] for row in action_rows]),
            "contexts": sorted_counts([row["context"] for row in action_rows]),
        },
        "mechanics": {
            "schema_version": mechanics["schema_version"],
            "data_version": mechanics["data_version"],
            "registered_actions": len(mechanic_rows),
            "verified_action_coverage": {
                "covered": sum(row["id"] in mechanics_by_action for row in verified_actions),
                "total": len(verified_actions),
            },
            "outcome_status": {
                key: dict(sorted(counts.items()))
                for key, counts in outcome_status.items()
            },
            "verified_numeric_outcomes": numeric_outcomes,
            "review_queue": missing_mechanics,
        },
        "evidence": {
            "contributors": len(contributors["contributors"]),
            "public_contributors": sum(
                row["public_credit"] for row in contributors["contributors"]
            ),
            "equipment_candidate_sets": len(equipment_candidates["candidates"]),
            "equipment_candidate_fields": sum(
                len(row["values"]) for row in equipment_candidates["candidates"]
            ),
            "mechanics_candidate_sets": len(mechanics_candidates["evidence_sets"]),
            "mechanics_candidate_fields": sum(
                len(row["values"]) for row in mechanics_candidates["evidence_sets"]
            ),
            "global_mechanics_claims": len(mechanics_candidates["global_claims"]),
            "matched_action_sets": sum(
                row["registry_status"] != "unmatched"
                for row in mechanics_candidates["evidence_sets"]
            ),
            "unmatched_action_sets": [
                {"evidence_id": row["evidence_id"], "name": row["action_name"]}
                for row in mechanics_candidates["evidence_sets"]
                if row["registry_status"] == "unmatched"
            ],
            "conflicts": {
                "equipment": gear_conflicts,
                "mechanics": mechanics_conflicts,
            },
            "runtime_eligible_candidate_sets": 0,
        },
    }


def summary(report: dict[str, Any]) -> str:
    catalog = report["catalog"]
    actions = report["actions"]
    mechanics = report["mechanics"]
    evidence = report["evidence"]
    coverage = mechanics["verified_action_coverage"]
    return "\n".join((
        f"Catalog: {catalog['optimizer_eligible_items']}/{catalog['total_items']} optimizer-eligible items",
        f"Effects: {report['effects']['total_effects']} records",
        f"Actions: {actions['verification'].get('Verified', 0)}/{actions['total_actions']} verified",
        f"Mechanics: {coverage['covered']}/{coverage['total']} verified actions registered",
        f"Numeric mechanics outcomes: {mechanics['verified_numeric_outcomes']}",
        f"Evidence: {evidence['equipment_candidate_sets']} gear / "
        f"{evidence['mechanics_candidate_sets']} action candidate sets",
        f"Contributors: {evidence['contributors']} records; candidate runtime eligibility: 0",
    ))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--json", action="store_true", help="Print the full JSON report.")
    args = parser.parse_args()
    report = build_report()
    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(rendered, encoding="utf-8")
    print(rendered if args.json else summary(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
