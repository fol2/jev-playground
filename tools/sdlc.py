#!/usr/bin/env python3
"""Dependency-free, source-only evidence routing. Unknown coverage is a failure."""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CODE = {"tools/sdlc.py", "tools/merge_pr.py", "tests/test_sdlc.py",
        "tests/test_merge_pr.py", "tests/test_maintenance.cjs", "tools/fishing_offline.py",
        "tests/test_visual_route.py", "tools/motor_offline.py"}
POLICY = {"AGENTS.md", "CLAUDE.md", "REVIEW.md", ".gitignore",
          ".github/pull_request_template.md", "docs/agents/ai-sdlc.md",
          ".github/workflows/ai-sdlc.yml", ".github/workflows/ai-sdlc-maintain.yml"}
FISHING = "experiments/001_wow_fishing/"
FISHING_CODE = {FISHING + name for name in """
analyse.py background.swift build.sh decision.swift jev.swift live.swift loot.swift motion.swift
probes/background-click/Adapter.swift probes/background-click/NativeBackgroundClickTransport.swift
probes/background-click/NativeWindowServerPreparation.swift probes/background-click/Probe.swift
record.py run_test_a.py self_tests.swift setup_camera.sh setup_camera.swift test_analyse.py
test_core.sh test_run_test_a.py tests/CoreTests.swift tests/MotionChecks.swift
""".split()} | {"data/001_wow_fishing/pilot_20260921/recorder.swift"}

VISUAL = "experiments/002_wow_visual/"
VISUAL_CODE = {VISUAL + name for name in ("observations.py", "test_observations.py")}
MOTOR = VISUAL + "m0/"
SEEK = VISUAL + "m1/"
FIGHT = VISUAL + "m3/"
NAV = VISUAL + "m4/"
MOTOR_PATHS = ({MOTOR + name for name in ("Motor.swift", "MotorTests.swift", "Probe.swift", "README.md")} |
               {SEEK + name for name in ("Seek.swift", "Plate.swift", "SeekTests.swift", "SeekProbe.swift", "README.md")} |
               {FIGHT + name for name in ("Fight.swift", "FightTests.swift", "FightProbe.swift", "README.md")} |
               {NAV + name for name in ("Nav.swift", "NavTests.swift", "NavProbe.swift", "README.md")})
# Load and count the suite here. Running the file trusts its own __main__, so deleting
# that one line would exit 0 having run nothing; a missing module raises instead.
VISUAL_SUITE = (f"import sys, unittest; sys.path.insert(0, {VISUAL!r}); import test_observations as m; "
                "suite = unittest.defaultTestLoader.loadTestsFromModule(m); "
                "assert suite.countTestCases() >= 6, 'visual contract suite lost its tests'; "
                "sys.exit(not unittest.TextTestRunner().run(suite).wasSuccessful())")


def fishing_path(path: str) -> bool:
    if path in FISHING_CODE or path == ".github/workflows/fishing-offline.yml":
        return True
    suffix = PurePosixPath(path).suffix
    if path.startswith(FISHING):
        return suffix in {".md", ".png", ".jpg", ".json", ".jsonl", ".log"} or path == FISHING + "probes/background-click/LICENSE"
    return path.startswith("data/001_wow_fishing/") and suffix in {".mp4", ".mov", ".png", ".json", ".md"}


REQUIRED = CODE | POLICY | {"README.md"}


class GateError(ValueError):
    pass


def git(*args: str, cwd: Path = ROOT) -> bytes:
    proc = subprocess.run(["git", *args], cwd=cwd, capture_output=True, timeout=30)
    if proc.returncode:
        raise GateError("git command failed: " + " ".join(args[:2]))
    return proc.stdout


def route(changes: list[tuple[str, str]]) -> dict:
    if not changes:
        raise GateError("empty diff: no acceptance claim to validate")
    full = False
    fishing = False
    visual = False
    motor = False
    for status, path in changes:
        parts = PurePosixPath(path).parts
        if (not path or path.startswith("/") or "\\" in path or
                any(x in {"", ".", ".."} for x in path.split("/")) or
                any(ord(x) < 32 for x in path) or status not in {"A", "M", "D", "T"}):
            raise GateError("malformed diff path/status")
        if path in CODE | POLICY:
            full = True
        elif path in VISUAL_CODE or path == VISUAL + "README.md":
            visual = True
        elif path in MOTOR_PATHS:
            motor = True
        elif fishing_path(path):
            fishing = True
        elif path in {"README.md", "experiments/README.md"} or (
                len(parts) == 3 and parts[:2] == ("docs", "changes") and path.endswith(".md")):
            full |= status != "M"  # added/deleted documentation gets the full contract
        else:
            raise GateError(f"unclassified path: {path}; register actual offline proof before promotion")
    return {"checks": ["integrity", "governance"] +
            (["python-tests", "automation-tests"] if full else []) + (["fishing-offline"] if fishing else []) +
            (["visual-offline"] if visual else []) + (["motor-offline"] if motor else []),
            "reason": "registered M0-M4 motor probes" if motor else "registered visual evidence contract" if visual else ("registered fishing source/evidence" if fishing else ("authority/code/addition/deletion" if full else "allowlisted documentation only")),
            "omitted": {"F3": "no real-runtime claim or live observation authority",
                        "F4": "source delivery grants no live-effect authority",
                        "model_calls": "deterministic proof; no provider or model runtime"}}


