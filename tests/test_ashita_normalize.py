from __future__ import annotations

import copy
import hashlib
import json
import unittest
from pathlib import Path

from tools.merge_catalog_sources import merge_catalog
from tools.normalize_ashita_items import AshitaNormalizeError, normalize_export


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "ashita_items_export.json"
RAW = FIXTURE.read_bytes()
PAYLOAD = json.loads(RAW.decode("utf-8"))
INPUT_SHA256 = hashlib.sha256(RAW).hexdigest()


class AshitaNormalizeTests(unittest.TestCase):
    def test_resource_fields_become_quarantined_schema_v2_rows(self) -> None:
        base, report = normalize_export(PAYLOAD, input_sha256=INPUT_SHA256)
        self.assertEqual(base["schema_version"], 2)
        self.assertEqual(base["input_sha256"], INPUT_SHA256)
        self.assertEqual([row["id"] for row in base["items"]], [9001, 9002])

        blade, ring = base["items"]
        self.assertEqual(blade["slots"], ["Main", "Sub"])
        self.assertEqual(blade["jobs"], ["WAR", "BLU"])
        self.assertEqual(blade["stats"], {"damage": 32, "delay": 229})
        self.assertEqual(
            blade["resource_evidence"]["raw_description"],
            "DMG:32 Delay:229",
        )
        self.assertEqual(ring["slots"], ["Ring"])
        self.assertEqual(ring["stats"], {})

        self.assertEqual(report["input_rows"], 4)
        self.assertEqual(report["normalized_equipment_rows"], 2)
        self.assertEqual(report["skipped_not_equippable"], 1)
        self.assertEqual(report["skipped_no_slot"], 1)
        self.assertEqual(report["multi_catalog_slot_items"], 1)

        overrides = {
            "schema_version": 1,
            "data_version": 1,
            "server_scope": "HorizonXI",
            "items": [],
        }
        catalog, _, merge_report = merge_catalog(base, overrides)
        self.assertEqual(catalog["schema_version"], 2)
        self.assertTrue(all(
            row["verification"] == "ID Verified"
            for row in catalog["items"]
        ))
        self.assertNotIn("resource_evidence", catalog["items"][0])
        self.assertEqual(merge_report["identity_only_items"], 2)

    def test_unknown_slot_bits_are_rejected(self) -> None:
        payload = copy.deepcopy(PAYLOAD)
        payload["items"][0]["Slots"] = 1 << 16
        with self.assertRaisesRegex(AshitaNormalizeError, "Unsupported Ashita slot bits"):
            normalize_export(payload, input_sha256=INPUT_SHA256)

    def test_duplicate_item_ids_are_rejected_even_if_filtered(self) -> None:
        payload = copy.deepcopy(PAYLOAD)
        payload["items"][3]["Id"] = payload["items"][2]["Id"]
        with self.assertRaisesRegex(AshitaNormalizeError, "Duplicate Ashita item ID"):
            normalize_export(payload, input_sha256=INPUT_SHA256)

    def test_non_english_export_is_rejected(self) -> None:
        payload = copy.deepcopy(PAYLOAD)
        payload["language"] = "Japanese"
        with self.assertRaisesRegex(AshitaNormalizeError, "language must be English"):
            normalize_export(payload, input_sha256=INPUT_SHA256)

    def test_description_is_evidence_not_parsed_stats(self) -> None:
        payload = copy.deepcopy(PAYLOAD)
        payload["items"][1]["Description"] = "STR+99 Accuracy+99 Hidden: unknown"
        base, _ = normalize_export(payload, input_sha256=INPUT_SHA256)
        blade = next(row for row in base["items"] if row["id"] == 9001)
        self.assertEqual(blade["stats"], {"damage": 32, "delay": 229})
        self.assertEqual(
            blade["resource_evidence"]["raw_description"],
            "STR+99 Accuracy+99 Hidden: unknown",
        )


if __name__ == "__main__":
    unittest.main()
