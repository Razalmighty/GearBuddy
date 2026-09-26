from __future__ import annotations

import unittest

from tools.audit_data_coverage import build_report


class CoverageAuditTests(unittest.TestCase):
    def test_current_seed_is_reported_without_promotion(self) -> None:
        report = build_report()
        self.assertEqual(report["catalog"]["total_items"], 13)
        self.assertEqual(report["catalog"]["optimizer_eligible_items"], 7)
        self.assertEqual(len(report["catalog"]["review_queue"]), 6)
        self.assertEqual(report["actions"]["total_actions"], 113)
        self.assertEqual(report["actions"]["verification"]["Verified"], 106)
        self.assertEqual(
            report["mechanics"]["verified_action_coverage"],
            {"covered": 4, "total": 106},
        )
        self.assertEqual(report["mechanics"]["verified_numeric_outcomes"], 0)
        self.assertEqual(len(report["mechanics"]["review_queue"]), 102)
        self.assertEqual(report["evidence"]["equipment_candidate_sets"], 7)
        self.assertEqual(report["evidence"]["mechanics_candidate_sets"], 13)
        self.assertEqual(report["evidence"]["global_mechanics_claims"], 3)
        self.assertEqual(report["evidence"]["runtime_eligible_candidate_sets"], 0)

    def test_coverage_report_preserves_per_outcome_status(self) -> None:
        report = build_report()
        status = report["mechanics"]["outcome_status"]
        self.assertEqual(set(status), {"landing", "potency", "duration", "utility"})
        self.assertEqual(sum(status["landing"].values()), 4)
        self.assertEqual(sum(status["duration"].values()), 4)


if __name__ == "__main__":
    unittest.main()
