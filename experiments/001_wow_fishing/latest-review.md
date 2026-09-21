# Latest evidence integration

The base branch advanced during this refactor. Commit
`d97e269264ae90670123895dbfe90f9808755cb0` adds a live run of the original
`98bd6a6` observer: 4/7 verified cycles in 147.99 seconds, with a confirmed
scenery acquisition at approximately (198.55, 143.36), not the visible float
at approximately (590, 167). Its evidence tree and visual audit are preserved
byte-for-byte. The original experimental branch is not changed by this work.

This establishes an upstream limitation that fixed-anchor tracking alone cannot
repair. The current changed-component acquisition is still a candidate detector,
not proof of object identity. In particular the inherited log event
`post_cast_visible_float_verified` must not be interpreted as semantic validation.
The timestamped action core and stale-response repairs do not prove that this
acquisition failure is solved. Do not reconnect this candidate to unattended play
on the strength of green offline tests.

Before acceptance, exercise the newly retained before/acquired pairs offline,
including all failed casts. Prefer a general foreground/appearance check over
excluding the coordinates of this particular rock or increasing retry counts.
Full temporal acquisition cannot be replayed from isolated stills; the retained
logs and images set regression constraints, not a complete validation corpus.
