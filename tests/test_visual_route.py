"""New product paths select their real offline proof, never a documentation bypass."""
import contextlib
import io
import unittest
from unittest.mock import patch
from tools import sdlc
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

    def test_gate_invokes_the_test_file_explicitly_not_empty_discovery(self):
        # Removing the only test file must fail, not turn discovery into zero green tests.
        with patch.object(sdlc, "inspect", return_value={"checks": ["visual-offline"]}), \
             patch.object(sdlc, "contracts"), patch.object(sdlc.subprocess, "run") as run, \
             patch.object(sdlc.sys, "argv", ["sdlc", "check", "--base", "base"]), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(sdlc.main(), 0)
        self.assertEqual(run.call_args.args[0],
                         [sdlc.sys.executable, "-S", VISUAL + "test_observations.py"])

    def test_combined_change_keeps_both_consumers_and_governance(self):
        checks = route([("M", "tools/sdlc.py"), ("M", FISHING + "motion.swift"),
                        ("A", VISUAL + "observations.py")])["checks"]
        self.assertEqual(checks, ["integrity", "governance", "python-tests", "automation-tests",
                                  "fishing-offline", "visual-offline"])


if __name__ == "__main__":
    unittest.main()
