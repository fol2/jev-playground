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
import struct
import tempfile
import zlib
from concurrent.futures import ThreadPoolExecutor
from tools.sdlc import MOTOR, SEEK, FIGHT, NAV, LEARN, ROOT, GateError

MIN_CHECKS = 100  # the suite must not silently lose its cases
MIN_SEEK_CHECKS = 103  # the current count: removing a check must lower this on purpose
MIN_FIGHT_CHECKS = 208  # the current count: removing a check must lower this on purpose
MIN_NAV_CHECKS = 244  # the current count: removing a check must lower this on purpose
LATE_MS = 100     # dry-runs stall their observer 400 ms per pulse; an observer-bound release fails
CLICK = "experiments/001_wow_fishing/probes/background-click/"
PERCEPTION = NAV + "perception.jsonl"  # the accepted readings of the perception regression set
MIN_PERCEPTION_FRAMES = 2397  # the current count: dropping frames from the set must lower this on purpose


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
    if FIGHT + "Fight.swift" in sources:
        sources = (*sources, FIGHT + "Tactics.swift", "experiments/002_wow_visual/runtime/Runtime.swift", "experiments/002_wow_visual/runtime/Input.swift",
                   "experiments/002_wow_visual/runtime/DecisionGraph.swift", "experiments/002_wow_visual/runtime/Experience.swift")
    # -j: the driver's own default ran one compiler job at a time; the jobs, not the output, change.
    subprocess.run(["swiftc", "-parse-as-library", "-j", str(os.cpu_count() or 1), *flags, *sources, "-o", output],
                   cwd=ROOT, check=True, timeout=300)


def build_all(builds: dict) -> None:
    """Every binary at once: the builds are independent. The -O builds, then the larger ones, start first
    because they take longest; the order changes only when each starts, never what is built. The checks
    run after all of them, on an idle machine: the dry-runs time their key-ups."""
    order = sorted(builds, key=lambda out: (-("-O" in builds[out][1]), -len(builds[out][0])))
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as pool:
        for job in [pool.submit(build, out, *builds[out][0], flags=builds[out][1]) for out in order]:
            job.result()


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


def saved_frames() -> Path | None:
    """The saved-frame corpus, shared by every worktree of this clone. A hosted runner has none: it stays local."""
    common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=ROOT, check=True,
                            capture_output=True, text=True, timeout=30).stdout.strip()
    frames = Path(common).parent / "runs/002_wow_visual"
    return frames if frames.is_dir() else None


def pixels(nav: str, frames: Path) -> dict:
    out = subprocess.run([nav, "--pixels", str(frames)], cwd=ROOT, check=True, capture_output=True, text=True, timeout=300)
    return {row["frame"]: row for row in map(json.loads, out.stdout.splitlines())}


def accepted(update: bool = False) -> dict:
    if update and not Path(ROOT, PERCEPTION).is_file():
        return {}
    rows = [json.loads(line) for line in Path(ROOT, PERCEPTION).read_text().splitlines()]
    frames = {row.get("frame"): row for row in rows}
    if not update and (len(frames) != len(rows) or len(rows) < MIN_PERCEPTION_FRAMES
            or any(not re.fullmatch(r"[0-9a-f]{64}", str(row.get("sha256"))) for row in rows)):
        raise GateError(f"{PERCEPTION} lost frames or holds a malformed row; at least {MIN_PERCEPTION_FRAMES} required")
    return frames


def shifts(old: dict, new: dict) -> list:
    """What differs from the accepted readings, reader by reader, with up to three example frames each."""
    changed: dict = {}
    for frame, row in old.items():
        now = new.get(frame)
        keys = (["missing"] if now is None else ["frame bytes"] if now["sha256"] != row["sha256"]
                else sorted(k for k in set(row) | set(now) if row.get(k) != now.get(k)))
        for key in keys:
            changed.setdefault(key, []).append(frame)
    return [f"{key} {len(frames)} ({', '.join(frames[:3])})" for key, frames in sorted(changed.items())]


def black_png(path: Path, width: int, height: int) -> None:
    row = b"\0" * (1 + 3 * width)  # filter byte, then RGB
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b""))


