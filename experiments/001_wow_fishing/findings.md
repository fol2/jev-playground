# Initial observations

Current position: the candidate passes offline regression checks and completed a
ten-minute live Test A at **26/30 verified cycles**, which is **not** a strict pass
(`perfect_run: false`). See the [ten-minute run](evidence/2026-09-21-test-a-600s/README.md)
and the final entry below. Earlier incomplete and failed stages are retained as
history and belong to their own recorded sources. No live Jev Test B has been
performed against this source.

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


## Test B preparation and shared inventory correction (20 September, later session)

Test B now asks Jev to choose equipment and action-bar preparation as well as
WAIT/REEL/ABSTAIN during fishing. It keeps the same capture, tracking, input and
loot checks. The requested target remains one pre-go followed by a perfect
five-minute background interval.

The first pre-go (`test_b_20260920T215409Z_b591e9`) used one Jev request. From
the equipped weapon tooltip it selected EQUIP_ROD (0.99 probability), but the
old fixed bag slot no longer held the rod. No cast occurred. The call took
1.061 seconds and reported 478 input / 48 output tokens.

The shared pre-go now tries the previous slot, then searches a bounded default
10-column, five-row combined-bag grid by hovering and reading tooltips. This
serves both policies. Test A `test_a_20260920T215646Z_816a91` found the rod at
window-relative (0.8641, 0.824), equipped it, verified equipment and selected
page 2 in 26.4 seconds. This proves movement between bag slots is handled in
the calibrated layout; it does not prove arbitrary bag/window rearrangement.

That run then failed three float acquisitions. Saved frames showed the actual
float around crop (340, 62), above the previous water corridor. The current
view needed window-relative y 0.17–0.40 instead of 0.25–0.40. The x range remains
0.42–0.62. This is an explicit scene calibration, not automatic water recognition.

The next trial (`test_a_20260920T215838Z_96121e`) collected one fish, then stopped
at 47.02 seconds on an unverified retrieval. The trace showed a real dip and
return, but the last two accepted recovery observations moved from y 50.14 to
52.3913. Input dispatch took approximately 0.222 seconds. A moving target at
dispatch is the leading explanation; the evidence alone cannot exclude a dropped
input. The shared recovery check now also requires less than one crop-pixel
movement between observations, for two consecutive accepted frames. A regression
using that trace failed before this change and passed afterwards.

### First live comparison

The subsequent rules trial `test_a_20260920T220144Z_3e9c7d` completed 315.20
seconds with one pre-go and 14/16 verified loot cycles. One cast failed the
single-frame channel confirmation; its saved JPEG visibly contains the fishing
bar and an independent OCR read returned 釣魚. Another cast timed out. Neither
failure is excluded. This changed-scene result is not the earlier 15/15 result.
A possible bounded multi-frame confirmation improvement was identified but
deferred to keep the shared executor unchanged during this comparison.

A foreground-start attempt (`test_b_20260920T220800Z_fd4386`) correctly stopped
before pre-go or provider calls because WoW was foreground. Chrome was then
raised before the next background test. No blocked app was operated.

Test B `test_b_20260920T220921Z_5ad174` completed its whole preparation in 28.99
seconds: EQUIP_ROD, EQUIP, PAGE_TWO and READY. The rod was found in its moved
bag slot. Its first cast falsely reeled after ordinary upward movement, and the
run stopped at 7.60 seconds with no loot. Six calls were made, including four
pre-go decisions. This demonstrates preparation, not successful autonomous fishing.

The false-positive sequence moved upwards by approximately 1.29 pixels without
a tracking gap, but Jev chose REEL with probability 0.75. Re-expressing coordinates
as relative displacements still yielded 0.74; adding an English description of
direction and scale also yielded 0.74. The same described representation gave
WAIT 0.97 for a quiet sample and REEL 0.93 for an observed bite. These six
fixture requests are development probes, not held-out accuracy estimates. Their
inputs and responses remain in `jev_relative_fixture_check` and
`jev_described_fixture_check` under the local run directory.

The live policy now abstains from REEL unless its probability is at least 0.90.
This threshold separates the observed development examples; it needs fresh live
evaluation. No Test A verdict or `fish_has_bitten` label is supplied to Jev. The
shared tracker and actuator were not changed for this prompt/threshold revision.

The 0.90 live trial (`test_b_20260920T221302Z_b757f6`) stopped after 73.57
seconds: one catch, one timeout and two acquisition failures, with 36 provider
requests. The missed bite produced REEL 0.86. The first acquisition failure
placed the new float within 15 crop pixels of the previous float retained in the
pre-cast background reference; the second placed it beyond the right edge of the
water corridor. Both were visible in the saved images.

