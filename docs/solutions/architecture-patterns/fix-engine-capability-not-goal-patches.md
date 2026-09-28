---
title: "Fix the engine capability behind a live failure, not the goal-serving patch"
date: 2026-09-28
category: architecture-patterns
module: 002_wow_visual engine
problem_type: architecture_pattern
component: development_workflow
severity: high
applies_when:
  - A live run fails and the quickest fix would only unblock the current goal
  - A fix would add another fixed screen box, ad hoc name matcher or coordinate list
  - A RULE would override Jev's choice because Jev looks too cautious
  - The engine's outcome log disagrees with the run recording
  - Self-improvement would store places or coordinates rather than generalisable knowledge
symptoms:
  - Eleven goal-serving PRs (99-109) moved the character only from level 4 to 5
  - Six separate name matchers across m4/Hunt.swift and m3/Fight.swift, each patched after a misread
  - A hard-coded tooltip box read nothing while the backpack was open and tooltips drew elsewhere
  - RULEs forced fights because Jev lacked the fact of which creatures are aggressive
  - Pick-ups and kills logged wrongly; only the video showed the true outcome
related_components:
  - perception
  - entity-resolution
  - outcome-verification
  - world-model
  - learning-loop
tags: [engine-capability, goal-driven-patches, entity-resolution, ui-localisation, outcome-verification, world-knowledge, learning-loop, live-run-failures]
---

# Fix the engine capability behind a live failure, not the goal-serving patch

## Context

