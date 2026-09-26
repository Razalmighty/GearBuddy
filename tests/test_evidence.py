from __future__ import annotations

import json
import unittest
from pathlib import Path

from tools.audit_data_coverage import build_report, find_candidate_conflicts


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"


def load(name: str) -> dict:
    return json.loads((DATA / name).read_text(encoding="utf-8"))


class EvidenceLedgerTests(unittest.TestCase):
    def test_recovered_seed_is_quarantined_and_attributed(self) -> None:
        gear = load("equipment_candidates_source.json")
        mechanics = load("mechanics_candidates_source.json")
        contributors = load("contributors_source.json")
        self.assertEqual(gear["runtime_policy"], "quarantined_never_score")
        self.assertEqual(mechanics["runtime_policy"], "quarantined_report_only")
        self.assertEqual(len(gear["candidates"]), 7)
        self.assertEqual(len(mechanics["evidence_sets"]), 13)
        self.assertEqual(len(mechanics["global_claims"]), 3)
        self.assertEqual(len(contributors["contributors"]), 3)
        self.assertTrue(all(
            row["evidence_status"] == "candidate"
            for row in gear["candidates"] + mechanics["evidence_sets"]
            + mechanics["global_claims"]
        ))

    def test_known_action_links_match_the_reviewed_registry(self) -> None:
        actions = {
            row["id"]: row for row in load("actions_source.json")["actions"]
        }
        candidates = load("mechanics_candidates_source.json")["evidence_sets"]
        for row in candidates:
            if row["action_id"] is None:
                self.assertEqual(row["registry_status"], "unmatched")
                continue
            action = actions[row["action_id"]]
            self.assertEqual(row["action_name"], action["name"])
            expected = (
                "matched_verified"
                if action["verification"] == "Verified"
                else "matched_pending"
            )
            self.assertEqual(row["registry_status"], expected)

    def test_candidates_do_not_enter_runtime_registries(self) -> None:
        catalog = load("catalog_source.json")
        mechanics = load("mechanics_source.json")
        report = build_report()
        self.assertEqual(len(catalog["items"]), 13)
        self.assertEqual(len(mechanics["mechanics"]), 4)
        self.assertEqual(report["evidence"]["runtime_eligible_candidate_sets"], 0)

    def test_coverage_audit_exposes_unmatched_rows_and_conflicts(self) -> None:
        report = build_report()["evidence"]
        self.assertEqual(report["matched_action_sets"], 9)
        self.assertEqual(len(report["unmatched_action_sets"]), 4)
        self.assertEqual(report["conflicts"], {"equipment": [], "mechanics": []})

    def test_conflicting_sources_are_preserved_not_silently_selected(self) -> None:
        rows = [
            {"evidence_id": "A", "action_name": "Example", "values": {"ftp": [1, 2, 3]}},
            {"evidence_id": "B", "action_name": "Example", "values": {"ftp": [1, 2, 4]}},
            {"evidence_id": "C", "action_name": "Example", "values": {"wsc": {"str": 0.5}}},
        ]
        conflicts = find_candidate_conflicts(rows, "action_name")
        self.assertEqual(len(conflicts), 1)
        self.assertEqual(conflicts[0]["field"], "ftp")
        self.assertEqual(set(conflicts[0]["assertions"]), {"[1,2,3]", "[1,2,4]"})


if __name__ == "__main__":
    unittest.main()
