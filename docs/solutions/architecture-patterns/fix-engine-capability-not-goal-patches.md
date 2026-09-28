---
title: "Fix the engine capability behind a live failure, not the per-run patch"
date: 2026-09-28
last_updated: 2026-09-28
category: architecture-patterns
module: 002_wow_visual engine
problem_type: architecture_pattern
component: development_workflow
severity: high
applies_when:
  - "A live run fails and the quickest fix would only unblock this run, goal or not"
  - "A fix would add another fixed screen box, ad hoc name matcher or coordinate list"
  - "A RULE would override Jev's choice because Jev looks too cautious"
  - "The engine's outcome log disagrees with the run recording"
  - "Self-improvement would store places or coordinates rather than generalisable knowledge"
symptoms:
  - "60 PRs merged over live runs 1-100 (25-28 Sept); 34 name in their title the run they fixed, and the rhythm predates the level 1-20 goal"
  - "Name matching was patched five separate times (#42, #44, #60, #82, #99) with no shared resolver"
  - "Fixed UI boxes and waits were patched after tooltips and windows drew elsewhere or late (#40, #41, #62, #64, #108)"
  - "Kill, loot and pick-up outcomes were patched six times (#68, #71, #74, #100, #103, #106) and loot still misses"
  - "Walker detours were patched five times until the owner asked to rethink the entire pathfinding; later RULEs overrode Jev on creature encounters (#107, #109)"
related_components:
  - perception
  - entity-resolution
  - outcome-verification
  - world-model
  - learning-loop
tags: [engine-capability, per-run-patching, entity-resolution, ui-localisation, outcome-verification, world-knowledge, learning-loop, live-run-failures]
---

# Fix the engine capability behind a live failure, not the per-run patch

## Context

The engine's live record is runs 1-100, from the first supervised `--quests` run on 25 September 2026 to the last on 28 September. Between #38 (the fixes from run 1) and #109, 60 PRs merged to main. 34 name the live run they fixed in the title, and #38-#44 were the fixes from runs 1-7. The working rhythm was "live run N failed → a PR that fixes run N".

That rhythm is older than the goal. The owner set the goal on the evening of 26 September: level from 1 to 20 "just like human do" (`experiments/002_wow_visual/m4/README.md:1126`). By then runs 1-13 (25-26 September) had already produced one-run patches: #38-#44 and #47. For example, #42 lets a dialogue title match with one letter in eight misread, and #43 makes a near "?" join its dot. The goal sped the rhythm up (from that evening, #52-#109: 46 PRs in about 33 hours) and made "does it level?" the only check, but it did not start it. Before the goal, six of the fourteen PRs were capability work (#45, #46, #48-#51). After it, capability work was the exception (#52, #55, #59, #63, #84, #86 among the 46; the classification is this note's). Over runs 85-100 (28 September), eleven PRs (#99-#109) moved the character from level 4 to level 5, per the session record, and the owner stopped the goal:

> "all in all i think because of the goal setting, you are more focus on how to level from 1 to lv20. all your patch are serving that but not in the higher thinking to improve the overall engine. that is actually why i stopped the goal."

Across all 100 runs the patches fall into a few failure classes. Only two of them got their capability.

| Failure class | Patch PRs (live runs) | Capability behind it | On main now |
|---|---|---|---|
| World marks read by pixel rules | #38, #39, #43, #47 (runs 1, 2, 6, 10-13) | A learned reader and detector | Built after the owner asked: M5 #48-#51, #55, #59 |
| Walking: position, facing, detours, stuck points | #56, #57, #67, #69, #83 (runs 46, 47, 58, 59, 78-80) | A steering walker on learned roads, using depth | Built: #86, reused by the hunt in #98 |
| Names misread or matched to the wrong thing | #42, #44, #60, #82, #99 (runs 5, 7, 48, 78, 85) | One closed-vocabulary entity resolver | Not built |
| Tooltips and windows read at a fixed box or after a fixed wait | #40, #41, #62, #64, #108 (runs 3, 4, 49, 53, 87-98) | UI located by anchors and by appearance | Planned on 25-26 Sept, now part of #92; not built |
| Kill, loot and pick-up outcomes | #68, #71, #74, #100, #103, #106 (runs 59, 64, 66, 86, 90, 93) | Outcome verification from several signals | Not built |
| Creatures fled from or fought wrongly | #107, #109 (runs 89-94, 99) | Learned creature knowledge in Jev's state | Not built: two RULEs |
| "Self-improvement" | #81, #83, #105 (runs 77-79, 78-80, 85-89) | The learning loop, with provenance and evaluation | Not built (#93) |

