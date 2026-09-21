"""New product paths select their real offline proof, never a documentation bypass."""
import unittest
from tools.sdlc import FISHING, VISUAL, VISUAL_CODE, GateError, route


class VisualRouteTests(unittest.TestCase):
    def test_visual_source_tests_and_contract_select_visual_proof(self):
        for path in VISUAL_CODE | {VISUAL + "README.md"}:
            for status in ("A", "M", "D"):
                with self.subTest(path=path, status=status):
                    checks = route([(status, path)])["checks"]
                    self.assertIn("visual-offline", checks)
                    self.assertNotIn("fishing-offline", checks)

    def test_unregistered_visual_executable_fails_closed(self):
        for path in (VISUAL + "executor.py", VISUAL + "nested/README.md", VISUAL + "capture.swift"):
            with self.subTest(path=path), self.assertRaises(GateError):
                route([("A", path)])

    def test_fishing_regression_selects_native_proof(self):
        checks = route([("A", FISHING + "tests/MotionChecks.swift")])["checks"]
        self.assertIn("fishing-offline", checks)
        self.assertNotIn("visual-offline", checks)

    def test_combined_change_keeps_both_consumers_and_governance(self):
        checks = route([("M", "tools/sdlc.py"), ("M", FISHING + "motion.swift"),
                        ("A", VISUAL + "observations.py")])["checks"]
        self.assertEqual(checks, ["integrity", "governance", "python-tests", "automation-tests",
                                  "fishing-offline", "visual-offline"])


if __name__ == "__main__":
    unittest.main()
