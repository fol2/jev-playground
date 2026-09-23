# M1/M2 — closed loop to a designated target

Status: **live-checked on 23 September 2026. The loop worked end to end once, with
WoW off screen.**

| Run | What happened |
| --- | --- |
| 1 | Centred and approached a designated lamp post. Forward budget spent at 1.4×. |
| 2 | Stopped on a tracker defect, since repaired. |
| 3 | WoW was on another Space behind Citrix. The loop centred the lamp post, faced it, approached it and stopped on its own at the 1.3× visible condition. |

Not yet observed live: a multi-pulse re-centre and occlusion handling. One success per
condition is an existence proof, not a rate. See
[Live checks](#live-checks-23-september-2026).

**M2** (below) replaces the manual oracle with the game's own designation: one Tab, then
WoW's white-outlined target nameplate for bearing and the unit's selection circle for the
visible stop. It reached that stop twice live. See [M2](#m2--game-designated-target-23-september-2026).

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
| `SeekTests.swift` | 102 fake-time checks | **Simulation only**: argument, budget, tracker and loop logic |
| `Plate.swift` | M2 perception: the white-outlined target nameplate and the selection circle under it | Synthetic frames in the checks; validated on captured frames locally |
| `SeekProbe.swift` | Native shell: preflight, dry-run, look, execute (M1), target (M2); the WoW window need not be on screen | Real timers and signals; live paths are compiled but not run offline |

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
  - Frames captured before the settle point never reach the tracker, so a mid-pulse
    frame cannot shift the next search's scale or height (independent review of `236d048`).
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
be running and not frontmost. Its window may be covered or on another Space, but not
minimised. Nothing is requested, launched or brought forward.

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
640×330, profile `wqe`. The same app was frontmost at start and end of each run: the terminal
for runs 1–2, Citrix for run 3. WoW never came forward. The runtime made zero model or provider calls. Frames and logs
stay local under `runs/002_wow_visual/`. Labels are the author's, from the saved frames
and trace.

| Run | Source | Start | Result |
| --- | --- | --- | --- |
| 1 | `458b82a` | Lamp post, x −0.078 | `STOPPED_budget_spent_before_visible_stop` |
| 2 | `458b82a` | Lantern on a log, x +0.189 | `STOPPED_target_lost` (tool defect) |
| 3 | `f351525` | Lamp post, x −0.114, WoW off screen | `VISIBLE_STOP_REACHED_PENDING_LABELS` |

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

**Before run 3: capture-only checks.** No input was sent.

- The owner had switched to other apps. `m1-seek` at `a863925` refused because its window
  filter required `isOnScreen`, which was a probe choice, not a macOS limit.
- WoW was on another Space with Mail frontmost. Window-only capture delivered 303
  complete frames in 5 s: about 57 fps with a 60 fps request. The median interval was
  17 ms and the maximum 41 ms, and frames were 1–3 ms old on delivery.
- An earlier check, with the character logged out to the character screen, got 8 frames
  in 3 s. The cause was not isolated.
- `f351525` therefore selects the game window from all windows, by size, and records
  whether it was on screen. The frame gate still stops a run whose frames go stale.

**Run 3:** WoW was on another Space the whole time and Citrix was frontmost at start and
end. That makes it both the pending visible-stop run and the first input test with WoW
off screen.

- **Centring:** one 83 ms Q moved the target from −0.114 to −0.023 (predicted shift
  +0.090, observed +0.091).
- **Facing:** `consistent`.
- **Approach:** five W pulses. x stayed within −0.034 and the scale rose 1.0 → 1.334.
- **Stop:** the loop stopped on the 1.3× visible condition, with 83 ms of turn and
  1.25 s of forward spent.
- **Timing:** key-ups were 1–3 ms late. The frame gate took 113 fresh frames and 1
  stale.
- **Labels:** the tracker stayed on the lamp head, and the avatar walked towards it with
  its back to the camera. There was no collision, combat or misrouted input, and the
  chat edit box was closed.

What this shows, and what it does not:

- **Shown:** the M0 transport also works inside a closed loop driven by the image. The
  fitted turn model predicted both live turns to within 0.03 of the screen width, and
  forward motion kept a centred target centred. On this client, then, centring by Q/E
  also set the walking direction.
- **Off screen:** the same pid-targeted keys also move the avatar with WoW on another
  Space. The owner can use the Mac while a bounded run proceeds.
- **Limits:** one success per condition is an existence proof, not a rate. A
  multi-pulse re-centre and occlusion handling have not been seen live. The designation is an oracle chosen by the author, and the 5 %
  scale grid is coarse. Night lighting kept the template contrast low (s.d. about 12 grey
  levels), yet it tracked.

## M2 — game-designated target (23 September 2026)

After M1, #5 asks to replace the manual oracle with actual perception. The cheapest
candidate is the game's own UI. There is no ML and no model call.

```sh
/tmp/m1-seek --target --keys wqe [--stop-row 0.45]   # one Tab, then the M1 loop
```

- **Designation.** One Tab (target nearest enemy) is sent as a 60 ms tap, outside the
  lease because it moves nothing. Within 1 s a full-resolution frame must show exactly
  one white-outlined nameplate. Otherwise the run ends `HOLD_NO_TARGET_PLATE` with no
  movement key and a `p00-refused` frame. The signal trap also releases Tab, and so does
  `m0-probe --release`.
- **Bearing.** WoW outlines only the target's nameplate in white.
  - The detector anchors on the bar's uninterrupted bottom edge, 3 rows thick and
    about 133 px at 2560×1320.
  - It needs the top edge only as ≥ 70 % coverage, because name descenders cut it. The
    level badge is a separate box and is excluded.
  - x is the bar's centre, which is the unit's bearing. Detection runs afresh in every
    frame, so there is no drift.
- **Visible stop.** The loop stops when the bottom row of the unit's selection circle
  reaches the stop row (default 0.45 of the height).
  - The circle is searched from just under the plate down to the game view's bottom,
    so any allowed stop row can be observed.
  - Its row is the lowest bottom among the neutral-yellow blobs that are large enough,
    not bar-shaped, and centred within 0.75 plate widths of the plate. The unit's body
    splits the circle into arcs, and reading low stops early.
  - Far circles read as unseen, which counts as "not yet". While the circle is unseen,
    facing is judged on bearing only (`bearing_only`).
  - Once the circle has been seen, two unseen sightings in a row stop the run with
    `ground_lost`, so the loop never walks on blind. A single unseen sighting, such as
    grass in run 3, does not stop it.
  - This is a visible condition, not a distance.
- **Envelope.** As for M1, plus one Tab per run. Only neutral mobs that the owner
  confirmed are non-aggressive, and no attack. Captured frames stay local; there are no
  names or frames in the repository.

### Discovery and two rejected stop cues

- **Capture only, plus four discovery Tabs** (a scratch tool, not this probe).
  - In the village Tab found no enemy, so the owner moved the character to a grove of
    neutral mobs.
  - The action bar is on screen, but **no hotkey or icon turned red out of range**, not
    even melee `1` at over 20 yd. The planned action-bar range stop is therefore
    unavailable on this client and UI.
- **Nameplate row: rejected on evidence (run 3).** The nameplate floats at about camera
  height.
  - While the unit and its circle grew over ten W pulses, the circle fell from 0.29 to
    0.37 of the height but the plate stayed within 0.01.
  - The circle's row became the third candidate. It was reviewed against that run's
    frames first, following #5's two-candidate rule.

### Live runs

The same client, capture 2560×1320 and profile `wqe` were used for every run. WoW was
on another Space throughout, never frontmost. Key-ups were 0–6 ms late, and there were
zero model calls. Labels are the author's.

| Run | Source | Outcome | Notes |
| --- | --- | --- | --- |
| 1 | `b711f6f` | `STOPPED_budget_spent_before_visible_stop` | Tab picked a distant Vuldren. One 80 ms E centred it (x 0.104 → −0.008), and ten W kept it within 0.017. The plate-row stop never fired. |
| 2 | `b711f6f` | `HOLD_NO_TARGET_PLATE`, no movement | The "y" in Pesky Cirrusfly cut the top edge into 61 + 56 px. Repaired in `46d80a4` (anchor on the bottom edge). |
| 3 | `46d80a4` | `STOPPED_budget_spent_before_visible_stop` | Evidence that the circle falls while the plate does not. Circle stop added in `bd3a106`. |
| 4 | `bd3a106` | `VISIBLE_STOP_REACHED` | Pesky Cirrusfly. One 99 ms E (0.154 → 0.004). Circle rows 0.26 → 0.46, monotonic. Stopped with the unit just ahead, on the last allowed W. |
| 5 | `bd3a106` | `VISIBLE_STOP_REACHED`, **false** | The target was still far. A neighbour's yellow glow 238 px aside was read as the circle. Early stops are safe. Repaired in `0c24f4f` (the circle must sit under the plate); run 5's frame then reads unseen. |
| 6 | `0c24f4f` | `VISIBLE_STOP_REACHED` | A near Cirrusfly. One 96 ms E, facing `consistent` (circle 0.41 → 0.46), stopped just ahead of it. |

A fresh-context cross-vendor review (Grok) of `0799dca` found one high-severity defect,
fixed in the reviewed head:

- **Defect:** the circle search stopped 0.3 of the height under the plate, and an unseen
  circle meant "keep going". With a high plate or a low stop row, the loop could walk on
  past the unit.
- **Fixes, each with a check:**
  - The search now reaches the game view's bottom.
  - `ground_lost` stops the run.
  - The lowest arc is used.
  - Tab is released on signals.

The detectors were re-checked on the captured frames after each repair:

- Plate: 8 of 8 targets found, 0 of 3 no-target frames flagged.
- Circle: monotonic wherever visible in runs 3–4.

What this shows, and what it does not:

- **Shown:** the manual oracle can be replaced by the game's own designation and UI.
  Tab, nameplate bearing and the circle row drove centring, facing and approach to a
  visible stop, twice after the fixes (runs 4 and 6).
- **Limits:**
  - Two good stops and one false stop are existence evidence, not a rate.
  - The circle stop depends on the circle colour (neutral yellow only) and on its being
    visible. Grass and the unit's body hide it at range, and a moving unit can outrun
    the 2.5 s forward budget.
  - Tab's choice is the game's, and it is not always the nearest unit.
  - Hostile (red) and friendly (green) circles, occlusion, and a target that leaves the
    view mid-run have not been seen live.