Shared corrections before the next comparison:

- Sample the static-scene reference 150 ms after casting, after the old float
  clears and before the new one lands. Retain this frame as `cast-clear.jpg`.
- Extend the calibrated corridor's right edge to window x 0.67.
- Re-read a failed channel confirmation up to twice, 200 ms apart, without
  issuing another cast key.

Test B's pilot threshold became 0.85. Broad change scheduling now wakes at more
than 1.5 pixels of vertical displacement, a tracking gap, or 50% area variation,
plus quiet-state checks every four seconds. This remains broader than A's bite
predicate. It reduces requests for ordinary bobbing; it is not a guarantee that
the model sees the peak frame when another request is in flight.

### Completed Test B result and final comparison limit

`test_b_20260920T221605Z_d778c1` completed **314.11 seconds**, one background
pre-go, **16/17 verified loot cycles (94.1%)**, with no human game input during
the timed interval. Its first cast timed out; the remaining 16 caught fish.
The missed sequence reached a 9.93-pixel downward displacement. A request was
already in flight at the peak; the following sequence was judged REEL 0.80,
below the fixed 0.85 execution threshold. Both sampling and the threshold are
relevant. The threshold was not changed during the trial.

There were **79 requests and 79 responses**, **57,548 input / 3,258 output tokens**;
request p50 was **0.286 seconds**, p95 **0.712 seconds** (nearest rank). Local
evidence occupied **5,138,912 bytes (4.90 MiB)** before verification metadata.
No videos were recorded. All 16 successful cycles had one cast, one retrieval,
a recognised fish label and a cleared loot window. The final image pair was
also visually inspected. This does not measure inventory contents directly.

This completed run started with the rod and page 2 already selected; pre-go
checked and retained that setup. The full main-weapon/page-1 transition was
proved in the earlier 28.99-second Jev pre-go, not combined with this successful
five-minute interval. That distinction must remain explicit.

The final same-source Test A (`test_a_20260920T222202Z_53f2ee`) successfully
searched the moved rod slot, equipped it and selected page 2. It then caught
10 consecutive fish, timed out once and failed two channel confirmations,
stopping at **236.26 seconds, 10/13 cycles**. WoW was subsequently observed at
the login screen. The exact cause/timing of the game session ending is not
established, so none of those failures is reclassified or excluded. This is
**not** a completed five-minute comparison. A user login is needed to repeat it.

Structural verification files were written for both runs and all recorded source
hashes matched at verification time. The experiment does not yet demonstrate
100% Test B parity or a controlled improvement over A. Live trials are sequential,
not identical bite sequences, and the earlier 15/15 A result used a different view.

Across Test B development plus the completed run, recorded usage totals
**128 requests, 91,488 input / 5,284 output tokens**. These are TypeSafe usage
figures, excluding this coding agent's tokens and provider billing adjustments.

A final code review found that consuming a non-actionable Jev reply could reuse
its older reference for the next request's relative coordinates. A small fix now
retains the fresh reference unless that reply is actually accepted as REEL. This
post-run correction compiles and passes offline checks, but needs a new live B
run after login; the 16/17 result describes the recorded pre-correction source.

## Image-first rod location after re-login

The user requested direct image recognition rather than hovering every slot.
Both policies now compare the known rod icon against 50 slot patches from one
bag screenshot. Each patch is reduced to a normalised 16-by-16 greyscale vector;
the highest correlation above 0.75 supplies a candidate coordinate. Tooltip OCR
still confirms the candidate before equipping. Weak/missing matches retain the
bounded tooltip search as a fallback. This uses native CoreGraphics, no package
or provider request, and a 32-by-32 reference `rod-icon.png`. It recognises this
rod's icon in the calibrated layout, not arbitrary fishing equipment or bag UI.

The reference was cropped from the locally retained, tooltip-verified bag image
`live_1789942922_9FF647/bag-rod.jpg`. Before testing, the rod was deliberately moved
from the previous (0.8641, 0.8240) slot to (0.9626, 0.8590), with the main weapon
equipped and action-bar page 1 selected. The first image-first pre-go
(`test_a_20260920T224437Z_9b02e7`) found the new position at correlation 0.8520,
confirmed the tooltip, equipped the rod and selected page 2 in **8.96 seconds**,
without a fallback scan. Earlier grid-scanning preparation took approximately
26 seconds. This is an observed preparation comparison, not a benchmark average.

That run was interrupted after two acquisition-related timeouts (66.18 seconds):
the re-login camera included a warm shoreline component that the tracker acquired
instead of the real float. The view was calibrated before the next trial, never
during an accepted timed interval. A preceding stale-binary launch
(`test_a_20260920T224311Z_d4bfe3`) was interrupted at 15.11 seconds after the new
Swift build failed; it is explicitly excluded from implementation proof. The
compiler issue was then corrected and the build passed before further trials.

