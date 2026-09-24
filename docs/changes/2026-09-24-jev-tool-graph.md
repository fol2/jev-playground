# Jev-selected tools and hierarchical decisions

Owner intent: Jev is the gameplay decision-maker, with mixed visual/state/reference
inputs and non-action outputs as well as composite skills. Human/LLM directions are
infrequent. Keep a small expandable skeleton; no new security/governance framework.
Base: `dd7c20b230f4212b23ae6b3b8184885e78eb2b49`.

## Delivered boundary

`runtime/DecisionGraph.swift` is a small in-process graph policy. A data catalogue
supplies nodes, children, skill IDs and reference descriptions. Jev selects READ,
ENTER, BACK or DO. `runHunt` consumes the terminal selection through the existing
executive and input owner. The real native CLI exposes opt-in `--graph PATH`; flat
Jev stays the baseline. The sample uses existing Hunt skills and the existing nested
M3 Jev fight, not a new general quest engine. Relevant local source sections are
loaded only into requested model contexts, with source qualifiers retained.

One shared named-Choice parser is extracted from the existing Fight parser, not a
second validation pipeline. No key, watchdog, decoder, tactical threshold, authority
or learning policy changes. A four-call decision/120-call Hunt-policy envelope
prevents unbounded tool loops; graph-mode Hunt disables hidden HTTP retry. These
limits exclude existing warm-up and nested Fight. Every actual graph request and
failed attempt is recorded; usage not returned by the provider remains unaccounted.

A session keeps its subgoal path/reference IDs across skills; memory snapshots are
refreshed from the next input, not reused as present facts. One decision chain uses
a frozen source observation, and the pre-existing executive reobserves before input.
No new live capture, provider call, game or OS-input action is run by this delivery.

## Proof and limitations

42 focused offline checks cover optional retrieval, causal input enrichment, fresh
snapshot memory, raw probability provenance, graph depth/backtracking/extension,
budget/errors, actual runHunt compound-skill dispatch and existing stale-input
rejection. Native graph dry-run is also selected by the existing motor proof lane.
Existing parser/consumer suites remain selected. The actual exact-head and introduced-
main CI results and review belong in the PR, not an invented result in this record.

The no-network demo uses canned choices and SimHunt's canned fight result. It can
exercise a graph without establishing Jev quality, autonomous success or lower cost.
No graph-enabled real Jev trial is claimed. The graph is opt-in because the new
question space changes policy behaviour and may cost more than a flat decision.

Full level 1-20 skills, team play, buffs/debuffs, general navigation, equipment and
profession integration are roadmap branches, not falsely selectable placeholders.
Legacy strategy restrictions remain in huntAdmissible; #23 still owns profile and
strategy/refinement consistency. The graph reads an explicitly unresolved reference,
not a promoted rotation. It does not complete #23's replay/live catalogue requirement.

The [runtime README](../../experiments/002_wow_visual/runtime/README.md) owns the
architecture entry point, executable graph and wider roadmap. Existing milestone
READMEs keep historical qualifications; no new AGENTS instructions are necessary.
No third-party code copied, packages added, database or service introduced. The
one-off read-only source export workflow is removed from the delivered tree.
