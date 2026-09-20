# Initial observations

Current acceptance: **the five-minute autonomous background Test A has passed**.
See the final acceptance entry below. Earlier incomplete/failed stages are retained
as history. No live Jev Test B has been performed.

## 20 September 2026: one assisted cast

- Environment: user-described "Forever" beta; Computer Use identified the
  `_classic_beta_` application. Exact build not collected.
- User authorised pressing `1` to cast and retained manual control of retrieval.
- One successful `1` key action was followed by six screenshots. The first showed
  the fishing channel and bobber; intermediate images showed waiting. The final
  image showed the bobber/channel gone and a new fish loot message.
- The bobber was approximately at (710, 225) in the 1366 x 768 returned image.
  These are screenshot coordinates, not calibrated desktop input coordinates.
- The splash/bite onset and user's right-click were not captured. Retrieval is
  supported by the changed game state, not a recorded input event.
- No agent right-click, Jev request or continuous video recording was performed.
  Images remain in the conversation; no local image/video dataset was saved.

This verifies that Computer Use can cast and inspect this game window. Sparse
screenshots missed the critical transition and cannot establish a bite detector.
For the next observation, a single short local recording around one cast would
provide better temporal evidence than repeated full-frame chat screenshots.

## 20 September 2026: first bounded recording

- Added `record.py`: Python standard library calling native `screencapture`.
  No installed dependencies, API calls, audio, automatic input or background loop.
- A one-second probe verified the capture region. The retained pilot is
  `data/001_wow_fishing/20260920T162733Z_00f93bdd.mov`, with a small JSON sidecar.
- Native desktop region: (960, 220, 680, 440). Recorded output: 680 x 440,
  H.264, 30.020 seconds, 12,625,806 bytes (12.04 MiB), no audio stream.
  Average frame rate is approximately 38.76 fps; use actual timestamps.
- Started recording, raised the game window and pressed `1` once. User handled
  retrieval. The bobber appears around 9 seconds into the recording.
- Sampling the 18–22 second interval at six frames per second shows a brief
  downward/disappearing movement around 20 seconds, followed by bobber movement
  and a loot window around 21 seconds. This is a candidate bite sequence, not a
  frame-accurate onset annotation or a verified detector.
- The pointer/interaction icon overlaps the target before retrieval, and the loot
  UI later covers part of the crop. These are visual confounders: do not let a
  future policy learn the user's cursor/click/loot response as advance bite evidence.

The pilot contains enough temporal material to begin a small offline feature
inspection. No further capture is needed before examining this clip. One cast
cannot establish accuracy or a useful comparison with Jev. No Jev calls were made.

Validation: dry-run, invalid rectangle and duration rejection, native one-second
probe, automatic completion of the 30-second recording, ffprobe stream inspection,
and two small contact sheets reviewed locally. The probe and temporary images were
removed after inspection; only the pilot and its metadata are retained locally.

## First offline A/B development check

Canonical comparison: `runs/001_wow_fishing/20260920T163410Z_b87a3ef3/`.
Video SHA-256: `6d8207c3519fa5f61ffbe0c267e58ebc859c7854e564b6367f243c9a0b550611`.
The run retains script identity, measured states, the exact question and raw responses.

| Clip time (seconds) | Rules A | Jev B | Request seconds |
| --- | --- | --- | --- |
| 8.1167 | ABSTAIN | ABSTAIN | 0.7785 |
| 12.0633 | WAIT | WAIT | 0.6423 |
| 19.5533 | WAIT | WAIT | 0.5324 |
| 20.0200 | REEL | ABSTAIN | 0.6048 |

At 20.0200, the mask contained 112 orange pixels with a centroid at y=300.36,
versus approximately 380 pixels near y=289 during preceding ordinary motion.
The rules first recommended REEL at 20.0200, with another raw recommendation at
20.1233; only the first counts as the per-cast recommendation. No input was executed.
Jev returned probabilities ABSTAIN=0.59, REEL=0.39, WAIT=0.02 at the bite candidate.
Its reported confidence was 0.39; this is not an empirical success rate.