The next image-first trial (`test_a_20260920T224644Z_f26fbc`) completed nine
verified catches, then stopped at 236.72 seconds on `retrieval_unverified`. Its
`live_1789944627_3F2848/after.jpg` actually shows the loot window and a fresh-fish
item. Re-reading the JPEG with Vision returned both 物品 and 新鮮美味小魚. The
original first-frame OCR therefore failed to confirm a visibly successful
retrieval; the run remains failed rather than being relabelled as ten catches.
The shared loot confirmation now retries capture/OCR at most twice, 250 ms apart,
without clicking again. It retains the initial failed image when retrying.

Before a further trial, the view was observed facing another direction and the
loot window had disappeared. The user was asked whether this was manual input;
no cause is assumed. The loot-confirmation change passes the native build and
offline tests but awaits a new controlled live interval.

## Colour-independent acquisition, collection and focus policy

The colour/feather prototype could recognise some changed views but failed on a
new cliff-side scene whose visible float did not contain the required red cue.
The current acquisition instead compares a post-cast reference with subsequent
frames, removes thin lines/noise with a 3-by-3 opening, and finds compact regions
whose local edge detail has increased. Candidate tracks must persist; a clear
novelty margin separates the leading stable object from competing detections.
The lower half of the changed object anchors the floating body. Native Vision
tracks a 160-pixel patch after acquisition. This replaces the colour requirement
and fixed landing corridor; it does not establish universal scene recognition.
Before/after fixtures cover the previously split float and the no-red cliff float.

Strong detected camera motion discards pending decisions and waits for stable
frames before requesting a fresh cast. It does not assign the identity of the
old float to a guessed object in a changed view. A controlled positive live test
of this recovery path remains open. Earlier exploratory camera calibration also
included four D key presses by the agent; those attempts are not treated as
controlled camera-only comparisons. Camera direction and character heading are
separate, and later setup avoids character-heading changes.

The user confirmed auto-loot is enabled and no manual looting was performed.
Collection now observes the early appearance/closure transition instead of waiting
800 ms before first looking. Persistent loot windows are handled by a close-button
visual and item-row rectangles. Item names, languages and classes never gate the
clicks; OCR is optional metadata. A text-masked loot fixture still exposes the
same item control, and a non-window fixture is rejected. Empty automatic-collection
label metadata is allowed. These are UI transitions, not direct inventory reads.

The sixth cast of `test_a_20260920T235907Z_ff10f4` is a confirmed false-positive
reel, not an auto-loot logging miss: the user observed no bite and the saved game
message also reports no fish on the hook. The exact gradual-dip sequence failed
the old rule's regression check. The rule now requires an abrupt single-step
drop as well as cumulative displacement. The old genuine-bite fixtures still pass.
On this development negative, Jev chose raw REEL 0.76, which the existing 0.85
execution threshold rejects; this is an abstention success, not a correct raw
classification. Its single fixture request used 731 input / 42 output tokens.
The user's annotation is retained beside that run's summary.

At the user's final preference, app-targeted input now preserves the user's focus
choice and continues if they bring WoW forward to watch. No route activates WoW.
Focus changes are recorded, and foreground observations are reported explicitly
instead of being labelled fully background. Gameplay/window changes and genuine
execution uncertainty retain their own stop conditions. Unknown item names do not.

Before this focus adjustment, `test_a_20260921T004056Z_fd863b` stopped at 85.15
seconds with 2/5 verified cycles (timeout, recovery failure and target loss). The
following B attempt `test_b_20260921T004331Z_0501ca` made no cast or provider call
because the old strict foreground check blocked it. These are unsuccessful
comparison attempts, not passes. The first adjusted-focus attempt
`test_a_20260921T004844Z_8725e9` stopped on a transient world-refresh notice before
casting. No failure has been removed from a run's denominator.

## Confirmed visual-contract regression

The [visual audit](visual-audit.md) establishes that the latest A false positive
was triggered by a one-frame confidence dropout, not a visually observed dip.
The retained gap-as-submersion alternative bypassed the abrupt-step condition.
The exact triggering trace failed the new regression test before the fix.
Gaps now invalidate pending decisions and restart stable-history collection;
Jev receives tracking-uncertainty wording rather than a fabricated disappearance.
No new live run was started during this audit. Other visual/policy reliability
issues remain, including the latest B false positive without a tracking gap.


## 21 September 2026: reliability corrections — offline proven only

Six corrections, each with an offline regression fixture or decision replay.
**No live Test A was run for any of them**, so none is an observed improvement.

### Motion peak disambiguation

