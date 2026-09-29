---
title: "Replay new logic on saved frames and states before a live run; cap repeats locally and show Jev its recent results"
date: 2026-09-28
category: workflow-issues
module: decision loops and offline replay (fight, walk, hunt, quest)
problem_type: workflow_issue
component: development_workflow
severity: high
root_cause: missing_workflow_step
resolution_type: workflow_improvement
applies_when:
  - "New perception or decision logic is about to be tried for the first time in a live run"
  - "A fix's evidence would read sim only, live the next run"
  - "An action can be chosen again and again with no local cap on consecutive repeats"
  - "The decision state carries only the last action and its result"
  - "A run ends at a budget (a decision, move or call limit) rather than a named outcome"
  - "A new consumer copies an older loop (fight, hunt, session, a new skill)"
symptoms:
  - "On 23 Sept live patches to a scratch fight loop made the character turn in place 40 times"
  - "Live runs 59 and 93 tried SELECT_TARGET over and over until the fight's decision limit"
  - "LOOK_AROUND, offered out of combat, turned the character round on the spot in live run 84"
  - "Fixes recorded their evidence as sim only, with the next live run as the test"
related_components:
  - perception
  - decision-graph
  - fight-loop
  - learning-loop
tags: [offline-replay, live-run, repeat-cap, action-history, decision-state, jev, perception, regression]
---

# Replay new logic on saved frames and states before a live run; cap repeats locally and show Jev its recent results

## Context

On 23 September 2026 the scratch Jev fight loop was patched live several times in a row. The owner watched the character walk to the left of the screen, walk the wrong way, then spin in place 40 times: "not sure what are you doing? you are turning endlessly" (auto memory [claude]). The agent's note that day names three causes:

- each patch went straight to a live run;
- the local layer offered a repeatable action (LOOK_AROUND) with no cap;
- Jev's state had no memory of repeated failed attempts.

The repo records it in two places. The M4 README says: "An earlier scratch fight loop showed the opposite risk. Offered an uncapped turn and no history, Jev chose that turn 40 times in a row. So M4a gives Jev the history and keeps the caps local" (`experiments/002_wow_visual/m4/README.md:48-49`). The architecture's "Do not ask" column keeps "Which way round a boulder, forty times" (`docs/architecture.md:106`). M3's seven runs that day "used the scratch predecessor of `FightProbe.swift`, with each fix below applied before the next run" (`experiments/002_wow_visual/m3/README.md:161-165`). One of those fixes was already checked on saved frames: the range-digit threshold was "Fixed and re-validated on nine frames" (`:171`).

The lesson was applied at once to the walk, and only partly to later consumers.

