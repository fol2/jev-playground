# 001: WoW fishing — rules and Jev

**Current candidate: 26/30 verified cycles over ten live minutes; not a strict
pass.** Read the [ten-minute run](evidence/2026-09-21-test-a-600s/README.md) for what
that does and does not establish, then the
[latest review](latest-review.md): an earlier failed cast may have placed the float inside rock, where it was visually
occluded. The retained stills do not establish a scenery misidentification.
The [refactor notes](refactor-notes.md) explain the observation contract and scope.
Raw historical evidence is preserved; interpretation corrections are annotated.

## Offline first

From the repository root, without WoW or a provider key:

```sh
python3 -m tools.fishing_offline
# or to run individual checks:
sh experiments/001_wow_fishing/test_core.sh
# macOS only: compile the real helper and the tools, and run retained image/decision fixtures.
sh experiments/001_wow_fishing/build.sh
```

The `tools.fishing_offline` module is the superset entry point that CI now runs; it
performs the core suite, the Test A/B runner checks, Swift typechecks and offline fixture
validation. The core suite uses synthetic pixels, fake monotonic time and fake HTTP.
Native checks also use eight retained development image pairs, not held-out data:
the original four, plus four acquired/first-missing pairs added for peak
disambiguation. CI never captures a screen or dispatches input. Swift and Python's
alone suffices for these checks. The historical pilot analyser (`analyse.swift`,
`/tmp/jev-fishing-analyse VIDEO`) needs FFmpeg only when it decodes a clip.

On 25 Sept the tools moved from Python to Swift: `analyse.swift`, `record.swift` and
`run_test_a.swift` (with `tests/RunnerTests.swift`) replace `analyse.py`, `record.py`,
`run_test_a.py` and their tests. Before the Python was deleted, the Swift analyser wrote
byte-identical `observations.jsonl` (268 rows) and `comparison.jsonl` for the pilot clip,
and the same Jev question bytes. The runner keeps all 14 Python checks and adds the call
budget, an interruption and a timeout. `build.sh` builds `/tmp/jev-fishing-analyse`,
`/tmp/jev-fishing-record` and `/tmp/jev-fishing-run`.

## Architecture

`live.swift` supplies native ScreenCaptureKit capture, default-UI preparation,
acquisition, input and visual collection verification. It owns one capture stream
and one policy loop, not separate A/B controllers. Only bounded current/previous
pixels, one acquisition patch and seven timestamped observations are retained.

`motion.swift` matches a 20-pixel template against a fixed acquisition image.
It does not integrate previous position estimates or fall back to a Vision tracker.
Ambiguous matches and peaks at the +/-12-pixel search boundary abstain. Only
distinct local maxima count as competing peaks, so the shoulder of a broad match
no longer forces abstention. This does not verify that the initially acquired changed
component is actually a float.

`decision.swift` owns the observation generation and one-shot action state. Missing,
stale or discontinuous observations invalidate both history and pending decisions.
A brief template dropout after a supported bite keeps the original recovery deadline,
never extending it, and resets the confirmations and last accepted frame. A supported
signal still needs two distinct recovered frames and a fresh position.

`jev.swift` allows one in-flight request and rejects old cancelled completions.
Jev receives actual relative timestamps, displacement, appearance correlation and
background change, not screenshots, audio, static-area ratios or a rules verdict.
`self_tests.swift` keeps the historical native assertions outside the live flow.

## Comparison protocol

Protocol `anchored-pixel-bite-only-v1` changes only the bite policy: A uses rules;
B asks Jev for WAIT, REEL or ABSTAIN. Preparation and execution are shared. No
provider call is made during preparation and there is no rules fallback in B.

Earlier B trials also delegated equipment/page decisions and used different
observations. Do not pool them with this version. Live casts remain separate
stochastic samples, not a paired or randomised benchmark. The latest upstream
A attempt achieved 4/7 verified cycles, including an unconfirmed/possibly occluded target, after
the earlier A 2/3 and B 0/1 regression snapshots. See the [visual audit](visual-audit.md).
None of those runs tested this candidate.

## Operating and evidence

Do not infer live readiness from passing offline checks. The [shared/Test A playbook](playbook.md)
and [Test B differences](test-b-playbook.md) describe a separately authorised trial,
not an acceptance claim. The runner performs one preparation and then bounded casts
for 300 seconds. No-visible-target, lost-target, or unrecovered-bite outcomes before
any retrieval click are recorded as `target_unconfirmed` and may recast. These and
timeouts count towards the existing three-consecutive-failure stop and remain in the
denominator. Other native `stopped_*` outcomes remain terminal; strong background
change does not trigger recasting or camera/character movement. A final in-flight
cast may finish, up to 45 extra seconds.

Targeted input preserves focus and the user may voluntarily watch WoW. The
[source-attributed transport](probes/background-click/README.md) is unchanged.
Existing Screen Recording and Accessibility permissions remain necessary for live
capture/input; no installers, services or Keychain changes are added.

Auto-loot is verified by observing a loot-window appearance/closure transition.
Manual collection remains bounded to eight visually located item controls. Names
are optional OCR metadata, not action gates. `loot_collected` is visual evidence,
not a game-memory/inventory query; uncertain retrievals are not successes.

Keep small JPEGs and JSONL under ignored `runs/`, and recordings under ignored
`data/`. Store source hashes, complete failures, timings and comparison scope.
The [recording protocol](recording-protocol.md) remains available for short
investigations; do not enable continuous video for normal runs.