The ambiguity check now compares only distinct local maxima on the correlation
surface, so the shoulder of one broad peak no longer counts as a competing object.
This makes abstention **less** likely, trading possible false negatives for possible
false positives. Four acquired/first-missing pairs from runs `live_1789999204_DEDF27`,
`live_1789999266_FDE8E6`, `live_1789999319_A6FA67` and `live_1789999396_5C9900` are
retained as fixtures with their source hashes, and are asserted to yield a downward
displacement of 5-11 pixels with `dx` within +/-2. Four pairs are not a rate.

### Template dropout and recovery windows

After a supported bite, a single lost template no longer discards the pending
decision. The original recovery deadline is retained and never extended, while
confirmations and the last accepted frame reset. Recovery windows may form from as
few as two observations; those short windows are never submitted to Jev, because
requests are gated while the loop is armed. The recorded trace
`dropout-observations.jsonl` comes from one real cast where a supported bite was
discarded after a single lost template; it replays to exactly one click after fresh
recovery. One trace is not evidence that dropouts are generally survivable.

### Acquisition filter and post-cast delay

Acquisition candidates must now satisfy the same 10-pixel template margin as the
matcher, so an edge distractor cannot become an untrackable acquisition. Post-cast
acquisition is delayed from 0.8 to 2 seconds to let the float materialise before
candidates are ranked against moving scenery. The six-second visible-target limit
is unchanged, so this shortens the available acquisition margin.

### Observation-based loot confirmation

Collection verification is now a bounded three-second observation: the loot window
must be seen, then absent for two consecutive frames. This replaces the fixed
eight-iteration loop and its single last-frame fallback. It is a stricter rule
than the one it replaces; that is a mechanism, not a measured error rate. The
capture path is unchanged and still crops from a full-window frame, because
`lootClose` matches a fixed-scale template and `lootLayout` uses absolute pixel
row bounds.

### Unconfirmed bite recovery

`stopped_bite_not_recovered` before any retrieval click is now recorded as
`target_unconfirmed` and may recast within the existing three-consecutive-failure
limit, like `stopped_no_visible_float` and `stopped_target_lost`. After a retrieval
click it stays terminal. It remains in the denominator, so acceptance is unchanged;
only the run no longer aborts. Its evidence must still be inspected on review.

### Camera restoration in pre-go

Pre-go restores the saved camera preset with the bound chord (Control+Option+F9),
having first read the local setup receipt and checked its `restore_key`. A missing
or unexpected receipt stops with `stopped_camera_setup_missing`. `stopped_after_camera_restore`
reports that the focus/geometry check failed after the chord was sent; **it does not
observe whether the camera actually moved**, and nothing here verifies the restored
view. The setup script still owns assigning, binding and saving.

### CI consolidation

`.github/workflows/fishing-offline.yml` is deleted and its work folded into the
single Focus Gate, now on `macos-14` because the fishing checks need `swiftc` and
the native image frameworks. `tools/fishing_offline.py` is the entry point and
`tools/sdlc.py` routes registered fishing source and evidence to it. See the
[change record](../../docs/changes/2026-09-21-fishing-gate-consolidation.md). CI
stays hosted, read-only and provider-free, and never runs on the owner's Mac.

## 21 September 2026: ten-minute live Test A — 26/30, not a strict pass

Run `test_a_20260921T163557Z_23b931` completed 602.19 autonomous seconds after one
pre-go, with **26/30 verified loot cycles**, zero unverified retrievals and zero
provider calls. Targeted input; all 31 focus observations were background. This is
the first live exercise of the same-day corrections above and the largest recorded
sample, but `perfect_run` is **false** and it is not an acceptance claim.

All 30 casts acquired a target and verified the channel. All 26 collections came
through the observed loot-window transition with no script click, so the manual
control fallback was never used. 26 clicks produced 26 collections: no false-positive
reel was observed in 30 casts, which is an absence, not a measured rate.

The dropout correction fired three times, in cycles 2, 4 and 9 — a supported bite,
a single lost template about 0.1 s later, restoration, then a click and a catch.
The previous code discarded the arm on that dropout and the already-dipped float
would not have re-armed a later window. `stopped_bite_not_recovered` never occurred,
so making it retryable remains untested live.

Two failures timed out without a bite inside the usual acquisition band. The other
two lost their target after acquiring at x 207 and x 308, y 165 and 177, well
outside the x 554-635, median y 76 band of all 26 successes. That is consistent
with the unresolved initial-object-identity problem, but two cases cannot separate
misacquisition from an unusual genuine landing, and no positional gate should be
added on one run's band. Details and the full failure table are in the
[run evidence](evidence/2026-09-21-test-a-600s/README.md).
