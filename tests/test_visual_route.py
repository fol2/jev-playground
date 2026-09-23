"""New product paths select their real offline proof, never a documentation bypass."""
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from tools import motor_offline, sdlc
from tools.sdlc import FISHING, MOTOR, MOTOR_PATHS, SEEK, VISUAL, VISUAL_CODE, GateError, route


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

    def test_gate_runs_a_counted_suite_not_the_files_own_main(self):
        # Running the file trusts its __main__; loading and counting the suite does not.
        with patch.object(sdlc, "inspect", return_value={"checks": ["visual-offline"]}), \
             patch.object(sdlc, "contracts"), patch.object(sdlc.subprocess, "run") as run, \
             patch.object(sdlc.sys, "argv", ["sdlc", "check", "--base", "base"]), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(sdlc.main(), 0)
        self.assertEqual(run.call_args.args[0], [sdlc.sys.executable, "-S", "-c", sdlc.VISUAL_SUITE])

    def test_counted_suite_fails_when_the_module_imports_but_carries_no_tests(self):
        for name, body in (("no tests at all", "import unittest\n"),
                           ("an empty case", "import unittest\n\n\nclass T(unittest.TestCase):\n    pass\n"),
                           ("a missing module", None)):
            with self.subTest(case=name), tempfile.TemporaryDirectory() as tmp:
                if body is not None:
                    (Path(tmp) / "test_observations.py").write_text(body)
                outcome = subprocess.run(
                    [sdlc.sys.executable, "-S", "-c",
                     sdlc.VISUAL_SUITE.replace(repr(VISUAL), repr(tmp + "/"))],
                    cwd=sdlc.ROOT, capture_output=True, text=True)
                self.assertNotEqual(outcome.returncode, 0, f"{name} produced a green run")

    def test_counted_suite_passes_on_the_real_registered_tests(self):
        outcome = subprocess.run([sdlc.sys.executable, "-S", "-c", sdlc.VISUAL_SUITE],
                                 cwd=sdlc.ROOT, capture_output=True, text=True)
        self.assertEqual(outcome.returncode, 0, outcome.stderr[-400:])

    def test_motor_probe_selects_its_native_proof(self):
        for path in MOTOR_PATHS:
            for status in ("A", "M", "D"):
                with self.subTest(path=path, status=status):
                    checks = route([(status, path)])["checks"]
                    self.assertIn("motor-offline", checks)
                    self.assertNotIn("visual-offline", checks)
                    self.assertNotIn("fishing-offline", checks)

    def test_unregistered_motor_paths_fail_closed(self):
        for path in (MOTOR + "Executor.swift", MOTOR + "nested/Probe.swift", MOTOR + "evidence.json", MOTOR + "run.sh",
                     SEEK + "Executor.swift", SEEK + "look.png", SEEK + "run.sh", VISUAL + "m2/Seek.swift"):
            with self.subTest(path=path), self.assertRaises(GateError):
                route([("A", path)])

    def test_gate_runs_the_motor_proof_module(self):
        with patch.object(sdlc, "inspect", return_value={"checks": ["motor-offline"]}), \
             patch.object(sdlc, "contracts"), patch.object(sdlc.subprocess, "run") as run, \
             patch.object(sdlc.sys, "argv", ["sdlc", "check", "--base", "base"]), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(sdlc.main(), 0)
        self.assertEqual(run.call_args.args[0], [sdlc.sys.executable, "-m", "tools.motor_offline"])

    def test_motor_suite_must_report_its_counted_checks(self):
        self.assertEqual(motor_offline.counted("header\nmotor checks passed: 114\n"), 114)
        for output in ("", "motor checks passed: 5", "motor checks passed: 114 extra",
                       "motor checks passed: 114\nmotor checks passed: 114"):
            with self.subTest(output=output), self.assertRaises(GateError):
                motor_offline.counted(output)
        self.assertEqual(motor_offline.counted("seek checks passed: 62", "seek", 60), 62)
        for output in ("motor checks passed: 62", "seek checks passed: 59"):
            with self.subTest(output=output), self.assertRaises(GateError):
                motor_offline.counted(output, "seek", 60)

    def test_dry_run_evidence_must_release_every_key(self):
        down, up = {"event": "key_down"}, {"event": "key_up"}
        motor_offline.released([down, up], 1)
        for rows in ([], [down], [down, up, down], [down, up, {"event": "release_unconfirmed"}]):
            with self.subTest(rows=rows), self.assertRaises(GateError):
                motor_offline.released(rows, 1)
        motor_offline.released([down, up, down, up])  # M1: any number, each one released
        for rows in ([], [down], [down, up, down]):
            with self.subTest(rows=rows), self.assertRaises(GateError):
                motor_offline.released(rows)

    def test_combined_change_keeps_both_consumers_and_governance(self):
        checks = route([("M", "tools/sdlc.py"), ("M", FISHING + "motion.swift"),
                        ("A", VISUAL + "observations.py")])["checks"]
        self.assertEqual(checks, ["integrity", "governance", "python-tests", "automation-tests",
                                  "fishing-offline", "visual-offline"])


if __name__ == "__main__":
    unittest.main()
