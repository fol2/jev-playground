# Latest evidence interpretation

## Owner correction: possible occlusion, not proven scenery acquisition

The owner clarified that the problematic cast may place the float inside the rock,
where a human cannot see it either. Tracing the line and observing a hover cursor
could help locate it, but neither establishes a bite. The earlier definitive claim
that cycle 6 selected scenery instead of a visible float is withdrawn. The saved
stills do not establish ownership/visibility of the apparent float elsewhere.

The historical result remains 4/7 verified cycles in 147.99 seconds. Raw images,
logs and source hashes are unchanged. Record the failed target as unconfirmed;
do not retroactively count it as a successful or harmless cast.

## Agreed lightweight behaviour

When acquisition or tracking cannot supply a target before any retrieval click,
record `target_unconfirmed` and permit a fresh cast within the existing limit of
three consecutive failures. Never guess a retrieval position from the fishing
line. Camera/geometry, provider and input stops remain terminal. No heading changes,
cursor probing or new recovery subsystem are introduced.

The acquisition log now says `post_cast_target_candidate_observed`; the former
`post_cast_visible_float_verified` name overstated semantic object validation.
This wording and retry change do not prove that all incorrectly acquired objects
are rejected. Initial object identity and fixed-anchor appearance changes remain
unresolved, and offline tests are not live acceptance.