No prompt tuning was performed to remove this disagreement. Four requests used
3,317 input and 168 output tokens, all served by `jev-1.13.0`. No retries occurred.
This clip has not demonstrated an advantage for Jev. It also cannot establish that
rules generalise better: the colour mask and thresholds were developed on this
same clip, and the cursor remains a confounder. Need fresh, separately labelled
casts with a manually located target before making an accuracy claim.

Resource check: replay without API calls took 3.03 seconds wall time, 2.68 seconds
user CPU and 0.18 seconds system CPU. macOS `time -l` reported maximum RSS of
42,909,696 bytes (40.9 MiB); this is not a measured simultaneous process-tree peak.
The canonical run occupies 44,647 bytes. No additional video or frame dataset was
generated. Four offline rule tests passed. Variable-frame-rate decoding explicitly
uses the source time base to avoid timestamp quantisation warnings.

## Live local script proof: 20 September 2026

The user corrected the acceptance order: prove the script can fish live before
resuming A/B work. Jev work is paused; no provider calls were made in this stage.
`live.swift` now performs one bounded attempt using screen pixels and native input.

| Local run suffix | Observed result |
| --- | --- |
| `1789922564_81E032` | Initial crop too short; a small candidate was lost, no right-click |
| `1789922643_6FC353` | Fresh Smallfish loot window after script right-click |
| `1789922709_9E0891` | Fresh Smallfish loot window after script right-click; fishing skill increased |
| `1789922790_01B718` | No stable target acquired; timed out without clicking |
| `1789922844_5325B7` | Acquired target, then stopped on stale capture; concurrent Computer Use screenshot was being taken |
| `1789922913_049A63` | Acquired target, then foreground changed to Chrome; stopped without clicking |
| `1789922948_9154AE` | Fresh Longjaw Mud Snapper loot window after script right-click, in the new viewing direction |

All paths are under `runs/001_wow_fishing/live_<suffix>/`. The three successful
`after.jpg` images were independently inspected after the script exited. Each log
contains exactly one cast and one right-click. The successful script did not depend
on the assistant watching frames or choosing the moment to click. It detected new
targets at different positions. Loot was visible, but collecting it into the bag
was not automated or counted as script proof.

These are three successes across seven live development attempts, **not** a 100%
success rate. The user confirmed manually changing the camera during testing;
the exact time of the change was not recorded, so do not assign every miss to it.
The stale-capture stop coincided with external screenshot activity; causation was
not separately established. Foreground switching was directly recorded as Chrome.

The initial small crop and hidden-window selection were corrected before the first
success. The same detection/decision logic produced all three successful catches;
only the final proof image format changed from PNG to JPEG before the third.
Current source SHA-256:
`65622581d6a543e2f5521f003513fcdeb2f0def41305cd5cf53092cc0c2efe6c`.

One successful measured run took 21.43 seconds wall time, 0.79 seconds user CPU and
0.40 seconds system CPU. Reported maximum RSS was 48,447,488 bytes (46.2 MiB).
These numbers describe the helper, not the game's or WindowServer's resource use.
Successful evidence folders occupy 1.58–1.69 MiB after JPEG conversion; there is no
live video recording. Cropped frames are processed at up to 10 Hz, without a backlog.

Remaining limitations: fixed camera during each cast; scene-specific orange mask
and search region; no automatic loot collection; result verification still requires
image review. Native permission/focus/capture checks and real failed attempts were
exercised, but no claim of broad robustness or unattended reliability is made.
Before resuming Jev comparisons, keep the baseline frozen and measure additional
controlled attempts, recording every miss and external interruption.

## Pre-go and background continuation

Added local OCR checks for the rod and Fishing tooltip, a visually calibrated
14 x 13 page-2 reference, the Fishing channel check, and a six-second float-acquisition
deadline. The beta character sheet produces a stock UI Lua error; the script does
not fix that game bug. It checks for and dismisses the known dialog in foreground
mode, and stops when it cannot do so. No error-display setting was disabled.

Live records exposed two decision gaps: bite onset could invalidate its own
stability window, and a smaller bobber could briefly disappear below the colour
mask threshold. Measured traces were turned into failing checks before the fixes.
`--self-test` now runs ten offline decision assertions. The rule uses an earlier
stable reference, a size-relative downward threshold, or a short disappearance
followed by a nearby visible return under stable background motion. These remain
provisional scene-specific rules, not proven general accuracy.

