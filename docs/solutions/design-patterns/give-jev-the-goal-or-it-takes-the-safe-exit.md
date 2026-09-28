---
title: "Frame Jev's question before trusting or overriding its choice: the goal in the state, every exit with its cost"
date: 2026-09-28
category: design-patterns
module: 002_wow_visual Jev decision graph
problem_type: design_pattern
component: assistant
severity: high
applies_when:
  - "Jev picks STOP, DECLINE, RETREAT or another way out in most decisions, or with high confidence"
  - "A RULE is about to take a choice from Jev, or an option is about to be removed because Jev keeps choosing it"
  - "A node's question, an option's criterion or the state's goal is being written or edited"
  - "A fact Jev needs lives only in a READ resource, a README or a pixel rule"
  - "A live run would be the first test of a changed question, criterion or state"
symptoms:
  - "STOP chosen at the first blocked move in all 10 walk rehearsals across three phrasings (0.42-0.54); detours once STOP was removed"
  - "The Agitators follow-up declined at 0.79 with no goal in the state and declining described as free"
  - "STOP chosen in combat at 0.39 in live run 68, where the character then died"
  - "RETREAT chosen at red-name stops in runs 85-99 even after the state named the creature and its level; two RULEs followed (#107, #109)"
related_components:
  - decision-graph
  - question-framing
  - world-model
tags: [jev, decision-graph, question-framing, safe-exit-bias, state-shape, judge-model, rule-override, offline-replay]
---

# Frame Jev's question before trusting or overriding its choice: the goal in the state, every exit with its cost

## Context

Jev is a judge, not a planner. At each decision-graph node the engine sends it compact state, the node's question and one short description (criterion) for each offered skill. Jev returns one skill with a probability for every option (`experiments/002_wow_visual/runtime/DecisionGraph.swift`, `experiments/002_wow_visual/runtime/skyborne-quest.graph.json:7-10`). So what Jev chooses depends on three texts the engine writes: the `goal` in the state, the facts in the state, and each option's description. One pattern repeats from the first rehearsals (23 September 2026) to live run 99 (28 September). When the state lacks the objective, or an option reads as a safe or free exit, Jev takes the exit.

