# Bounded experience loop for Jev Hunt decisions

Base: `975d164e296e82c15d0aaa6b3776526f93a0c9bc`. This source-only slice adds
non-parametric adaptation to the opt-in Skyborne Hunt decision graph. It does not
run WoW, post OS input, call a provider, train model weights or promote a new tactic.

## Decision

Keep Jev stable and make experience the plastic layer. Native code records an
executed skill's coarse pre-action context and later observed outcome. On future
turns Jev sees only a small index and may explicitly choose `READ:experience` before
selecting a skill. Comparable cases include contrasting blocked/progress outcomes
and action counts; they are evidence, not causal rules or calibrated probabilities.

A separate `improve` graph node lets Jev attach one typed hypothesis/bookmark to the
latest matching episode: perception, movement, tactics, retain-example or unclear.
This branch sends no game input and returns to the Hunt root. It cannot edit code,
the graph, references or live policy. Human/LLM development may later inspect these
queued cases and propose ordinary reviewed changes.

This follows a common lifelong-agent separation without importing another framework:
Voyager uses environment feedback and a reusable skill library; Reflexion retains
trial feedback in episodic memory; ExpeL recalls experience-derived knowledge;
MemRL separates a stable reasoner from plastic episodic memory; and ProactAgent makes
retrieval an explicit policy action. Sources checked 24 September 2026:

- https://arxiv.org/abs/2305.16291
- https://arxiv.org/abs/2303.11366
- https://arxiv.org/abs/2308.10144
- https://arxiv.org/abs/2601.03192
- https://arxiv.org/abs/2604.20572

No external implementation was copied and no dependency was added.

## Implemented boundary

- `ExperienceStore` persists at most 256 cases under one explicit graph/profile
  scope. Duplicate IDs, incompatible scope and malformed records do not become
  additional trials. A persistence failure remains visible while in-memory evidence
  survives the process.
- Hunt derives exact coarse buckets from allowed observations: phase, health/mana,
  target kind, quest-area relation, nearby hostiles, blocked-heading presence,
  coarse zone-map cell and unfinished objective set.
- Executed Hunt skills are finalized against the next ordinary survey, avoiding an
  extra vision/model cycle. Missing or reordered post-action evidence stays unknown.
- `experience_index` is compact and always available when a store is enabled.
  Full `experience_recall` is hidden until Jev selects the graph resource.
- The `improve` branch offers only review tools not already applied to the latest
  matching case. Reviews remain labelled hypotheses.
- `--experience PATH` is opt-in for Hunt dry-run, simulated-provider and live modes.
  The selected graph ID is the store scope; the flat policy uses its own legacy scope.

## Proof and limits

Synthetic tests cover persistence, restart, exact-context isolation, contrasting
retrieval, uncertain outcomes, bounded retention, review deduplication, progressive
disclosure and an actual `runHunt` review/skill sequence. The native no-effect graph
rehearsal uses the same file twice so the second run exercises proactive recall.

This proves plumbing and evidence semantics, not self-improvement in task success.
No utility/Q-value learning, semantic retrieval, automatic skill creation, nested M3
combat memory, experience consolidation or policy promotion is implemented. Those
require held-out comparisons and a later source change, not a claim based on the
existence of stored episodes.