The owner pointed at the capability again and again, and each time the lesson was applied only to the domain it came up in:

- **24 Sept (survival):** "those reactions should be written in jev engine" (`experiments/002_wow_visual/m4/README.md:576`). The answer was a SAFETY fight-back for walks (#30).
- **25 Sept (geometry):** "hardcode distance is dangerous. relative?" (#39 body). The answer was the same fixed 50 px search, now scaled to max(50 px, 2.5 mark heights).
- **25 Sept (working memory):** "remember what was read, to cut rescans" (`experiments/002_wow_visual/m4/README.md:438`). It was built (#45, #46).
- **26 Sept (perception):** after a day of mark-rule patches the owner asked "whether patching the rules frame by frame is the right way" (the README's wording). The answer: world objects move to a learned detector, "and fixed HUD boxes to anchors" (`experiments/002_wow_visual/m4/README.md:627-628`). Only the first half was done.
- **27 Sept (drift checks):** "visual we agreed not using machine/pixel decode instead of ml" (`experiments/002_wow_visual/m5/README.md:371-372`). The Jev-driven line turned #58's scripted cast into a Jev option (#58 body). "Rethink the entire pathfinding" produced #86 (its title).
- **28 Sept:** the goal was stopped.

Each redirect was stored in the agent's private memory as a note about its own domain: perception, the walker, the skeleton, survival (auto memory [claude]). The only other place lessons were written down was the milestone READMEs; `docs/solutions/` was empty until #110. So the next domain started the same habit again. The 26 September plan already says "fixed HUD boxes to anchors", yet #108 patched a fixed tooltip box two days later.

What the tree holds today:

- **Fixed UI boxes.** There are 18 named screen boxes at fixed pixel positions in `experiments/002_wow_visual/m3/FightProbe.swift`, `experiments/002_wow_visual/m4/QuestProbe.swift` and `experiments/002_wow_visual/m4/HuntProbe.swift`. Unit tooltips are read from `unitTooltipBox = CGRect(x: 2200, y: 1000, ...)` (`experiments/002_wow_visual/m3/FightProbe.swift:515`, used as `QuestHUD.unitTip` at `experiments/002_wow_visual/m4/QuestProbe.swift:15`). #108 closes the backpack after a read (`experiments/002_wow_visual/m4/QuestProbe.swift:259-262`) so that the game draws the tooltip back inside that box. The owner: "we should read tooptip where it located".
- **Name matchers.** Eleven functions decide whether two strings name the same thing, and they use at least seven different rules:
  - in `experiments/002_wow_visual/m4/Hunt.swift`: `objective(for:)` (`:110`, a prefix or `mostlyIn`), `pickedUp` (`:141`, an exact key), `targetCue` (`:151`), `mostlyIn` (`:162`, 60% of four-letter runs) and `counts` (`:436`, whose whole-word rule for collect objectives came in #99 at `:445-446`);
  - in `experiments/002_wow_visual/m3/Fight.swift`: `fuzzyNameMatch` (`:397`, two shared four-letter runs);
  - in `experiments/002_wow_visual/m4/Quest.swift`: `sameUnit` (`:425`, containment within two letters), `likeName` (`:444`, 60% of the shorter name's letters in order), `sameTitle` (`:476`, one edit in eight letters), `townNameHit` (`:1511`, #82's length bound of three letters) and `Creatures.isUnaggressive` (`:789`, via `mostlyIn`).

  Ten of them build on `nameKey` (`experiments/002_wow_visual/m4/Hunt.swift:102`, which maps i to l), directly or through `mostlyIn`. `fuzzyNameMatch` does not: it only lowercases and keeps the letters, so one matcher forgives an i read as l and another does not. The tree never gives Vision the known vocabulary: `customWords` appears nowhere in it.
- **RULEs that override Jev.** #107 added `fightsBlocker` (`experiments/002_wow_visual/m4/Quest.swift:811`, applied at `:1339`) because Jev chose RETREAT with confidence 0.77-0.98 at every walk stop. #109 adds a hand-written unaggressive list (`experiments/002_wow_visual/learning/knowledge/zephras-creatures.json`, loaded at `experiments/002_wow_visual/m4/Quest.swift:783-789`) and a second RULE, WALK_PAST (`:1387-1390`). The owner: "we didn't mentione which are agreesive which are not, that's on us. but when it's agreesive, we will understand what we should do".
- **Coordinate caches called learning.** After the owner asked "can the engine self-improve?" (#81 body), the answers were step records in `character.json` (`experiments/002_wow_visual/m4/QuestProbe.swift:46`, #81), stuck points in `stuck.json` (`:48`, #83) and pick-up places in `places.json` (`experiments/002_wow_visual/m4/HuntProbe.swift:27`, #105). #86 added `bumps.json` beside its walker (`experiments/002_wow_visual/m4/NavProbe.swift:75`). The owner: "sounds like the self-improvment is hard-coded memory? i don't disagree that but i expect more intelligent".
- **An outcome log that needs the video to be believed.** #100 turned a pick-up logged as failed into a success by matching on the objective's text (`pickedUp`). Five loot and kill-attribution PRs (#68, #71, #74, #103, #106) have not made loot work. The last corpse looted was in run 93. Every kill in runs 94-99 ended `KILLED_NO_CORPSE`, on Ursera and Vuldren, which do leave corpses (private run logs, counts only). The owner: "that means our log is not accurate. yes it's truth but doesn't mean we always rely on video".

The owner's six corrections to the 28 September lessons still stand. They, and the undated owner quotes in "What the tree holds today" above, were given to the session on 28 September and are recorded here:

1. Jev was not at fault for retreating. Nobody had told it which creatures are aggressive.
2. The engine's own log must be accurate.
3. Read a tooltip wherever it is drawn.
4. Name matching needs a method, not more fuzzy rules.
5. A grey plate means another player has tagged the creature: no credit and no loot.
6. Self-improvement stored as coordinate files is too little.

## Guidance

**Before you fix a live failure, name the engine capability it exposes, and improve that capability for every consumer.** A patch that only moves this run forward is at most a labelled stopgap.

**Stop patching and name the capability as soon as any of these happens:**

- A second PR is about to land in a failure class that already has one. Use the table's classes. Loot's second PR (#71) came two hours after the first (#68), and three more followed.
- The owner asks whether the method is "the right way", asks "relative?", asks to "rethink" something, or points at hard-coding. Treat that as a rule for every class, not only the one named. Then check the other rows of the table for the same smell that day.
- The obvious fix is a constant, a threshold, a fixed box, a name list, a coordinate file or a RULE.

At that point, write the capability into the PR and the capsule. Then either build it, or ship the patch labelled as a stopgap and linked to the capability's issue. Write the lesson down as the general rule, here in `docs/solutions/`, not as a note about one domain.

**Each class and its capability:**

- **Element missed at a fixed box or after a fixed wait → UI localisation.** Find tooltips, windows and panels by their appearance and anchors (border, title, position relative to the pointer) wherever the game draws them. Wait until they show, not for a set time. #92 already names the anchored HUD.
- **Name misread or matched to the wrong thing → one closed-vocabulary entity resolver.**
  - Candidates come from what the engine knows: quest objectives, NPCs, creature knowledge and bag items. Pass them to Vision as `customWords`.
  - Score with a token edit distance that knows OCR confusions (i/l/1, rn/m).
  - Accept only with a margin over the runner-up. Otherwise return "unknown" with the ranked candidates.
  - An "unknown" is never settled by a looser match. When the choice matters, the candidates go to Jev as a question, which is how #92 sends semantic ambiguity to the judge.
  - Every consumer calls this resolver, and a fixture set of real misreads from runs 5, 7, 48, 78 and 85 tests it.
- **Outcome logged wrongly → multi-evidence outcome verification.** Claim a kill, loot, pick-up or count change only when at least two independent signals agree. Store the evidence frames so that the log can be audited offline. Recordings are for diagnosis, not a crutch for an inaccurate log.
- **Creature fled from or fought wrongly → learned world knowledge.** Track aggression from observed behaviour, tap state and level. A grey plate means another player tagged the creature, so check it before engaging and before looting. Give each fact provenance, a confidence and an evaluation, and put it in Jev's state. Do not override Jev.
- **Repeated walk, search or step failures → the learning loop, not coordinate lists.** AGENTS.md: "question → … → grounded observations → candidate knowledge/skill → held-out evaluation → versioned promotion".

**Working rules:**

- A goal such as level 1-20 measures the engine. It is not the design driver, and progress made through special cases is not engine progress.
- The per-run rhythm is the risk, with or without a goal. One run is one sample of a failure class. Read the class across runs before choosing the fix.
- A RULE that overrides the model usually means the model lacked a fact. Find the fact first. Keep RULEs for what AGENTS.md gives to scripts: admissibility, watchdogs, budgets and emergency stops.
- A capability still has to earn its place on held-out data. The learned facing reader (#63) was "confidently wrong" live and was demoted to filling the rule's gaps (#70).
- A memory beside a capability is fine when it has provenance and invalidation, but it is not learning. #46's log memory was keyed by OCR text that changed with the subzone, so it rescanned anyway until #84 (`experiments/002_wow_visual/m4/README.md:1301-1304`).
- "Gameplay failures feed bounded learning; … add a regression" (AGENTS.md) still applies. The regression should test the capability, such as the resolver against the misread fixtures, not just one frame.
- Align with the open engine-level programme: epic #85, world model #89, perception with uncertainty #92 and offline learning loop #93.

## Why This Matters

The two classes that got their capability stopped producing patches. The five that did not kept producing them until the goal was stopped:

- **Walking.** Five walk patches (#56, #57, #67, #69, #83) each handled one boulder, turn or detour. The owner had already named obstacles and cliffs on 27 September, and that got a patch too (#69). Only "rethink the entire pathfinding" produced #86: roads plus a depth model, with no model call per move.
  - Live walk 3 still ended `NO_PROGRESS` among the standing stones. Walks 4 and 5 then arrived, with one bump and then none (`experiments/002_wow_visual/m4/README.md:1358-1368`). The hunt reused the walker in #98 without a new patch.
  - The tents that still stop walks (runs 88 and 100, per the private run recordings) are a gap in that capability, not a new class.
- **Perception.** The pixel mark rules needed a patch every few runs (#38, #39, #43, #47). The learned readers (#48-#51, #55, #59) moved new cases into labelled data and held-out scores.
- **Working memory.** #45 cut the skill bar's rescans: reading all twelve tooltips had taken about 8 s a run (`experiments/002_wow_visual/m3/README.md:71`). #46's log memory held only once #84 tied its invalidation to events, as noted above.
- **Names.** Five PRs, and a sixth rule came in with #109.
- **Outcomes.** Six PRs, and loot still misses.

Patches in one consumer let the same class back in through a sibling. `unitLevel` checks names with `fuzzyNameMatch` (`experiments/002_wow_visual/m4/Quest.swift:820-821`). The hunt's `counts` has rules of its own, and #109's list matches with `mostlyIn`. Rules that live in one control flow also drift from the others: when #96's session loop (`runSession`) was brought up to date with main, the rules added to `runQuests` after it was copied (M4ah, M4ai, M4ak) were missing and had to be ported by hand (PR #96's description, commits 7-11).

The costliest part is how the lessons were stored. Each redirect from the owner was stored as a lesson about its own domain, so it had to be learnt again in the next domain. That costs the owner's attention each time, and it is the opposite of the mission in AGENTS.md, an engine "that learns how to play". Capability fixes compound across zones and classes, whereas every new zone inherits the patches as debt.

## When to Apply

- A live run has just failed and the fix would name that run in its title.
- A second PR is about to land in a class from the table: UI position or timing, name matching, outcome logging, creature behaviour, walking, or "self-improvement".
- The owner questions the method ("the right way", "relative?", "rethink", "hard-coded"). Apply the answer to every class, not only the one in front of you.
- Jev keeps making the "wrong" choice. Check what its state was missing before constraining it.
- A new memory file would store coordinates or names without provenance, confidence or invalidation.

Exception: a safety stop or held-input release acts at once. Do the capability work afterwards.

## Examples

**Walking (#56, #57, #67, #69, #83 → #86), the capability that worked.**
- *Patches:* turn in place when a plate hides the coordinates (#56); read the start's place as a quest read does (#57); trust whichever facing reader followed the unstick turn (#67); go by road when a straight walk leaves the roads (#69); remember where walks stopped (#83).
- *Capability:* one walker that follows learned roads and steers continuously by depth. Jev is optional.
- *Result:* later walk failures were tuning within it (the 0.8 impassable level, the bump side rules), not new classes.

**Tooltip position (#108).**
- *Patch:* close the backpack after each read so that the unit tooltip lands in `unitTooltipBox` again.
- *Capability:* find the tooltip by its frame wherever it is drawn. The 26 September plan had already moved fixed HUD boxes to anchors (`experiments/002_wow_visual/m4/README.md:627-628`). With that capability, an open backpack or vendor window no longer affects any tooltip reader.

**Name matching (#42 → #99).**
- *Patches:* a title that matches with one letter in eight misread (#42); a bracket misread as "[51" (#44); a plate that counts only with every word, and a cue that ignores OCR tails (#60); a town NPC matched within three letters of its length (#82); a whole-word rule for collect objectives (#99).
- *Capability:* the plate resolves to the known creature "Roiling Wind". Whether it counts for "Windstone Cluster" then becomes a lookup of what it drops, not a comparison of shared letters.

**Creature behaviour (#107, #109).**
- *Patch:* a RULE that fights a lone creature no higher than the character, plus a hand-written unaggressive list with a second RULE.
- *Capability:* creature knowledge learned from what happened on approach (did it attack, and at what range?), with provenance and confidence, added to Jev's state. Then Jev makes the decision.

**Outcomes (#68 → #106, #100).**
- *Patches:*
  - loot by Interact With Target (#68);
  - loot by hovering below the last plate (#71);
  - no kill claimed when attacked with nothing selected (#74);
  - a pick-up matched by the objective's text, waiting 15 s (#100);
  - a second attacker handled before looting (#103);
  - a corpse seen at the start is not our kill (#106).
- *Capability:* a verifier that claims a pick-up only when at least two signals agree (the tracker count rises, the item appears in the bags, the object leaves the view), and a kill or loot only when the chat's loot line, the target frame and the corpse agree. It stores the frames. An offline audit then treats any disagreement between the log and a recording as a verifier defect.

## Related

- `AGENTS.md`: the mission ("learns how to play"), the learning loop quoted above, and controller provenance (JEV, RULE, SAFETY, OWNER).
- `docs/agents/ai-sdlc.md:110-111`: do not "teach" a combat rule "to compensate for an unmeasured HUD". This is the general form of the owner's first correction.
- `experiments/002_wow_visual/m4/README.md:622-628`: the 26 September decision after runs 10-13 to stop mark patches, with HUD anchors as the unfinished half.
- `experiments/002_wow_visual/m5/README.md:486-487`: the next step, moving the HUD anchors to the detector.
- The decision-architecture review (`docs/changes/2026-09-27-decision-architecture-review.md`), merged with PR #96 beside the standing architecture (`docs/architecture.md`), diagnoses the same patching pattern from runs 1-84. This note adds the per-run rhythm as the cause (the goal only amplified it), the failure-class table, the owner's repeated redirects, grey-plate tap state and multi-signal verification.
- Issues:
  - epic #85;
  - #88 (the reflex table, which has a "hostile ahead" entry; in this note's reading, learned aggression should feed it);
  - #89 (world model);
  - #92 (perception with uncertainty, including the anchored HUD);
  - #93 (offline learning loop).
- PR #109: the hand-written creature list, a stopgap for learned aggression.