def perception(nav: str, tmp: str, update: bool = False) -> str:
    """The perception regression set: every pixel reader on every saved frame must read as accepted.
    The frames stay local, so a hosted runner checks the accepted file and a black-frame negative control only."""
    control = Path(tmp, "control")
    control.mkdir()
    black_png(control / "black.png", 2560, 1320)
    black_png(control / "small.png", 1280, 660)  # not the calibrated layout: skipped
    read = pixels(nav, control)
    black = {k: v for k, v in read.get("black.png", {}).items() if k != "sha256"}
    if list(read) != ["black.png"] or black != {"frame": "black.png", "player": 0, "mana": 0, "target": 0, "cast": 0}:
        raise GateError(f"a black frame read something, or a wrong-size frame was read: {read}")
    old = accepted(update)
    first = min(old, default="")
    if old and (shifts(old, {**old, first: {**old[first], "red": [[1, 2, 3, 4]]}}) != [f"red 1 ({first})"]
                or shifts(old, {**old, first: {**old[first], "sha256": "0" * 64}}) != [f"frame bytes 1 ({first})"]
                or shifts(old, {k: v for k, v in old.items() if k != first}) != [f"missing 1 ({first})"]):
        raise GateError("the perception comparer missed a planted shift")
    frames = saved_frames()
    if frames is None:
        if update:
            raise GateError("no saved frames here to accept readings from")
        return f"perception: {len(old)} accepted frames well-formed, black frame reads nothing; replay not run (no saved frames here)"
    new = pixels(nav, frames)
    if update:
        Path(ROOT, PERCEPTION).write_text("".join(json.dumps(new[f], sort_keys=True, separators=(",", ":")) + "\n"
                                                  for f in sorted(new)))
        return (f"accepted {len(new)} frames into {PERCEPTION}; changed from before: "
                + ("; ".join(shifts(old, new)) or "nothing") + f"; new {len(set(new) - set(old))}")
    changed = shifts(old, new)
    if changed:
        raise GateError(f"perception shifted from the accepted readings: {'; '.join(changed)}. Review the frames, "
                        "then accept with python3 -m tools.motor_offline --update-perception")
    return (f"perception: {len(old)} saved frames read as accepted, black frame reads nothing"
            + (f"; {len(set(new) - set(old))} newer frames not yet in the set" if set(new) - set(old) else ""))


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
    quest = Path(ROOT, NAV + "QuestProbe.swift").read_text()
    execute = quest.split("func questsExecute", 1)[-1]
    if ("also: { body.releaseAll(); host.releaseAll() }," not in execute
            or "holding: { body.holding || host.holding }" not in execute
            or "defer { body.releaseAll(); host.releaseAll() }" not in execute):
        raise GateError("questsExecute does not trap signals and defer onto its body's and its host's keys")
    host = quest.split("final class LiveQuestHost", 1)[-1].split("func fightBack", 1)[0]
    if ("walker?.releaseAll()" not in host or "lock.withLock { fighting }?.releaseAll()" not in host
            or "(walker?.holding ?? false) || lock.withLock { fighting?.holdingKeys ?? false }" not in host):
        raise GateError("the quest host's exit sweep and holding do not cover the current walk and fight")
    if ('if walker?.holding == true { return "WALK_KEYS_HELD" }' not in quest
            or 'guard !legs.holding else { return "WALK_KEYS_HELD" }' not in quest):
        raise GateError("a quest walk whose key release is unconfirmed does not end the run")


def fight_trap() -> None:
    """Execute must trap SIGINT onto a retrying host.releaseAll; this is not OS-key proof."""
    probe = Path(ROOT, FIGHT + "FightProbe.swift").read_text()
    core = Path(ROOT, "experiments/002_wow_visual/runtime/Input.swift").read_text()
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


