# 001: WoW fishing — rules and Jev

## Latest experiment status

- **Test B:** one background pre-go, 314.11 seconds, **16/17 verified loot cycles**.
  It used 79 Jev calls and 60,806 tokens; one bite was missed. Full equipment/page
  switching was verified in a separate Jev pre-go; the completed run began prepared.
- **Current Test A comparison:** moved-rod search and weapon/page transition passed,
  then 10/13 cycles over 236.26 seconds before stopping. WoW was later observed at
  the login screen. A new full comparison needs the user to log in again.
- A post-run fix keeps a fresh observation baseline after non-actionable Jev replies.
  It passes offline checks; the recorded live B result predates that correction.
- **Parity is not established.** Preserve failures and distinguish the earlier
  fixed-scene A result below from the current comparison.

Use the [Test A playbook](playbook.md) or [Test B playbook](test-b-playbook.md).
Detailed run IDs, measurements and limitations are in [findings](findings.md).

## Earlier Test A acceptance

**Historical stricter acceptance passed:** starting with the main weapon and action-bar
page 1, the script equipped the fishing rod, selected page 2 and verified Fishing
in slot 1 during **one background pre-go**. It then ran autonomously for
**304.35 seconds**, with **15 casts and 15 verified loot cycles (100% in this run)**.
There were no timeouts, unverified retrievals, human intervention, foreground
fallback, videos or model calls in the timed interval.

Evidence: `runs/001_wow_fishing/test_a_20260920T210535Z_2e9814/summary.json` and
`verification.json`. Run, cycle and pre-go evidence occupy approximately **5.15 MiB**.
Recorded source hashes matched after the run. This is one successful fixed-scene
trial, not a general 100% reliability claim. Earlier failed trials are retained in
[findings](findings.md), including the previous 9/14 autonomy result.

See the [Test A operating playbook](playbook.md) for starting conditions, stopping,
acceptance checks and troubleshooting.

## Reproduce

From the repository root on the tested Mac, with WoW already running:

```sh
sh experiments/001_wow_fishing/build.sh
python3 experiments/001_wow_fishing/run_test_a.py --background
```

The build uses Apple's installed Swift toolchain and native frameworks. There are
no added package dependencies, installers, services or Keychain changes.
Test A needs no model key; Test B uses the existing local TypeSafe key.
The attributed background input files live in [probes/background-click](probes/background-click/README.md).
Existing Screen Recording and Accessibility permissions are required.

The runner performs pre-go exactly once, then invokes the internal `--prepared`
mode for subsequent casts. Each cast still checks the Fishing progress bar and
requires a visible float within six seconds. Those are per-cast execution checks,
not repeated equipment/shortcut preparation.

The loop runs for at least 300 seconds and finishes its in-flight cast; normal
completion may therefore take up to one extra 45-second cycle. Three consecutive
failures, uncertain loot, a focus/geometry interruption or a child timeout stop the
run for review. An early stop is not a five-minute pass. Results always include
failed casts, source hashes, elapsed time, mode and pre-go count.

The user explicitly authorised foreground fallback if background fails, as a
separate run with its own pre-go and full five-minute interval:

```sh
python3 experiments/001_wow_fishing/run_test_a.py
```

The successful acceptance run did not need that fallback. Stop a run with Ctrl-C;
the native attempt also checks Escape. Do not leave multiple runners active.

## What the script does

1. Pre-go inspects the equipped weapon. When it is not a rod, it verifies the rod
   tooltip by scanning the calibrated combined-bag grid, equips it and checks the equipped tooltip.
   It then selects action-bar page 2 and verifies
   Fishing in slot 1 plus the small page-number reference. It recognises and closes
   the known beta character-sheet Lua error on each opening, checking that it
   actually disappeared.
2. Presses the user-configured `1` binding and confirms a green Fishing progress bar.
3. Finds a newly appearing float and tracks its warm colour in a small water region.
4. Detects a downward movement or a short local disappearance followed by a visible
   return under stable background motion. It retains that signal for up to two
   seconds, waits for two recovered observations with less than one pixel of
   movement near the original position, then
   right-clicks. This accounts for the measured background input delay while the
   float is dipping.
5. Reads the fish label in the resulting loot window, clicks it and verifies that
   the loot window cleared. It then begins the next cast without repeating pre-go.

`loot_collected` means that visible item-selection and window-clearing transition;
it is not a game-memory or direct inventory query. Fresh-fish labels are supported;
unknown loot stops for review. Beta refresh notices prevent starting pre-go.

## Limits and resource boundaries

- Rod placement may change within the visible default combined-bag grid. The
  search covers ten columns and five rows; other layouts require calibration.
  An unreadable tooltip or missing rod stops pre-go.
- New targets must be in the calibrated cast corridor (window x 0.42–0.67,
  y 0.17–0.40); tall narrow colour components are rejected. This excludes the
  observed rod, upper rocks and neighbouring NPC float, not every possible decoy.
- The camera and window geometry must stay stable during a run. The current colour
  mask, UI coordinates and 563 x 260 water crop are calibrated to this scene/layout.
  Water/line-of-sight is not inferred as fact from a colour mask: a visible float is
  the post-cast gate. In development, a downward camera angle placed it off-screen;
  the camera was corrected before the successful timed run, not during it.
- Native ScreenCaptureKit streams at up to 10 Hz. Only current/previous pixels and
  six target observations are retained; no frame backlog or video is written.
- Source-attributed SkyLight input targets WoW. Background mode does not activate
  the app or fall back to global HID clicks. Right-button support is our tested local
  extension, not a claim about the original upstream implementation.
- Startup OCR increases memory use: observed development RSS was approximately
  154–171 MiB with OCR, versus approximately 46 MiB before OCR was added. These are
  helper-process measurements, not total game/WindowServer consumption.
- Evidence is small JPEG crops and JSONL logs under ignored `runs/`; raw recordings
  stay under ignored `data/`. The original development video is about 12 MiB.
- Twenty-one native regression assertions cover the measured onset, size and disappearance
  cases plus rejection cases and acquisition boundaries. They supplement, rather than replace, live proof.

## Diagnostic commands

```sh
/tmp/jev-fishing-live --self-test
/tmp/jev-fishing-live --check --background
/tmp/jev-fishing-live --execute --background
```

`--check` is an optional diagnostic, not a required extra step before the runner.
Do not invoke `--prepared` directly without a successful pre-go and unchanged setup.
Exit code alone is not a catch assertion; inspect structured outcomes and evidence.
`perfect_run` is true only for a completed interval of at least 300 seconds with
verified loot on every recorded cycle. It does not exclude failed attempts or
claim a general 100% success rate.

## Test B and earlier exploration

Test B uses `--jev` on the same runner. It asks Jev to choose equipment/page
preparation and judge bite observations, while code supplies capture, tracking,
input and result verification. There is no rules fallback. The [Test B playbook](test-b-playbook.md)
describes its 120-call budget, 1.5-second deadline, 0.85 REEL threshold and limitations.
The earlier `analyse.py` comparison used four recorded checkpoints and is separate
from these live trials.

The lightweight `record.py` and [recording protocol](recording-protocol.md) remain
available for short diagnostics. Do not enable continuous recording for normal runs.