On 26 September 2026 the owner set the goal "robustly able to level from lv1 to lv20, just like human do". Over live runs 85-100 (27-28 September) every failure got its own local fix: eleven PRs (#99-#109), the last merged just after the stop. Per the session record the character went from level 4 to 5, and the owner stopped the goal:

> "all in all i think because of the goal setting, you are more focus on how to level from 1 to lv20. all your patch are serving that but not in the higher thinking to improve the overall engine. that is actually why i stopped the goal."

Each patch was locally correct and tested, but together they added special cases, not capability:

- **Fixed UI boxes.** Unit tooltips are read from a hard-coded `unitTooltipBox = CGRect(x: 2200, y: 1000, ...)` (`experiments/002_wow_visual/m3/FightProbe.swift:515`). #108 closes the backpack after a read (`experiments/002_wow_visual/m4/QuestProbe.swift:259-262`) so that the game draws the tooltip back inside that box. The owner: "we should read tooptip where it located".
- **Scattered name matchers.** At least six ad hoc matchers use different rules: `nameKey` (`experiments/002_wow_visual/m4/Hunt.swift:102`, maps i to l), `objective(for:)` (`:110`), `targetCue` (`:151`), `mostlyIn` (`:162`, 60% of four-letter runs), `counts` (`:436`) and `fuzzyNameMatch` (`experiments/002_wow_visual/m3/Fight.swift:397`, two shared runs). `sameTitle` (`experiments/002_wow_visual/m4/Quest.swift:476`) is a seventh. #99 added one more whole-word rule inside `counts` (`experiments/002_wow_visual/m4/Hunt.swift:445-448`). The tree never gives Vision the known vocabulary: no `customWords` appears anywhere in it.
- **RULEs that override Jev.** #107 added `fightsBlocker` (`experiments/002_wow_visual/m4/Quest.swift:811`, applied at `:1339`) because Jev chose RETREAT with confidence 0.77-0.98 at every walk stop. The owner: "we didn't mentione which are agreesive which are not, that's on us. but when it's agreesive, we will understand what we should do". #109 (merged after the stop) adds a hand-written list of unaggressive creatures and another RULE.
- **Coordinate caches called learning.** `places.json` (`experiments/002_wow_visual/m4/HuntProbe.swift:27`), `bumps.json` (`experiments/002_wow_visual/m4/NavProbe.swift:75`), `stuck.json` (`experiments/002_wow_visual/m4/QuestProbe.swift:48`). The owner: "sounds like the self-improvment is hard-coded memory? i don't disagree that but i expect more intelligent".
- **An outcome log that needs video to be believed.** #100 turned a pick-up logged as failed into a success by matching on the objective text (`pickedUp`, `experiments/002_wow_visual/m4/Hunt.swift:141`). On treating recordings as ground truth, the owner said: "that means our log is not accurate. yes it's truth but doesn't mean we always rely on video".

## Guidance

**Before you fix a live failure, name the engine capability it exposes, and improve that capability for every consumer.** A patch that only moves this run forward is at most a labelled stopgap.

- **Element missed at a fixed box → UI localisation.** Find tooltips, windows and panels by their appearance and anchors (border, title, position relative to the pointer) wherever the game draws them. The owner already asked for "UI boxes from anchors, not hardcoded" on 25 September.
- **Name misread or matched to the wrong thing → one closed-vocabulary entity resolver.** Candidates come from what the engine knows: quest objectives, NPCs, creature knowledge and bag items. Pass them to Vision as `customWords`. Score with a token edit distance that knows OCR confusions (i/l/1, rn/m). Accept only with a margin over the runner-up; otherwise return "unknown". Every consumer calls this resolver, and a fixture set of real misreads from runs tests it.
- **Outcome logged wrongly → multi-evidence outcome verification.** Claim a kill, pick-up or count change only from at least two independent signals. Store the evidence frames so that the log can be audited offline. Recordings are for diagnosis, not a crutch for an inaccurate log.
- **Creature fled from or fought wrongly → learned world knowledge.** Track aggression from observed behaviour, tap state and level. A grey plate means another player tagged the creature: no credit and no loot, so check it before engaging and before looting. Give each fact provenance, a confidence and an evaluation, and put it in Jev's state. Do not override Jev.
- **Repeated walk or search failures → the learning loop, not coordinate lists.** AGENTS.md: "question → … → grounded observations → candidate knowledge/skill → held-out evaluation → versioned promotion".

Working rules:

- A goal such as level 1-20 measures the engine. It is not the design driver, and progress made through special cases is not engine progress.
- A RULE that overrides the model usually means the model lacked a fact. Find the fact first. Keep RULEs for what AGENTS.md gives to scripts: admissibility, watchdogs, budgets and emergency stops.
- "Gameplay failures feed bounded learning; … add a regression" (AGENTS.md) still applies. The regression should test the capability, such as the resolver against the misread fixtures, not just one frame.
- Align with the open engine-level programme: epic #85, world model #89, perception with uncertainty #92 and offline learning loop #93.

## Why This Matters

The ten PRs merged before the stop bought one level. Each patch put a narrow condition into a single consumer, so the next failure of the same class came in through a sibling. For example, `unitLevel` checks names with `fuzzyNameMatch` (`experiments/002_wow_visual/m4/Quest.swift:820-821`), while the hunt uses `counts` with rules of its own. Rules that live in one control flow also drift from the others. When #96's session loop (`runSession`) was brought up to date with main, the rules added to `runQuests` after it was copied (M4ah, M4ai, M4ak) were missing and had to be ported by hand (session history). The special cases also pile up: #107's RULE and #109's list both override Jev on creature encounters, and the list is hand-written knowledge with no provenance or evaluation. That is the opposite of the mission in AGENTS.md, an engine "that learns how to play". Capability fixes compound across zones and classes, whereas every new zone inherits the patches as debt.

## When to Apply

- The obvious fix is a constant, a threshold, a new branch in one matcher, or a RULE.
- A second PR is about to land for the same class of failure (UI position, name matching, outcome logging, creature behaviour).
- Jev keeps making the "wrong" choice. Check what its state was missing before constraining it.
- A new memory file would store coordinates or names without provenance or confidence.

Exception: a safety stop or held-input release acts at once. Do the capability work afterwards.

## Examples

**Tooltip position (#108).** *Patch:* close the backpack after each read so that the unit tooltip lands in `unitTooltipBox` again. *Capability:* find the tooltip by its frame wherever it is drawn. Then an open backpack or vendor window no longer affects any tooltip reader.

**Name matching (#99).** *Patch:* a whole-word rule for collect objectives inside `counts`, alongside the four-letter-run rules in `mostlyIn` and `fuzzyNameMatch`. *Capability:* the plate resolves to the known creature "Roiling Wind". Whether it counts for "Windstone Cluster" then becomes a lookup of what it drops, not a comparison of shared letters.

**Creature behaviour (#107, #109).** *Patch:* a RULE that fights a lone creature no higher than the character, plus a hand-written unaggressive list with a second RULE. *Capability:* creature knowledge learned from what happened on approach (did it attack, and at what range?), with provenance and confidence, added to Jev's state. Then Jev makes the decision.

**Outcome logging (#100).** *Patch:* match the pick-up by objective text and wait 15 s. *Capability:* a verifier that claims a pick-up only when at least two signals agree (the tracker count rises, the item appears in the bags, the object leaves the view) and stores the frames. An offline audit then treats any disagreement between the log and a recording as a verifier defect.

## Related

- `docs/agents/ai-sdlc.md`: the learning loop and the rule "do not "teach" a combat rule to compensate for an unmeasured HUD", the general form of the owner's first point.
- `AGENTS.md`: the mission ("learns how to play"), the learning loop quoted above, and controller provenance (JEV, RULE, SAFETY, OWNER).
- `experiments/002_wow_visual/m5/README.md`: the owner's 26 September decision for a learned detector over hand-tuned mark rules; moving the HUD anchors to that detector is listed there as a later step.
- The decision-architecture review and the architecture document on PR #96's branch (unmerged at the time of writing) diagnose the same patching pattern from runs 1-84. This note adds the goal-setting cause, the failure-to-capability map, grey-plate tap state and multi-signal verification.
- Issues: epic #85; #88 (reflex table: aggression knowledge should feed its "hostile ahead" entry); #89 (world model); #92 (perception with uncertainty); #93 (offline learning loop); #109 (the hand-written creature list, a stopgap for learned aggression).
