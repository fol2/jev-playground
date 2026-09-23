"""Registered M0/M1 motor proof: counted fake-time checks plus each real binary's no-effect modes.

Never captures, posts OS input, runs --look/--execute/--release or contacts a provider.
"""
from __future__ import annotations
import json
from pathlib import Path
import re
import signal
import subprocess
import tempfile
from tools.sdlc import MOTOR, SEEK, ROOT, GateError

MIN_CHECKS = 100  # the suite must not silently lose its cases
MIN_SEEK_CHECKS = 96  # the current count: removing a check must lower this on purpose
LATE_MS = 100     # dry-runs stall their observer 400 ms per pulse; an observer-bound release fails


def counted(output: str, name: str = "motor", minimum: int = MIN_CHECKS) -> int:
    found = re.findall(rf"^{name} checks passed: (\d+)$", output, re.M)
    if len(found) != 1 or int(found[0]) < minimum:
        raise GateError(f"{name} suite reported {found or 'no'} checks; at least {minimum} required")
    return int(found[0])


def released(rows: list, pulses: int | None = None) -> None:
    downs = [r for r in rows if r["event"] == "key_down"]
    ups = [r for r in rows if r["event"] == "key_up"]
    if (len(downs) != len(ups) or not downs or (pulses is not None and len(downs) != pulses)
            or any(r["event"] == "release_unconfirmed" for r in rows)):
        raise GateError(f"dry-run dispatched {len(downs)} key-downs and {len(ups)} key-ups for {pulses or 'any'} pulses")


def build(output: str, *sources: str, flags: tuple = ()) -> None:
    subprocess.run(["swiftc", "-parse-as-library", *flags, *sources, "-o", output], cwd=ROOT, check=True, timeout=300)


def suite(binary: str, name: str, minimum: int) -> int:
    return counted(subprocess.run([binary], cwd=ROOT, check=True, capture_output=True, text=True, timeout=60).stdout,
                   name, minimum)


def refuses(binary: str, cases: tuple) -> None:
    for args in cases:
        outcome = subprocess.run([binary, *args], cwd=ROOT, capture_output=True, text=True, timeout=30)
        if outcome.returncode != 64 or not outcome.stderr.startswith("HOLD:") or outcome.stdout:
            raise GateError(f"invalid arguments {args} were not refused before any effect")


def on_time(binary: str, pulses: int | None) -> tuple[list, int]:
    dry = subprocess.run([binary, "--dry-run"], cwd=ROOT, check=True, capture_output=True, text=True, timeout=90)
    rows = [json.loads(line) for line in dry.stdout.splitlines()]
    released(rows, pulses)
    late = max(r["lateness_ms"] for r in rows if r["event"] == "key_up")
    if late >= LATE_MS or any(r["reason"] != "expired" for r in rows if r["event"] == "key_up"):
        raise GateError(f"dry-run key-up waited for the stalled observer ({late} ms late)")
    return rows, late


def interrupted(command: list) -> None:
    """Operator Ctrl-C during a held key must still release before exit."""
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, text=True)
    rows = []
    for line in process.stdout:
        rows.append(json.loads(line))
        if rows[-1]["event"] == "key_down":
            process.send_signal(signal.SIGINT)
            break
    rows += [json.loads(line) for line in process.stdout]
    if process.wait(timeout=10) != 130 or rows[-1] != {**rows[-1], "event": "exit", "reason": "SIGINT", "holding": False}:
        raise GateError(f"SIGINT did not end {command[0]} cleanly")
    released(rows, 1)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        tests, probe = str(Path(tmp, "motor-tests")), str(Path(tmp, "m0-probe"))
        seek_tests, seek = str(Path(tmp, "seek-tests")), str(Path(tmp, "m1-seek"))
        build(tests, MOTOR + "Motor.swift", MOTOR + "MotorTests.swift")
        checks = suite(tests, "motor", MIN_CHECKS)
        build(probe, MOTOR + "Motor.swift", MOTOR + "Probe.swift")
        refuses(probe, (["--bogus"], ["--execute"], ["--execute", "--keys", "arrows"], ["--execute", "turn-left:100"],
                        ["--execute", "--keys", "arrows", "turn-left:300"], ["--release"], ["--preflight", "extra"]))
        _, late = on_time(probe, 6)
        interrupted([probe, "--dry-run", "forward:200"])

        build(seek_tests, MOTOR + "Motor.swift", SEEK + "Seek.swift", SEEK + "Plate.swift", SEEK + "SeekTests.swift")
        seek_checks = suite(seek_tests, "seek", MIN_SEEK_CHECKS)
        build(seek, MOTOR + "Motor.swift", MOTOR + "Probe.swift", SEEK + "Seek.swift", SEEK + "Plate.swift", SEEK + "SeekProbe.swift",
              flags=("-O", "-D", "SEEK"))
        refuses(seek, (["--bogus"], ["--dry-run", "x"], ["--look", "x"], ["--execute"],
                       ["--execute", "--keys", "wqe", "--look", "f.png"], ["--execute", "--keys", "wqe", "--box", "1,1,20,20"],
                       ["--execute", "--keys", "wqe", "--look", "f.png", "--box", "1,1,20,20", "--stop-growth", "9"],
                       ["--target"], ["--target", "--keys", "wqe", "--stop-row", "0.9"], ["--target", "--keys", "wqe", "--look", "f.png"]))
        rows, seek_late = on_time(seek, None)
        summary = rows[-1]
        if summary.get("event") != "summary" or summary.get("outcome") != "VISIBLE_STOP_REACHED_PENDING_LABELS":
            raise GateError("M1 dry-run did not reach the simulated visible stop")
        interrupted([seek, "--dry-run"])
    print(f"M0/M1 motor proof passed: {checks} + {seek_checks} fake-time checks, argument refusal, release under a "
          f"400 ms observer stall (max {max(late, seek_late)} ms late), SIGINT release and the simulated M1 loop "
          f"({summary['pulses_used']} pulses); zero capture, OS input or model calls.")


if __name__ == "__main__":
    main()