| Episode | What the state and options said | Jev's choice | The engine's response then | The framing fix |
|---|---|---|---|---|
| M4a walk rehearsals, 23 Sept (`--sim-jev`, 10 rehearsals) | STOP offered beside the moves, in three phrasings of the question and of STOP | STOP at the first blocked move in all 10. On one state: 0.54 as first sent, 0.42 with criteria saying STOP never reaches the destination | Option removed (#17). Local stops end a walk | Right fix. The local stops already cover the exit. Without STOP, Jev chose the 45° detours (0.32, 0.27) |
| "Agitators" follow-up, 23 Sept, after live walk 3 | The owner's goal was missing from the state, and declining was described as free | DECLINE (0.79) | Accepted by hand. Then the owner rule "Always accept quests", ACCEPT steps with no decline (#28), and follow-ups accepted by RULE in the hand-in | Right fix for owner policy: do not ask a question that the owner's policy already answers |
| Fight in combat, live run 68, 27 Sept | STOP: "return control to the owner: … the situation is unsafe or unclear". The goal said "The owner is supervising". Health was 53% after six failed target searches | STOP (0.39). The character died where it stood | Option removed in combat (#76) | Half done. STOP is still offered out of combat, with the same free-exit text |
| RETREAT at red-name stops, live runs 85-99, 28 Sept | Goal: the zone-first quest order. RETREAT: "Walk back to where the last walk began", with no cost. FIGHT_AHEAD: its benefit and its risks. From run 91 the state has `stopped_by` (name, objective), and from run 92 the creature's level | RETREAT in 22 of 23 decisions (0.53-0.98). FIGHT_AHEAD never above 0.27 | Facts added (#102, #104), then two RULEs: `fightsBlocker` (#107) and WALK_PAST (#109) | Open. Give RETREAT its cost and give the state the creature's aggression and tap state. Replay offline before the next live run |

The sources, row by row:

- **Walk STOP.** `experiments/002_wow_visual/m4/README.md:96-100`: "With STOP in the set, Jev chose it the moment the first move was blocked, in all 10 rehearsals across three phrasings of the question and of STOP's description. On one blocked state, Jev put 0.54 on STOP as first sent, and 0.42 even with structured criteria saying it never reaches the destination. With STOP removed, it put 0.32 and 0.27 on the two 45° detours." The reason given is at `:102`: "A walk has no danger that the local stops miss." The code comment is at `experiments/002_wow_visual/m4/Nav.swift:356-357`, and `experiments/002_wow_visual/m4/NavTests.swift:734` checks that "STOP is not a move Jev can choose". The hunt was built the same way: "a hunt has no STOP: its ends are local" (`experiments/002_wow_visual/m4/HuntTests.swift:354`).
- **Agitators.** `experiments/002_wow_visual/m4/README.md:244-247`: Jev "declined it (0.79). The owner overruled: taking quests is the owner's policy. The state had lacked the owner's goal, and it described declining as free. That is the same draw towards a safe exit that STOP showed. The quest was accepted by hand." Per the agent's notes from that day, the state also said the character "has only fought level-1 beasts", and the owner said: "i against the jev decision, why we decline? we need to rethink to take the quests" (auto memory [claude]). The policy now:
  - `experiments/002_wow_visual/learning/knowledge/owner-rules.md:12`: "Always accept quests. [owner] 24 Sept 2026".
  - M4g (#28, `experiments/002_wow_visual/m4/README.md:522`) turns each "!" giver into an ACCEPT step. The quest node's skills include no decline (`experiments/002_wow_visual/runtime/skyborne-quest.graph.json:8`).
  - A follow-up offered on completion is accepted by the hand-in (`experiments/002_wow_visual/m4/QuestProbe.swift:982-984`; the graph profile at `skyborne-quest.graph.json:3`: "(owner rule)").
- **Fight STOP.** `experiments/002_wow_visual/m3/README.md:228-235`, with #76's fix "STOP is offered only out of combat". The STOP text is at `experiments/002_wow_visual/m3/Fight.swift:195`, and the fight goal ends "The owner is supervising" (`:313`). The owner's own rule says the opposite: "a stop hands the fight to an owner who may be away" (`owner-rules.md:20`). That rule is only a READ away, and STOP's description does not mention it. The 0.39 comes from run 68's private log. STOP is still in the fight graph's skills (`experiments/002_wow_visual/runtime/skyborne-fight.graph.json:12`).
- **RETREAT, M4ah to M4am.**
  - M4ah (#102, `experiments/002_wow_visual/m4/README.md:1488-1492`): in run 89, four walks stopped and four retreats followed. "Jev's state said nothing of what stood ahead, and the owner's rules say a red name is danger."
  - M4ai (#104, `:1529-1531`): in run 92, level 3 against character level 4, "Jev still chose RETREAT, but FIGHT_AHEAD rose from 0.02–0.13 (run 89) to 0.19."
  - M4ak (#107, `:1557-1563`) then fought by RULE, and M4am (#109, `:1599-1603`) walks past by RULE.
  - The private run logs (counts only) cover every stop in runs 85-99. That is 23 decisions with RETREAT and FIGHT_AHEAD offered: 22 RETREATs and one other quest's hunt.
  - Without `stopped_by` (runs 85-89, 95, 99), P(RETREAT) was 0.83-0.98 and P(FIGHT_AHEAD) 0.02-0.15. With it (runs 91, 92, 94, 96, 98: seven decisions), P(RETREAT) was 0.53-0.97 and P(FIGHT_AHEAD) 0.03-0.27.
  - Run 94's first stop (a level 1 creature, character level 4) was 0.55 against 0.27. M4ak's summary "0.77–0.98" (`:1561`) is narrower than the logs.
  - Across 27-28 September Jev chose FIGHT_AHEAD in none of the 39 decisions that offered it.

**What the quest node's question and state contain today:**

- **The question** (`skyborne-quest.graph.json:7`) describes RETREAT only as what it does: it "walks back to where that walk began". FIGHT_AHEAD gets a benefit: "a kill offers the stopped step again, and its experience is how the character levels".
- **The criteria Jev reads** (`experiments/002_wow_visual/m4/Quest.swift:1210-1217`) have the same imbalance:
  - RETREAT: "Walk back to where the last walk began: a hostile creature's red name or plate came into view ahead of it." No cost is stated.
  - FIGHT_AHEAD states its benefit and its risks: "it may be a level above the character, and others near it may join". That text is the same even when `stopped_by` says level 1, with no other hostile in view.
- **RETREAT's real cost is in code only.**
  - The stopped step is failed for the rest of the run (`Quest.swift:1434`, `:1438` "danger: the step is not offered again"; `experiments/002_wow_visual/m4/README.md:552`).
  - Any retreat that does not get back ends the run (`Quest.swift:1433`).
  - Jev never reads either fact.
- **The state** (`questState`, `Quest.swift:1270-1288`) holds:
  - `"goal": "Finish the quests of the player's zone; the next zone's quests come after (the owner's order)."` (`:1273`);
  - the position and units, with the quest log, the givers and the recent steps kept for READs;
  - after a stop, `stopped_by` with `name`, `level`, `character_level`, `other_hostiles_in_view` and `counts_for_objective` (`:1283-1286`).

  There is no aggression or tap-state (grey plate) field.
- **The owner's rules** are a READ resource (`skyborne-quest.graph.json:16`, from `owner-rules.md` "## Quests"):
  - "Survive first" (`:8`);
  - "A hostile creature's red name is danger" (`:9`);
  - since #109, "Tell aggressive creatures from unaggressive ones. Juvenile Vuldren are unaggressive." (`:15`).

  In runs 85-99 Jev never chose `READ:owner_rules` at a stop; it chose `READ:recent` six times. In 10 of the 23 stop decisions the rules were already loaded from an earlier read in the same run (private run logs, counts only). Either way, the aggression rule was not there to read: it entered `owner-rules.md` with #109, merged after run 99. So in those runs Jev was never told which creatures attack. Since #109, the one creature the rule names is walked past by RULE before Jev is asked (`Quest.swift:1387`), so that fact still does not reach Jev at a stop. `experiments/002_wow_visual/m4/README.md:561-562` already called Juvenile Vuldren "a neutral red-brown creature" on 24 September, and `:888-892` did again on 27 September. Both times it was a pixel rule, never a fact in Jev's state.

**The offline evaluation of framings that exists:**

- **Walk rehearsals.** `--sim-jev` runs the real Jev against simulated walks: open, wall, pocket (`experiments/002_wow_visual/m4/README.md:217-224`, `Nav.swift:1275`). It caught STOP before any live walk.
- **Hunt rehearsals.** `--hunt-sim-jev` does the same for hunts (`experiments/002_wow_visual/m4/HuntProbe.swift:5`).
- **The tabletop.** `experiments/002_wow_visual/m4/Tabletop.swift` holds 13 situations from the owner's demo play. Its goal is the owner's: "level up … like a skilled human … and never die" (`:12-14`). Its exits (FLEE, AVOID_ALL, IGNORE) are plain alternatives. Live Jev agreed with the owner 13/13 (`experiments/002_wow_visual/m4/README.md:278-279`). The set was tuned until it agreed ("a first run missed two situations until it did", `Tabletop.swift:5`), so it is not a held-out test.
- **Video replay.** `experiments/002_wow_visual/learning/VideoJev.swift` replays 236 video decisions. Its totals are historical (`experiments/002_wow_visual/learning/README.md:28-38`), and the held-out relabel is still "Next" (`:130`).
- **Missing: any rehearsal of the quest node.** `--quests` exists only as a live mode (`Nav.swift:1172-1175`). The sim checks for M4ah-M4am use canned replies ("RETREAT in the script", `experiments/002_wow_visual/m4/README.md:1579`), so they test the state's shape and the RULEs, not what Jev chooses. The private run logs save every stop decision with its state, criteria and probabilities: 39 on 27-28 September. No framing has been compared on them.

This note is the prompt and state side of [Fix the engine capability behind a live failure, not the per-run patch](../architecture-patterns/fix-engine-capability-not-goal-patches.md). That note's rule, "A RULE that overrides the model usually means the model lacked a fact. Find the fact first", applies here. So does its creature example: "creature knowledge … added to Jev's state. Then Jev makes the decision." This note is about how to ask Jev: what the question, the options and the state must say before Jev's choice counts as a judgement.

## Guidance

**Before you trust Jev's choice, or override it, check the framing. Put the objective in the state. Describe every exit by its cost. Do not offer an exit that the engine's own stops cover. Give Jev the facts the choice turns on. Then replay the framing on saved states before a live run.**

1. **Put the objective in the state.** The `goal` names what the owner wants now, in words the options can be weighed against. The Agitators state had no goal and got a decline. The tabletop had the owner's goal and got 13/13 agreement. The quest node's goal today names only the zone order. So a RETREAT that drops a quest for the run does not visibly conflict with anything Jev was given.
2. **Describe an exit by its cost, never as free or safe.** Write RETREAT, STOP and DECLINE the way FIGHT_AHEAD is written: what they give up, in the terms of the goal.
   - RETREAT gives up the stopped step for this run and may end the run.
   - STOP hands control to an owner "who may be away" (`owner-rules.md:20`), so the goal's "The owner is supervising" should not stand beside it unqualified.
   - A risk stated for one option and no cost for its alternative is a thumb on the scale.
3. **Do not offer a give-up option that local stops already cover, and do not ask a question that owner policy answers.** Walk and hunt endings are local (arrival, combat, health, the owner's focus, no progress), so STOP there is only a way out. "Always accept quests" is policy, so there is no decline to ask about. Remove an option only on these grounds. Where the choice is a real judgement, such as fighting or leaving a creature in the way, keep both options and fix their descriptions and the state.
4. **Give Jev the facts the choice turns on, where the choice is made.**
   - For a creature ahead, these are: does it attack first, is it tapped by another player (grey plate), its level against the character's, and its company. Mark each one known or unknown, with its source, and never guess (AGENTS.md: "Preserve unknowns").
   - A fact in a READ resource that Jev does not read at that decision has not reached it. `docs/agents/ai-sdlc.md:140`: "Log knowledge consumed, not only knowledge available."
   - Static option text must not contradict the state. FIGHT_AHEAD's "it may be a level above the character, and others near it may join" says so even when `stopped_by` rules it out.
5. **Test a framing offline before you trust it or override it.**
   - The saved stop decisions are the test set. Compare framings on them: the current text, RETREAT with its cost, `stopped_by` with aggression and tap state, and the fixed FIGHT_AHEAD text. Record how the probabilities move, not only which option was chosen.
   - Hold some stops out and freeze the texts before you score them: "held-out episodes/sessions/sources, same available observations and actions, with frozen tuning" (`docs/agents/ai-sdlc.md:157-160`); "do not … tune against the held-out test" (AGENTS.md).
   - Prompt and state text is behaviour: "Changes to learned parameters, prompts and knowledge are behaviour changes even when stored as Markdown" (`docs/agents/ai-sdlc.md:134-135`).
   - `--sim-jev` did this for walks on 23 September. The quest node needs the same before its next live stop.
6. **Only then consider a RULE.** Label it a stopgap and say which fact or framing it stands in for. A RULE also hides the question: with `fightsBlocker` and WALK_PAST in place, the easy stops never reach Jev, so a framing fix can no longer be measured on them live. Offline replay is then the only place to measure it.

**The open question: be honest about it.** Name and level alone did not flip Jev's choice in runs 91-98. They moved it: P(FIGHT_AHEAD) rose from at most 0.15 to at most 0.27, and P(RETREAT) fell to 0.53 at its lowest. They never made FIGHT_AHEAD the choice. The owner's reading is that the missing fact was aggression. From the session on 28 September, recorded in the capability note: "we didn't mentione which are agreesive which are not, that's on us. but when it's agreesive, we will understand what we should do". M4ai's reading (`experiments/002_wow_visual/m4/README.md:1530-1531`) was that fighting such a blocker is "a policy question for the reflex table (#88)". Neither has been tested. Aggression was never in `stopped_by`. RETREAT's cost was never stated. FIGHT_AHEAD's risk text never changed. The goal never named what a retreat costs. A replay of the saved stops that changes one of these at a time can tell them apart. Until then, "Jev is too cautious" is a claim about a framing, not about Jev.

## Why This Matters

- **The exits had real costs.**
  - Run 68's STOP left a fight in combat, and the character died where it stood.
  - The Agitators decline would have dropped a quest the owner wanted; it was taken by hand.
  - In runs 85-99, 22 retreats each dropped a quest step for the rest of its run. The walks to Foul Matriarch, Skysight and the Windstones' grove "stood still, and so did the levelling" (`experiments/002_wow_visual/m4/README.md:1563`).
- **The responses moved decisions out of Jev** against the owner's direction. From 24 September: "the engine's skeleton is Jev-driven" (`experiments/002_wow_visual/m4/README.md:496`). From 27 September: "a script does not make gameplay choices" (`:956`). Two RULEs now decide creature stops. Each has its own matcher and its own failure modes:
  - M4al found the level unread at most stops, so `fightsBlocker` "seldom fired" (`:1591`);
  - PR #109's description notes that the far creature's own red name counted as company.
- **The same mistake cost less once the fix was the question.**
  - STOP was removed on the grounds that local stops cover it, and walks and hunts have not needed it since.
  - Quest acceptance became policy, and has not been asked about since.
  - The creature stop got facts but never a fair question, and it took four PRs (#102, #104, #107, #109) without settling.
- **A framing that is not tested offline is tested live,** one run at a time. That is the per-run rhythm the capability note warns about, applied to prompts.

## When to Apply

- Jev picks STOP, DECLINE, RETREAT or any other way out in most decisions, or with high confidence.
- You are about to add a RULE that takes a choice from Jev, or remove an option because Jev "keeps choosing it".
- You are writing or editing a node's question, an option's criterion, or the state's `goal`.
- A new option is an exit (stop, leave, skip, hand to the owner): write down what it gives up before you offer it.
- A fact Jev needs lives only in a READ resource, a README or a pixel rule.
- Before a live run that changes a question, a criterion or the state: replay it on saved decisions first.

Exception: a safety stop (combat, low health, the owner taking focus, stale vision) acts locally at once and is not offered to Jev as a choice.

## Examples

**Walk STOP (#17): the fix that worked.**
- *Framing:* STOP as one of the moves. Jev chose it at the first block in every rehearsal.
- *Fix:* the walk's endings are local (`experiments/002_wow_visual/m4/README.md:87-94`), so STOP was removed. The rehearsals then showed detours (fence: arrived twice; pocket: `NO_PROGRESS` twice, `:217-224`).

**Agitators (#28 and the hand-in): policy is not a question.**
- *Framing:* "accept or decline?", with no goal in the state and declining described as free.
- *Fix:* the owner's rule, then ACCEPT as the only action at a giver and the follow-up accepted by rule. Where a real choice remains, such as which giver first or hand in first, the ACCEPT criteria are on offer beside the other steps.

**RETREAT at a red-name stop (#102 → #109): the fix still owed.** These are proposals, not code on main.
- *Today:* `"RETREAT": "Walk back to where the last walk began: a hostile creature's red name or plate came into view ahead of it."`
- *With its cost:* "Walk back to where the last walk began. The stopped step is not offered again this run, so its quest makes no progress in this run. A red name on the way back ends the run and hands it to the owner."
- *`stopped_by` with the facts the choice turns on:* `{"name", "level", "character_level", "other_hostiles_in_view", "counts_for_objective", "attacks_first": true | false | "unknown", "attacks_first_source": "owner, 28 Sept" | "observed on approach" | null, "tapped_by_another_player": true | false | "unknown"}`
- *FIGHT_AHEAD:* its criterion says what the fight does and gains. Its level and company come from `stopped_by`, not from a fixed warning.
- *Test:* replay the 39 saved stop decisions with each change on its own, holding some out. The RULEs stay on until the chosen framing moves the held-out stops and a live run confirms it. Then decide whether to retire them. Run the replay whether or not the RULEs stay: it is the only way to measure the question behind them.

**Fight STOP (#76): half done.**
- *Today:* removed in combat, but still offered out of combat as "return control to the owner: … the situation is unsafe or unclear", beside a goal that says "The owner is supervising".
- *Fix, to test offline:* state the cost ("the owner may be away; the creature may follow"). Alternatively, show that out of combat the fight's own ends (a kill, the start-health hold, safety) cover every case and remove STOP there as well, as for walks and hunts.

## Related

- [Fix the engine capability behind a live failure, not the per-run patch](../architecture-patterns/fix-engine-capability-not-goal-patches.md): the capability side. A RULE over Jev usually means Jev lacked a fact, and creature knowledge belongs in Jev's state.
- `AGENTS.md`:
  - "JEV owns contextual choices where it adds value";
  - "log the real controller (JEV, RULE, SAFETY or OWNER)";
  - "Preserve unknowns";
  - no tuning against the held-out test.
- `docs/agents/ai-sdlc.md:130-140` (name the real consumer; a knowledge file is not read automatically; log knowledge consumed) and `:157-160` (decision evaluation on held-out episodes with frozen tuning).
- `experiments/002_wow_visual/learning/knowledge/owner-rules.md`: the READ resource that holds the owner's quest and fight rules, including the aggression rule of 28 September.
- Issues:
  - #90 (planner): its motivation already names this: "Live: STOP and RETREAT chosen as safe exits". A planner that filters options before Jev is asked may replace some per-node framing fixes.
  - #91 (judge): a question library, small state slices and replay scoring against labelled cases before a question shape is trusted live. This note's test belongs there.
  - #88 (the reflex table, with its "hostile ahead" entry): it may take some of these choices from Jev altogether.
  - #89 (world model): where facts such as aggression and tap state would live.
  - #93 (offline learning loop): where a quest-node replay set belongs.