def main(update: bool = False):
    with tempfile.TemporaryDirectory() as tmp:
        runtime = "experiments/002_wow_visual/runtime/"
        core_tests = str(Path(tmp, "runtime-tests"))
        experience_tests = str(Path(tmp, "experience-tests"))
        integration = str(Path(tmp, "integration-tests"))
        graph_tests = str(Path(tmp, "graph-tests"))
        tests, probe = str(Path(tmp, "motor-tests")), str(Path(tmp, "m0-probe"))
        fight_tests, fight = str(Path(tmp, "fight-tests")), str(Path(tmp, "m3-fight"))
        tabletop, video = str(Path(tmp, "tabletop")), str(Path(tmp, "video-jev"))
        nav_tests, nav = str(Path(tmp, "nav-tests")), str(Path(tmp, "m4-nav"))
        memory_file = str(Path(tmp, "hunt-experience.json"))
        seek_tests, seek = str(Path(tmp, "seek-tests")), str(Path(tmp, "m1-seek"))
        fight_sources = (MOTOR + "Motor.swift", SEEK + "Plate.swift", FIGHT + "Fight.swift")
        nav_sources = fight_sources + (NAV + "Nav.swift", NAV + "Hunt.swift", NAV + "Quest.swift")
        seek_shell = (MOTOR + "Motor.swift", MOTOR + "Probe.swift", SEEK + "Seek.swift", SEEK + "Plate.swift", SEEK + "SeekProbe.swift")
        clicks = (CLICK + "Adapter.swift", CLICK + "NativeWindowServerPreparation.swift", CLICK + "NativeBackgroundClickTransport.swift")
        builds = {
            core_tests: ((runtime + "Runtime.swift", runtime + "RuntimeTests.swift"), ()),
            experience_tests: ((runtime + "Experience.swift", runtime + "ExperienceTests.swift"), ()),
            integration: (nav_sources + (runtime + "IntegrationTests.swift",), ()),
            graph_tests: (nav_sources + (runtime + "GraphTests.swift",), ()),
            tests: ((MOTOR + "Motor.swift", MOTOR + "MotorTests.swift"), ()),
            probe: ((MOTOR + "Motor.swift", MOTOR + "Probe.swift"), ()),
            seek_tests: ((MOTOR + "Motor.swift", SEEK + "Seek.swift", SEEK + "Plate.swift", SEEK + "SeekTests.swift"), ()),
            seek: (seek_shell, ("-O", "-D", "SEEK")),
            fight_tests: (fight_sources + (FIGHT + "FightTests.swift",), ()),
            fight: (seek_shell + (FIGHT + "Fight.swift", FIGHT + "FightProbe.swift") + clicks, ("-O", "-D", "SEEK", "-D", "FIGHT")),
            nav_tests: (fight_sources + (NAV + "Nav.swift", NAV + "NavTests.swift", NAV + "Hunt.swift", NAV + "HuntTests.swift",
                                         NAV + "Quest.swift"), ()),
            nav: (seek_shell + (FIGHT + "Fight.swift", FIGHT + "FightProbe.swift", NAV + "Nav.swift", NAV + "NavProbe.swift",
                                NAV + "Hunt.swift", NAV + "HuntProbe.swift", NAV + "Quest.swift", NAV + "QuestProbe.swift") + clicks,
                  ("-O", "-D", "SEEK", "-D", "FIGHT", "-D", "NAV")),
            tabletop: ((NAV + "Tabletop.swift", runtime + "JSON.swift"), ()),
            video: ((LEARN + "VideoJev.swift", runtime + "JSON.swift"), ()),
        }
        if update:
            build_all({nav: builds[nav]})
            print(perception(nav, tmp, update=True))
            return
        build_all(builds)
        suite(core_tests, "runtime", 33)
        experience_checks = suite(experience_tests, "experience", 34)
        suite(integration, "runtime integration", 41)
        graph_checks = suite(graph_tests, "decision graph", 56)
        checks = suite(tests, "motor", MIN_CHECKS)
        refuses(probe, (["--bogus"], ["--execute"], ["--execute", "--keys", "arrows"], ["--execute", "turn-left:100"],
                        ["--execute", "--keys", "arrows", "turn-left:300"], ["--release"], ["--preflight", "extra"]))
        _, late = on_time(probe, 6)
        interrupted([probe, "--dry-run", "forward:200"])

        seek_checks = suite(seek_tests, "seek", MIN_SEEK_CHECKS)
        refuses(seek, (["--bogus"], ["--dry-run", "x"], ["--look", "x"], ["--execute"],
                       ["--execute", "--keys", "wqe", "--look", "f.png"], ["--execute", "--keys", "wqe", "--box", "1,1,20,20"],
                       ["--execute", "--keys", "wqe", "--look", "f.png", "--box", "1,1,20,20", "--stop-growth", "9"],
                       ["--target"], ["--target", "--keys", "wqe", "--stop-row", "0.9"], ["--target", "--keys", "wqe", "--look", "f.png"]))
        rows, seek_late = on_time(seek, None)
        summary = rows[-1]
        if summary.get("event") != "summary" or summary.get("outcome") != "VISIBLE_STOP_REACHED_PENDING_LABELS":
            raise GateError("M1 dry-run did not reach the simulated visible stop")
        interrupted([seek, "--dry-run"])

        fight_checks = suite(fight_tests, "fight", MIN_FIGHT_CHECKS)
        refuses(fight, (["--bogus"], ["--dry-run", "x"], ["--execute"], ["--execute", "--keys", "arrows"],
                        ["--execute", "--keys", "wqe", "extra"], ["--preflight", "extra"], ["--dry-run", "--graph"],
                        ["--dry-run", "--keys", "wqe"], ["--execute", "--graph", "g.json"]))
        fight_dry = subprocess.run([fight, "--dry-run"], cwd=ROOT, check=True, capture_output=True, text=True, timeout=90)
        fight_rows = [json.loads(line) for line in fight_dry.stdout.splitlines() if line.strip()]
        fight_summary = fight_rows[-1] if fight_rows else {}
        if fight_summary.get("event") != "summary" or fight_summary.get("outcome") != "KILLED_AND_LOOTED":
            raise GateError("M3 dry-run did not reach KILLED_AND_LOOTED")
        chain_dry = subprocess.run([fight, "--dry-run", "--graph", runtime + "skyborne-fight.graph.json"], cwd=ROOT, check=True,
                                   capture_output=True, text=True, timeout=90)
        chain_rows = [json.loads(line) for line in chain_dry.stdout.splitlines() if line.strip()]
        chain_summary = chain_rows[-1] if chain_rows else {}
        performed = chain_summary.get("performed", [])
        if (chain_summary.get("outcome") != "KILLED_AND_LOOTED" or chain_summary.get("policy") != "skyborne-fight-v1"
                or chain_summary.get("chain_steps", 0) < 3 or chain_summary.get("holding") is not False
                or chain_summary.get("provider_calls") != 0 or "CAST_LIGHTNING_BOLT" not in performed
                or "START_MELEE" not in performed or performed.index("CAST_LIGHTNING_BOLT") > performed.index("START_MELEE")
                or chain_summary.get("decisions", 99) >= fight_summary.get("decisions", 0)):
            raise GateError("M3b dry-run did not kill and loot through a chain of 3+ unasked steps, bolt before melee, in fewer Jev decisions")
        fight_trap()
        interrupted_dry([fight, "--dry-run"])

        nav_checks = suite(nav_tests, "nav", MIN_NAV_CHECKS)
        refuses(nav, (["--bogus"], ["--dry-run", "x"], ["--preflight", "x"], ["--replay"], ["--pixels"], ["--sim-jev"],
                      ["--sim-jev", "--scenario", "maze"], ["--execute", "--keys", "wqe"], ["--execute", "--to", "47.1,21.8"],
                      ["--execute", "--keys", "arrows", "--to", "47.1,21.8"], ["--execute", "--keys", "wqe", "--to", "47.1"],
                      ["--execute", "--keys", "wqe", "--to", "47.1,21.8", "--arrive", "5"], ["--hunt"],
                      ["--hunt", "--keys", "arrows"], ["--hunt", "--keys", "wqe", "extra"], ["--hunt-dry-run", "x"],
                      ["--hunt-sim-jev", "x"], ["--hunt-dry-run", "--experience"],
                      ["--dry-run", "--experience", "/tmp/x"], ["--hunt", "--keys", "wqe", "--to", "47.1,21.8"],
                      ["--plan"], ["--quests", "--keys", "wqe"], ["--quests", "--graph", "g.json"],
                      ["--quests", "--graph", "g.json", "--keys", "arrows"], ["--hunt-dry-run", "--fight-graph", "f.json"],
                      ["--quests", "--graph", "g.json", "--keys", "wqe", "--fight-graph"]))
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
        graph_dry = subprocess.run([nav, "--hunt-dry-run", "--graph", runtime + "skyborne-hunt.graph.json",
                                    "--experience", memory_file],
                                   cwd=ROOT, check=True, capture_output=True, text=True, timeout=90)
        graph_rows = [json.loads(line) for line in graph_dry.stdout.splitlines() if line.strip()]
        graph_summary = graph_rows[-1]
        if (not graph_summary.get("graph_calls") or not graph_summary.get("fights")
                or graph_summary.get("holding") is not False or graph_summary.get("provider_calls") != 0
                or not graph_summary.get("experience_cases")):
            raise GateError("graph dry-run did not exercise tools, experience recording and real Hunt skills")
        recalled = subprocess.run([nav, "--hunt-dry-run", "--graph", runtime + "skyborne-hunt.graph.json",
                                   "--experience", memory_file],
                                  cwd=ROOT, check=True, capture_output=True, text=True, timeout=90)
        recalled_rows = [json.loads(line) for line in recalled.stdout.splitlines() if line.strip()]
        if not any(row.get("event") == "graph_call" and "READ:experience" in str(row.get("question"))
                   for row in recalled_rows):
            raise GateError("second graph run did not proactively retrieve retained experience")
        nav_trap()
        checked = subprocess.run([tabletop, "--check"], cwd=ROOT, check=True, capture_output=True, text=True, timeout=60,
                                 env={"PATH": os.environ.get("PATH", "")})
        if not re.search(r"^tabletop scenarios checked: (1[3-9]|[2-9]\d)$", checked.stdout, re.M):
            raise GateError(f"tabletop --check reported {checked.stdout.strip() or 'nothing'}")
        replay = subprocess.run([video, "--check"], cwd=ROOT, check=True, capture_output=True, text=True, timeout=60,
                                env={"PATH": os.environ.get("PATH", "")})
        if not (re.search(r"^learning regression checks: (6[7-9]|[7-9]\d|\d{3,})$", replay.stdout, re.M)
                and re.search(r"^askable decision points: 236$", replay.stdout, re.M)
                and re.search(r"^historical replays reconciled: 6$", replay.stdout, re.M)):
            raise GateError(f"video-jev --check reported {replay.stdout.strip() or 'nothing'}")
        interrupted_dry([nav, "--dry-run"])
        interrupted_dry([nav, "--hunt-dry-run"])
        seen = perception(nav, tmp)  # last: it loads every core, and the dry-runs above time their key-ups
    print(f"Experience: {experience_checks} checks. Decision graph: {graph_checks} checks and native tool/skill/recall dry-run passed. M0/M1/M3/M4 motor proof passed: {checks} + {seek_checks} + {fight_checks} + {nav_checks} fake-time checks, argument refusal, "
          f"release under a 400 ms observer stall (max {max(late, seek_late)} ms late), SIGINT release, the simulated "
          f"M1 loop ({summary['pulses_used']} pulses), the simulated M3 fight ({fight_summary.get('decisions')} "
          f"decisions; M3b's chains {chain_summary.get('decisions')} decisions and {chain_summary.get('chain_steps')} unasked steps) and the simulated M4 walk ({nav_summary.get('decisions')} decisions); M3/M4 dry-run SIGINT stops the "
          f"loop (130, holding false) with no OS keys; {seen}; zero capture, OS input or live model calls.")


if __name__ == "__main__":
    if sys.argv[1:] not in ([], ["--update-perception"]):
        sys.exit("usage: python3 -m tools.motor_offline [--update-perception]")
    main(update=sys.argv[1:] == ["--update-perception"])
