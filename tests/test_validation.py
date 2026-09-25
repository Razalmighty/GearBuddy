from __future__ import annotations

import copy
import unittest

from tools.validate_repo import load, validate_actions, validate_mechanics


class ActionValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.actions = load("actions_source.json")
        self.sources = load("sources.json")
        self.policies = load("policies_source.json")
        self.source_ids = {source["id"] for source in self.sources["sources"]}

    def test_documented_action_cannot_be_downgraded_silently(self) -> None:
        payload = copy.deepcopy(self.actions)
        payload["actions"][0]["verification"] = "Pending"
        with self.assertRaisesRegex(AssertionError, "documented Horizon evidence"):
            validate_actions(payload, self.source_ids, self.policies)

    def test_missing_policy_context_is_rejected(self) -> None:
        payload = copy.deepcopy(self.actions)
        payload["actions"][0]["context"] = "invented_context"
        with self.assertRaisesRegex(AssertionError, "missing policy context"):
            validate_actions(payload, self.source_ids, self.policies)

    def test_incomplete_evidence_chain_is_rejected(self) -> None:
        payload = copy.deepcopy(self.actions)
        payload["actions"][0]["source_ids"] = []
        with self.assertRaisesRegex(AssertionError, "evidence chain"):
            validate_actions(payload, self.source_ids, self.policies)

    def test_horizon_change_requires_explicit_override(self) -> None:
        payload = copy.deepcopy(self.actions)
        changed = next(
            row for row in payload["actions"]
            if row["horizon_verification"] == "Horizon change"
        )
        changed["horizon_override"] = None
        with self.assertRaisesRegex(AssertionError, "lacks its Horizon override"):
            validate_actions(payload, self.source_ids, self.policies)

    def test_horizon_evidence_page_is_required(self) -> None:
        payload = copy.deepcopy(self.actions)
        payload["actions"][0]["horizon_spell_page"] = "https://example.invalid/spell"
        with self.assertRaisesRegex(AssertionError, "Horizon evidence page"):
            validate_actions(payload, self.source_ids, self.policies)

    def test_duplicate_lookup_alias_is_rejected(self) -> None:
        payload = copy.deepcopy(self.actions)
        payload["actions"][1]["aliases"] = [payload["actions"][0]["name"]]
        with self.assertRaisesRegex(AssertionError, "duplicate lookup alias"):
            validate_actions(payload, self.source_ids, self.policies)

    def test_unresolved_horizon_row_cannot_enter_verified_runtime(self) -> None:
        payload = copy.deepcopy(self.actions)
        pending = next(
            row for row in payload["actions"]
            if row["horizon_verification"] == "Era excluded"
        )
        pending["verification"] = "Verified"
        with self.assertRaisesRegex(AssertionError, "cannot be Verified"):
            validate_actions(payload, self.source_ids, self.policies)

    def test_resolved_conflict_requires_selected_value(self) -> None:
        payload = copy.deepcopy(self.actions)
        conflict = next(
            row for row in payload["actions"]
            if any(
                detail.get("status") == "resolved"
                for detail in row.get("source_conflicts", [])
            )
        )
        del conflict["source_conflicts"][0]["selected_value"]
        with self.assertRaisesRegex(AssertionError, "lacks a selected value"):
            validate_actions(payload, self.source_ids, self.policies)


class MechanicsValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mechanics = load("mechanics_source.json")
        self.actions = load("actions_source.json")
        self.sources = load("sources.json")
        self.source_ids = {source["id"] for source in self.sources["sources"]}
        self.action_ids = {row["id"] for row in self.actions["actions"]}

    def validate(self, payload: dict) -> int:
        return validate_mechanics(payload, self.source_ids, self.action_ids)

    def test_reviewed_registry_is_valid(self) -> None:
        self.assertEqual(self.validate(self.mechanics), 4)

    def test_unknown_outcome_cannot_assert_drivers(self) -> None:
        payload = copy.deepcopy(self.mechanics)
        duration = next(
            row for row in payload["mechanics"][0]["outcomes"]
            if row["type"] == "duration"
        )
        duration["drivers"] = [
            {"kind": "stat", "key": "int", "role": "invented"}
        ]
        with self.assertRaisesRegex(AssertionError, "Unknown mechanics"):
            self.validate(payload)

    def test_qualitative_driver_cannot_hide_numeric_weight(self) -> None:
        payload = copy.deepcopy(self.mechanics)
        driver = payload["mechanics"][0]["outcomes"][0]["drivers"][0]
        driver["coefficient"] = 0.5
        with self.assertRaisesRegex(AssertionError, "unverified number"):
            self.validate(payload)

    def test_every_row_requires_all_outcomes(self) -> None:
        payload = copy.deepcopy(self.mechanics)
        payload["mechanics"][0]["outcomes"].pop()
        with self.assertRaisesRegex(AssertionError, "explicit outcome"):
            self.validate(payload)

    def test_unknown_action_reference_is_rejected(self) -> None:
        payload = copy.deepcopy(self.mechanics)
        payload["mechanics"][0]["action_id"] = 999999
        with self.assertRaisesRegex(AssertionError, "unknown action"):
            self.validate(payload)


if __name__ == "__main__":
    unittest.main()
