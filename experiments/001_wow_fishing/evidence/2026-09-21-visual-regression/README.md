# Visual regression investigation snapshot

This is a review hand-off, not an accepted fishing release. The snapshot includes
both failed live runs and a subsequent locally tested correction. Historical run
source hashes differ from the current code: do not treat those runs as tests of it.

## Reproduce local checks

```sh
sh experiments/001_wow_fishing/build.sh
python3 -m unittest discover -s experiments/001_wow_fishing -p 'test_*.py'
```

Both passed: 32 native checks and 10 Python tests. `local-checks.json` records source
hashes. These checks do not establish autonomous fishing accuracy.

## Retained evidence

- `a-summary.json`: 2 verified loot cycles out of 3, 65.47 seconds. The third cast
  incorrectly reeled after a one-frame tracker dropout; game feedback reported no fish.
- `b-summary.json`: 0 out of 1, 25.96 seconds, 17 provider requests, 12,620 tokens.
  Jev selected REEL at 0.92 probability on misleading tracker motion.
- `a-*.log` / `b-*.log`: complete preparation and cycle event logs, including B
  requests/responses. No API keys. Local workspace prefixes removed.
- `*-verification.json`: historical verification records, not current-source proof.
- `true-1-*` / `true-2-*`: small image patches around signals followed by observed
  collection. `false-a-*` / `false-b-*`: patches around failed retrieval signals.
  B patches are at action time, after API latency, not exact request-time frames.
- `../../motion-fixtures.png`: central 64-pixel crops of these four pairs, in the
  same order. Before is left, after right. Measured vertical translations are
  approximately 8, 4, 0, 0 pixels. These are development fixtures, not held-out data.

Full videos and full-screen captures remain local to avoid repository growth.
A and B views differed; these failures do not establish policy superiority.

## Current correction and unresolved questions

Vision localises a small patch; direct frame-to-frame normalised correlation now
supplies motion. Tracker loss means unavailable evidence, not submersion. Reference
object area is no longer treated as changing visible occupancy. A requires an
abrupt downward step; B receives pixel motion and match correlation. Match correlation
is appearance agreement, not a bite probability. This has not yet been tested live.

Review priorities: can the matcher follow water instead of the float, accumulate
drift, or reject a real splash? Are the hand-tuned bite thresholds justified across
scenes? Can acquisition, tracking and policy be reduced instead of adding more
recovery branches? `live.swift` alone is 1,119 lines; splitting files alone would
not reduce the accumulated complexity. Prefer deleting superseded paths and proving
one small observation-to-action loop before claiming environmental adaptability.

Latest operating preference: targeted input must not activate WoW; continue if the
user voluntarily watches it in the foreground. Auto-loot is enabled. Item labels
are optional metadata and must never gate collection. Camera angle is distinct
from character heading. Do not change the latter to repair a visual failure.

For parallel review, use a separate checkout/worktree. Run offline checks freely;
only one process should control the live game at a time.