**Where it landed: the walk (M4a, #17, merged the same day).**

- The state carries "the last six moves, each with its heading, time, distance moved, distance before and after, and whether it was blocked" (`experiments/002_wow_visual/m4/README.md:65-66`; `recent_moves` at `experiments/002_wow_visual/m4/Nav.swift:524`, `NavLimits.recentMoves = 6` at `:70`).
- "The same move is not offered a fourth consecutive time without a new best distance" (`experiments/002_wow_visual/m4/README.md:77`; `navAdmissible`, `Nav.swift:494-507`, `repeatCap = 3` at `:63`).
- Tests pin both. "A fourth consecutive repeat without a new best is not offered" (`experiments/002_wow_visual/m4/NavTests.swift:354-358`). A scripted Jev that insists on one move "gets it 3 times in a row at most, then NO_PROGRESS" (`:730-732`). The state holds exactly six recent moves (`:381-383`).
- Rehearsals came before any live walk. `--sim-jev` runs the real Jev against simulated maps (`experiments/002_wow_visual/m4/README.md:217-224`), and it caught Jev choosing STOP at the first block in all 10 rehearsals (`:96-100`).

**Where it landed partly.**

- **The hunt (#18).** It carries `recent_actions` (`experiments/002_wow_visual/m4/Hunt.swift:701`, six kept, `:26`). It caps one compass walk at four in a row (`:19`, `:579-580`), a search at 12 decisions without a fight (`:17`, `:974`) and pick-ups at two empty ones (`:595`). LOOK_AROUND is one bounded circle: "Four 90° turns to the right … the facing ends where it began" (`:837-854`). Until #98, though, it was offered out of combat whenever the last step was not a look round (`if last != .lookAround`; tested as "a look is not repeated at once", `experiments/002_wow_visual/m4/HuntTests.swift:291-292`). Looks round separated by other steps were never capped. On 27 September the owner said "don't stuck and 360 screen". In live run 84 (28 September), "LOOK_AROUND, offered out of combat, turned the character round on the spot" (`experiments/002_wow_visual/m4/README.md:1444-1446`). #98 now offers it only in combat (`:1454`, `Hunt.swift:575`, `:590-591`). In combat it is still offered at every decision without a count.
- **The quest loop.** A failed step is not offered again that run (`experiments/002_wow_visual/m4/Quest.swift:1439`, `:1451`, `:1457`; `experiments/002_wow_visual/m4/README.md:529`, `:552`). That caps a repeated step at one.
- **The session loop (#96).** It ends at the second stuck walk and after eight failed tasks in a row (`experiments/002_wow_visual/m4/Session.swift:45-46`, `:362-365`; `experiments/002_wow_visual/engine/Controller.swift:202`, `:278-279`). It has not run live (`experiments/002_wow_visual/m4/README.md:1405-1407`).
- **The planner.** `repeatFailurePenalty` lowers a step by 15 for each earlier failure (`experiments/002_wow_visual/engine/Planner.swift:24`, `:90-94`). Only `EngineTests.swift` calls `GoalPlanner.rank`, and `experiments/002_wow_visual/engine/README.md:7-8` says `Planner.swift`, `Judge.swift` and `Report.swift` "have no consumer yet". It is tested, not live.

**Where it did not land: the fight.**

- **The state has one step of history.** The fight's state has `last_action` only: its name and result (`experiments/002_wow_visual/m3/Fight.swift:292-318`, `:312`, `:315`; `var lastAction … lastResult` at `:569`).
- **The fight graph (#33) keeps more, behind a READ.** It keeps the fight's steps with who chose them and their results (`Fight.swift:579`, `:675`, `:765`). But `recent_steps` is a READ resource (`experiments/002_wow_visual/runtime/skyborne-fight.graph.json:21`), and the decision graph removes every resource key from Jev's input until Jev chooses to read it (`experiments/002_wow_visual/runtime/DecisionGraph.swift:168-170`, `:175`). The hunt's and the quest's histories work the same way under a graph (`experiments/002_wow_visual/runtime/skyborne-hunt.graph.json:107-113`, `experiments/002_wow_visual/runtime/skyborne-quest.graph.json:15`).
- **No cap spans decisions.** Nothing caps an action repeated across decisions. SELECT_TARGET is offered whenever nothing alive is selected and no kill waits (`Fight.swift:250`). The only bounds are budgets: `FightLimits.maxDecisions = 40`, `maxSteps = 120` and `maxSeconds = 150` (`:51-53`, the loop at `:620`).
- **The caps that do exist sit inside one action or one outcome.** SELECT_TARGET's own search turns "a whole turn at most" (`experiments/002_wow_visual/m3/README.md:236-237`, `Fight.swift:63`). A loot hover right-clicks a corpse twice at most (`experiments/002_wow_visual/m3/FightProbe.swift:325`, `:436`). A kill with no corpse label ends the fight, because "Live, Jev otherwise tried LOOT 20 times" (`Fight.swift:783-786`).
- **The result: two runs ended at the decision budget on the same repeated action.**
  - Live run 59 (27 September): "SELECT_TARGET was tried 37 times until the decision limit" (`experiments/002_wow_visual/m3/README.md:191-194`).
  - Live run 93 (28 September): "30 SELECT_TARGETs out of combat followed, and DECISION_LIMIT" (`Fight.swift:627-629`). #106 fixed its cause, the start's corpse. The repeat itself stays uncapped.
  - The private run logs (counts only) show 36 SELECT_TARGETs in a row in run 59 and 33 in run 93. After the first, each state said only "no target selected" as the last result. Jev chose `READ:recent` in none of the fight graph calls: 99 in run 59 and 56 in run 93.

**The replay surfaces on main, and what each one proves:**

| Surface | What it replays | What it proves | What it cannot |
|---|---|---|---|
| Perception regression set (`tools/sdlc motor`, `experiments/002_wow_visual/m4/perception.jsonl`, `tools/MotorProof.swift:15`) | Every pixel reader on every saved frame at the layout, in about 8 s (`experiments/002_wow_visual/m4/README.md:179-201`) | A code change that moves any reading. The diff is the review record (`:199-201`) | Calibration. "Saved JPEGs are not live frames"; OCR readers are left out (`:211-213`). The file was last refreshed in #53 (27 September), so later runs' frames are not in it. The README still describes 2,397 frames from 22-24 September (`:189`) |
| `m4-nav --replay DIR` (`experiments/002_wow_visual/m4/NavProbe.swift:296-327`) | Saved frames of one folder through the live readers, and `redDanger`, the walk's own danger decision (`:313`, the same function the live look calls at `:183`) | What the live loop would have read and flagged on each frame (`experiments/002_wow_visual/m5/README.md:329`, `:358-362`) | Jev's state, the admissible set or a decision. It prints readings, not a state packet |
| `--sim-jev`, `--hunt-sim-jev` (`NavProbe.swift:374-402`, `experiments/002_wow_visual/m4/HuntProbe.swift:451-476`) | The real Jev against SimNav or SimHunt | What Jev chooses on a simulated map, before any live walk (`experiments/002_wow_visual/m4/README.md:217-224`) | The game's terrain, packs or OCR noise (issue #94) |
| `--dry-run`, `--hunt-dry-run` (`NavProbe.swift:257-278`, `HuntProbe.swift:428-449`, `FightProbe.swift:3-8`) | The loop against a simulated world, with scripted or canned replies | The loop, keys, stops and limits | What Jev chooses. The fight has no sim-Jev and no replay mode |
| Tabletop (`experiments/002_wow_visual/m4/Tabletop.swift`) | 13 situations from the owner's demo, with live Jev | Agreement with the owner (13/13, `experiments/002_wow_visual/m4/README.md:278-279`) | Held-out judgement: it was tuned until it agreed (`Tabletop.swift:5`) |
| `experiments/002_wow_visual/learning/VideoJev.swift` | 236 video decisions | Historical totals, "reported, not independently recomputed" (`experiments/002_wow_visual/learning/README.md:28-57`) | Live play: "A replay measures decisions on a supplied description" (`:4-5`) |

**Live runs save what a decision replay needs:**

- **Frames.** A walk keeps every other frame and every frame with a red name or hostile plate (`NavProbe.swift:171-174`). A fight keeps every other observation (`FightProbe.swift:194-196`), in the quest run's `fight%d` folder (`experiments/002_wow_visual/m4/QuestProbe.swift:1185`).
- **Decisions.** Every Jev call is logged with the exact state and question it was sent, and the response: `graph_call` for quests, hunts and sessions (`Quest.swift:1381-1384`, `Hunt.swift:1000`, `Session.swift:144`; the trace itself at `DecisionGraph.swift:187-193`), and `decision` with `trace` or `state` for fights (`Fight.swift:697-702`, `:728-733`).

So the frames and states exist. What does not exist is a replay of saved states: no tool feeds a saved state or frame through new admissibility, a new RULE or a new framing and prints the difference. The quest node's missing rehearsal is covered in [Frame Jev's question before trusting or overriding its choice](../design-patterns/give-jev-the-goal-or-it-takes-the-safe-exit.md). This note covers the rest: perception, RULEs and local limits, and what Jev is shown of its own history.

The fixes of 27 September record their evidence as "Evidence: sim only (`FightTests`) … Live: the next run" (`experiments/002_wow_visual/m3/README.md:212`, `:226`, `:242`; `:247` has "sim" and "live: the next run"). M3's README does not use the word replay.

## Guidance

**Before a live run, replay the changed logic on what earlier runs saved. Make "never repeat forever" an admissibility rule with a test. Put the recent actions and their results in the state Jev sees. Only then go live, and treat the live run as the test that the replay could not be.**

1. **Pick the replay by what changed.**
   - *A pixel reader, threshold or learned reader:* `tools/sdlc motor` runs the perception set. Then run `m4-nav --replay` on the folders of the failing run and of runs where the reader worked. Refresh the set with the frames of runs since #53 when a change touches them.
   - *A decision fed by perception (a walk warning, a stop, a RULE such as `blocker_fight` (`experiments/002_wow_visual/engine/Controller.swift`)):* replay the function the live path calls, not a copy. `redDanger` is shared by the live look and `--replay` (`NavProbe.swift:183`, `:313`), which is why M5 could replay "the walk's own decision" (`experiments/002_wow_visual/m5/README.md:358-362`).
   - *A RULE or limit that reads saved state:* run it over the saved `graph_call` and `stopped_by` events, and count how often it would fire and on what inputs.
   - *A question, criterion, goal or state field:* replay the saved `graph_call` states through Jev. See the framing note for how.
   - *A new skill or loop:* run a dry run with a scripted Jev that insists on one action, then a sim-Jev run where the mode exists.
2. **Make each replay print enough to falsify the change.**
   - The inputs: run folders and frame files. The perception set adds each frame's hash.
   - The old and new result side by side, counted over the whole set, not just the frame that failed.
   - The frames whose reading changed, with a few checked by eye. M4t replayed runs 58-67. It showed no hostile plate on village walks, and six flagged frames were all Roiling Winds plates (`experiments/002_wow_visual/m4/README.md:1116-1120`).
   - Whether the set is calibration or held out. The red-name classifier's replay "is calibration, not a held-out result" (`experiments/002_wow_visual/m4/README.md:563`). Split by run, as M5 does (`experiments/002_wow_visual/m5/README.md:64`). "Mask later frames, action labels and outcomes" from the input of an earlier decision (`docs/agents/ai-sdlc.md:105-106`).
   - Cases near the decision boundary, and a check that the replay can fail. In experiment 001, 174 matcher checks stayed green when both abstention thresholds were loosened (0.55 to 0.50, and the separation 0.10 to 0.02), because no case fell inside the decision band (PR #7's review on GitHub; session history). Move the decision constant once: if the replay's result does not move, the replay does not guard that decision.
   - Label the result as offline or simulated, apart from live evidence.
3. **Cap every repeatable action locally, and test the cap with a stubborn Jev.**
   - A turning skill does at most one circle per action: four quarter turns, as `lookAround` and SELECT_TARGET's search already do.
   - Across decisions, the same action with no new result is not offered again after a small count. The walk allows three without a new best and the hunt four compass walks. The quest loop allows a failed step once.
   - The cap ends with a named outcome (`NO_PROGRESS`, `MOVE_LIMIT`, `NO_TARGET_FOUND`), never by running out the budget. `maxDecisions` is a budget, not a cap: it let 37 SELECT_TARGETs through in run 59.
   - The test is `NavTests.swift:730-732`'s shape: a scripted Jev that always picks the capped action, and a check on the longest run and the outcome.
   - The fight still needs one: for example, SELECT_TARGET not offered after N consecutive "no target selected" with nothing changed (combat, health, a target). This is a proposal, not code on main.
   - Keep caps in admissibility and the loop, the script's side. AGENTS.md gives scripts "admissibility, key execution, watchdogs, budgets and emergency stops", and `docs/agents/ai-sdlc.md:203` says "Recovery is bounded; no endless retries".
4. **Show Jev its recent actions and their results in the state it is asked on.**
   - `last_action` alone is not memory: 36 "no target selected" in a row look like one.
   - A READ that Jev never takes does not reach it. `docs/agents/ai-sdlc.md:140` asks to "Log knowledge consumed, not only knowledge available", and runs 59 and 93 consumed none.
   - Keep a short history in the base state, as the walk does, or give a count of repeats and their shared result. Add a test that the state carries it, as `NavTests.swift:381-383` does.
5. **Then go live, supervised, and keep that run as the next replay set.**
   - "Merged instructions and replay agreement do not prove live-game capability" (AGENTS.md).
   - The lifecycle is "candidate → offline-validated → runtime-qualified → active" (`docs/agents/ai-sdlc.md:125-128`), and live evidence comes "when fixtures cannot establish the property" (`:161-163`).
   - Before the next live run, replay the new logic on the last live run's frames and states. They are the freshest held-out data.
6. **At the second PR in a failure class, stop.** It must bring the replay that would have caught the first failure, and a cap or regression test for its loop. See [Fix the engine capability behind a live failure, not the per-run patch](../architecture-patterns/fix-engine-capability-not-goal-patches.md).

## Why This Matters

- **Repeats cost what the owner sees and what the budget pays.**
  - 40 spins on 23 September (auto memory [claude]).
  - 37 SELECT_TARGETs in run 59 and 30 in run 93, each a model call, ending at the decision limit.
  - 20 LOOT attempts before a cap existed (`Fight.swift:785`).
  - The look round in run 84 (28 September), five days after the first spin.

  Each is one bounded action repeated with no local count and no memory in Jev's state. The fix that held was the walk's: a cap in admissibility, six moves in the state, and a test. Where the lesson was not carried over, the fight and the hunt's looks, it came back.
- **A replay costs seconds. A live trial costs the owner's attention, wall time and the character's safety.** The perception set replays in about 8 s (`experiments/002_wow_visual/m4/README.md:196`). A replay with no key makes no provider call. Evidence that says "Live: the next run" turns the owner into the test harness.
- **The frames and states are already on disk.** Every Jev call's exact input is logged, and the frames are kept. Skipping the replay is a choice, not a missing capability.
- **Replay has limits, and they matter as much.** Saved JPEGs are not the live decode (`experiments/002_wow_visual/m4/README.md:131-133`, `:213`). A set tuned on or chosen against is spent (`experiments/002_wow_visual/m5/README.md:466-469`). A saved state cannot show what the game would have done after a different action. That is what the sims are for, and they lack terrain, packs and OCR noise (issue #94). A new character, light or place is only seen live.

## When to Apply

- Before a live run that includes a changed reader, threshold, model, RULE, limit, question, criterion or state field.
- When a fix's evidence would read "sim only … Live: the next run".
- When adding or changing an action that can be chosen again: a turn, a search, a target, a loot, a walk, a retry.
- When a run ends at a budget (`DECISION_LIMIT`, `MOVE_LIMIT`, `GRAPH_callLimit`) rather than a named outcome.
- When the owner reports the character spinning, stuck or doing the same thing over and over.
- When a new consumer copies an older one's loop: the fight, the hunt, the session or a new skill. Check that the cap and the history came with it.

Exception: a safety stop or held-input release acts at once. Replay, cap and test afterwards.

## Examples

**The walk (#17): the lesson applied the same day.**
- *Before any live walk:* 10 `--sim-jev` rehearsals exposed Jev's pull to STOP, and it was removed (`experiments/002_wow_visual/m4/README.md:96-100`).
- *Engine rules:* six recent moves in the state, a fourth repeat without progress not offered, and tests for both.
- *Result:* later walk failures were terrain and perception, not repeats. The steering walker keeps its own spin checks: "unreadable frames stop the steering after one pulse, not a spin" (`NavTests.swift:516`); "nothing open in view: a side turn, not a spin" (`:586`); "without depth, a block turns the walk aside toward the gap, never round and round" (`:643-644`).

**Red names and plates: the walk's own decision replayed on saved frames.**
- *M5:* `m4-nav --replay` ran `redDanger`, the same function as the live look, over the quest runs' walk and hunt frames. Of the held-out test runs' frames, 2 of 9 still stopped, both at a real name (`experiments/002_wow_visual/m5/README.md:358-362`).
- *M4t:* after run 67, `nameplates` replayed on that walk's frames read the hostile plate "ten frames, about 5 s, before combat" (`experiments/002_wow_visual/m4/README.md:1108-1110`). The fix was then replayed on runs 58-67 before the next live run (`:1116-1120`).
- *The Spirit Healer:* the live frames of 27 September were replayed through the crop OCR before the engine ran it live (`experiments/002_wow_visual/m4/README.md:1094-1099`).

**Run 59 → run 93: a repeat that a cap would have ended, and a replay would have shown.**
- *What happened:* 37, then 30, SELECT_TARGETs to the decision limit. Each time the state showed one "no target selected", and history sat behind an unread READ.
- *What was fixed:* the causes, the start's corpse (#68, #106). Not the repeat.
- *Inference:* replaying run 59's saved decisions against `admissible` would have shown SELECT_TARGET still offered after 36 failures. A stubborn-Jev test in `FightTests` would have failed.

**M4ak's RULE on levels that were seldom read (#107 → M4al).**
- *What happened:* #107 fights a lone creature "whose level reads no higher than the character's" (`experiments/002_wow_visual/m4/README.md:1599`). The live RULE is now `blocker_fight` in `experiments/002_wow_visual/engine/Controller.swift`; `fightsBlocker` in Quest.swift is gone. Its sim checks used synthetic reads. After live runs 87-98, M4al found that "M4ai's target levels read null at most stops, and M4ak's rule seldom fired" (`:1622-1626`), because an open backpack moved the tooltip.
- *What was saved:* every stop's `stopped_by` went into the saved `graph_call` states (`Quest.swift:1288`, `:1381-1384`).
- *Inference:* a count over the saved stop states before #107 went live would have shown how often its input was missing. Across the 28 September runs, the creature's level was read in 2 of the 6 distinct stop states sent to Jev (private run logs, counts only).

**Run 66: a hover that could never run.**
- *What happened:* #71 (after run 64) added a corpse hover below the fought creature's last plate. Its evidence was "Sim only" (`experiments/002_wow_visual/m3/README.md:212`). In run 66, "the plate reader read no plate in any quest fight that day (8 runs), so the plate hover never ran" (`:214`).
- *What was saved:* that day's quest runs had saved their fights' frames in the private runs, as every quest fight does (`experiments/002_wow_visual/m3/FightProbe.swift:194-196`, `experiments/002_wow_visual/m4/QuestProbe.swift:1185`).
- *Inference:* a replay of the plate reader on them would have shown that the hover's input never appeared.

**Where replay could not have caught it: new conditions.**
- *The learned facing reader.* On held-out frames it was more than 30° wrong on 4 of 83 at 0.7 confidence or more. Live on runs 54 and 58-62, "a new character, dusk", it "was wrong at up to 1.00 where the rule was right" (`experiments/002_wow_visual/m5/README.md:474-477`; `experiments/002_wow_visual/m4/README.md:140-143`). No saved frame had that character or that light. What replay could do afterwards: those runs "log their frame's file and the rule's reading: they are the next training rows" (`experiments/002_wow_visual/m5/README.md:476-477`), and the reader was limited to filling the rule's gaps.
- *Steering live walk 3 (27 September).* Six bumps among the village's standing stones, "whose gaps are finer than the roads' 1-unit places", then `NO_PROGRESS` (`experiments/002_wow_visual/m4/README.md:1362-1364`). The offline evidence was an AUC over 350 saved moves, and the sims used boxes (`:1352-1358`). Neither had those stones. Walk 4, with walk 3's bumps remembered, arrived (`:1364-1366`). The live failure became the next test.
- *Juvenile Vuldren.* A replay of the saved stops would reproduce Jev's retreats, but no frame says the creature does not attack first: "Only knowledge tells them apart" (`experiments/002_wow_visual/m4/README.md:1637-1639`). Replay tests logic and framing. It cannot supply a fact the saved data does not hold.

## Related

- [Frame Jev's question before trusting or overriding its choice](../design-patterns/give-jev-the-goal-or-it-takes-the-safe-exit.md): the quest node's saved stop decisions, never replayed across framings. This note is the general form for readers, RULEs, limits and history.
- [Fix the engine capability behind a live failure, not the per-run patch](../architecture-patterns/fix-engine-capability-not-goal-patches.md): the per-run rhythm this note's replay step interrupts, and the second-PR stop.
- [Keep the live-run harness and envelope in the repo](../workflow-issues/live-run-harness-and-envelope-belong-in-the-repo.md): operator lessons become checks, not notes. The same applies here: a repeat cap is a test, not a memory entry.
- `AGENTS.md`: "merged instructions and replay agreement do not prove live-game capability"; "Gameplay failures feed bounded learning; preserve the last accepted policy, add a regression and revalidate changes. No silent live self-edit."
- `docs/agents/ai-sdlc.md:105-112` (mask later frames; prefer discriminating observations over repeated blind trials), `:125-128` (lifecycle), `:148-163` (cheapest decisive evidence; shadow/replay and simulation for decision variants), `:203` (bounded recovery).
- `docs/architecture.md:30` and `:81`: the target design asks for "a labelled held-out set and a replay score" for every reader, and replay scoring for every question "before it acts live". Neither is built.
- Issues:
  - #91: the judge's replay harness over labelled cases from the saved runs.
  - #93: run reports and the offline learning loop; `experiments/002_wow_visual/engine/Report.swift` is its unwired skeleton.
  - #94: one simulated world with terrain, packs and OCR noise, and scenario files for the recorded failures.
- PRs #17 (the walk's cap and history), #18 (the hunt's), #33 (the fight graph's READ-only history), #98 (LOOK_AROUND only in combat) and #106 (run 93's cause).
