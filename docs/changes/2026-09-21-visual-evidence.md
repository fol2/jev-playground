# Bounded fishing hardening and a visual-state skeleton

Inputs: current-main `94549ee2de14b5a755bc562b8239f4a849da3391` and preserved
experiment `eb6356385b5853ab61a00de31641051c0cb55c34`, which already includes it.
The topic starts from current main and incorporates that immutable experiment.
Target the existing experiment branch to avoid promoting all historical experiments
and shared recordings to main as a side effect. Extend the existing read-only Focus
Gate's PR base list to that branch; no duplicate workflow or feature-push gate.

## Evidence-led decision

The latest ten-minute A report records 26/30 collections in 602.19 seconds, not a
strict pass or a new result of this patch. Preserve the supported-bite dropout
recovery, recast bounds, camera setup, input transport and loot verification.
The owner correction in `latest-review.md` supersedes the earlier certain-scenery
interpretation. Existing recordings are development data, with explicit incomplete
clips and timing caveats; they do not justify a new coordinate blacklist.

Keep the current matcher and thresholds. Reserve its known bounded arrays, reject
non-finite/overflowing image arithmetic, and skip peak analysis after a conclusive
low-correlation/search-boundary rejection. A frozen copy of the exact previous
matcher verifies 160 deterministic translated/noisy/edge cases with matching
accept/abstain and numeric output, plus malformed/ambiguous-input assertions.
The retained native image regressions remain part of the gate.

Two more invasive alternatives (summed-area normalisation and a single-surface
rewrite) did not justify replacement in exploratory Linux synthetic timing. An
initial summed-area comparison measured about 1.02x and the single-surface centred
comparison about 0.96x relative to the old matcher. These noisy local microbenchmarks
are not game timings. Neither alternative was shipped. No speed, catch-rate or token
saving is claimed for the selected small hardening patch. The optional non-gating
`MotionChecks --benchmark` measures the actual selected candidate against its frozen
reference; it is not run repeatedly in CI and never asserts a speed threshold.

## Minimal new surface

`experiments/002_wow_visual/observations.py` is a small provider-free evidence
validator, not a recogniser, planner or actuator. It checks frame/session/geometry
metadata, freshness, finite bounded values and ROI provenance, preserving unknowns.
The new experiment README is the design skeleton; #4, #5 and #6 own subsequent
perception, Shaman shadow-policy and one-quest work. No second framework, server,
database, navigation subsystem or model is introduced.

Acceptance of this PR is source/contract proof only. Actual visual truth, calibration,
client profile, unseen-scene reliability, live latency and Jev advantage remain open.
The exact-head CI and disclosed author review belong in the PR, not a duplicated
claim of live acceptance. No Mac, capture, game, provider or input effects occurred.
