# Skyborne Shaman: scoped training and video-review curriculum

Status: research-backed curriculum and proposed fixtures, **not** an implemented
policy, new visual annotation set, trained weights or authorised live run.
Created 24 September 2026; pair with [the source review](review_20260924.md).

## First, fix the racial context

Primary reference: Blizzard Entertainment, *WoW: Forever Meet the New Skyborne*,
22 September 2026, [official race article](https://worldofwarcraft.blizzard.com/en-gb/news/24302071).
Cross-check: [official race/class article](https://worldofwarcraft.blizzard.com/en-us/news/24304075/erschafft-den-helden-der-ihr-sein-wollt-in-world-of-warcraft-forever).
Retrieved 24 September; these are published descriptions, not this character's
observed tooltip, buff state or an immutable beta-client build.

The relevant identity is Horde **Windshaper Skyborne / Shaman**, not Alliance
High Order. The race article describes Skysight as an Elemental Blessing granting
10% run speed, Walk on Air as a ten-second downward glide, and Elemental Insight
as 5% additional damage against Elementals. Its 100% health/mana-regeneration
increase belongs to High Order's Read Ley Line, not Windshaper. The starting
experience is described as levels 1-12.

Implications to test, not established tactics: check whether the speed blessing is
active before assuming a same-speed chase. Never use the Alliance racial to explain
this Shaman's regeneration. Do not treat a downward glide as flight or permission
to cross an unverified gap. Enemy family must be observed before applying an
Elemental-specific damage expectation. Keep unlocks, durations, stacking rules,
cooldowns and this character's learned spells unknown until separately supported.

## A state card that Jev can actually reason from

This is a proposed annotation shape, not a compatible replacement for HuntObs.
Every non-null observed field needs a frame/time/crop reference. Confidence should
be calibrated against labels; a model's confident prose is not calibration.

```json
{
  "schema_version": "proposal-1",
  "source": {"video_id": "hCXWhb2_CyQ", "decision_time_s": 1268},
  "observation": {"frame_sha256": null, "frame_age_ms": null, "valid": false},
  "context": {"game": "forever-beta", "build": null, "class": "shaman",
              "race": "windshaper_skyborne", "faction": "horde"},
  "activity": null,
  "player": {"level": null, "health_pct": null, "mana_pct": null,
             "in_combat": null, "skysight_active": null},
  "target": {"level": null, "family": null, "attacking_player": null,
             "counts_for_objective": null, "objective_match_evidence": null,
             "distance_band": null, "tag_ownership": null},
  "abilities": {"trained_and_usable": [], "inventory_verified": false},
  "navigation": {"landing_visible": null, "blocked_heading": null},
  "recent_actions": []
}
```

The example deliberately contains unknowns; its timestamp identifies an existing
annotation, not a newly reviewed frame. `valid: false` and an empty ability list
must not become a confident combat decision or proof that no abilities are trained.
Use a separate known/unknown flag or nullable list in the implemented schema.
An unreadable quest match is not a known non-match. Preserve the last verified
objective and report the current observation failure separately.

## Conditional tactics rather than universal rules

**Pull/finish.** For the narrow owner-demo context, bolt-then-melee is a candidate
baseline, not proof that every rank, level, enemy and mana state has the same cost.
Before a discretionary pull, check objective relevance, target difficulty, nearby
adds, current resources and usable recovery. Unknown target level should not be
silently treated as same-level. Body-pull is a contextual option, not the curriculum's
default merely because the streamer used it in a crowded starting area.

**Kite/escape.** Compare a no-speed-advantage case with otherwise matched cases
where a verified movement blessing or usable slow changes separation. Require a
safe path, fresh enemy distance and known ability availability; test melee enemies
separately from ranged/casters. Do not assume Earthbind is trained or deployable
from player level alone: verify the actual spell, resource and any required item.
No safe landing means glide is unavailable to the planner. These comparisons can
first be synthetic/offline; do not turn them into an unapproved live trial.

**Heal/recover.** Prefer a margin-based decision over an unexplained universal HP
percentage: incoming damage over cast/reaction latency, interruption exposure,
current mana, usable heal and escape options. Keep uncertainty explicit. Distinguish
recovery while travelling from stationary rest, and verified food/water from merely
pressing their hotkeys. Reobserve combat and resources after waiting for Jev.
A low-mana demonstration does not establish that a low-mana elite pull is safe.

**Task/UI.** Classify cinematics, guild browsing and discretionary camera flourishes
apart from accepting/turning in quests, training, buying supplies, repairing and
inventory management. The latter are core end-to-end skills. Shopping needs a
verified vendor, item identity, unit price, quantity, budget and inventory delta;
protect quest items and upgrades rather than learning an unconditional sell rule.

## How to turn an actual video into useful supervision

Choose a bounded, contiguous clip around one decision. Retain a full-resolution
pre-action frame and relevant tracker, target, player, buff and action-bar crops;
record timestamps, crop boxes, media/frame hashes and a source identifier. Redact
irrelevant player identity/chat in any published derivative. Raw third-party media
remains local and untracked. A title, thumbnail or subtitle is not a viewed action.

First label only evidence available before the action. Then inspect later frames
to label the observed action and outcome separately. State, candidate actions and
facts must not contain the human label, future tracker completion or a bar "about
to reset". Keep ambiguous spell identity, target level and objective credit unknown.
Review a small disagreement sample independently before scaling extraction.

Store human action, **acceptable alternatives**, unsafe actions and the reason for
each label. Lack of visibility can make a case unscorable for action accuracy;
retain it in the observation-failure metric instead of silently dropping it.
Freeze the labels and scenario set before evaluating changes. All episode #1 parts
have already informed this work, so none is a clean untouched test set. Use a new
contiguous episode/session, after scoped annotation review, for final holdout; never
randomly split adjacent frames across training and test.

For a facts experiment, compare baseline, one scoped fact and a small context-matched
fact set on identical frozen states/options. Separately compare old versus corrected
state with facts held constant. Record all paired predictions, hashes, model version,
calls, token usage and latency when supplied by the provider. Selected training
misses remain training data. Do not infer a statistically reliable gain from +2
agreements without the paired results and an appropriate independent evaluation.

## Phases and acceptance questions

| Phase | Offline deliverable | Advancement question |
| --- | --- | --- |
| 1. Observe | Labelled missing-frame, unreadable-level, tracker-loss and known-state cases | Are unknowns preserved, critical errors counted, and stale observations refused? |
| 2. One fight | Single-mob pull, melee finish, heal, unexpected add and interrupted-recovery cases | Do admissible actions avoid known hazards and respect release/stop conditions? |
| 3. Hunt objectives | Known match/non-match/unknown, tapped target, verified progress and false-completion cases | Is progress measured from evidence rather than target names or missing text? |
| 4. Navigate | Short waypoints, blocked route, repeat loop, aggro diversion and unsafe ledge cases | Can the agent stop/recover without inventing a route or crossing an unseen landing? |
| 5. Quest and shop | Accept/complete/turn-in and budgeted vendor state transitions | Are task and inventory/currency changes actually verified? |

For every phase, report tested episode count and uncertainty alongside failures,
minimum health where observable, verified progress, stuck duration, recovery success
and decision/provider cost. Human agreement is a secondary diagnostic, not the
objective. Set numerical acceptance budgets before trials, not after seeing results.
No phase is declared passed by this document. Bounded, supervised live proof is a
separate later authorisation; zero deaths in a small sample cannot prove immortality.

## Suggested division of work

This reviewer can contribute source audits, source-backed scoped facts, fixture
design and visual annotation of frames actually made accessible in the conversation.
The local visual agent produces the approved full-resolution crops and labels; the
runtime owner implements fresh-state/action contracts and runs authorised Mac proof;
Jev is evaluated on frozen state/action questions. Call this improving Jev's inputs,
knowledge and evaluation unless a real training mechanism has been implemented.
