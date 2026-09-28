# Why Jev-driven play barely works, and what to build instead

Date: 27 September 2026. Base: `8e30eeb` (main after #83). Author: an architecture review
session, fresh context, reading the source, the M3/M4/M5 READMEs, the record of live runs
1-81, the TypeSafe documentation for `jev-1.13` and the 84 pull requests since 21 September.

The owner's question: the ideas and the direction are right, so why is the result so
unnatural, and why does it barely work? This record answers with evidence, then names the
architecture to move to. The target architecture itself lives in
[docs/architecture.md](../architecture.md); the work is tracked by the GitHub epic linked
there. Nothing here changes runtime behaviour.

## 1. The finding in one paragraph

Jev is a System One judge and the engine uses it as the executive. TypeSafe documents
`jev-1.13` as fast, calibrated and consistent on semantic judgements over a small state,
and as poor at counting, arithmetic, indirection and anything that needs several steps of
reasoning; it is not trained to generate text, and the endpoint is literally named
`systemone`. The engine instead hands it the whole sequential-planning problem: pick one of
up to seventeen quest steps from paragraphs of prose, decide whether to read more context
first, enter or leave sub-menus, label its own past episodes for review, and choose every
move of a walk. Everything that a game AI would normally decide with a planner, a behaviour
tree and a world model is pushed through one `choice` question per tick, and the
deterministic side is reduced to an admissibility filter plus bounded skill runners. At
the same time the real bottleneck, perception, has no model of its own uncertainty, so
every live failure is answered with one more hand-written pixel or OCR rule and one more
pull request. The result is an engine that is expensive to steer, brittle to observe with,
and stops at the first unreadable frame.

The owner reached the same conclusion for one decision on 27 September: "rethink the entire
pathfinding ... depth map and pre-calculate the pathfinding realtime, then the input is to
adjust for the path finding. jev can interrupt but it should be optional." Pull request #86
(a walk steered along the learned roads by a depth model, no model call per move) is that
conclusion applied to walking. This review applies it to every other decision.

## 2. What the live record actually shows

The M4 README records runs 1-81 step by step. Sorting every recorded failure by its cause:

| Cause | Share of recorded failures (approx.) | Examples |
| --- | --- | --- |
| Perception: OCR, pixel rules, layout | about half | coordinates read `42.G,24.3`, `4.9, 23`, a Cyrillic З; tracker lines `[51`, `3 12]`, `..• `; a target cue whose OCR tail changes every frame (26 `FACE_TARGET` refused, then STOP); the facing arrow misread beside quest icons (131 s turning on the spot); a Vuldren's red-brown body read as a red name (three runs stopped); quest marks broken by zoom, a new character, an orange foot, grass; a nameplate over the coordinates; no fresh frame after a loot click read as 0% health; the world map's `...` pins; the cursor line not parsing |
| Execution: skills and UI mechanics | about a quarter | Click-to-Move landing on the ground beside the NPC; a greeting taken for an offer; Esc closing the wrong panel; the walk ending under a bridge; stuck on a boulder, a tree, a ramp; no reading of a cliff lip; `/equip` leaving the chat box open; the child key set retired before a fight could start; plate flicker ending fights |
| Decision: what Jev chose | about a sixth | STOP the moment a move is blocked (10 of 10 rehearsals); the follow-up quest declined; ENTER/BACK wandering to the call limit; `FIGHT_TARGET` unseen for six decisions; `BUFF_WEAPON` offered thirteen times and never taken; `SELECT_TARGET` 37 times to the limit; the Windstones hunt chosen again after it failed the same way |
| Control flow: the run ends on one failure | the rest | `LOG_INCOMPLETE`, `POSITION_UNREADABLE`, `WALK_HUD_UNREADABLE`, `HUD_UNREADABLE`, `JEV_FAILED`, `RETREAT_*`, `NO_PROGRESS_TWICE`, `NOTHING_TO_HAND_IN_OR_TAKE`; the character idle for 70 minutes until the client logged it out; killed standing idle between runs |

Three things follow.

- **Jev is not the main reason the engine fails.** Where the menu was small and the state
  concrete, Jev did well: five kills in seven supervised M3 fights, 13 of 13 on the tabletop,
  most walks arriving. Where it failed, it failed in the documented ways of a System One model
  asked to plan: it takes the safe exit, it does not sustain a multi-step intention, it does
  not notice a cheap prerequisite (the buff) that a rule would never miss.
- **Perception failures dominate, and each one has been fixed as a special case.** Roughly
  forty of the 84 pull requests since 21 September answer one live run with a patch to a
  reader or a skill (the shares in the table are the reviewer's tally of the README's
  entries, not a measured count). The
  perception regression set records what the rules read, not what is true; the learned M5
  readers are the right idea but were bolted on beside the rules with a handful of held-out
  marks, and the rule still leads.
- **The run is a pipeline, not a session.** `runQuests` is a fixed twelve-step, twenty-minute
  loop with a dozen terminal codes. One unread frame, one failed hand-in, one refused reply,
  and the run ends; the character stands where it is. A human player never "ends the run".

## 3. The design flaws, named

### 3.1 Jev as executive

`skyborne-quest.graph.json` offers up to seventeen skills whose criteria are paragraphs, and a
`question` string of some 1,600 characters. The hunt state's `goal` is a 1,500-character
paragraph that mixes instructions, cost estimates and anecdotes from particular runs
("live run 28, 26 Sept: six such targets were walked past"). The M4y history line appends
"Earlier runs: this step failed 2 times since it last worked ..." to the criterion so that Jev
will avoid a step. All of this is the deterministic side trying to steer a model in prose,
which is exactly what TypeSafe's jaggedness page says not to do ("retrieve and filter in code
first, and send only the fields the question needs"; "Jev is not a calculator").

Quest ordering, road choice, when to visit town, whether a failed step is worth retrying:
these are utility calculations over known facts. They belong in code. Jev has nothing to add
and something to subtract.

### 3.2 The tool graph: meta-actions for a model that cannot plan

`DecisionGraph.swift` lets Jev choose `READ`, `ENTER`, `BACK` or `DO`, up to four sequential
calls per decision and 120 per session. TypeSafe's own guidance is the opposite: batch
independent questions in one request ("two requests are the exception"), and make a second
request only when the first answer changes which data to fetch. The graph turned every
decision into a possible four-hop conversation with a model that does no reasoning between
hops. Live run 23 wandered `ENTER`/`BACK` to the call limit; run 27 sat in the `compass` node
while the root's `FIGHT_TARGET` went unseen; both were then patched with more rules in the
graph engine (the last call commits; ancestors' skills stay offered). The experience `improve`
node asks Jev to classify its own past episode for later study, a meta-cognitive task the
model is not built for, and the README already concedes that retrieval has not been shown to
improve anything.

### 3.3 Reflexes given to Jev, then taken back one at a time

Buff before the fight, heal under 60%, fight back when attacked, loot the kill, resurrect,
leave the danger zone: each was first offered to Jev as a choice, each failed live (the buff
never chosen; STOP chosen in combat; a hunt ending under 30% health and the character dying on
the way to safety), and each was then re-implemented as a `RULE` or `SAFETY` reflex in its own
pull request (#72, #73, #76, #79). The pattern is the diagnosis: these are reflexes, and a
behaviour tree would have held them from the start. The owner's own words fit a reflex layer
exactly: "buff and heal are not in the skills chain but they are needed when needed".

### 3.4 No world model

Each mode has its own flat observation struct (`Obs`, `NavObs`, `HuntObs`, `QuestRead`), read
fresh from the frame, with no confidence, no per-field freshness and no entity identity. What
memory exists was bolted on when a run failed: sightings `merged` across looks, a
`PositionTrack` that drops impossible jumps, a raw OCR string as the "target cue", a working
memory for the quest log keyed by tracker text, `stuck.json`, `character.json`. Pull request #84
(open) is one more of these: caching the log, bags and level because every step re-read them.
A blackboard with typed beliefs (value, confidence, captured-at, source) and entity tracks
would have made all of these one mechanism, and would give the planner and the reflexes a
single thing to read.

### 3.5 Perception without uncertainty, calibrated on one layout

Every reader is a hand-tuned rule on absolute pixel boxes of one 2560×1320 window (health on
row 997, mana on 1013, the arrow at x 2406-2440). The owner's UI change on 23 September and a
swing-timer addon each moved boxes and broke readers. OCR is trusted as text and then repaired
with ever-longer fuzzy matchers (`fuzzyNameMatch`, `sameTitle`, `townNameHit`, `questTitle`
with three stray characters, then five). The regression set holds accepted readings, not
labelled truth. The M5 work (a local labelling teacher, audited labels, Create ML readers,
honest held-out scores) is the right loop, but it has eight held-out marks, the rule still
leads on live frames, and it covers marks, red names, objects and facing only. The HUD
anchors, coordinates, tracker and tooltips are still rules.

### 3.6 A pipeline with a dozen exits, not a session

`runQuests` ends the run on `LOG_INCOMPLETE`, `POSITION_UNREADABLE`, a second `NO_PROGRESS`, a
failed retreat, a refused reply, the twelfth step or the twentieth minute. `runHunt` ends on
three unread surveys. Each end releases the keys and leaves the character standing, often
among hostiles (runs 56-57 and 65-66: killed while idle; run 41-42: logged out after 70
minutes). Then the owner starts the next run, which re-reads the bar, the log, the bags and
the level from scratch. A session loop that treats every failure as a task outcome and
re-plans, and that has an idle-safe mode, is what a player does; it also removes most of the
re-reading that #84 is trying to cache.

### 3.7 Structure and process

- One `swiftc` command line of twenty-odd files with `-D` flags; no package, no modules, no
  test framework. Hand-counted "checks" with floors (`nav checks 446 → 447`).
- `Quest.swift` (1,497 lines) and `QuestProbe.swift` (1,638) hold the quest loop, its offers,
  the town stop, the enders, the gear rule and the death recovery in one file each.
- The M4 README is 1,344 lines of chronological changelog. The current behaviour of a walk has
  to be reconstructed from twenty-six sections. There is no spec.
- 84 pull requests in seven days, one per live run, each with the four-section template, a
  Focus Gate route, an exact-head review and a merge helper. The governance is well built, but
  its unit of work is wrong for this stage: a live failure should produce a label and a
  regression, not a pull request per patch.
- The prose style of the READMEs is dense and defensive. Every reader (human or agent) pays
  for the disclaimers on every task. The disclaimers are honest; they are also the wrong place
  for them. A spec states behaviour; a changelog states what happened.

## 4. What Jev is good for here

Keep Jev, and use it as what it is: a calibrated judge over a small state, several questions
at once, in one request, at about half a second. Concretely:

- **Perception disambiguation**, replacing fuzzy matchers: "Does this tooltip line name the
  NPC `Windshaper Boro`?" (noul); "Which quest objective is this OCR line?" (choice over the
  log's objectives); "Is this objective text a kill, collect, use-at, talk or travel task?"
  (choice). Jev reads garbled text the way a person does, and a probability is what the
  caller needs.
- **Tactical judgement in combat**, batched every decision tick: "Should the character heal
  now?" (noul), "Is it safer to finish the target than to heal?" (noul), "Is this pull
  dangerous?" (score), "Which chain fits this fight?" (choice over the chain book). The
  reflex layer applies hard floors; Jev judges the grey zone.
- **Tie-breaks in planning**, only when the utility planner has two candidates within a
  margin, and then a `choice` between two or three, with the planner's reasons as the state.
- **Situation classification for the learning loop**: "Was this walk blocked by terrain, a
  creature or a misread?" (choice) run offline over recorded episodes, cheaply, to label at
  scale for the analyst.

Do not use Jev to: choose among a dozen tasks; decide whether to read more context; carry an
intention across ticks; label its own episodes; or do anything that a table lookup, a sort or
a threshold does exactly.

## 5. The target architecture

The full statement is [docs/architecture.md](../architecture.md). In brief:

1. **Perception → world model.** Readers produce typed readings with confidence and
   capture time. A blackboard merges them into beliefs and keeps entity tracks. Unknowns are
   first-class and decay. HUD boxes are anchored, not absolute.
2. **Reflex layer.** A fixed, ordered set of rules evaluated every tick before any task:
   owner takeover, stale vision, death, combat, low health, danger ahead, buff missing. Each
   is `SAFETY` or `RULE` and is tested in simulation.
3. **Session loop.** Modes: dead, recovering, idle-safe, in town, questing, paused. A task
   failure changes the plan, never ends the session. Budgets are envelope limits (time,
   deaths, calls, tokens), not step counts.
4. **Planner.** A utility ranking over goals from the log, the wiki knowledge, the level,
   the bags and the money, encoding the owner's rules as terms. Jev breaks near-ties.
5. **Skills** as they are today: bounded, watchdogged, with pre- and postconditions on the
   world model, and one failure taxonomy (perception, knowledge, plan, execution,
   environment, safety, budget).
6. **Judge.** One request, several questions, a state slice of the fields the questions
   need, a cache keyed by the slice, a replay harness that scores calibration against
   labelled outcomes. The question library is versioned data.
7. **Offline learning loop (System Two).** A run-report generator classifies every failure;
   Claude reads the reports and the frames, writes labels, retrains readers, edits knowledge
   and proposes rule changes as ordinary reviewed changes. The in-run `improve` node retires.
8. **Simulation and metrics.** One simulated world (terrain, packs, OCR noise) for the
   controller; per-run metrics (quests per hour, deaths, unread-frame rate, calls and
   tokens per decision) as the acceptance for every change to the decision path.

## 6. The change programme

Ordered by leverage. Each item is a GitHub sub-issue of the epic named in
[docs/architecture.md](../architecture.md); each names its acceptance and the evidence that
counts. The skeleton in `experiments/002_wow_visual/engine/` gives the types and the tests
to build on; it changes no live path.

1. Session loop and failure taxonomy: no run ends on one unread frame; every failure is a
   recorded task outcome; idle-safe and recovery are modes.
2. Reflex layer: the existing `RULE`/`SAFETY` reflexes move into one ordered table with
   simulation tests; nothing reflexive is offered to Jev.
3. World model: one blackboard with beliefs and entity tracks; `Obs`, `NavObs`, `HuntObs`
   and `QuestRead` become readers that write into it; the ad-hoc memories fold in.
4. Planner: the quest step choice becomes a utility ranking; the quest graph's seventeen
   skills become at most three candidates for a tie-break.
5. Judge: batched questions, state slices, cache, replay scoring; the first questions
   replace `fuzzyNameMatch`, `sameTitle`, `questKind` and the fight's heal decision.
6. Perception: anchored HUD, per-field validators, labelled truth sets, the standard
   live-failure → label → retrain → replay loop for every reader; the rule readers become
   fallbacks.
7. Offline learning loop: run reports, failure classification, an analyst procedure.
8. Simulation and metrics: one simulated world and the per-run metric set as acceptance.
9. Repository structure: a Swift package with modules and a test target; README as spec,
   changelog apart; fewer and larger pull requests.

## 7. What to stop doing now

- Stop adding skills to the quest graph. Stop appending run-specific text to criteria.
- Stop patching a reader after one live run without adding the frame to a labelled set.
- Stop ending runs on unread frames. Hold, re-observe, re-plan.
- Stop offering reflexes (buff, heal, loot, fight back) to Jev.
- Stop asking Jev whether to read more context.

## 8. What to keep

The input owner and watchdogs (`Input.swift`), the executive's freshness and identity checks
(`Runtime.swift`), the bounded skills, the M5 labelling and training loop, the road graph from
videos, the owner's rules as data, the simulators, the discipline of recording every
prediction and outcome, and the honesty of the evidence boundaries. The four rules in
AGENTS.md stand; this programme is how rules 2 and 3 are finally served.