The capture loop now uses a bounded native SCStream, retaining one latest frame
with a three-surface capture queue at up to 10 Hz. Stale frames are discarded rather
than applied. No video or model request is made by the live script.

Foreground development runs retained for audit:

| Run suffix | Result |
| --- | --- |
| `1789923995_3A8353` | Pre-go passed; bite onset was vetoed by the stability window |
| `1789924193_1CC824` | Fish loot window after corrected onset handling |
| `1789924317_6E8B7D` | Smaller bobber movement below the fixed pixel threshold; no click |
| `1789924490_A5EDA2` | No click; world-refresh notification appeared during the attempt |
| `1789924708_44A97B` | Stopped on a stale screenshot before native streaming was introduced |
| `1789924876_A09AB4` | Native streaming exposed two missing frames, then a return; no click |
| `1789925142_83EE2E` | Full foreground pre-go, cast, tracking and retrieval; Fresh Longjaw Mud Snapper loot and skill 81 visible |

The last run took 26.50 seconds including pre-go and occupied 2,796,390 bytes.
This remains foreground evidence. Measured pre-go/OCR runs peaked around 154–171 MiB
reported RSS; earlier approximately 46 MiB figures excluded the added OCR work.
Pre-go latency varied with system load, approximately 6–23 seconds in development.

Background evidence:

- `background_1789925737`: one process-targeted `1` key. Before: no Fishing channel.
  After: Fishing channel visible. TextEdit stayed foreground, its known test document
  was unchanged, and the pointer stayed in place. No mouse event was sent.
- `background_1789925914`, `background_1789926064`, `background_1789926156`: full
  background attempts stopped in pre-go on the Lua overlay. No retrieval click was
  sent. The control document, pointer and foreground checks remained unchanged.
- Process-targeted mouse events, including window/click metadata and a window-addressed
  NSEvent probe, did not close the known Lua dialog. This proves failure of the tested
  methods here, not impossibility of all background interaction.
- Sending Escape in the background closed the character sheet but left the Lua
  dialog visible. The key path and mouse path have different observed behaviour.

Next decision: whether one-off foreground configuration is acceptable. A native
interaction key may offer a keyboard-only retrieval path; it has not been configured
or verified in this beta. Live Test B remains paused until background Test A works.

## Computer Use as a working background reference

The user clarified that **all pre-go/configuration must also stay in the background**;
one-off foreground preparation is not acceptable. This supersedes the proposed
foreground-setup option above. The native test helper no longer activates TextEdit.

