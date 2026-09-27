# Target architecture: Jev judges, code decides

This is the standing statement of how the engine should be built. The evidence for it is in
[the review of 27 September 2026](changes/2026-09-27-decision-architecture-review.md); the work
is tracked by [epic #85](https://github.com/fol2/jev-playground/issues/85); the contracts are in
[`experiments/002_wow_visual/engine/`](../experiments/002_wow_visual/engine/README.md). Read this
before changing the decision path. It states behaviour; the milestone READMEs record what happened.

## The one rule

**Jev is a System One judge. Code is the executive.** TypeSafe's `jev-1.13` is fast, calibrated and
consistent on semantic judgements over a small state, and is not a planner, a calculator or a text
generator. So the engine asks it questions with short answers about one situation, several at once in
one request, and never asks it to choose among many tasks, to decide whether to read more, to carry an
intention across ticks, or to label its own past. Everything with a right answer computable from known
facts is computed.

## The layers

```text
pixels -> readers -> world model -> reflexes -> session loop -> planner -> skills -> outcomes -> report
                        ^                                         |                              |
                        |                                      judge (one batched call)          v
                        +-------------------- offline learning loop (labels, knowledge, rules) <-+
```

### Readers and the world model

- A reader turns pixels, OCR, a learned model, a knowledge file or memory into a `Reading`: value,
  confidence, capture time, source. Every reader has a labelled held-out set and a replay score.
- The world model is one blackboard (`WorldState`). Fields are beliefs, and an unknown is a value with a
  reason and an age. One merge policy: newer wins, a weak reading within a second does not overturn a
  confident one, a miss erases a belief only after a few seconds.
- Things in the world are entity tracks, matched by name key and bearing across frames. A raw OCR string
  is never an identity.
- HUD boxes are anchored (a detector or a template finds the minimap, the portrait, the bars), never
  absolute pixels of one window size.
- OCR is untrusted text. Each field has a grammar or a validator; a value that fails it is unknown, and
  a semantic ambiguity ("is this line the NPC's name?") is a judge question, not a fuzzy matcher.

### Reflexes

One ordered table, tried every tick before any task: owner takeover, stale vision, death, combat with
low health, combat, hostile ahead of a walk, hurt out of combat, buff before a fight. Each is `OWNER`,
`SAFETY` or `RULE`, each has a simulation test, and none is ever offered to Jev. The owner's words:
"buff and heal are not in the skills chain but they are needed when needed".

### The session loop

Modes: dead, recovering, idle-safe, in town, questing, paused. A task failure is an outcome with a kind
(perception, knowledge, plan, execution, environment, safety, budget); the loop records it and plans
again. An unread frame holds and re-observes. Only the owner's takeover or an exhausted envelope
(time, deaths, calls, consecutive failures) ends a session, and the end walks to safety first. The
first implementation is `runSession` (`experiments/002_wow_visual/m4/Session.swift`), opt-in with
`--quests --session`; the run loop stays the baseline until a live session has run.

### The planner

A utility ranking over goals from the log, the wiki knowledge, the givers, the services, the level, the
bags and the money, with the owner's rules as named terms: this zone first, accept every quest, survive
first, roads between zones, sell when the bags fill, train when the level rises, a step that failed the
same way is worth less. The best candidate is taken with no call. When the top candidates lie within a
margin, the judge chooses among at most three, with the planner's reasons as the state.

### Skills

The existing bounded skills (walk, fight, hand-in, accept, hunt, use, town visit, revive) stay: capture
timing, admissibility, key execution, watchdogs and budgets are theirs. Each declares its preconditions
on the world model, reports one `TaskOutcome`, and never ends the session. The walk is the first skill
rebuilt this way: a path along the learned roads, steered by a depth model, with no model call per move
(the owner's "rethink the entire pathfinding", pull request #86).

### The judge

One request, several independent questions of the three TypeSafe kinds (choice, score, noul), over a
flat state slice of the fields those questions need. Answers are validated against exactly what was
asked. Identical requests within a short window are served from a cache. The question library is
versioned data; every question is scored on replays against labelled outcomes before it acts live.
First uses: name matching, objective kind, the heal decision, pull danger, planner tie-breaks.

### The offline learning loop

Every run ends with a report: decisions by controller, judge calls, latency, tokens, unread-frame rate,
deaths, quests, failures by kind with their frames. The analyst (Claude, offline, not in the input
loop) reads reports and frames, labels, retrains readers, edits knowledge and the chain book, tunes the
planner's terms and proposes rule changes as ordinary reviewed changes. This is where the engine
improves; the in-run `improve` node and exact-bucket experience recall retire.

### Simulation and metrics

One simulated world (terrain with lips and walls, hostile packs, OCR noise) exercises the controller
without the game. The per-run metrics are the acceptance for every change to the decision path; a
pull request that touches it attaches the report of a simulated run and, when authorised, a live one.

## What Jev is asked, and not asked

| Ask | Do not ask |
| --- | --- |
| Does this tooltip line name NPC X? (noul) | Which of these seventeen steps next? |
| What does this objective ask for: kill, collect, use, talk, travel? (choice) | Should I read the quest log first? |
| Should the character heal now? (noul) | Enter or leave a sub-menu |
| How dangerous is this pull? (score) | Whether to buff, loot, fight back or resurrect |
| Which of these two or three near-equal goals? (choice) | Which way round a boulder, forty times |
| Offline: was this walk blocked by terrain, a creature or a misread? (choice) | Label your own episode for later study |

## Non-goals

No hidden game state, memory reading, packet telemetry or anti-detection work. No second knowledge
store, agent framework, database or service. No model weight training. The four rules of AGENTS.md
and the live-authority boundary stand unchanged.
