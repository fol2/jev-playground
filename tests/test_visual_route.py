"""New product paths select their real offline proof, never a documentation bypass."""
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from tools import motor_offline, sdlc
from tools.sdlc import FISHING, LEARN, MOTOR, MOTOR_PATHS, SEEK, FIGHT, NAV, RUNTIME, VISUAL, GateError, route


class VisualRouteTests(unittest.TestCase):
    def test_visual_contract_selects_the_native_proof(self):
        for status in ("A", "M", "D"):
            checks = route([(status, VISUAL + "README.md")])["checks"]
            self.assertIn("motor-offline", checks)
            self.assertNotIn("fishing-offline", checks)

    def test_unregistered_visual_executable_fails_closed(self):
        # The retired Python tools may not come back unregistered.
        for path in (VISUAL + "executor.py", VISUAL + "nested/README.md", VISUAL + "capture.swift",
                     VISUAL + "observations.py", NAV + "tabletop.py", LEARN + "video_jev.py"):
            with self.subTest(path=path), self.assertRaises(GateError):
                route([("A", path)])

    def test_fishing_regression_selects_native_proof(self):
        checks = route([("A", FISHING + "tests/MotionChecks.swift")])["checks"]
        self.assertIn("fishing-offline", checks)
        self.assertNotIn("visual-offline", checks)

    def test_runtime_contracts_select_actual_consumer_proof(self):
        for name in ("Runtime.swift", "Input.swift", "RuntimeTests.swift", "IntegrationTests.swift"):
            self.assertIn("motor-offline", route([("M", RUNTIME + name)])["checks"])
        with self.assertRaises(GateError):
            route([("A", RUNTIME + "Unregistered.swift")])
        for name, minimum in (("runtime", 33), ("runtime integration", 41)):
            self.assertEqual(motor_offline.counted(f"{name} checks passed: {minimum}", name, minimum), minimum)
            with self.assertRaises(GateError):
                motor_offline.counted(f"{name} checks passed: {minimum - 1}", name, minimum)

    def test_graph_definition_and_code_select_actual_native_consumer_proof(self):
        for name in ("DecisionGraph.swift", "GraphTests.swift", "Experience.swift", "ExperienceTests.swift",
                     "skyborne-hunt.graph.json", "skyborne-quest.graph.json", "README.md"):
            self.assertIn("motor-offline", route([("M", RUNTIME + name)])["checks"])
        with patch.object(motor_offline.subprocess, "run") as run:
            motor_offline.build("unused", FIGHT + "Fight.swift")
        self.assertIn(RUNTIME + "DecisionGraph.swift", run.call_args.args[0])
        self.assertIn(RUNTIME + "Experience.swift", run.call_args.args[0])
        self.assertEqual(motor_offline.counted("decision graph checks passed: 56", "decision graph", 56), 56)
        self.assertEqual(motor_offline.counted("experience checks passed: 34", "experience", 34), 34)
        # Compilation inputs must not turn the existing single-file checks into nested paths.
        motor_offline.fight_trap()
        motor_offline.nav_trap()

    def test_motor_probe_selects_its_native_proof(self):
        for path in MOTOR_PATHS:
            for status in ("A", "M", "D"):
                with self.subTest(path=path, status=status):
                    checks = route([(status, path)])["checks"]
                    self.assertIn("motor-offline", checks)
                    self.assertNotIn("visual-offline", checks)
                    self.assertNotIn("fishing-offline", checks)

    def test_a_changed_proof_runner_runs_its_own_proof(self):
        self.assertIn("motor-offline", route([("M", "tools/motor_offline.py")])["checks"])
        self.assertIn("fishing-offline", route([("M", "tools/fishing_offline.py")])["checks"])
        self.assertNotIn("motor-offline", route([("M", "tools/merge_pr.py")])["checks"])

    def test_unregistered_motor_paths_fail_closed(self):
        for path in (MOTOR + "Executor.swift", MOTOR + "nested/Probe.swift", MOTOR + "evidence.json", MOTOR + "run.sh",
                     SEEK + "Executor.swift", SEEK + "look.png", SEEK + "run.sh", VISUAL + "m2/Seek.swift",
                     FIGHT + "Executor.swift", FIGHT + "run.sh", FIGHT + "evidence.json",
                     NAV + "Executor.swift", NAV + "run.sh", NAV + "frames.jpg", NAV + "nested/Nav.swift"):
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
                        ("M", VISUAL + "README.md")])["checks"]
        self.assertEqual(checks, ["integrity", "governance", "python-tests", "automation-tests",
                                  "fishing-offline", "motor-offline"])


if __name__ == "__main__":
    unittest.main()
