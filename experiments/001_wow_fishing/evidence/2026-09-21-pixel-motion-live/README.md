# Pixel-motion live Test A — failed acceptance

Tested commit: `98bd6a6ab0544cd7aa9ea24e340ef3e3f6f05c6e`.
All source hashes in `summary.json` match this checkout. No code changed during
the run. No Jev requests. Targeted input; all recorded focus observations were
background. Pre-go ran once in the recorded autonomous attempt.

Result: 4/7 verified loot cycles in 147.99 seconds. The runner stopped after
three consecutive failures. This is not five-minute acceptance or 100% accuracy.
The first four completed through an observed auto-loot window transition. Cycle 5
timed out, cycle 6 lost its acquired target, cycle 7 timed out. There were no
unverified retrieval clicks in this attempt; this does not establish that bites
were never missed.

Before this attempt, a separate pre-go failed to dismiss the beta Lua dialog.
An agent closed the dialog through Computer Use, then closed the character sheet,
and restarted the unchanged runner. That intervention is outside the timed run;
it is recorded here so the overall session is not mistaken for wholly autonomous
preparation from the original state. Earlier failure logs are included.

## Directly established acquisition failure

Cycle 6 logged target `(198.55, 143.36)` in the 1062 x 338 capture. In the saved
`cycle-06-acquired.jpg`, that position is on the left bank/rock region, while the
visible float is around `(590, 167)`. Thus acquisition selected scenery before
tracking failed. The event name `post_cast_visible_float_verified` overstates what
the current changed-component detector actually establishes.

Cycles 5 and 7 had tracking gaps late in the cast and no accepted bite. Their
sparse retained stills do not establish the exact bite time or whether a splash
caused matching to fail. Do not classify these as harmless no-bite casts or invent
an image sequence that was not captured.

## Simplification priority

The immediate issue is an incorrect observation contract, not too few recovery
branches. A persistent changed component is not proof of a float. The next useful
work is a small offline acquisition check against the included before/acquired
pairs, including the false scenery selection, then replacing the false-positive
selection rule. Do not append location-specific exclusions for this rock, widen
retry counts, or restore the tracking-gap-as-bite shortcut. Investigate whether
Vision plus pixel tracking is redundant once acquisition is reliable. Removing
area/gap fields from policy payloads is also possible now their former physical
meaning has been withdrawn, but was not mixed into this live run.

A single helper snapshot during tracking showed 9.8% CPU and 95,440 KiB RSS. This
is not an average or peak and excludes WoW/WindowServer. Full-screen recordings
are not included; evidence is limited to logs and small playfield captures.
