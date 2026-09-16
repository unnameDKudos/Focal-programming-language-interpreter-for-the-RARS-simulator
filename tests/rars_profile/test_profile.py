"""Structural tests for the independent TZ v1.2 acceptance manifest."""

from copy import deepcopy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from run_rars_profile_tests import ManifestError, load_manifest, validate_manifest


class ProfileManifestTests(unittest.TestCase):
    def test_manifest_meets_frozen_tz_quantitative_contract(self):
        counts = validate_manifest(load_manifest())
        self.assertGreaterEqual(counts["mandatory"], 40)
        self.assertGreaterEqual(counts["negative"], 10)
        self.assertGreaterEqual(counts["integration"], 5)
        self.assertGreaterEqual(counts["historical_programs"], 6)
        self.assertGreaterEqual(counts["historical_executions"],
                                counts["historical_programs"])
        self.assertEqual(counts["fr"], 26)
        self.assertEqual(counts["ar"], 6)
        self.assertEqual(counts["rel"], 5)
        self.assertEqual(counts["k"], 5)

    def test_repeated_historical_fixture_does_not_meet_program_minimum(self):
        manifest = deepcopy(load_manifest())
        historical = [scenario for scenario in manifest["scenarios"]
                      if scenario.get("mandatory", True)
                      and scenario["kind"] == "historical"]
        repeated = historical[0]["program"]["fixture"]
        for scenario in historical:
            scenario["program"] = {"fixture": repeated}
        with self.assertRaisesRegex(ManifestError, "historical_programs=1"):
            validate_manifest(manifest)

    def test_unknown_requirement_id_is_rejected(self):
        manifest = deepcopy(load_manifest())
        manifest["scenarios"][0]["requirements"].append("FR-99")
        with self.assertRaisesRegex(ManifestError, "unknown requirement ID"):
            validate_manifest(manifest)


if __name__ == "__main__":
    unittest.main()