Official [Computer Use documentation](https://learn.chatgpt.com/docs/computer-use)
and the [desktop use case](https://learn.chatgpt.com/use-cases/use-your-computer-with-codex)
explicitly describe macOS background operation. The pages inspected do not supply
the native mouse-injection implementation or a documented Swift interface to it.

A direct comparison used Computer Use's app-scoped coordinate click to close the
same Lua dialog that the standalone process-targeted mouse attempts could not close.
No `Raise` call was made. The dialog disappeared in the resulting screenshot.
An independent 20-second monitor sampled foreground identity and pointer position
1,630 times, with a nominal 10 ms interval. WoW PID 38506 was never observed in the
foreground; pointer displacement was zero. Foreground changed from Ghostty to
UserNotificationCenter, so this does **not** prove the foreground app never changed,
nor does sampling exclude shorter unobserved transitions. Evidence is retained at
`runs/001_wow_fishing/cua_reference/result.json`.

Conclusion: Computer Use is a useful working actuator reference for this client;
failure of our direct CoreGraphics route does not establish that background mouse
operation is impossible. Do not inspect unsupported private runtime interfaces or
claim Computer Use is directly reusable by the standalone script without a supported
integration. Test A remains incomplete; live Test B remains unstarted.

## Correction: public standalone background drivers exist

A broader primary-source search found reusable implementations. The earlier lack
of a documented OpenAI-native embedding interface must not be read as absence of
standalone solutions or a requirement to keep an LLM in the control loop.

- [Cua Driver](https://github.com/trycua/cua/tree/main/libs/cua-driver) documents CLI,
  Python and TypeScript integration, including direct in-process native SDK use.
- [BackgroundComputerUse](https://github.com/actuallyepic/background-computer-use)
  provides a local HTTP API and a direct Swift library product. Its MIT licence
  permits reuse with attribution; its Package.swift declares no external package
  dependencies. It is a candidate for the current Swift helper, not yet tested here.
- [osaurus-macos-use](https://github.com/osaurus-ai/osaurus-macos-use) publishes a
  Swift background-input implementation using the Cua/SkyLight approach.

The [Cua implementation article](https://github.com/trycua/cua/blob/main/blog/inside-macos-window-internals.md)
describes a different macOS event route from our public CoreGraphics attempts.
It also explicitly warns that some game/canvas paths used foreground fallback.
The [current action ledger](https://github.com/trycua/cua/blob/main/libs/cua-driver/docs/action-support.md)
provides tested desktop/framework coverage, not proof for this WoW beta.

Next gate: inspect the chosen driver's licence and input/focus paths, then test one
background UI click on WoW with focus/cursor monitoring. No foreground fallback is
acceptable. No candidate has been installed or run yet; no claim of WoW support
or measured resource savings has been made. Standalone driver calls themselves
need no LLM inference, so the script-only Test A remains a viable direction.

## Bounded open-source transport test: successful background left click

Audited and copied only two unmodified MIT-licensed input files from
`actuallyepic/background-computer-use` at
`52116acfe0f2f57174f5e0166881abe944cb6eeb`; no full repository installation, service,
signing bootstrap or Keychain modification was performed. Reproduction and licence
are in [the small probe directory](probes/background-click/README.md).

Run `runs/001_wow_fishing/opensource_1789928366/` successfully closed the known Lua
dialog. OCR changed from present to absent, and the after image was independently
inspected. Chrome stayed foreground before/after and the pointer was unchanged.
A concurrent monitor recorded 1,647 samples, only Chrome PID 42672, and zero pointer
movement. This is sampled evidence, not a proof against arbitrarily short transitions.

The source bundle is 29,161 bytes and the compiled probe is 165,496 bytes. Capture,
OCR and dispatch together took 19.05 seconds; user/system CPU was 2.27/0.41 seconds,
with maximum reported RSS of 120,733,696 bytes. Retained evidence is 1,430,239 bytes.
No model calls occurred. These are probe measurements, not isolated input latency.

The upstream transport explicitly implements left clicks only. Background right
click and full Test A remain unverified. This bounded positive result justifies
investigating that next missing capability without adopting an entire agent stack.

## Five-minute autonomous Test A acceptance

The user subsequently set the concrete acceptance gate: one pre-go, then five
minutes of autonomous operation. Background remained preferred; foreground fallback
was explicitly authorised if necessary. No foreground fallback was used in the
successful run.

**Accepted run:** `test_a_20260920T190124Z_ee0ffe`, stored under
`runs/001_wow_fishing/`. `summary.json` records every cycle and `verification.json`
records the independent log/hash checks.

| Measure | Observed result |
| --- | --- |
| Autonomous duration after pre-go | 306.39 seconds; finished the in-flight cast |
| Pre-go invocations/passes | 1 / 1 |
| Casts | 14 |
| Retrieval clicks | 10 |
| Verified item-selection and loot-window-clearing cycles | 9 |
| Timeouts without retrieval | 4 |
| Retrieval with no verified loot window | 1 |
| Model/provider calls | 0 |
| Foreground fallback / manual game intervention during the timed interval | None |
| Source hashes after run | All recorded hashes unchanged |
| Run, cycle and pre-go evidence | Approximately 3.92 MiB; no video |

The first and final collection image pairs were independently inspected; the
loot-window disappearance agreed with the logs. Every cycle had exactly one cast
and at most one retrieval click. No cycle repeated pre-go. No live helper or runner
process remained after completion. This meets the user-defined autonomy gate;
9/14 collection outcomes are not evidence of perfect bite detection or broad
generalisation. Collection is a UI observation, not a direct inventory count.

Before the accepted interval, an earlier 21.6-second trial stopped after three
off-crop targets. Full-frame inspection showed the camera was pointed too far down.
A process-targeted End key selected a usable camera view before restarting the test.
The colour mask was also corrected using an actual visible-float miss: warm/yellow
pixels remained visible while the old orange-only mask fell below its area threshold.
The native channel check now combines a green progress bar with the fishing label,
including the observed Vision misreading of 釣魚 as 鉤魚. None of these fixes or camera
adjustments happened inside the accepted five-minute interval.

`build.sh` reproduces the native binary and runs ten local regression checks.
`run_test_a.py --background` owns the bounded repeat loop and pre-go-once behaviour.
Both successful and failed development attempts remain distinct from this acceptance
result. Test B is still unstarted.

## Refinement: main weapon to rod and a perfect five-minute target

The next requested gate is stricter: begin with the normal main weapon and action
bar, prepare once in the background, then collect loot on every cast for at least
five minutes. A timeout or unverified retrieval is a failed cast, even if subsequent
casts work. `perfect_run` records this gate separately from autonomous completion.

Re-reading the earlier failed logs showed all four timeout targets clustered near
(335.5, 219.5) in the crop; visual evidence places that point on the fishing rod.
The unverified retrieval instead tracked a float far to the left among neighbouring
NPCs. The refinement rejects tall narrow components and limits new targets to the
visually calibrated water corridor (window x 0.42–0.62, y 0.25–0.40). This is an
explicit scene constraint, not general water recognition.

Pre-go now checks the known bag slot's tooltip before right-clicking the rod, then
reopens the character sheet and verifies the equipped item. It still verifies page
2 and Fishing in slot 1. The bag slot must remain unchanged; an unknown tooltip
stops preparation instead of equipping an arbitrary item.

Development run `test_a_20260920T205942Z_790f53` was interrupted after a verified
catch and two completed timeouts (another cast was in progress). A second character
sheet opening had reopened the beta Lua error; acquisition also selected a rock
above the water. Both were visible in retained images. The next revision dismisses
and verifies this second error and excludes the rock by the calibrated water bounds.
The aborted run is not a perfect or five-minute pass. Its old runner wrote a partial
summary without status after KeyboardInterrupt; interruption handling is now explicit.

Sixteen native checks cover decision behaviour and the added acquisition boundaries.
No packages, models or continuous video were added.

The next development run (`test_a_20260920T210225Z_4875b3`) collected twice,
then right-clicked a visibly dipping float without producing a loot window. Two
subsequent cycles failed and the run stopped at 45.9 seconds. The input dispatch
took about 0.23 seconds while the float was moving. This supports a moving-target
miss; it does not conclusively distinguish hit-testing from a dropped input.
The retained signal now waits for two visible observations near the float's
pre-dip position (within two seconds) before dispatch. Unverified retrieval now
stops the runner immediately for review.

**Successful refined run: `test_a_20260920T210535Z_2e9814`.**

- Start: visually verified Stained Ritual Dagger equipped and action-bar page 1.
- One background pre-go equipped the rod, verified its tooltip, closed both beta
  character-sheet errors and verified page 2 / Fishing in slot 1.
- Autonomous interval: **304.35 seconds**, 15 casts, 15 retrieval clicks and
  **15 verified fish-item selections followed by cleared loot windows**.
- Zero failed cycles, no foreground fallback, no human game input or model calls
  during the interval. Camera and code remained unchanged.
- All 15 cycle logs and their four principal evidence images were present; each
  had one cast, one reel click and no repeated pre-go. Source hashes, including
  the Python runner, matched after the run.
- Starting equipment/page evidence and first/final loot-image pairs were manually
  inspected in addition to the per-cycle OCR evidence.
- Complete successful run evidence: approximately **5.15 MiB**, no video.

`perfect_run: true` and the separate `verification.json` record this result.
This demonstrates the requested five-minute 100% trial in the calibrated scene;
it does not establish a universal success rate. Earlier failures are not erased
or combined into this run. Test B remains unstarted. The task's caffeinate process
was stopped afterwards; no runner or fishing helper remains active.
