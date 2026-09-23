# M1 — closed loop to a manually designated target

Status: **partly live-checked on 23 September 2026.**

- **Run 1 (worked).** Background Q/W pulses centred a designated lamp post, walked
  straight at it with the target held on the centre line, and grew it to 1.4×. The
  forward budget ran out before the 1.6× visible stop.
- **Run 2 (stopped, tool defect).** Its first turn moved the target as predicted, but a
  tracker defect stopped the run with no further input. The defect is repaired offline
  in `236d048`, but the repair has not been checked live.
- **Run 3 (not run).** The WoW window left the screen when the owner switched to
  another app.

Not yet observed live: the visible stop firing, a multi-pulse re-centre, and the
repaired tracker. See [Live checks](#live-checks-23-september-2026).

Question ([#5](https://github.com/fol2/jev-playground/issues/5)): M0 showed that
background Q/E/W pulses turn, move and stop the avatar. Can a deterministic loop use
only those pulses to do three things, each judged separately?

1. Bring a designated target to the screen centre (**centring**).
2. Show that walking forward keeps that target centred and does not shrink it
   (**facing**, not just the camera pointing that way).
3. Approach it until a defined visible stop condition (**approach and stop**).

It should work from different starting views. Target designation is manual, so
recognition is not a confound. This is not a recognition, navigation or reliability
claim.

## What is here

| File | Role | What its proof covers |
| --- | --- | --- |
| `Seek.swift` | Pure core: arguments, tracker, controller loop and a simulated world | Time, frames, sightings and key sink are injected |
| `SeekTests.swift` | 63 fake-time checks | **Simulation only**: argument, budget, tracker and loop logic |
| `SeekProbe.swift` | Native shell: preflight, dry-run, look, execute | Real timers and signals; live paths are compiled but not run offline |

Reused, not reinvented: M0's input lease, frame gate, pid key route, window capture,
signal trap, preflight and release. M1 builds `m0/Probe.swift` with `-D SEEK`, which only
removes M0's entry point. M0 changed in three small ways:

- The lease takes a `Budget`. M0 keeps its fixed six-pulse default.
- The frame feed also exposes the newest frame with its PTS.
- The shell driver can be subclassed.

## How it works

- **Designation (the oracle).**
  1. `--look` saves one frame of the WoW window.
  2. A person or agent picks a box on a static object in that frame.
  3. `--execute` cuts the template from that exact frame.

  Before any input is sent, the template must be found in the first live frame with
  correlation ≥ 0.8, a margin of ≥ 0.1 over any other place, and within 6 px of where
  it was designated. This also proves that the look frame and live frame share
  coordinates. Otherwise the run ends `HOLD_DESIGNATION_NOT_CONFIRMED` with zero keys.
- **Tracker.** Normalised cross-correlation of the designation on a 320-pixel grey frame.
  - The search is centred on an absolute prediction: the target's x before the pulse
    plus the predicted shift. It is not relative to the tracker's last match; live run 2
    showed a relative prediction applied twice.
  - Scale is searched at 0.95–1.2× the last scale per sighting, always against the
    original designation, so errors do not compound.
  - Below 0.6 the target counts as unseen. Unseen frames never move the tracker, and no
    key is pressed while it is unseen. A target unseen for over 1 s stops the run.
  - Measured on a synthetic 320×165 frame with `-O`: 81 ms for the full-frame search,
    7–18 ms per tracking step.
- **Controller.** Every decision uses a confident sighting from a fresh frame captured
  at least 0.3 s after the previous key-up. In M0, motion ended ≤ 68 ms after key-up.
  - Turn duration = dead time + gain × error ÷ rate, clamped to 60–250 ms.
  - Rate is 2.1 screen widths/s and dead time 40 ms, both fitted to M0 run 2. Gain is
    0.8, deliberately aiming short.
  - Centred means |x| ≤ 0.03 of the frame width. The run stops after six turns in a
    phase without centring (`centring_not_converged`), or after two turns that barely
    move the target (`no_visible_turn_response`). Turns never get longer.
- **Facing check.** After centring comes one 250 ms forward pulse. The check is
  `consistent` when the target stays within 0.06 of centre and does not shrink by more
  than 0.03. Otherwise the run stops with `facing_inconsistent`. A single pulse cannot
  resolve small facing errors on distant targets. Those appear later as repeated
  same-side re-centring.
- **Approach and visible stop.** The loop alternates re-centring (whenever |x| > 0.06)
  with 250 ms forward pulses. It stops when the target's apparent size reaches the stop
  growth (default 1.6×) against the designation. This is a visible condition. It is
  not a world distance: sprite scale is not calibrated to yards.
- **Budget.** Each process gets at most 20 pulses. Turns are capped at 1.2 s total per
  direction, and forward at 2.5 s total (about 15 yards at WoW's run speed). A spent
  budget stops the run with `STOPPED_budget_spent_before_visible_stop`.
- **Stops.** All of M0's stops apply: stale or stalled frames, capture identity or
  geometry change, the process exiting, a focus change, Escape, SIGINT/SIGTERM/SIGHUP,
  and unconfirmed release. Every stop cancels the lease, which releases the key first.
  Key-up comes from M0's independent timer and never waits for the tracker.
- **Evidence.** Each run writes these files, which stay local:
  - `designation.jpg`
  - `pNN-before/after.jpg`, with the tracked box and a centre line (`pNN-end.jpg` when
    no confident sighting followed)
  - `events.jsonl`, including every sighting with its score, runner-up and tracking time
  - `manifest.json`
  - a `labels.json` template

  The loop reports only dispatch, tracked image position and apparent growth. Whether
  the tracker stayed on the object, the avatar faced and approached it, and there was
  no collision, combat or misrouted input are all manual labels.

## Reproduce offline

```sh
python3 -m tools.motor_offline      # M0 + M1 suites, both dry-runs, refusals, SIGINT
```

Or by hand, from the repository root:

```sh
V=experiments/002_wow_visual
swiftc -parse-as-library $V/m0/Motor.swift $V/m1/Seek.swift $V/m1/SeekTests.swift -o /tmp/seek-tests && /tmp/seek-tests
swiftc -O -parse-as-library -D SEEK $V/m0/Motor.swift $V/m0/Probe.swift $V/m1/Seek.swift $V/m1/SeekProbe.swift -o /tmp/m1-seek
/tmp/m1-seek --dry-run    # SimWorld as the key sink: no capture, OS input or files
```

The dry-run uses real timers and M0's simulated 400 ms observer stall after each
key-down. A target starting 20° left and 20 yd away was reached in 8 pulses, with every
key-up on time.

## Live commands

These run from a terminal that already has Screen Recording and Accessibility. WoW must
be running and in the background; nothing is requested, launched or brought forward.

```sh
/tmp/m1-seek --look                                   # prints runs/.../look.png
/tmp/m1-seek --execute --keys wqe --look runs/002_wow_visual/m1_look_…/look.png --box X,Y,W,H
m0-probe --release --keys wqe                         # recovery after a crash or kill
```

## Live envelope (set 23 September 2026)

The owner delegated the envelope to the implementation owner ("you should do that by
yourself under AI-SDLC") and asked to continue after M0.

- **Target.** The same Mac and WoW Forever Beta client, with the character the owner
  loaded, a Shaman in a non-combat spot. WoW stays in the background throughout, and
  existing grants are used without asking for new ones.
- **Inputs.** Only `wqe`: Q/E turn, W forward. No strafe, jump, mouse, targeting,
  interaction, combat, chat, binding or camera change.
- **Limits.**
  - At most three runs, each from a different starting view and with a fresh
    designation.
  - Per-run budget as above: roughly 15 yards of forward at most.
  - Targets are static scenery with open ground in between, away from visible mobs.
  - The series stops on the first HOLD, misrouted input, combat, collision or
    unexpected state.
- **Recovery.** `m0-probe --release --keys wqe`. Positions are not reset by automatic
  reverse movement. Any human reset is recorded.
- **Evidence.** Local `runs/` only, plus a before/after post-check frame. The public
  repository gets this summary only: no character, realm or other players' names, and no
  frames.

## Live checks (23 September 2026)

All runs were on the envelope above: WoW 1.60.1 (build 69913), window 2560×1320, capture
640×330, profile `wqe`. The terminal was frontmost at every start and end, and WoW
never came forward. The runtime made zero model or provider calls. Frames and logs
stay local under `runs/002_wow_visual/`. Labels are the author's, from the saved frames
and trace.

| Run | Source | Start | Result |
| --- | --- | --- | --- |
| 1 | `458b82a` | Lamp post, x −0.078 | `STOPPED_budget_spent_before_visible_stop` |
| 2 | `458b82a` | Lantern on a log, x +0.189 | `STOPPED_target_lost` (tool defect) |
| 3 | `236d048` | — | Not run: the WoW window was off-screen (the owner was using another app) |

**Run 1:** 11 pulses. Every key-up was 0–2 ms late, and tracking took ≤ 11 ms per frame.

- **Centring:** one 70 ms Q moved the target from −0.078 to +0.009 (predicted shift
  +0.063, observed +0.087).
- **Facing:** `consistent`. One 250 ms W left x unchanged. Scale was unresolved at that
  distance.
- **Approach:** nine more W pulses. The target stayed at x 0.009–0.012 and its
  apparent scale rose 1.0 → 1.395, in the tracker's 5 % steps. The eleventh W was
  refused by the 2.5 s forward cap.
- **Labels:** from the frames, the tracker stayed on the lamp, and the avatar kept its
  back to the camera and left the path straight towards it. There was no collision,
  combat or misrouted input, and the chat edit box was closed. Growth implies the lamp
  was about 50 yd away rather than the 25 yd the author guessed. That estimate is not a
  distance measurement.

**Run 2:** one 112 ms E.

- A frame from just before the settle point tracked the lantern at x 0.031, against a
  predicted 0.038, with score 0.79. The turn itself matched the fit.
- The tracker then re-applied its relative shift and searched around −0.12. Every
  settled frame scored about 0.49, so the loop waited 1 s with no input and stopped.
- **Fix (`236d048`):** an absolute prediction, a regression check, and a `pNN-end`
  snapshot on failure. The first repair for this hypothesis.
- **Not assessed:** no after-frame was kept, and the window left the screen before a
  post-check. Facing, chat and combat after run 2 are therefore unlabelled.

What this shows, and what it does not:

- **Shown:** the M0 transport also works inside a closed loop driven by the image. The
  fitted turn model predicted both live turns to within 0.03 of the screen width, and
  forward motion kept a centred target centred. On this client, then, centring by Q/E
  also set the walking direction.
- **Limits:** one successful trial is an existence proof, not a rate. The visible stop
  condition, a multi-pulse re-centre, occlusion handling and the repaired tracker have
  not been seen live. The designation is an oracle chosen by the author, and the 5 %
  scale grid is coarse. Night lighting kept the template contrast low (s.d. about 12 grey
  levels), yet it tracked.
- **Next live step, same envelope:** one run with a larger offset and `--stop-growth
  1.3`, when the WoW window is on screen with another app in front.
