"""Registered M0/M1/M3/M4 motor proof: counted fake-time checks plus each real binary's no-effect modes.

Never captures, posts OS input, runs --look/--execute/--release/--sim-jev or contacts a provider.
"""
from __future__ import annotations
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
from tools.sdlc import MOTOR, SEEK, FIGHT, NAV, LEARN, ROOT, GateError

MIN_CHECKS = 100  # the suite must not silently lose its cases
MIN_SEEK_CHECKS = 103  # the current count: removing a check must lower this on purpose
MIN_FIGHT_CHECKS = 120  # the current count: removing a check must lower this on purpose
MIN_NAV_CHECKS = 167  # the current count: removing a check must lower this on purpose
LATE_MS = 100     # dry-runs stall their observer 400 ms per pulse; an observer-bound release fails
CLICK = "experiments/001_wow_fishing/probes/background-click/"


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


def nav_trap() -> None:
    """M4 execute must trap SIGINT onto the body's LiveKeys sweep; this is not OS-key proof."""
    probe = Path(ROOT, NAV + "NavProbe.swift").read_text()
    execute = probe.split("func navExecute", 1)[-1]
    if "also: { body.releaseAll() }, holding: { body.holding }" not in execute:
        raise GateError("navExecute does not trap signals onto body.releaseAll and body.holding")
    if "defer { body.releaseAll() }" not in execute:
        raise GateError("navExecute does not defer body.releaseAll")
    if "LiveKeys(sink: sink, releaseCodes: NavLimits.releaseCodes" not in probe:
        raise GateError("M4 keys do not go through LiveKeys with NavLimits.releaseCodes")
    hunt = Path(ROOT, NAV + "HuntProbe.swift").read_text()
    execute = hunt.split("func huntExecute", 1)[-1]
    if "also: { host.releaseAll() }, holding: { host.holding }" not in execute or "defer { host.releaseAll() }" not in execute:
        raise GateError("huntExecute does not trap signals and defer onto host.releaseAll and host.holding")
    if "keys.releaseAll()\n        lock.withLock { fighting }?.releaseAll()" not in hunt:
        raise GateError("the hunt's release does not sweep both its own keys and the current fight's")


def fight_trap() -> None:
    """Execute must trap SIGINT onto a retrying host.releaseAll; this is not OS-key proof."""
    probe = Path(ROOT, FIGHT + "FightProbe.swift").read_text()
    core = Path(ROOT, FIGHT + "Fight.swift").read_text()
    if "struct HeldKey" not in core or "func expired(now:" not in core:
        raise GateError("watchdog decision is not HeldKey")
    execute = probe.split("func fightExecute", 1)[-1]
    if "also: { host.releaseAll() }, holding: { host.holdingKeys }" not in execute:
        raise GateError("fightExecute does not trap signals onto host.releaseAll and host.holdingKeys")
    if "defer { host.releaseAll() }" not in execute:
        raise GateError("fightExecute does not defer host.releaseAll")
    if "FightLimits.releaseCodes" not in probe:
        raise GateError("M3 release does not sweep FightLimits.releaseCodes")


