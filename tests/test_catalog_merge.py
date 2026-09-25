from __future__ import annotations

import copy
import unittest

from tools.merge_catalog_sources import CatalogMergeError, merge_catalog


BASE = {
    "schema_version": 1,
    "source_id": "S011",
    "extracted_on": "2026-09-25",
    "items": [
        {
            "id": 100,
            "name": "Test Hat",
            "slot": "Head",
            "required_level": 10,
            "jobs": ["BLU"],
            "stats": {"defense": 3, "accuracy": 1},
        },
        {
            "id": 101,
            "name": "Unreviewed Hat",
            "slot": "Head",
            "required_level": 12,
            "jobs": ["BLU"],
            "stats": {"defense": 4},
        },
    ],
}

OVERRIDES = {
    "schema_version": 1,
    "data_version": 2,
    "server_scope": "HorizonXI",
    "items": [
        {
            "id": 100,
            "decision": "verify",
            "source_id": "S007",
            "last_verified": "2026-09-25",
            "set": {"stats": {"accuracy": 2}},
            "resolutions": {
                "stats.accuracy": "Current Horizon page documents Accuracy +2."
            },
            "notes": "Reviewed Horizon override.",
            "effects": [
                {
                    "id": "E-TEST-100",
                    "category": "Utility",
                    "tag": "test_effect",
                    "stat": None,
                    "value": None,
                    "unit": "Unknown magnitude",
                    "applies_to": ["idle"],
                    "condition_type": "Equipped",
                    "condition_value": "Head",
                    "verification": "Verified text; magnitude unknown",
                    "confidence": "high",
                    "verified_text": True,
                    "source_id": "S007",
                    "horizon_specific": True,
                    "notes": "Test-only effect.",
                }
            ],
        }
    ],
}


class CatalogMergeTests(unittest.TestCase):
    def test_unreviewed_bulk_rows_cannot_become_runtime_candidates(self) -> None:
        catalog, effects, report = merge_catalog(BASE, OVERRIDES)
        by_id = {row["id"]: row for row in catalog["items"]}
        self.assertEqual(catalog["schema_version"], 2)
        self.assertEqual(by_id[100]["slots"], ["Head"])
        self.assertNotIn("slot", by_id[100])
        self.assertEqual(by_id[100]["verification"], "Verified")
        self.assertEqual(by_id[100]["stats"]["accuracy"], 2)
        self.assertEqual(by_id[101]["verification"], "ID Verified")
        self.assertEqual(report["verified_items"], 1)
        self.assertEqual(report["identity_only_items"], 1)
        self.assertEqual(effects["effects"][0]["item_id"], 100)

    def test_verified_change_requires_resolution(self) -> None:
        overrides = copy.deepcopy(OVERRIDES)
        overrides["items"][0]["resolutions"] = {}
        with self.assertRaisesRegex(CatalogMergeError, "without a resolution"):
            merge_catalog(BASE, overrides)

    def test_unknown_override_item_is_rejected(self) -> None:
        overrides = copy.deepcopy(OVERRIDES)
        overrides["items"][0]["id"] = 999
        with self.assertRaisesRegex(CatalogMergeError, "unknown item"):
            merge_catalog(BASE, overrides)

    def test_schema_v2_preserves_multi_slot_compatibility(self) -> None:
        base = copy.deepcopy(BASE)
        base["schema_version"] = 2
        for row in base["items"]:
            row["slots"] = [row.pop("slot")]
        base["items"][0]["slots"] = ["Main", "Sub"]
        overrides = copy.deepcopy(OVERRIDES)
        overrides["items"][0]["set"] = {"stats": {"accuracy": 2}}
        catalog, _, _ = merge_catalog(base, overrides)
        self.assertEqual(catalog["items"][0]["slots"], ["Main", "Sub"])

    def test_verified_slot_change_requires_resolution(self) -> None:
        overrides = copy.deepcopy(OVERRIDES)
        overrides["items"][0]["set"] = {"slots": ["Head", "Body"]}
        overrides["items"][0]["resolutions"] = {}
        with self.assertRaisesRegex(CatalogMergeError, "without a resolution"):
            merge_catalog(BASE, overrides)


if __name__ == "__main__":
    unittest.main()
