# Visual regression audit — 21 September 2026

> Interpretation correction following owner feedback: the float may have been
> cast inside rock and visually occluded. The earlier definitive scenery-selection
> claim below is withdrawn; isolated stills cannot establish it. Treat the target
> as unconfirmed. Raw evidence and the 4/7 outcome remain unchanged.


The expanded visual pipeline is not an accepted replacement for the earlier
fixed-scene baseline. The observation contract has a locally tested correction with failed live validation recorded below. Passing local checks is not five-minute fishing acceptance.

## Confirmed regression: tracker dropout became a bite

Evidence: `runs/001_wow_fishing/live_1789951877_2A592F/`, cycle 3 of
`test_a_20260921T005018Z_bb3c07`.

- `FloatTracker.observe` returned no observation for one frame when the tracking
  request failed its confidence/validity gate.
- The next reliable sample arrived after 0.107 seconds and had only 0.299 pixels
  of displacement relative to the reference.
- The old `returnedAfterDip` alternative nevertheless selected REEL. It bypassed
  the newly added abrupt-step requirement.
- The float is visible in both `pre-signal.jpg` and `signal.jpg`. A simple red-feature
  measurement on these saved JPEGs moved vertically by about 0.24 pixels; this is
  corroborating image evidence, not a general-purpose bite detector.
- The game subsequently reported no fish on the hook.

The implementation confused **unavailable tracking** with **visually established
submersion**. These are different observations. The older colour-component detector
and the newer Vision tracker had different failure meanings, but the decision
interface retained the same `missing` fields and inference.

The exact triggering trace was added as a regression check. It failed before the
correction. Tracking gaps now abstain, invalidate pending actions/response references,
and require fresh stable history. Jev wording no longer describes a tracker gap
as the float disappearing. The old disappearance-only positive fixture is now a
negative under this corrected contract.

## Other issues remain

`area` changed from counted colour pixels to one quarter of a tracking rectangle's
area. The latter is a size estimate, not visible-pixel occupancy. Its calibration
and the old thresholds cannot be assumed equivalent across viewpoints.

The latest B failure (`live_1789952295_BBAD9E`, from
`test_b_20260921T005808Z_4ada86`) was different: the accepted request reported no
current tracking gap, 2.67 pixels of downward displacement and a largest downward
step of 2.32 pixels. Jev chose REEL with probability 0.92. The game reported no
fish on the hook. Removing the dropout inference alone does not establish that
this B error is fixed.

Jev receives structured tracker estimates and descriptions, not the screenshots.
An event detector still needs reliable visual evidence that separates ordinary
bobbing from a bite. Tracking confidence and model confidence are not that evidence.
The audit has not established a coordinate-axis/Retina conversion bug.

## Direction before further autonomous runs

Keep localisation/tracking, bite-event evidence and input verification distinct.
Use tracker output to locate the observation patch; do not turn tracking loss into
a physical event. Establish any bite-specific visual evidence on retained positive
and negative examples before reconnecting it to either policy. Small labelled
patch sequences are sufficient for these regressions; they do not replace live
acceptance. Retain the earlier baseline and all failed runs, and change one layer
at a time. No universal environmental support or five-minute parity is claimed.

## Pixel-motion correction and subsequent live failure

The current snapshot uses Vision for localisation and direct frame-to-frame image
correlation for displacement. The acquisition footprint is retained as reference
size only, and is no longer used as changing visible area or as the A bite threshold.
Four retained image pairs measure approximately 8, 4, 0 and 0 pixels of downward
motion for two successful and two failed retrieval examples. All four native
regressions pass, alongside the other local checks (32 native, 10 Python).
This does not establish live accuracy or the elimination of the B failure.

The [compact review evidence](evidence/2026-09-21-visual-regression/README.md)
contains logs, source hashes, small signal patches and a parallel-review hand-off.
The priority is to simplify the observation-to-action loop, not accumulate more
special cases. The monolithic controller remains a known maintenance problem.

## Subsequent live attempt on commit 98bd6a6

[Retained live evidence](evidence/2026-09-21-pixel-motion-live/README.md): 4/7 verified
loot cycles over 147.99 seconds; stopped after three consecutive failures. Cycle 6
acquired scenery at (198.55, 143.36), while the visible float was around (590, 167).
The acquisition event overclaims object identity: a persistent changed component
is not sufficient visual proof of a float. Cycles 5 and 7 timed out; retained stills
are insufficient to establish exact bite timing. The observer remains unaccepted.
No further recovery patches were added during or after this run.
