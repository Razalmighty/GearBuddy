from __future__ import annotations

import unittest

from reference_model import ACTIONS, CATALOG, EFFECTS, MECHANICS, resolve


class GearBuddyDataTests(unittest.TestCase):
    def test_seed_counts_match_reviewed_workbook(self) -> None:
        self.assertEqual(CATALOG["schema_version"], 2)
        self.assertEqual(CATALOG["data_version"], 2)
        self.assertEqual(len(CATALOG["items"]), 13)
        self.assertEqual(
            sum(item["verification"] == "Verified" for item in CATALOG["items"]),
            7,
        )
        self.assertEqual(len(EFFECTS["effects"]), 3)
        self.assertTrue(all(item.get("slots") for item in CATALOG["items"]))
        self.assertTrue(all("slot" not in item for item in CATALOG["items"]))

    def test_engaged_prefers_accuracy_hands(self) -> None:
        result = resolve(
            [14939, 14928, 15684, 15600, 14521, 15265],
            "BLU",
            60,
            "engaged",
        )
        self.assertEqual(result["Hands"]["name"], "Akinji Bazubands")

    def test_learning_prefers_text_verified_learning_effect(self) -> None:
        result = resolve(
            [14939, 14928, 15684, 15600, 14521, 15265],
            "BLU",
            60,
            "learning",
        )
        self.assertEqual(result["Hands"]["name"], "Magus Bazubands")

    def test_level_sync_excludes_over_level_items(self) -> None:
        result = resolve(
            [14939, 14928, 15684, 15600, 14521, 15265],
            "BLU",
            55,
            "engaged",
        )
        selected_ids = {item["id"] for item in result.values()}
        self.assertNotIn(14928, selected_ids)
        self.assertNotIn(14521, selected_ids)
        self.assertNotIn(15265, selected_ids)
        self.assertIn(14939, selected_ids)
        self.assertIn(15684, selected_ids)
        self.assertIn(15600, selected_ids)

    def test_partial_item_cannot_win(self) -> None:
        result = resolve([13734, 14521], "BLU", 60, "engaged")
        self.assertEqual(result["Body"]["id"], 14521)

    def test_unknown_effects_are_null_not_zero(self) -> None:
        unknown = [
            effect
            for effect in EFFECTS["effects"]
            if effect["verification"] != "Verified"
        ]
        self.assertTrue(unknown)
        self.assertTrue(all(effect["value"] is None for effect in unknown))

    def test_action_registry_has_versioned_verified_only_boundary(self) -> None:
        self.assertEqual(ACTIONS["schema_version"], 1)
        self.assertGreaterEqual(ACTIONS["data_version"], 4)
        self.assertEqual(ACTIONS["server_scope"], "HorizonXI")
        self.assertIsInstance(ACTIONS["actions"], list)
        self.assertEqual(len(ACTIONS["actions"]), 113)
        self.assertEqual(
            sum(row["verification"] == "Verified" for row in ACTIONS["actions"]),
            106,
        )
        self.assertEqual(max(row["required_level"] for row in ACTIONS["actions"]), 75)
        for action in ACTIONS["actions"]:
            self.assertIn(action["confidence"], {"high", "medium", "low", "unknown"})
            self.assertTrue(action["horizon_spell_page"].startswith("https://horizonffxi.wiki/"))
            self.assertTrue(action["best_use"])
            self.assertTrue(action["era_notes"])
            self.assertTrue(action["tracker_priority"])
            self.assertTrue(action["job_trait"])

    def test_action_mechanics_keep_outcomes_separate_and_fail_closed(self) -> None:
        self.assertEqual(MECHANICS["schema_version"], 1)
        self.assertEqual(MECHANICS["server_scope"], "HorizonXI")
        self.assertEqual(
            set(MECHANICS["outcome_types"]),
            {"landing", "potency", "duration", "utility"},
        )
        self.assertEqual(len(MECHANICS["mechanics"]), 4)
        by_action = {row["action_id"]: row for row in MECHANICS["mechanics"]}
        sandspin = by_action[524]
        outcomes = {row["type"]: row for row in sandspin["outcomes"]}
        self.assertEqual(outcomes["landing"]["status"], "qualitative")
        self.assertEqual(outcomes["duration"]["status"], "unknown")
        self.assertEqual(outcomes["duration"]["drivers"], [])
        for row in MECHANICS["mechanics"]:
            for outcome in row["outcomes"]:
                if outcome["status"] != "verified_numeric":
                    self.assertNotIn("formula", outcome)
                for driver in outcome["drivers"]:
                    self.assertFalse(
                        {"coefficient", "multiplier", "value", "weight"}
                        & set(driver)
                    )

    def test_blu_level_1_to_75_slice_covers_distinct_routing_paths(self) -> None:
        by_name = {action["name"]: action for action in ACTIONS["actions"]}
        self.assertEqual(len(by_name), 113)
        self.assertEqual(by_name["Pollen"]["context"], "healing")
        self.assertEqual(by_name["Metallic Body"]["context"], "buff_skill")
        self.assertEqual(by_name["Bludgeon"]["hit_count"], 3)
        self.assertEqual(by_name["Cursed Sphere"]["context"], "magical")
        self.assertEqual(by_name["Poison Breath"]["context"], "breath")
        self.assertTrue(by_name["Poison Breath"]["flags"]["hp_sensitive"])
        self.assertEqual(by_name["Refueling"]["context"], "buff")
        self.assertEqual(by_name["Filamented Hold"]["context"], "debuff")
        self.assertEqual(by_name["Blood Drain"]["context"], "drain")
        self.assertEqual(by_name["Blank Gaze"]["category"], "dispel")
        self.assertEqual(by_name["Queasyshroom"]["context"], "physical")
        self.assertTrue(by_name["Queasyshroom"]["flags"]["profile_routing_discrepancy"])
        self.assertEqual(by_name["Quad. Continuum"]["hit_count"], 4)
        self.assertEqual(by_name["Magic Hammer"]["context"], "drain")
        self.assertEqual(by_name["Cannonball"]["dominant_stats"], ["str", "defense"])
        self.assertEqual(by_name["Hysteric Barrage"]["hit_count"], 5)
        self.assertEqual(by_name["Disseverment"]["hit_count"], 5)
        self.assertEqual(by_name["1000 Needles"]["context"], "magical")
        self.assertTrue(by_name["1000 Needles"]["flags"]["profile_routing_discrepancy"])

    def test_horizon_level_changes_are_explicit_not_silent(self) -> None:
        by_name = {action["name"]: action for action in ACTIONS["actions"]}
        expected = {
            "Vanity Dive": (28, 82),
            "Empty Thrash": (32, 87),
            "Occultation": (38, 88),
            "Auroral Drape": (42, 84),
            "Quad. Continuum": (54, 85),
            "Winds of Promyvion": (54, 89),
        }
        changed = {
            name
            for name, action in by_name.items()
            if action["horizon_verification"] == "Horizon change"
        }
        self.assertEqual(changed, set(expected))
        for name, (horizon_level, retail_level) in expected.items():
            action = by_name[name]
            self.assertEqual(action["required_level"], horizon_level)
            self.assertEqual(action["horizon_override"]["retail_value"], retail_level)
            self.assertEqual(action["horizon_override"]["horizon_value"], horizon_level)

    def test_era_excluded_horizon_rows_remain_quarantined(self) -> None:
        quarantined = {
            action["name"]: action for action in ACTIONS["actions"]
            if action["verification"] != "Verified"
        }
        self.assertEqual(
            set(quarantined),
            {
                "Spiral Spin", "Seedspray", "Corrosive Ooze",
                "Regurgitation", "Asuran Claws", "Triumphant Roar",
                "Sub-Zero Smash",
            },
        )
        self.assertTrue(all(
            action["horizon_verification"] == "Era excluded"
            for action in quarantined.values()
        ))
        self.assertEqual(
            quarantined["Triumphant Roar"]["source_conflicts"][0]["field"],
            "mp_cost",
        )

    def test_plasma_charge_conflicts_are_explicitly_resolved(self) -> None:
        plasma = next(
            action for action in ACTIONS["actions"]
            if action["name"] == "Plasma Charge"
        )
        self.assertEqual(plasma["verification"], "Verified")
        self.assertEqual(plasma["horizon_verification"], "Documented")
        self.assertEqual(plasma["element"], "Lightning")
        self.assertEqual(plasma["blue_points"], 5)
        self.assertEqual(plasma["duration_seconds"], 60)
        self.assertEqual(
            {conflict["field"] for conflict in plasma["source_conflicts"]},
            {"blue_points", "duration_seconds"},
        )
        self.assertTrue(all(
            conflict["status"] == "resolved"
            for conflict in plasma["source_conflicts"]
        ))


if __name__ == "__main__":
    unittest.main()