def inspect(base: str, head: str, cwd: Path = ROOT) -> dict:
    def resolve(ref: str) -> str:
        return git("rev-parse", "--verify", "--end-of-options", ref + "^{commit}", cwd=cwd).decode().strip()
    base, head = resolve(base), resolve(head)
    if resolve("HEAD") != head:
        raise GateError("checkout does not match requested head")
    if git("status", "--porcelain", "--untracked-files=all", cwd=cwd):
        raise GateError("dirty tree: commit or isolate changes before final evidence")
    git("merge-base", "--is-ancestor", base, head, cwd=cwd)
    fields = git("diff", "--no-ext-diff", "--no-renames", "--name-status", "-z", base, head, cwd=cwd).decode().split("\0")
    if fields[-1] != "" or len(fields[:-1]) % 2:
        raise GateError("malformed git diff")
    changes = list(zip(fields[0:-1:2], fields[1:-1:2]))
    result = route(changes)
    entries = git("ls-tree", "-rz", head, cwd=cwd).split(b"\0")
    for entry in filter(None, entries):
        metadata, name = entry.split(b"\t", 1)
        mode = metadata.split()[0]
        if mode not in {b"100644", b"100755"}:
            raise GateError("symlink/submodule is not a validated source surface")
        if mode == b"100755" and name.decode() not in CODE | FISHING_CODE | VISUAL_CODE:
            raise GateError("unregistered executable mode")
        if name.decode() not in REQUIRED and name.decode() not in {p for _, p in changes}:
            route([("M", name.decode())])  # do not hide pre-existing unknown executable inputs
    git("diff", "--check", base, head, cwd=cwd)
    result.update(base=base, head=head, tree=git("rev-parse", head + "^{tree}", cwd=cwd).decode().strip(),
                  changes=changes)
    return result


def contracts(root: Path = ROOT) -> None:
    missing = [p for p in sorted(REQUIRED) if not (root / p).is_file()]
    if missing:
        raise GateError("missing maintained contracts: " + ", ".join(missing))
    agents = (root / "AGENTS.md").read_text()
    if len(agents.encode()) > 6500:
        raise GateError("AGENTS.md exceeds the bounded always-loaded context")
    for phrase in ("AI-SDLC DNA", "Minimise Wall Time", "Minimise Token Consumption", "No compromise"):
        if phrase not in agents:
            raise GateError("missing governing rule: " + phrase)
    if "@AGENTS.md" not in (root / "CLAUDE.md").read_text():
        raise GateError("Claude entry point drift")
    for p in sorted(CODE):
        if p.endswith(".py"):
            ast.parse((root / p).read_text(), filename=p)
    for p in sorted(REQUIRED | {str(p.relative_to(root)) for p in (root / "docs/changes").glob("*.md")}):
        data = (root / p).read_text()
        if re.search(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36,}", data):
            raise GateError("possible credential in " + p)  # never echo matched data
    for name in ("ai-sdlc", "ai-sdlc-maintain"):
        workflow = json.loads((root / f".github/workflows/{name}.yml").read_text())
        expected = {"contents": "read"} if name == "ai-sdlc" else {"contents": "read", "issues": "write", "actions": "read"}
        if workflow.get("permissions") != expected:
            raise GateError("workflow permission drift")
        events = set(workflow["on"])
        if events != ({"pull_request", "push", "workflow_dispatch"} if name == "ai-sdlc" else {"workflow_run"}):
            raise GateError("workflow trigger drift")
        for job in workflow["jobs"].values():
            expected_runner = "macos-14" if name == "ai-sdlc" else "ubuntu-24.04"
            if job.get("runs-on") != expected_runner or "permissions" in job or "container" in job:
                raise GateError("workflow runner/permission drift")
            for step in job["steps"]:
                uses = step.get("uses", "")
                if uses and not re.fullmatch(r"actions/(checkout|github-script)@[0-9a-f]{40}", uses):
                    raise GateError("unapproved or unpinned action")
                if name.endswith("maintain") and ("run" in step or "checkout@" in uses):
                    raise GateError("privileged maintenance must not execute a checkout")
                if "checkout@" in uses and step.get("with", {}).get("persist-credentials") is not False:
                    raise GateError("checkout must not persist credentials")
    ci = json.loads((root / ".github/workflows/ai-sdlc.yml").read_text())
    if ci["jobs"]["focus"]["name"] != "Focus Gate":
        raise GateError("stable gate name changed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["route", "check"])
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--full", action="store_true", help="run all maintained offline tests")
    args = parser.parse_args()
    started = time.monotonic()
    try:
        report = inspect(args.base, args.head)
        if args.full:
            report["checks"] = list(dict.fromkeys(report["checks"] + ["integrity", "governance", "python-tests", "automation-tests", "fishing-offline", "visual-offline", "motor-offline"]))
            report["reason"] = "explicit full offline verification"
        if args.command == "check":
            contracts()
            commands = {"python-tests": [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
                        "automation-tests": ["node", "--test", "tests/test_maintenance.cjs"],
                        "fishing-offline": [sys.executable, "-m", "tools.fishing_offline"],
                        "visual-offline": [sys.executable, "-S", "-c", VISUAL_SUITE],
                        "motor-offline": [sys.executable, "-m", "tools.motor_offline"]}
            for check in report["checks"]:
                if check in commands:
                    subprocess.run(commands[check], cwd=ROOT, check=True, timeout=300, stdout=sys.stderr)
            report["result"] = "PASS"
        report["model_tokens"] = 0  # this deterministic command only, not the author session
        # Hash before timing: a manifest nobody can reproduce on a second run anchors nothing.
        report["manifest_sha256"] = hashlib.sha256(json.dumps(report, sort_keys=True).encode()).hexdigest()
        report["elapsed_seconds"] = round(time.monotonic() - started, 4)
        print(json.dumps(report, indent=2))
        return 0
    except (GateError, OSError, UnicodeError, json.JSONDecodeError, SyntaxError,
            subprocess.SubprocessError, KeyError, TypeError) as exc:
        print(f"HOLD: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
