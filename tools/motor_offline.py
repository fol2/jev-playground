"""Registered M0 motor proof: counted fake-time checks plus the real binary's no-effect modes.

Never captures, posts OS input, runs --execute/--release or contacts a provider.
"""
import json
from pathlib import Path
import re
import signal
import subprocess
import tempfile
from tools.sdlc import MOTOR, ROOT, GateError

MIN_CHECKS = 100  # the suite must not silently lose its cases
LATE_MS = 100     # dry-run stalls its observer 400 ms per pulse; an observer-bound release fails


def counted(output: str) -> int:
    found = re.findall(r"^motor checks passed: (\d+)$", output, re.M)
    if len(found) != 1 or int(found[0]) < MIN_CHECKS:
        raise GateError(f"motor suite reported {found or 'no'} checks; at least {MIN_CHECKS} required")
    return int(found[0])


def released(rows: list, pulses: int) -> None:
    downs = [r for r in rows if r["event"] == "key_down"]
    ups = [r for r in rows if r["event"] == "key_up"]
    if len(downs) != pulses or len(ups) != pulses or any(r["event"] == "release_unconfirmed" for r in rows):
        raise GateError(f"dry-run dispatched {len(downs)} key-downs and {len(ups)} key-ups for {pulses} pulses")


def main():
    with tempfile.TemporaryDirectory() as tmp:
        tests, probe = str(Path(tmp, "motor-tests")), str(Path(tmp, "m0-probe"))
        subprocess.run(["swiftc", "-parse-as-library", MOTOR + "Motor.swift", MOTOR + "MotorTests.swift", "-o", tests],
                       cwd=ROOT, check=True, timeout=300)
        checks = counted(subprocess.run([tests], cwd=ROOT, check=True, capture_output=True, text=True, timeout=60).stdout)
        subprocess.run(["swiftc", "-parse-as-library", MOTOR + "Motor.swift", MOTOR + "Probe.swift", "-o", probe],
                       cwd=ROOT, check=True, timeout=300)

        for args in (["--bogus"], ["--execute"], ["--execute", "--keys", "arrows"], ["--execute", "turn-left:100"],
                     ["--execute", "--keys", "arrows", "turn-left:300"], ["--release"], ["--preflight", "extra"]):
            outcome = subprocess.run([probe, *args], cwd=ROOT, capture_output=True, text=True, timeout=30)
            if outcome.returncode != 64 or not outcome.stderr.startswith("HOLD:") or outcome.stdout:
                raise GateError(f"invalid arguments {args} were not refused before any effect")

        dry = subprocess.run([probe, "--dry-run"], cwd=ROOT, check=True, capture_output=True, text=True, timeout=90)
        rows = [json.loads(line) for line in dry.stdout.splitlines()]
        released(rows, 6)
        late = max(r["lateness_ms"] for r in rows if r["event"] == "key_up")
        if late >= LATE_MS or any(r["reason"] != "expired" for r in rows if r["event"] == "key_up"):
            raise GateError(f"dry-run key-up waited for the stalled observer ({late} ms late)")

        # Operator Ctrl-C during a held key must still release before exit.
        process = subprocess.Popen([probe, "--dry-run", "forward:200"], cwd=ROOT, stdout=subprocess.PIPE, text=True)
        rows = []
        for line in process.stdout:
            rows.append(json.loads(line))
            if rows[-1]["event"] == "key_down":
                process.send_signal(signal.SIGINT)
                break
        rows += [json.loads(line) for line in process.stdout]
        if process.wait(timeout=10) != 130 or rows[-1] != {**rows[-1], "event": "exit", "reason": "SIGINT", "holding": False}:
            raise GateError("SIGINT did not end the dry-run cleanly")
        released(rows, 1)
    print(f"M0 motor proof passed: {checks} fake-time checks, argument refusal, release under a 400 ms observer "
          f"stall (max {late} ms late) and SIGINT release; zero capture, OS input or model calls.")


if __name__ == "__main__":
    main()
