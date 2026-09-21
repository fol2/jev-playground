# A smaller observation contract, not another recovery layer

Candidate based on `98bd6a6ab0544cd7aa9ea24e340ef3e3f6f05c6e` from
`experiment/test-b-parity`. The historical evidence and findings remain unchanged.
This is **not live fishing acceptance** and does not establish that Jev outperforms
rules. Full recordings and request-time B frames are not available in the repository.

## What the evidence supports

The retained regression snapshot records A at 2/3 verified cycles and B at 0/1;
B used 17 requests and reported 12,620 tokens. Views and historical source versions
differ, so these are failure investigations, not a controlled A/B result. Both
failed on misleading visual observations; a high model probability did not repair
that input. The four image pairs are development fixtures, not held-out validation.

Code inspection additionally found a chained position estimate plus a second
Vision search hint, a hard-coded 0.6-second sequence duration, menu decisions mixed
with the bite comparison, and no identity check protecting the asynchronous reply
slot against an older cancelled callback. The initial macOS-14 CI baseline also
failed to compile the mixed CGFloat/Double expression in the old Vision tracker.

## One path from pixels to permission

```text
One acquired float / fixed image anchor
    -> bounded normalised-correlation displacement
    -> seven real timestamped observations
    -> rules OR Jev (same observations, no A verdict sent to B)
    -> same-generation, fresh-response check
    -> two distinct recovered frames
    -> consume one click permission
```

`FloatTracker` no longer integrates frame-to-frame motion or asks a second tracker
for a new position. It matches a 20-pixel template against the fixed acquisition
patch. Ambiguous matches and peaks at the +/-12-pixel search boundary are rejected.
This removes an accumulating-drift mechanism; a distractor can still correlate,
and appearance changes or larger movement can cause abstention. It is deliberately
a short, fixed-view experiment, not a general object tracker.

`decision.swift` is a pure state machine, independent of macOS capture, network and
input. A tracker gap, capture gap over 0.25 seconds, out-of-order observation or
stale frame invalidates the history, request generation and pending action. It
requires a new one-second warm-up. The live adapter cancels outstanding work at
that boundary; the HTTP client also rejects completions with an obsolete call ID.

The model gets numeric rows `[time, dx, downward dy, match]` and background change.
Actual capture times replace the nominal duration. Static reference area is not
presented as changing visibility; duplicate English motion descriptions are gone.
`policy_observation` links each request to capture time and generation in the log.
The pinned model, request timeout, probability gate and total attempted-call budget
remain unchanged. No token or latency improvement is claimed without measurement.

## Changed versus preserved behaviour

Protocol `anchored-pixel-bite-only-v1` compares **bite decisions only**. Equipment,
page preparation, capture, input and collection verification are shared. Jev no
longer judges preparation menus. This removes both provider calls and a comparison
confound, but is a protocol change: do not pool old expanded B results with it.
Separate live casts are still not paired or randomised observations.

Strong background change now stops for review; there is no speculative reacquisition
or automatic recast after a native safety stop. The runner treats every `stopped_*`
outcome as terminal. It never changes camera direction or character heading.

Targeted input still does not activate WoW, including when the user voluntarily
watches the game in the foreground. The source-attributed input transport is
untouched. Default-layout equipment checks and both automatic/manual loot-window
verification remain; item labels are still optional metadata, not action gates.
There is no rules fallback after a provider error.

## Size and scope

The original repository contains 2,651 Swift/Python lines when diagnostic scripts,
probes and tests are included; that is not a 2,651-line bite algorithm. In particular,
the attributed background-input runtime itself is 570 lines and is retained.

The main native file falls from 1,119 to 841 lines. Of that change, 132 lines are
historical tests moved to `self_tests.swift`, not deleted functionality. A new
135-line pure observation/action core and regression tests make the boundaries
explicit. Counting all compiled Swift including those tests gives 1,359 lines
before and 1,362 after this change (excluding the unchanged input adapter).
This is a reduction in competing behaviours and untestable state, **not a claim
that splitting files made the total application dramatically smaller**. Further
large reductions would require dropping default-UI preparation, manual loot
fallback or background-input compatibility; this change does not silently remove
them just to hit a line-count target.

## Offline validation

```sh
# Linux or macOS, Swift installed; synthetic pixels, fake time and fake HTTP.
sh experiments/001_wow_fishing/test_core.sh
# Python standard library only; mocked subprocesses, no game or provider.
python3 -m unittest discover -s experiments/001_wow_fishing -p 'test_*.py' -v
# macOS only: build the real helper and run the retained image/decision fixtures.
sh experiments/001_wow_fishing/build.sh
```

The pure checks include stale/duplicate/future timestamps, tracking loss, reply
expiry, delayed cancellation callbacks, ambiguous matching, one-shot input,
provider schema/budget failures and measured sequence timing. Python checks cover
shared preparation, terminal safety stops and honest result accounting. The native
checks retain the positive/negative image pairs and loot/acquisition regressions.
CI builds and checks without a provider key, screen capture or input dispatch.

Next acceptance must use new, source-hashed recordings with matched scenes and
held-out complete casts, including failed acquisition and abstentions. Measure
false reels, missed bites, tracking failures and end-to-end response ages. Then
separately test native input timing and collection on the Mac. Passing these offline
checks does not prove successful catches or account-policy permission.
