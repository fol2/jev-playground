# M0 — bounded native turn/move/stop probe

Status: **live-checked on 22 September 2026, no transport blocker found.** Twelve
background pulses were dispatched and released on time. Each produced a visible
effect that stopped after key-up, with focus unchanged and no misrouted input. See
[Live checks](#live-checks-22-september-2026). This is the cheap early veto from #5, not
an error rate, reliability or navigation claim. Building the probe itself involved no
game, capture, input or model call.

Question ([#5](https://github.com/fol2/jev-playground/issues/5)): can the existing
native Mac key route produce bounded avatar turn/move/stop actions without taking
focus, with visual effects that can be inspected separately? A dispatched key is not
movement, and a visual change is not avatar facing.

## What is here

| File | Role | What its proof covers |
| --- | --- | --- |
| `Motor.swift` | Pure core: fixed allowlist, argument limits, input lease, frame gate, response heuristic, batch runner | Time, frames and key sink are injected |
| `MotorTests.swift` | 117 fake-time checks | **Dispatch intent only**: argument, lease, gate and batch logic |
| `Probe.swift` | Native shell: preflight, dry-run, execute, release | Real timers and signals; live paths are compiled but not run |

M1 ([`../m1/`](../m1/README.md)) reuses this core and shell. The lease takes a `Budget` (M0 keeps its fixed
six-pulse default), the frame feed also exposes the newest frame's PTS, and `Probe.swift` built with
`-D SEEK` drops only M0's entry point.

Reused, not reinvented: fishing's background key route (`live.swift` `key()`: a
private event source posted to one pid, previously shown to cast in the background
with TextEdit frontmost) and its ScreenCaptureKit latest-frame pattern. The
SkyLight click transport is not used; the fishing key route never used it either. The fishing code is
unchanged.

Safety design:

- **Allowlist.** `turn-left`, `turn-right` and `forward` only, at 100 or 200 ms, at most six
  pulses per process, one key at a time. There are three fixed key profiles:
  - `arrows` (←/→/↑, codes 123/124/126) and `wasd` (A/D/W, codes 0/2/13) are WoW defaults.
  - `wqe` (Q/E/W, codes 12/14/13) is this owner's layout, where A/D strafe.

  `--execute` has no default profile. A wrong profile sends the wrong action, as live
  check 1 showed.
- **Lease.** Key-up comes from a strict, zero-leeway timer on its own queue, so it never
  waits for the observer or any inference. Every stop path cancels the lease, which
  releases the key first. A stop cannot be undone within that process. A failed key-up
  is retried and then reported as `HOLD_RELEASE_UNCONFIRMED`, never hidden.
- **Gate.** A command runs only with a frame from the same capture stream and size no
  older than 0.35 s. The run stops on stale, duplicate, reordered, future or non-finite
  frames, a stalled detector, a capture-identity or window-geometry change, the target
  process exiting, a change of frontmost app, or Escape.
- **Observation.** Each pulse runs as 1 s baseline, pulse, then 1.5 s observation. A
  whole-frame change heuristic times the visible response and settling. If motion
  continues more than 1 s after key-up, or the observation window is incomplete, the
  run stops. If no effect is resolved the result is `INCONCLUSIVE`; pulses never get longer.
- **Separation.** Each pulse report keeps three things apart: `dispatch`
  (`posted_to_pid`), the heuristic `visual_effect`, and `avatar_movement` (`UNLABELLED`
  until the owner fills in `labels.json`). The heuristic cannot distinguish avatar
  movement from camera-only or scene motion.

## Preflight report (read-only, 22 September 2026)

Collected with `m0-probe --preflight` plus toolchain version commands. The probe
requested nothing: no capture, input, permission prompt, window title or game-file read.

| Fact | Value | Status |
| --- | --- | --- |
| Mac | `Mac16,10`, arm64 | verified |
| macOS | 27.0 (build `26A428`) | verified |
| Toolchain | Xcode 26.6, Swift 6.3.3, Python 3.14.7, Node 24.18.0, git 2.55.0 | verified |
| CI toolchain | GitHub `macos-14` image compiles and runs the same proof | see the PR's Focus Gate run |
| Screen Recording / Accessibility / post / listen events | all `true` | verified **for the terminal app that launched this session only**. macOS attributes the grant to the launching app; another launcher may differ |
| Installed client | `/Applications/World of Warcraft/_classic_beta_/World of Warcraft Beta.app`, Info.plist `1.60.1` / `1.60.1.69913` | verified install; **not** proof of the session the owner will open |
| WoW running at preflight | no process, no window | verified snapshot |
| Frontmost app at preflight | Chrome | verified snapshot |
| Session client build, realm, character, location | — | **unknown** |
| Session client | WoW Forever Beta (`_classic_beta_`, 1.60.1 / 1.60.1.69913), English UI, a level-2 Shaman on open ground | owner statement plus live preflight |
| Movement bindings | W forward, A/D strafe, Q/E turn (profile `wqe`) | owner statement, consistent with both live checks |
| Capture rate and frame age | 474–476 fresh frames per batch (about 30 fps), age median 13–15 ms, maximum 31 ms, none rejected | observed live |
| Whether WoW applies held keys it receives in the background | yes, for W, A/D and Q/E | observed live; see below |
| Escape readable in the live launch context | — | **unverified**: the owner declined a manual press, and a synthetic Escape would go to the frontmost agent terminal |

## Reproduce offline (no effects)

From the repository root:

```sh
python3 -m tools.motor_offline      # 117 counted checks, argument refusal, dry-run release, SIGINT release
python3 tools/sdlc.py check --base origin/main --head HEAD   # the Focus Gate route (clean tree)
```

`tools.motor_offline` compiles the checks and the probe, confirms invalid arguments exit
64 with no output, and runs `--dry-run`. The dry-run blocks its own observer for 400 ms
after each key-down, and every key-up must still land within 100 ms of its deadline
(0 ms measured here). The last step sends SIGINT during a held key and requires the
key-up before exit. The dry-run uses synthetic frames and a no-effect sink: it makes no
capture, OS event or file.

## Commands after separate authorisation

Build and inspect (both no-effect):

```sh
swiftc -parse-as-library -O experiments/002_wow_visual/m0/Motor.swift \
  experiments/002_wow_visual/m0/Probe.swift -o /tmp/jev-m0-probe
/tmp/jev-m0-probe                    # read-only preflight JSON
/tmp/jev-m0-probe --dry-run          # no-effect stage 1; hold Escape once to see STOPPED_operator_escape
```

The one approved live batch runs from the repository root with WoW in the background.
Use the key profile confirmed in-game:

```sh
/tmp/jev-m0-probe --execute --keys wqe \
  turn-left:100 turn-right:100 forward:100 turn-left:200 turn-right:200 forward:200
```

Emergency stop: press Escape (polled every 10 ms) or Ctrl-C in the probe's terminal;
either releases immediately. SIGKILL, a crash or power loss cannot run any handler.
In that case, recover with key-ups only, or bring WoW forward and tap the same keys:

```sh
/tmp/jev-m0-probe --release --keys wqe       # key-up for the three allowlisted keys; no key-down
```

Exit codes: 0 completed or inconclusive, 2 stopped or refused, 3 release unconfirmed,
64 invalid arguments, 130 interrupted.

Evidence goes to `runs/002_wow_visual/m0_<UTC>_<id>/`, which Git ignores:

- `events.jsonl`: key-down/up times, lateness, frame rejections, stops.
- `manifest.json`: git head/dirty, machine, target pid/window/bounds/capture stream,
  focus at start and end, profile, plan, frame counts and `model_calls: 0`. It also holds
  the per-pulse reports. Each report has a `trace` with one
  `[capture PTS − key-down ms, admission age ms, grey change]` row per frame, so the
  response and settle times can be recomputed.
- `labels.json`: to be filled in by the owner.
- `pNN-before.jpg` and `pNN-after.jpg`: at most 12 window-only JPEGs, at most 640 px wide.
  No video is kept. If these frames and the trace cannot separate avatar movement from
  camera-only change, add a short window recording.

Screenshots can show character, realm or chat, so treat them as private until reviewed.

## Live checks (22 September 2026)

Both batches ran from a clean committed head with WoW in the background. The frontmost
app was the agent's terminal, unchanged from start to end, and WoW was never activated.
Before and after each batch, a window-only screenshot showed the chat input box empty
and the character out of combat. Runtime made zero model calls. Evidence stays local
in `runs/002_wow_visual/`.

| # | Pulse | Check 1 (`wasd` at `d1967bf`) | Check 2 (`wqe` at `1ce396b`) |
| --- | --- | --- | --- |
| 1 | turn-left 100 | A: held 100 ms, response 94 ms, stopped 61 ms after key-up, scenery +4 px: **strafe left** | Q: 100 ms, 90 ms, 57 ms, +60 px: **turn left** |
| 2 | turn-right 100 | D: 100, 49, 17, −4 px: **strafe right** | E: 102, 68, 68, −100 px: **turn right** |
| 3 | forward 100 | W: 100, 39, 41, 0 px: **forward** | W: 101, 24, 24, 0 px: **forward** |
| 4 | turn-left 200 | A: 201, 28, 30, +8 px: **strafe left** | Q: 201, 82, 49, +214 px: **turn left** |
| 5 | turn-right 200 | D: 201, 75, 46, −8 px: **strafe right** | E: 201, 74, 46, −214 px: **turn right** |
| 6 | forward 200 | W: 200, 28, 31, 0 px: **forward** | W: 201, 29, 31, 0 px: **forward** |

How to read a cell:
- Numbers are held time, visible response after key-down, and last motion after key-up.
- px is the best-fit horizontal shift of distant scenery between the before and after
  frames, on the 640 px capture. It is not an angle or a distance.
- Between pulses the scene was static: the after-to-next-before difference was 1.3–1.8
  grey levels, against 8–16 during a hold.
- After a Q/E turn the character stays centred with its back to the camera, so its
  facing rotated with the view rather than the camera swinging alone.

Disclosed limits:
- **Twelve probes, not the proposed six.** Check 1's profile mapped the turns to A/D,
  which strafe on this client, so it tested move/strafe/stop but no turn. The owner
  then gave the bindings and delegated the live decisions, so the batch was repeated
  once with the fixed `wqe` profile.
- The labels are the author agent's, from the frames, traces and the owner's binding
  statement. They are not independent.
- Amplitude is not linear in hold time. 100 ms turns shifted the scenery 60–100 px and
  200 ms turns 214 px, because the visible response started 24–94 ms after key-down. The
  100 ms left/right asymmetry is unexplained.
- Distant mobs moved throughout, but the baselines stayed around 0.1, so the threshold
  held at its 0.5 floor.
- Two six-pulse batches cannot establish an error rate, leak-free operation, emergency
  stop behaviour or navigation reliability.

Next, per #5: a small closed loop to a manually designated target from different starting
views. Centring and facing/approach are validated separately, with a defined visible
stopping condition.

## Proposed bounded live envelope (as approved; executed above)

1. **Machine/account:** this Mac, the owner's logged-in session. Launch from the same
   terminal app whose permissions the preflight verified. Change no grants.
2. **Client/session:** the owner opens the client and character, then confirms which
   client, realm and character it is. The character stands idle on open, unobstructed,
   non-combat ground with no NPC, vendor, mailbox or quest giver nearby. The chat edit
   box is closed. Camera mode and bindings stay as they are; the owner confirms which
   profile (`arrows` or `wasd`) is bound to Move Forward, Turn Left and Turn Right.
3. **Focus mode:** background only. The probe's terminal stays frontmost and the WoW
   window stays visible (not minimised or hidden). The probe never activates or
   switches apps. Any change of frontmost app stops the batch. There is no foreground
   fallback.
4. **Stage 1, no game effect:** run `--dry-run` once and hold Escape. This proves the
   emergency stop is readable from this launch context before anything reaches WoW.
5. **Stage 2, permitted input:** one `--execute` run of the six pulses above: 0.9 s total
   hold, one key at a time. No retries, longer pulses, compound turns, auto-run, mouse,
   clicks, combat, interaction, purchases or quests. The only other input allowed is
   `--release` key-ups for recovery.
6. **Stop:** the automatic rules in the Safety design section, plus the owner's
   Escape/Ctrl-C. Any misrouted input, unclear release or unexpected state ends the M0
   attempt; do not re-run without new approval.
7. **Privacy:** window-only capture with audio off and the cursor hidden. Evidence stays
   local and uncommitted. Share only a reviewed capsule: manifest, labels and a few frames.
8. **Recovery:** release happens automatically at the deadline, and Escape/Ctrl-C also
   release. Use `--release` after a kill. Record any human repositioning in
   `labels.json`; there are no automatic inverse moves.
9. **Post-condition:** WoW is still in the background with the character stationary,
   bindings and camera unchanged, and the run directory present with `outcome`
   recorded. Report dispatch, visual effect and labelled avatar movement separately.
   Six probes can expose a blocker. They cannot establish an error rate, leak-free
   operation or navigation reliability.

Runtime model/API calls: zero. Blizzard's EULA restricts unauthorised automation (see
the parent README). The owner's approval covers this Mac action only, not service
permission.