def interrupted_dry(command: list) -> None:
    """SIGINT of the M3/M4 --dry-run, sent on "start" (emitted after the trap), must stop the paced loop
    with exit 130 and holding false. No OS keys are posted."""
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, text=True)
    rows = []
    for line in process.stdout:
        if line.strip():
            rows.append(json.loads(line))
        if rows and rows[-1].get("event") == "start":
            process.send_signal(signal.SIGINT)
            break
    rows += [json.loads(line) for line in process.stdout if line.strip()]
    code = process.wait(timeout=10)
    if code != 130:
        raise GateError(f"SIGINT of {command[0]} dry-run exited {code}")
    if not any(r.get("event") == "exit" and r.get("holding") is False for r in rows):
        raise GateError(f"SIGINT of {command[0]} dry-run did not report holding false")


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

        fight_tests, fight = str(Path(tmp, "fight-tests")), str(Path(tmp, "m3-fight"))
        build(fight_tests, MOTOR + "Motor.swift", SEEK + "Plate.swift", FIGHT + "Fight.swift", FIGHT + "FightTests.swift")
        fight_checks = suite(fight_tests, "fight", MIN_FIGHT_CHECKS)
        build(fight, MOTOR + "Motor.swift", MOTOR + "Probe.swift", SEEK + "Seek.swift", SEEK + "Plate.swift",
              SEEK + "SeekProbe.swift", FIGHT + "Fight.swift", FIGHT + "FightProbe.swift",
              CLICK + "Adapter.swift", CLICK + "NativeWindowServerPreparation.swift",
              CLICK + "NativeBackgroundClickTransport.swift",
              flags=("-O", "-D", "SEEK", "-D", "FIGHT"))
        refuses(fight, (["--bogus"], ["--dry-run", "x"], ["--execute"], ["--execute", "--keys", "arrows"],
                        ["--execute", "--keys", "wqe", "extra"], ["--preflight", "extra"]))
        fight_dry = subprocess.run([fight, "--dry-run"], cwd=ROOT, check=True, capture_output=True, text=True, timeout=90)
        fight_rows = [json.loads(line) for line in fight_dry.stdout.splitlines() if line.strip()]
        fight_summary = fight_rows[-1] if fight_rows else {}
        if fight_summary.get("event") != "summary" or fight_summary.get("outcome") != "KILLED_AND_LOOTED":
            raise GateError("M3 dry-run did not reach KILLED_AND_LOOTED")
        fight_trap()
        interrupted_dry([fight, "--dry-run"])

        nav_tests, nav = str(Path(tmp, "nav-tests")), str(Path(tmp, "m4-nav"))
        build(nav_tests, MOTOR + "Motor.swift", SEEK + "Plate.swift", FIGHT + "Fight.swift", NAV + "Nav.swift", NAV + "NavTests.swift",
              NAV + "Hunt.swift", NAV + "HuntTests.swift")
        nav_checks = suite(nav_tests, "nav", MIN_NAV_CHECKS)
        build(nav, MOTOR + "Motor.swift", MOTOR + "Probe.swift", SEEK + "Seek.swift", SEEK + "Plate.swift",
              SEEK + "SeekProbe.swift", FIGHT + "Fight.swift", FIGHT + "FightProbe.swift", NAV + "Nav.swift", NAV + "NavProbe.swift",
              NAV + "Hunt.swift", NAV + "HuntProbe.swift",
              CLICK + "Adapter.swift", CLICK + "NativeWindowServerPreparation.swift",
              CLICK + "NativeBackgroundClickTransport.swift",
              flags=("-O", "-D", "SEEK", "-D", "FIGHT", "-D", "NAV"))
        refuses(nav, (["--bogus"], ["--dry-run", "x"], ["--preflight", "x"], ["--replay"], ["--sim-jev"],
                      ["--sim-jev", "--scenario", "maze"], ["--execute", "--keys", "wqe"], ["--execute", "--to", "47.1,21.8"],
                      ["--execute", "--keys", "arrows", "--to", "47.1,21.8"], ["--execute", "--keys", "wqe", "--to", "47.1"],
                      ["--execute", "--keys", "wqe", "--to", "47.1,21.8", "--arrive", "5"], ["--hunt"],
                      ["--hunt", "--keys", "arrows"], ["--hunt", "--keys", "wqe", "extra"], ["--hunt-dry-run", "x"],
                      ["--hunt-sim-jev", "x"], ["--hunt", "--keys", "wqe", "--to", "47.1,21.8"]))
        nav_dry = subprocess.run([nav, "--dry-run"], cwd=ROOT, check=True, capture_output=True, text=True, timeout=90)
        nav_rows = [json.loads(line) for line in nav_dry.stdout.splitlines() if line.strip()]
        nav_summary = nav_rows[-1] if nav_rows else {}
        if (nav_summary.get("event") != "summary" or nav_summary.get("outcome") != "ARRIVED"
                or nav_summary.get("holding") is not False):
            raise GateError("M4 dry-run did not reach ARRIVED with keys released")
        hunt_dry = subprocess.run([nav, "--hunt-dry-run"], cwd=ROOT, check=True, capture_output=True, text=True, timeout=90)
        hunt_rows = [json.loads(line) for line in hunt_dry.stdout.splitlines() if line.strip()]
        hunt_summary = hunt_rows[-1] if hunt_rows else {}
        if (hunt_summary.get("event") != "summary" or not hunt_summary.get("fights")
                or hunt_summary.get("holding") is not False or hunt_summary.get("provider_calls") != 0):
            raise GateError("M4 hunt dry-run did not fight with keys released and no provider call")
        nav_trap()
        tabletop = subprocess.run([sys.executable, NAV + "tabletop.py", "--check"], cwd=ROOT, check=True,
                                  capture_output=True, text=True, timeout=60, env={"PATH": os.environ.get("PATH", "")})
        if not re.search(r"^tabletop scenarios checked: (1[2-9]|[2-9]\d)$", tabletop.stdout, re.M):
            raise GateError(f"tabletop --check reported {tabletop.stdout.strip() or 'nothing'}")
        video = subprocess.run([sys.executable, LEARN + "video_jev.py", "--check"], cwd=ROOT, check=True,
                               capture_output=True, text=True, timeout=60, env={"PATH": os.environ.get("PATH", "")})
        if not re.search(r"^askable decision points: (2[3-9]\d|[3-9]\d\d)$", video.stdout, re.M):
            raise GateError(f"video_jev --check reported {video.stdout.strip() or 'nothing'}")
        interrupted_dry([nav, "--dry-run"])
        interrupted_dry([nav, "--hunt-dry-run"])
    print(f"M0/M1/M3/M4 motor proof passed: {checks} + {seek_checks} + {fight_checks} + {nav_checks} fake-time checks, argument refusal, "
          f"release under a 400 ms observer stall (max {max(late, seek_late)} ms late), SIGINT release, the simulated "
          f"M1 loop ({summary['pulses_used']} pulses), the simulated M3 fight ({fight_summary.get('decisions')} "
          f"decisions) and the simulated M4 walk ({nav_summary.get('decisions')} decisions); M3/M4 dry-run SIGINT stops the "
          f"loop (130, holding false) with no OS keys; zero capture, OS input or live model calls.")


if __name__ == "__main__":
    main()
