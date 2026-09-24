"""Replay video annotations, not gameplay ability or model training.

  python3 video_jev.py --check       # offline regressions + registered corpus
  python3 video_jev.py --self-test   # offline regressions only
  python3 video_jev.py FILE [...]   # explicit live replay; TYPESAFE_API_KEY; KB=1 optional

All inputs are validated before any provider call. Unknown observations stay unknown.
Historical replay totals predate the provenance-preserving loader; do not reuse them
as evidence for this version. No capture, game input, or weight updates happen here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import urllib.request

HERE = Path(__file__).resolve().parent
MODEL = "jev-1.13.0"
EXPECTED_COUNTS = {"zerocks1/part1_decisions.jsonl": 93,
                   "zerocks1/part2_decisions.jsonl": 75,
                   "zerocks1/part3_decisions.jsonl": 68}
# The historical table's agreements: decisions minus the committed mismatch rows of each run.
HISTORY = {"part1_facts": 67, "part2_facts": 48, "part3_facts": 36,
           "part1_kb": 65, "part2_kb": 48, "part3_kb": 40}

# Historical hand-written baseline, NOT independently verified mechanics. Kept
# verbatim so that a research change is not disguised as a mechanics correction.
FACTS = ("Mechanics a skilled player knows: a same-level fight takes about 10 s and 15-30% health; melee costs no "
         "mana; each Lightning Bolt costs about 15% mana and each hit taken pushes a cast back 0.5-1 s; a melee "
         "creature runs as fast as the character, so walking away only gives it free hits; eating and drinking "
         "restore both to full in about 20 s, standing still takes minutes; creatures attack when approached "
         "within about 20 yards (less if lower level); grey nameplates are creatures another player has tagged and "
         "give no credit; a hotkey digit turns red while the target is out of that spell's range. Out of combat, health and mana regenerate while standing or walking once 5 s pass without casting; at levels 1-5 the pools are small and refill in about 10-20 s, so sitting to drink costs more time than it saves unless mana is below about 30%; a skilled player uses those seconds to turn the camera and find the next target.")
GOAL = "Level up a new Shaman by finishing quests quickly and safely, like a skilled human; never die."


def unique_object(pairs):
    """json.loads normally hides duplicate keys, including duplicate action IDs."""
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError("duplicate JSON key: " + key)
        out[key] = value
    return out


def decode(text):
    def reject_constant(value):
        raise ValueError("non-finite JSON constant: " + value)
    return json.loads(text, object_pairs_hook=unique_object, parse_constant=reject_constant)


def options_of(d: dict) -> dict[str, str]:
    """Accept the three historical formats; never drop or stringify bad options."""
    options = d.get("options")
    if isinstance(options, dict):
        items = list(options.items())
    elif isinstance(options, list):
        items = []
        for option in options:
            if isinstance(option, dict) and option:
                items.extend(option.items())
            elif isinstance(option, str) and ":" in option:
                key, value = option.split(":", 1)
                items.append((key.strip(), value.strip()))
            else:
                raise ValueError("malformed option")
    else:
        raise ValueError("options must be an object or list")
    out = {}
    for key, value in items:
        if not isinstance(key, str) or not key.strip() or key != key.strip():
            raise ValueError("action ID must be a non-empty, trimmed string")
        if not isinstance(value, str) or not value.strip():
            raise ValueError("action description must be a non-empty string")
        if key in out:
            raise ValueError("duplicate action ID: " + key)
        out[key] = value
    if len(out) < 2:
        raise ValueError("at least two distinct options required")
    return out


def timestamp_seconds(value: str) -> int:
    if not isinstance(value, str):
        raise ValueError("timestamp must be a string")
    match = re.fullmatch(r"(\d+)m([0-5]\d)s", value)
    if match:
        return int(match[1]) * 60 + int(match[2])
    if re.fullmatch(r"\d+:[0-5]\d(?::[0-5]\d)?", value):
        parts = [int(x) for x in value.split(":")]
        return sum(x * 60 ** i for i, x in enumerate(reversed(parts)))
    raise ValueError("timestamp must be MMmSSs, MM:SS or HH:MM:SS")


def validate_decision(d):
    if not isinstance(d, dict):
        raise ValueError("decision must be an object")
    json.dumps(d, allow_nan=False)
    timestamp_seconds(d.get("t"))
    if not isinstance(d.get("state"), dict) or not d["state"]:
        raise ValueError("state must be a non-empty object")
    # The annotation is an observation, not an authority over the experiment.
    if {"goal", "facts"} & d["state"].keys():
        raise ValueError("state must not override goal or facts")
    if not isinstance(d.get("evidence"), str) or not d["evidence"].strip():
        raise ValueError("non-empty evidence required")
    options = options_of(d)
    if not isinstance(d.get("human"), str) or d["human"] not in options:
        raise ValueError("human choice must name an offered action")
    return options


def load_decisions(path: str | Path) -> list[dict]:
    rows, seen = [], set()
    for line_number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = decode(line)
            validate_decision(row)
            identity = json.dumps(row, sort_keys=True, ensure_ascii=False)
            if identity in seen:
                raise ValueError("duplicate decision row")
            seen.add(identity)
            rows.append(row)
        except (ValueError, TypeError) as error:
            raise ValueError(f"{Path(path).name}:{line_number}: {error}") from error
    if not rows:
        raise ValueError(f"{Path(path).name}: empty decision file")
    return rows


def knowledge(here: Path = HERE) -> dict[str, list[str]]:
    """Load flat Markdown facts, preserving their complete trust/source suffixes.

    The fenced YAML class schema is documentation, not an executed policy. This
    loader does not certify the tags or resolve knowledge/conflicts.md.
    """
    out = {}
    for name in ("general.md", "shaman.md"):
        section, fenced = name[:-3], False
        text = (Path(here) / "knowledge" / name).read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("```"):
                fenced = not fenced
            elif not fenced and line.startswith("## "):
                section = name[:-3] + ": " + line[3:].strip()
            elif not fenced and line.startswith("- "):
                fact = line[2:].strip()
                if fact:
                    out.setdefault(section, []).append(f"{fact} [knowledge/{name}:{line_number}]")
    return out


def check_corpus(here: Path = HERE, expected: dict[str, int] | None = None, minimum_facts: int = 100) -> int:
    here = Path(here)
    expected = EXPECTED_COUNTS if expected is None else expected
    found = {p.relative_to(here).as_posix() for p in here.glob("*/part*_decisions.jsonl")}
    if not expected or found != set(expected):
        raise ValueError(f"corpus manifest mismatch: missing={sorted(set(expected) - found)}, "
                         f"unregistered={sorted(found - set(expected))}")
    total = 0
    for relative, count in expected.items():
        rows = load_decisions(here / relative)
        if len(rows) != count:
            raise ValueError(f"{relative}: expected {count} decisions, found {len(rows)}")
        # Also exercises the exact request constructor without contacting Jev.
        for row in rows:
            json.dumps(payload(row["state"], options_of(row), FACTS), allow_nan=False)
        total += len(rows)
    facts = sum(map(len, knowledge(here).values()))
    if facts < minimum_facts:
        raise ValueError(f"knowledge base lost its facts ({facts}; minimum {minimum_facts})")
    return total


def check_history(here: Path = HERE) -> int:
    """Each historical run's mismatch rows are real decisions (same time and human choice) and
    reproduce the README table: agreement = decisions - mismatches."""
    for run, agree in HISTORY.items():
        part = run.split("_")[0]
        decisions = {(r["t"], r["human"]) for r in load_decisions(here / f"zerocks1/{part}_decisions.jsonl")}
        misses = [json.loads(line) for line in
                  (here / f"zerocks1/replay_mismatches/{run}.mismatches.jsonl").read_text(encoding="utf-8").splitlines()]
        total = EXPECTED_COUNTS[f"zerocks1/{part}_decisions.jsonl"]
        if len(misses) != total - agree or any((m["t"], m["human"]) not in decisions or m["jev"] == m["human"]
                                               for m in misses):
            raise ValueError(f"{run}: mismatch rows do not reproduce {agree}/{total}")
    return len(HISTORY)


def payload(state, options, facts):
    return {"model": MODEL, "state": {**state, "goal": GOAL, "facts": facts},
            "questions": {"action": {"type": "choice",
                                     "instructions": "Which action should the character take next?",
                                     "criteria": options}}}


def probabilities_of(answer, options):
    probs = answer.get("probabilities") if isinstance(answer, dict) else None
    if not isinstance(probs, dict) or not probs or set(probs) - set(options):
        raise ValueError("provider probabilities are empty or contain an unoffered action")
    if any(isinstance(p, bool) or not isinstance(p, (int, float)) or not 0 <= p <= 1
           or not math.isfinite(p) for p in probs.values()) or max(probs.values()) <= 0:
        raise ValueError("provider probabilities must be finite numbers in [0, 1] with a positive maximum")
    return probs


def ask(key, state, options, facts=FACTS):
    body = payload(state, options, facts)
    req = urllib.request.Request("https://api.typesafe.ai/v1/systemone",
                                 data=json.dumps(body, allow_nan=False).encode(),
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=25) as response:
                answer = decode(response.read().decode("utf-8"))["answers"]["action"]
            probabilities_of(answer, options)
            return answer
        except (OSError, TimeoutError):
            if attempt == 2:
                raise


def self_test():
    """Counted, provider-free regressions, colocated on the registered code path."""
    import copy
    import io
    import tempfile
    from contextlib import redirect_stdout, redirect_stderr
    from unittest.mock import patch

    checks = 0

    def require(condition, label):
        nonlocal checks
        if not condition:
            raise ValueError("self-test failed: " + label)
        checks += 1

    def refuses(call, label):
        try:
            call()
        except (ValueError, TypeError):
            require(True, label)
        else:
            require(False, label)

    row = {"t": "01m02s", "state": {"level": "unreadable", "counts_for_objective": None},
           "options": {"A": "Observe", "B": "Move"}, "human": "A", "evidence": "synthetic fixture"}
    for options in ({"A": "Observe", "B": "Move"},
                    ["A: Observe", "B: Move"], [{"A": "Observe"}, {"B": "Move"}]):
        require(validate_decision({**row, "options": options}) == row["options"], "historical option format")
    for options in (None, [], {}, ["A: Observe"], ["A: Observe", "A: Move"],
                    [{"A": "Observe"}, {"A": "Move"}], ["broken", "B: Move"],
                    {"A": 2, "B": "Move"}, {"": "Observe", "B": "Move"},
                    {"A": " ", "B": "Move"}, {" A": "Observe", "B": "Move"}, [True, "B: Move"]):
        refuses(lambda options=options: validate_decision({**row, "options": options}), "invalid options")
    for key, value in (("state", None), ("state", {}), ("state", []), ("state", {"goal": "override"}),
                       ("state", {"facts": "override"}), ("state", {"health": float("inf")}),
                       ("human", "C"), ("human", []),
                       ("evidence", ""), ("t", "0:88:00"), ("t", "01m99s"), ("t", None)):
        refuses(lambda key=key, value=value: validate_decision({**row, key: value}), "invalid decision field")
    refuses(lambda: validate_decision([]), "non-object decision")
    refuses(lambda: decode('{"a":1,"a":2}'), "duplicate JSON keys")
    refuses(lambda: decode('{"a":NaN}'), "NaN JSON")
    for value, seconds in (("01m02s", 62), ("01:02", 62), ("01:02:03", 3723)):
        require(timestamp_seconds(value) == seconds, "timestamp conversion")
    before = copy.deepcopy(row)
    packet = payload(row["state"], row["options"], "facts")
    require(row == before and packet["state"]["counts_for_objective"] is None, "unknown and input preserved")
    require("human" not in packet["state"] and "evidence" not in packet["state"], "labels withheld")
    require(payload({"goal": "bad", "facts": "bad"}, {}, "good")["state"]["facts"] == "good", "reserved precedence")
    for probs in ({}, {"C": 1}, {"A": float("nan")}, {"A": float("inf")},
                  {"A": -0.1}, {"A": 1.1}, {"A": 10 ** 500}, {"A": True}, {"A": "1"}, {"A": 0}):
        refuses(lambda probs=probs: probabilities_of({"probabilities": probs}, row["options"]), "bad response")
    require(probabilities_of({"probabilities": {"A": 0.6, "B": 0.4}}, row["options"])["A"] == 0.6, "good response")
    with tempfile.TemporaryDirectory() as tmp, patch.object(urllib.request, "urlopen", side_effect=AssertionError("network forbidden")):
        root = Path(tmp)
        (root / "knowledge").mkdir()
        (root / "knowledge/general.md").write_text("## Test\n- Low confidence [classic-transfer] source-x\n", encoding="utf-8")
        (root / "knowledge/shaman.md").write_text("```yaml\n- not a flat fact\n```\n## Test\n- Observed [owner-live] source-y\n", encoding="utf-8")
        facts = knowledge(root)
        require(sum(map(len, facts.values())) == 2, "fenced YAML not counted")
        require("[classic-transfer] source-x" in facts["general: Test"][0], "trust and source preserved")
        require("knowledge/general.md:2" in facts["general: Test"][0], "source location preserved")
        (root / "video").mkdir()
        path = root / "video/part1_decisions.jsonl"
        path.write_text(json.dumps(row) + "\n", encoding="utf-8")
        manifest = {"video/part1_decisions.jsonl": 1}
        require(check_corpus(root, manifest, 2) == 1, "offline corpus request construction")
        refuses(lambda: check_corpus(root, manifest, 3), "lost knowledge facts")
        refuses(lambda: check_corpus(root, {"video/part1_decisions.jsonl": 2}, 2), "deleted row")
        refuses(lambda: check_corpus(root, {}, 2), "empty manifest")
        refuses(lambda: check_corpus(root, {"missing/part1_decisions.jsonl": 1}, 2), "missing file")
        for text in ("", "not JSON\n", json.dumps(row) + "\n" + json.dumps(row),
                     json.dumps({**row, "human": "C"}), '{"t":"00m00s","t":"01m00s"}'):
            path.write_text(text, encoding="utf-8")
            refuses(lambda: load_decisions(path), "corrupt/empty/duplicate row")
        path.write_text(json.dumps(row) + "\n", encoding="utf-8")
        output, errors = io.StringIO(), io.StringIO()
        with patch.dict(os.environ, {"TYPESAFE_API_KEY": "offline-test-not-a-secret", "KB": "0"}), \
             patch.object(sys.modules[__name__], "ask", return_value={"probabilities": {"A": 0.612345, "B": 0.387655}}) as model, \
             redirect_stdout(output), redirect_stderr(errors):
            require(main([str(path)]) == 0, "mock replay CLI")
            prediction = json.loads(output.getvalue().splitlines()[0])
            require(prediction["probabilities"]["A"] == 0.612345, "unrounded probabilities retained")
            require(prediction["source"] == str(path) and prediction["decision_index"] == 1, "stable replay identity")
            require(len(json.loads(errors.getvalue())["evaluator_sha256"]) == 64, "replay evaluator identity")
            model.reset_mock()
            bad = root / "bad.jsonl"
            bad.write_text(json.dumps({**row, "human": "C"}), encoding="utf-8")
            refuses(lambda: main([str(path), str(bad)]), "validate all files before replay")
            require(model.call_count == 0, "bad later file spends no provider calls")
        extra = root / "video/part2_decisions.jsonl"
        extra.write_text(json.dumps(row), encoding="utf-8")
        refuses(lambda: check_corpus(root, manifest, 2), "unregistered file")
    if checks < 67:
        raise ValueError(f"self-test suite lost checks ({checks})")
    return checks


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    parser.add_argument("files", nargs="*")
    args = parser.parse_args(argv)
    if args.check or args.self_test:
        if args.files:
            parser.error("offline modes do not accept replay files")
        print(f"learning regression checks: {self_test()}")
        if args.check:
            print(f"askable decision points: {check_corpus()}")
            print(f"historical replays reconciled: {check_history()}")
        return 0
    if not args.files:
        parser.error("choose --check, --self-test, or explicit files for a live replay")
    # Validate EVERY input first: no silent skips or partial provider spend on bad data.
    if len({Path(path).resolve() for path in args.files}) != len(args.files):
        parser.error("a replay file must not be counted twice")
    rows = [(str(path), index, row) for path in args.files
            for index, row in enumerate(load_decisions(path), 1)]
    kb_mode = os.environ.get("KB") == "1"
    facts = knowledge() if kb_mode else FACTS
    key = os.environ.get("TYPESAFE_API_KEY", "")
    if not key:
        parser.error("live replay requires TYPESAFE_API_KEY; --check is offline")
    metadata = {"model": MODEL, "evaluator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "mode": "provenance-kb" if kb_mode else "legacy-hand-written",
                "facts_sha256": hashlib.sha256(json.dumps(facts, sort_keys=True).encode()).hexdigest(),
                "inputs": {str(p): hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in args.files},
                "metric": "annotation agreement; not gameplay competence"}
    print(json.dumps(metadata), file=sys.stderr)
    agree, misses = 0, []
    for source, index, d in rows:
        opts = options_of(d)
        probs = probabilities_of(ask(key, d["state"], opts, facts), opts)
        pick = max(probs, key=probs.get)
        agree += pick == d["human"]
        print(json.dumps({"source": source, "decision_index": index, "t": d["t"], "jev": pick,
                          "human": d["human"], "p": round(probs[pick], 2), "probabilities": probs}), flush=True)
        if pick != d["human"]:
            misses.append({**d, "jev": pick, "p": {k: round(v, 2) for k, v in probs.items()}})
    print(f"agreement {agree}/{len(rows)}")
    with open(args.files[0] + ".mismatches.jsonl", "w", encoding="utf-8") as out:
        for miss in misses:
            out.write(json.dumps(miss) + "\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
