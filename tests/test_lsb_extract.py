from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.extract_lsb_blue_candidates import extract


class LandSandBoatCandidateTests(unittest.TestCase):
    def test_static_values_are_quarantined_as_comparison_candidates(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            root = Path(raw_root)
            scripts = root / "scripts" / "actions" / "spells" / "blue"
            scripts.mkdir(parents=True)
            (scripts / "bludgeon.lua").write_text(
                """
                params.numHits = 3
                params.ftp0 = 1.0
                params.attackMult = 1.55
                params.chr_wsc = 0.3
                params.tpModifier = xi.spells.blue.tpMod.ACC
                params.baseDamageCap = calculateAtRuntime()
                """,
                encoding="utf-8",
            )
            actions = root / "actions.json"
            actions.write_text(json.dumps({"actions": [{
                "id": 513, "name": "Bludgeon", "verification": "Verified",
            }]}), encoding="utf-8")
            result = extract(root, actions)

        self.assertEqual(result["server_scope"], "comparison_only_not_HorizonXI")
        self.assertEqual(result["promotion_policy"], "manual_per_outcome_review_required")
        row = result["candidate_actions"][0]
        self.assertEqual(row["verification"], "Comparison only")
        self.assertEqual(row["candidate_values"]["hit_count"], 3)
        self.assertEqual(row["candidate_values"]["ftp_0"], 1)
        self.assertEqual(row["candidate_values"]["attack_multiplier"], 1.55)
        self.assertEqual(row["candidate_values"]["wsc.chr"], 0.3)
        self.assertEqual(row["candidate_values"]["tp_modifier"], "acc")
        self.assertEqual(row["ignored_dynamic_fields"], ["baseDamageCap"])


if __name__ == "__main__":
    unittest.main()
