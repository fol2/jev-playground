# Test A reliability fixtures — offline only

Retained development images and one recorded observation trace, extracted while
correcting two failures seen in earlier live Test A attempts. They are **not**
held-out evaluation data and **not** a live result. No live run was performed for
any change they cover; the source they were taken against was uncommitted at the
time of writing, so no tested commit SHA is quoted here.

## Peak disambiguation pairs

`peak-fixtures.json` records four acquired/first-missing pairs, each with the run
it came from, the correlation-surface centre, the crop applied and the SHA-256 of
both original frames:

| Prefix | Run | Centre (x, y) |
| --- | --- | --- |
| `peak-1` | `live_1789999204_DEDF27` | 80.000, 45.500 |
| `peak-2` | `live_1789999266_FDE8E6` | 80.082, 74.721 |
| `peak-3` | `live_1789999319_A6FA67` | 80.308, 44.923 |
| `peak-4` | `live_1789999396_5C9900` | 80.500, 80.364 |

`self_tests.swift` asserts each pair yields a downward displacement of 5-11 pixels
with `dx` within +/-2. Before the change, the broad shoulder of the single true
match could be scored as a competing object, and the matcher abstained.

These four pairs constrain the change in the direction it was made. They do not
measure how often it is right. The change makes abstention **less** likely, so it
trades possible false negatives for possible false positives; nothing here bounds
the false-positive side.

## Dropout trace

`dropout-observations.jsonl` is the recorded observation sequence from one real
cast in which a supported bite was discarded after a single lost template.
Generation 0 samples end at 25.90 s, one `tracking_temporarily_unavailable` is
recorded at 26.00 s, and generation 1 samples resume at 27.15 s.

`CoreTests.swift` replays the trace through `FishingLoop` and asserts exactly one
click, taken only after two distinct fresh recovered frames. The replay needs no
capture, no sleeps and no provider, because the loop takes all its time from the
caller's monotonic clock.

One trace from one cast does not establish that dropouts are generally survivable,
that the discarded bite was genuine, or that holding the recovery deadline is safe
across scenes. It reproduces the specific failure and shows the corrected path.

## What none of this establishes

Passing these fixtures is not five-minute acceptance, not a catch rate, and not
evidence about any cast other than the ones recorded here. The initially acquired
object's identity remains unverified, as elsewhere in this experiment. A new
autonomous Test A is still required.
