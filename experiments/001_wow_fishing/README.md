# 001: WoW fishing — rules and Jev

**Current candidate: offline-tested, not live-accepted.** Read the
[latest review](latest-review.md): new upstream evidence confirms that initial
acquisition can select scenery. This refactor does not establish that it is fixed.
The [refactor notes](refactor-notes.md) explain the observation contract and scope.
Historical findings and both retained evidence folders are preserved unchanged.

## Offline first

From the repository root, without WoW or a provider key:

```sh
sh experiments/001_wow_fishing/test_core.sh
python3 -S -m unittest discover -s experiments/001_wow_fishing -p 'test_*.py' -v
# macOS only: compile the real helper and run retained image/decision fixtures.
sh experiments/001_wow_fishing/build.sh
```

The core suite uses synthetic pixels, fake monotonic time and fake HTTP. Native
checks also use the four retained development image pairs, not held-out data.
CI never captures a screen or dispatches input. Swift and Python's standard
library suffice for these checks. The historical `analyse.py` video decoder still
needs NumPy and FFmpeg; those are loaded only when decoding is requested.

## Architecture

`live.swift` supplies native ScreenCaptureKit capture, default-UI preparation,
acquisition, input and visual collection verification. It owns one capture stream
and one policy loop, not separate A/B controllers. Only bounded current/previous
pixels, one acquisition patch and seven timestamped observations are retained.

`motion.swift` matches a 20-pixel template against a fixed acquisition image.
It does not integrate previous position estimates or fall back to a Vision tracker.
Ambiguous matches and peaks at the +/-12-pixel search boundary abstain. This does
not verify that the initially acquired changed component is actually a float.

`decision.swift` owns the observation generation and one-shot action state. Missing,
stale or discontinuous observations invalidate both history and pending decisions.
A supported signal still needs two distinct recovered frames and a fresh position.

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
A attempt achieved 4/7 verified cycles, with confirmed scenery acquisition, after
the earlier A 2/3 and B 0/1 regression snapshots. See the [visual audit](visual-audit.md).
None of those runs tested this candidate.

## Operating and evidence

Do not infer live readiness from passing offline checks. The [shared/Test A playbook](playbook.md)
and [Test B differences](test-b-playbook.md) describe a separately authorised trial,
not an acceptance claim. The runner performs one preparation and then bounded casts
for 300 seconds. Every native `stopped_*` safety outcome is terminal; strong
background change does not trigger automatic reacquisition, recasting or
camera/character movement. Non-terminal timeouts stop after three consecutive
failures. A final in-flight cast may finish, up to 45 extra seconds.

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
