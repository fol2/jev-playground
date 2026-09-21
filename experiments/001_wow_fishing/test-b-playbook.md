# Test B: Jev preparation and fishing

Test B uses the same native capture, tracking, background input, float recovery
and loot verification as Test A. Jev chooses preparation actions and whether to
wait, reel or abstain. There is no automatic rules fallback.

## Run

Follow the [Test A playbook](playbook.md) for the default UI, camera, permissions,
starting state and stop procedure. Start with a normal main weapon and action-bar
page 1 when testing the whole preparation transition. Keep Fishing in slot 1 of
page 2. A moved rod is located from the shared bag-icon comparison, then confirmed by
its tooltip. Bounded tooltip scanning is the fallback.

Keep `TYPESAFE_API_KEY` in the local ignored `.env` or environment, then run:

```sh
sh experiments/001_wow_fishing/build.sh
caffeinate -di python3 experiments/001_wow_fishing/run_test_a.py --background --jev
```

The existing runner hosts both policies to avoid maintaining two control loops.
Test B output is named `runs/001_wow_fishing/test_b_<timestamp>_<id>/`.
Only one controller may run at once. Ctrl-C stops it. The five-minute timer starts
following one successful pre-go; a final in-flight cast is allowed to finish.

## Division of work

- Native OCR reads the equipped item and candidate bag item. Jev chooses KEEP,
  EQUIP_ROD or ABSTAIN, and confirms the found item before it is equipped.
- Jev chooses KEEP or PAGE_TWO from the current page glyph and slot tooltip,
  then judges readiness from the verified equipment and controls.
- Code handles the known beta Lua dialogue, locates the rod icon in the calibrated bag grid,
  performs input and checks actual results. Water visibility remains a post-cast
  float check, not a claim made by Jev from an image it cannot see.
- While fishing, Jev receives seven chronological relative `[dx, downward dy, estimated-size ratio]` observations,
  a computed English description of motion direction/magnitude, background change
  and any short tracking gap. It receives no Test A verdict. The size estimate comes from a tracked image patch,
  rather than a literal count of coloured pixels.
  REEL needs model probability at least 0.85, a pilot-calibrated abstention
  threshold rather than a claimed success rate. A supported REEL decision still waits for a fresh, visible, recovered float before clicking.

This is an expanded policy comparison: preparation differs as well as bite
judgement. It is not an isolated estimate of the bite classifier's contribution.
The capture/executor are shared; live casts are different stochastic samples.

## Resource and failure limits

- Model pinned to `jev-1.13.0`, direct HTTPS via Apple's URLSession; no new package.
- At most 120 attempted calls across pre-go and all casts, one in flight at a time.
- Fishing requests occur on broad observed changes or every four seconds while
  quiet, with at least 0.2 seconds between submissions. The scheduler is independent
  of Test A's bite predicate, but still limits the evidence that Jev sees.
- Request timeout and response age limit: 1.5 seconds; no application retries.
  Failure stops the run. ABSTAIN does not click. Capture continues during requests.
- Existing two-second recovery deadline is measured from the observation that
  prompted REEL, so network time reduces the remaining action window.
- No video or audio is recorded or transmitted. Only numeric float observations
  and cropped-tooltip OCR text go to TypeSafe. Local JPEG evidence remains ignored.

`jev_request` records the exact question and observations. `jev_response` records
raw output, probabilities, confidence, model, token usage and round-trip time.
The summary totals actual attempted calls and reported tokens. A cancelled or failed
request may have provider usage not returned to the client; reported totals are
not a billing guarantee. Confidence is not an empirical success probability.

Use the same strict five-minute acceptance as A, except provider calls must be
present and the pre-go/REEL choices must be visible in the logs. Inspect all failed
casts as well as successes. Keep both source hashes and starting-state evidence.
Do not claim general 100% reliability from a single perfect run.

## Shared visual and collection behaviour

A and B share the image-first bag lookup, wider float search, native Vision tracker
and language-independent loot controls. Acquisition uses before/after pixel
changes, compact shape, increased local detail and temporal stability, not a
required red/yellow hue. A 3-by-3 opening removes thin lines/noise. Vision then
tracks a 160-pixel patch. Strong camera motion discards the current decision and
requests a fresh cast after stable frames; its recovery path still needs controlled
live verification. Different starting views and in-flight view changes are separate
claims. See [Apple's tracking API](https://developer.apple.com/documentation/vision/vntrackingrequest).

Loot names are advisory. Item-row geometry and the close-button visual identify
the loot UI. Auto-loot is handled by observing the early window appearance and
closure; manual collection is bounded to eight item-control clicks. No item type
or language whitelist controls whether something is collected. Automatic-window
completion can have empty label metadata; this does not imply an empty catch.
Other pre-go text checks still target the tested Chinese/English UI and default
layout; this is not a claim of complete localisation support for all setup screens.

## Focus policy

The final user preference is to preserve focus rather than require WoW to remain
unfocused. `--background` keeps app-targeted input whether the user is watching
WoW or another app, and never calls app activation. `focus_observed` records state
changes. A summary of `targeted_mixed_focus` means WoW was foreground at least
once; it must not be reported as an entirely background run. The explicit global
foreground input route also no longer activates the app; it requires existing focus.
