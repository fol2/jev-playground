# Ten-minute live Test A — completed, not a strict pass

Run `test_a_20260921T163557Z_23b931`, 21 September 2026, 16:35:57-16:46:05 UTC.
First live exercise of the same-day reliability corrections. Source was uncommitted
at run time; the 20 recorded `source_hashes` still match the working tree, and no
source changed during the run.

Result: **26/30 verified loot cycles in 602.19 seconds**, one pre-go, targeted
input, all 31 focus observations background, zero provider calls. `perfect_run` is
**false**: the playbook's strict pass requires every recorded cycle verified, and
four were not. This is the longest and largest-sample live attempt recorded, not
an acceptance claim, and one run does not establish general reliability.

## Cycles

| Outcome | Count |
| --- | --- |
| `loot_collected` | 26 |
| `timed_out_without_click` | 2 |
| `stopped_target_lost` (recorded `target_unconfirmed`) | 2 |

All 30 casts acquired a target and verified the fishing channel. Every one of the
26 collections completed through the observed loot-window transition with
`loot_clicks: 0`; the manual eight-control fallback was never entered. There were
26 retrieval clicks and 26 collections, so no false-positive reel and no
unverified retrieval was observed in this run. That is an absence in 30 casts,
not a measured false-positive rate.

## Dropout recovery fired three times

Cycles 2, 4 and 9 each recorded `bite_detected_waiting_for_return`, then a
single-frame `tracker_unavailable` invalidation roughly 0.1 s later, then
`tracking_restored_waiting_for_stable_history`, then a click and a collection:

| Cycle | Bite drop | Dropout | Click | Collected |
| --- | --- | --- | --- | --- |
| 2 | 5.39 px | 14.286 s | 15.442 s | 16.613 s |
| 4 | 10.72 px | 16.466 s | 17.531 s | 18.727 s |
| 9 | 5.30 px | 19.660 s | 20.822 s | 21.993 s |

Before the correction, `invalidate()` returned the loop to `watching` on that
dropout, discarding the armed bite. The float had already dipped, so no later
window would have re-armed it. These three catches are therefore attributable to
retaining the recovery deadline; the counterfactual outcome of each cast is
inferred, not observed.

15 dropouts occurred in total across the run. `stopped_bite_not_recovered` never
occurred, so the change making it retryable is still **untested live**.

## The four failures

| Cycle | Outcome | Dropouts | Acquired at |
| --- | --- | --- | --- |
| 5 | `timed_out_without_click` | 2 | (631, 120) |
| 12 | `timed_out_without_click` | 0 | (667, 58) |
| 15 | `stopped_target_lost` | 4 | (207, 165) |
| 24 | `stopped_target_lost` | 6 | (308, 177) |

None reached a retrieval click, so none is a false positive. Both timeouts
acquired inside the band used by successful cycles and simply saw no bite within
the 30-second cast.

All 26 collected cycles acquired within x 554-635, median y 76. Both lost-target
cycles acquired at x 207 and x 308, with y 165 and 177 — well outside that band
and lower in the playfield. This is consistent with acquiring something that was
not the float, which remains the unresolved initial-object-identity problem, but
two cases cannot distinguish misacquisition from an unusual but genuine landing.
**Do not add a positional gate on the strength of one run**; the band is an
observation from 26 samples in one calibrated view, not a validated constraint.

## Not established

No Test B ran, so no A/B comparison is available for this source. Auto-loot
remains a UI transition, not an inventory query. Nothing here verifies that the
acquired object was a float, and no claim is made about other views, window sizes
or UI scales.
