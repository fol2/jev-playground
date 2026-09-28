# M3 — Jev chooses the actions of a supervised fight

Issue [#5](https://github.com/fol2/jev-playground/issues/5). The owner's intent (23 September
2026): Jev makes the tactical choices; local code only perceives, offers what is possible, runs
bounded skills and stops on safety rules. The owner supervises every live episode.

```text
2560x1320 window frames -> pixel/OCR detectors -> Obs -> Episode rules -> admissible actions
                                                                   |
                                  state packet + one Choice question (only admissible actions)
                                                                   |
                                     Jev (jev-1.13.0) -> choice, probabilities, confidence
                                                                   |
                                      validated -> one bounded skill -> fresh Obs -> ...
```

| File | Role | Proof |
|---|---|---|
| `Fight.swift` | Pure core: HUD detectors, `Obs`, `Episode`, admissibility, state packet, question, reply validation, `SimFight`, `ScriptedJev`, `runFight` | `FightTests.swift` |
| `Tactics.swift` | M3b: the bar's skill cards, the chain book, a chain's steps and breaks, offers and calculations | `FightTests.swift` |
| `FightProbe.swift` | Native shell: capture, keys, held-key watchdog, background loot click, Vision OCR, Jev HTTP, run files | `--dry-run` and argument refusals in `tools/MotorProof.swift` |
| `FightTests.swift` | Counted offline checks on synthetic frames, rules, rejections and a simulated episode | Focus Gate `motor-offline` |

## What Jev decides, and what it does not

Each decision sends the state below and one `choice` question whose criteria are only the
currently admissible actions. The criteria state facts about each action (cast time, what a
melee hit does to a cast, that automatic swings need no further key), never the owner's tactics.

- **Character:** health, mana, in combat, casting and cast progress, weapon enchant, whether
  automatic swings are on.
- **Target:** selected, alive, health, within Lightning Bolt range, position in view.
- **Context:** the last action and its observed result, and events since the last decision,
  including the text of any new red game error ("Out of range.").

Local code keeps what must not wait on a model or be left to it:

- **Admissibility.** For example, no `SELECT_TARGET` while a kill is unlooted, no
  `CAST_LIGHTNING_BOLT` while the range digit is red, no `BUFF_WEAPON` while the enchant icon
  is present.
- **Skill execution and budgets.** Turns and walking have millisecond budgets; the held
  Lightning Bolt key has a watchdog that releases it after 4 s without a refresh; SIGINT
  releases every key.
- **Safety stops.** Player health below 30 %, the owner bringing WoW to the front, 40
  decisions or 150 s.
- **Reply validation.** The model, an admissible choice, probabilities over exactly the
  admissible actions summing to 1 ± 0.02, and a confidence in 0–1. A failed call ends the
  episode; there is no hidden rules fallback.

## Capability catalogue, verified live

| Slot | Action | How it was verified |
|---|---|---|
| 1 | Attack (automatic swings) | Icon matches the spellbook's Attack; melee damage followed |
| 2 | Lightning Bolt | Cast bar OCR; ~2 s cast; about a third of a level-1 beast's health |
| 3 | Healing Wave | Cast bar OCR; health returned to 100 % |
| 4 | Weapon enchant | Told by the owner; costs mana, no health change; icon left of the minimap, 60 min |

That table is the 23 Sept bar. By 24 Sept (level 5) slot 3 held Earth Shock, 4 Healing Wave and
8 Rockbiter Weapon, so fixed slots would have cast Earth Shock to heal. A live run now reads the
bar first: the pointer rests on each slot in the background, Vision reads the tooltip, and each
skill's role comes from its text (`Attack`; a cast with "damage" and a range; a cast that "Heals";
"Imbue"; an item that restores mana or health). A missing role, or one tooltip on two slots (the
pointer was contested), stops the run before any key. One tooltip on two slots first reads the whole bar once more,
1.5 s a slot: a client just launched fetches item data as each tooltip opens (live run 49, 27 Sept). A bar read wholly
empty does too, after 5 s: 8 s after Enter World no tooltip showed at all (live run 53, 27 Sept). The range digit box follows the bolt's slot.

The bar has a working memory (the owner, 25 Sept: remember what was read, to cut rescans), in
`runs/002_wow_visual/memory/skill-bar.json`, which is private and not in the repository.
- **The icons.** Each slot's icon is kept as nine mean colours, compared with the pointer off the bar.
  - Reading all twelve tooltips took about 8 s a run.
  - Now only a changed icon is hovered, plus every spell with a cast time: the bolt's and the heal's
    roles come from their cast, and those cards matter most. (A live cast is waited for by the cast
    bar, not by the tooltip's time.)
  - A rank learnt at a trainer keeps its icon, so an instant spell's card (rank, mana, damage) could
    stay old. The memory is therefore trusted for one hour from the last full read, then the whole
    bar is read again. Deleting the file forces a full read.
- **Stale memory.** If one of those reads differently from memory, the whole bar is read again.
  A bar the roles do not fit is never remembered: the file is removed, and the next run reads all twelve.
- **On saved frames:**
  - The prints of four runs on 25-26 Sept differed by 0-1 per value on average, so no slot changed.
  - The 24 Sept bar, before its two totems, changed in exactly those two slots (78 and 86).
- **The log.** Each `skill_slot` event says whether it was `read` or taken from `memory`.

Until 25 Sept the run held F10 (Camera Zoom Out) for the widest view; the owner then found that view
too far, because it hid the NPCs' "?" and "!". Since 26 Sept `--quests` and `--hunt` set the engine's own
zoom: F10 to the widest view, then F11 back 0.75 s, the distance the owner chose (M4 README, M4j).

A weapon enchant is not required on the bar: a level-1 Shaman has none (live run 10, 26 Sept). Without one,
the chain policy is offered neither `BUFF_WEAPON` nor a chain that needs it; a bolt and a heal are still
required, the heal for the safety rule.

FACE_TARGET is F9, Interact With Target (owner, 24 Sept: "why can't F9 work for everything?"): the
game turns to the target wherever it is and turns on automatic swings, and a forward tap cancels the
walk it starts so a cast can follow. It is offered whenever the target's nameplate is not centred,
including when none is in view: a creature that attacks from behind has no nameplate on screen, and
the old nameplate-steered turn was never offered then.

Two more 24 Sept live findings. The owner's new swing timer pushed the cast bar up 36 px (fill row
1169, was 1205), so a bolt that cost mana read as "did not start". And both live fights that day
stopped at SAFETY_STOP_PLAYER_BELOW_30 with full health, right after the background loot click: no
frame newer than 1 s arrived for about 2 s, and the empty observation read as 0 % health. A fight
now waits up to 2 s for a fresh frame (event `frame_wait`, with the seconds waited) and otherwise
ends NO_FRESH_FRAME; it never turns a missing frame into a health reading. Why the capture goes
quiet after that click is not yet measured.

The second live fight killed its target but then pressed Lightning Bolt 12 times with nothing cast:
"Target needs to be in front of you." was on screen, and zoomed out, an adjacent creature's
nameplate sits mid-screen whichever way the character faces, so FACE_TARGET was not offered. The
owner: "should detect 'you are not face the mob' to trigger F9". A bolt that fails with the game's
facing error now turns with F9 and retries once, inside the same action; the log records it as
a `reflex` row with controller RULE, apart from Jev's choice. START_MELEE is also F9:
the bar's Attack is a toggle, so pressing it while swinging would stop the swings. A fight needs
bolt, heal and enchant skills on the bar; a hunt also needs food and drink.

The owner's taught tactics, recorded as the reference Jev is not given: enchant before a
fight; pull at the farthest range where the spell's hotkey is no longer red; cast
continuously until first hit; then rely on automatic swings, because melee hits delay casts;
heal only when needed.

## Perception, calibrated on this layout

All boxes are capture pixels of the 2560×1320 window; `HUD` in `Fight.swift` holds them.

- **Health.** Player and target bars are 130 px of green on row 997. Mana is on row 1013.
- **Combat.** The player portrait ring is about 750 red pixels in combat and 0 outside. It
  lingers for seconds after a kill, so a kill is not gated on it clearing.
- **Range.** Slot 2's hotkey digit turns dark red (r 90–162, g and b below 70) beyond
  Lightning Bolt range: 8–10 px on nine labelled frames, 0 in range. It lags a target
  change by up to about a second. This corrects M2's claim that the client shows no range
  colouring.
- **Casting.** The cast bar track and yellow fill (row 1205, 216 px). With Press and Hold
  Casting, held casts chain without a gap, so a new cast is a fill that drops back.
- **Weapon enchant.** About 234 green pixels of its icon when present.
- **Errors.** Salmon-red text below the top centre. It lingers about 3 s, so only a new
  one counts as a failure. Its text is OCR'd into the state.
- **Corpse.** Its floating grey name is larger than live nameplate text (OCR box ≥ 22 px);
  the corpse is about 200 px below it. The name is matched fuzzily, because the floating
  "XP: 15" can overlap it ("Xypenil Uuldren").

## UI findings

- **No whole-button range colour in the built-in UI.** On the owner's request the Options
  were searched for "range" (no results) and the Action Bars page was read; neither offers it.
  Whole-button colouring comes from addons such as
  [tullaRange](https://www.curseforge.com/wow/addons/tullarange) or
  [Bartender4](https://www.wowace.com/projects/bartender4/issues/1491). None was installed.
- **Press and Hold Casting** (Options → Gameplay → Combat), enabled by the owner on
  23 September 2026. The tooltip says: "allows the player to press and hold a keyboard hotkey
  to continually cast a spell on an ActionBar without having to repeatedly press the button.
  This only supports keyboard hotkeys." M3 holds slot 2 while Jev keeps choosing Lightning
  Bolt, which removes the gap between casts.
- **Auto Loot** is on. With **Open Loot Window at Mouse**, the loot window briefly appears at
  the click point; the items can arrive more than 1.2 s after the click, so the chat is polled.
- **Esc** first clears a target before it opens the Game Menu.
- **Vision's first OCR in a process takes about 30 s**, so the shell warms it up before any
  decision needs it.
- **World refresh.** This client can announce "The world around you will refresh in N
  minutes". The episode refuses to start while that notice is showing.

## Live episodes, 23 September 2026

Supervised; level-1 neutral beasts (Juvenile Vuldren); window-only capture; WoW not frontmost.
Runs `m3_jev_1` to `m3_jev_7` are kept locally under `runs/002_wow_visual/`. They used the
scratch predecessor of `FightProbe.swift`, with each fix below applied before the next run.

| Run | Jev's choices | Outcome | What it exposed |
|---|---|---|---|
| 1 | Select, Bolt, Wait, Bolt, Bolt, Select, Bolt, Stop | Kill; not looted | The kill rule waited for the combat ring, so a new target was offered; a stale red error counted as a failure. Fixed. |
| 2 | Loot, Select, Bolt, Wait, Bolt, Loot | **Killed and looted** (6 decisions, ~11 s) | A false corpse at the start cost one call; reset by the loot skill. |
| 3 | Select, Bolt, Stop | Stopped | The range digit threshold was too bright; the target was out of range. Fixed and re-validated on nine frames. |
| 4 | Select, Bolt, Approach, Bolt, Wait, Loot, Stop | Kill; loot missed | "XP: 15" overlapped the corpse name. Fixed with fuzzy matching. |
| 5 | Loot, Stop | Run 4's corpse looted | The loot lines arrived after the 1.2 s check. Fixed by polling. |
| 6 | Select, Bolt (held), Bolt, Bolt, Loot | **Killed and looted** (5 decisions, ~11 s) | The first episode with Press and Hold Casting: no gap between bolts. |
| 7 | Select, Bolt (held), Bolt, Bolt, Loot | **Killed and looted** (5 decisions, ~12 s) | Chained held casts now read as new casts (fill drop). No damage taken. |

Across the seven runs: 36 Jev calls, about 24k input and 2k output tokens in total,
latency p50 0.35 s and p95 0.48 s. Jev chose to approach when the target was out of range,
waited while a cast was in flight, and stopped when the state left it no clear option. It
never chose `START_MELEE`: every target died before or just as it reached the character.

Before Jev, five discovery fights used fixed scripts and taught the catalogue, the range and
error cues and the owner's tactics. Their lessons are folded into the rules above.

## Limits

- Seven supervised episodes against one creature type: no rate, no hostile packs, no deaths,
  no ranged or casting enemies.
- One layout and window size; the boxes move with UI scale, Edit Mode or window size.
- Melee, healing under pressure and a corpse far away have not been exercised under Jev.
- **Loot, live run 59 (27 Sept).** The owner saw nothing looted. Of three kills at Lightning Bolt range, two read
  "no corpse label visible", because the far corpse's name was under the label's 22 px. One looted a Chipped Claw
  and Stringy Wolf Meat, but it was taken for the corpse seen at the fight's start: the loot was undone, and
  SELECT_TARGET was tried 37 times until the decision limit.
  - Now a dead target still selected is looted first by Interact With Target (F9). The game walks to the corpse and
    loots it, however far or small its label. A walk that loots nothing within 7 s is stopped by a forward tap, and
    the label click follows as before.
  - Our own kill after a corpse seen at the start clears that old corpse (`Episode.update`), so its loot ends the
    fight `KILLED_AND_LOOTED`.
- **Loot, live run 64 (27 Sept).** The owner again saw no loot. After each kill the game cleared the target and no
  label stood over the corpse, so the fight read "no corpse label visible" six times. Interact With Target had nothing
  selected.
  - The fight keeps the plate of the creature it fights while it lives. With no target after the kill, the pointer
    rests on up to 12 points below that plate (`corpseHoverPoints`).
  - The hover follows M4's rule (review of #71):
    - First the pointer rests off every unit until two fresh frames show no tooltip.
    - At each point, two reads on frames captured after the move must both say "Corpse" and name the fought creature
      (`corpseTooltip`, `confirmedCorpse`). One read may be a tooltip fading from the last point.
    - After a point with any tooltip, the pointer rests off again, and it rests off after the loot.
  - Only then is the point right-clicked, and chat is polled for the loot line, as before.
  - A right-click with no loot line lets Jev loot again once. The second ends the fight `KILLED_NO_CORPSE`.
- **Evidence.** Sim only: `FightTests` covers the points and the reads. Live: the next run.
- **Loot and fight back, live run 66 (27 Sept).** Every fight still ended `KILLED_NO_CORPSE`, and the character died.
  - The plate reader read no plate in any quest fight that day (8 runs), so the plate hover never ran.
  - A quest's fight back sought only M3's two creatures (`fightNames`). A grey "Roiling Winds" label 41 px tall stood
    over the corpse, and was not taken.
  - Attacked with nothing selected, a fight took combat alone for a kill (`Episode.update`). It was offered LOOT and
    STOP but not SELECT_TARGET. Fourteen fight backs ended within a second, and the way to safety spent its rounds on
    them without a walk. The owner's recovery rule then resurrected the character at the Spirit Healer.
  - Now:
    - A kill is a target seen alive that has gone. Combat alone offers SELECT_TARGET (Tab).
    - The fight adds the creature it fights, read from the target frame while it lives, to the corpse names.
    - The hover also tries below a label that names the corpse, then round the character, where a creature killed in
      melee falls (`corpseSearchPoints`). Every point is confirmed by the corpse's tooltip first. The label is never
      clicked blind: a living creature's plate of the same name reads as one. The search stops after 30 s.
  - Evidence: sim only (`FightTests`). Live: the next run.
- **Fight back from behind, live run 68 (27 Sept).** The character died on the way to safety.
  - Its fight back was attacked by Roiling Winds casting from behind. Tab finds only an enemy in front, and six
    SELECT_TARGETs read "no target selected" while health fell from 69% to 53%.
  - Jev then chose STOP. The fight ended `JEV_STOP`, the way to safety (M4r) gave up, and the character died where it
    stood.
  - SELECT_TARGET's check was also wrong. It read the plate reader, which read no plate in any quest fight that day,
    and in run 67 it said "no target selected" once when Tab had in fact selected a Roiling Winds.
  - Now:
    - STOP is offered only out of combat.
    - In combat, SELECT_TARGET tabs, then turns a quarter (E for 600 ms, at the walk's measured 150° a second) and tabs
      again, a whole turn at most.
    - The target frame is its evidence (`Episode.alive`), not a plate. The search is pure (`searchTarget`), and Jev's
      SELECT_TARGET text says that it turns round in combat.
    - Every key the live fight host presses is granted to the watchdog first, the turn round's E included, and the motor
      proof checks it (review of #76). The turns round are kept apart from the approach's turn budget.
  - Evidence: sim only (`FightTests`: the search behind, a whole turn at most, one Tab out of combat); live: the next run.
- **Buff when needed, live run 72 (27 Sept).** The owner: buff and heal "are not in the skills chain but they are needed
  when needed". Rockbiter Weapon, trained that day, was offered as BUFF_WEAPON in every decision of run 72 and never chosen
  (13 bolts, no enchant). Now a chain fight casts the bar's weapon enchant first, as a rule (`reflex`, controller RULE),
  when the HUD shows it not active; once a fight, and it stays Jev's offer after. The enchant reader was checked live: the
  Rockbiter icon (60 min) read `buff` false before the cast and true after it. Evidence: sim (`FightTests`); live: the next run.
- Labels are the author's, from the saved frames and chat lines.
- The fixed-script and Jev runs were not compared on the same episodes, so nothing here
  claims Jev beats rules.

## M3b — Jev chooses chains, and breaks them

The owner, 25 Sept: the fight should be Jev's to decide and improve, with a dictionary of the skills,
the prepared calculations and the true state of the fight; flat, or one or two levels; "not every move
needs JEV. but JEV can decide to break the chain"; the chain can differ by level, preset "from online
or from our experience" or customised, changed outside the fight; "in the fight, jev can also choose
specific skill ... if jev want micro-control". With `--graph runtime/skyborne-fight.graph.json` a fight
runs this way; without it, the legacy flat policy above runs unchanged.

- **One flat node.** Each decision offers up to four chains (`CHAIN_1`-`CHAIN_4`), every admissible
  single skill, and `CONTINUE` while a running chain's next step can be done. Jev may first read the
  bar's skills, `learning/knowledge/combat-mechanics.md`, the owner's `## Fighting` rules or this fight's
  steps: at most two calls a decision, within the fight's 4 s decision deadline.
- **A chain runs without calls.** Its steps (a role: bolt, shock, melee, heal, buff, face, approach,
  wait) each run until a condition holds: `once`, `contact` (a hit on the character, or for melee the
  creature losing health to the swings) or `dead`, with an optional cap. The script asks Jev again at
  a break: health below 30% in combat (then only HEAL is offered, as before), the target dead, a step
  that failed or cannot be done now (out of range, the shock cooling down), 20% health lost since Jev
  last chose, or an 8 s check-in. Every step, Jev's or the chain's, goes through the same freshness,
  admissibility and owner checks; a rejected step drops the chain.
- **The chain book** (`learning/knowledge/fight-chains.jsonl`) holds each chain's class, levels, the
  roles it needs, its steps and its source. Only `accepted` rows that fit the class, the level (when
  read) and the bar are offered: the owner's bolt-pull-melee, melee-to-kill, bolt-to-kill (levels
  1-10) and the guides' shock-melee. `bolt-pull-shock-melee` is a `candidate`, not offered. A chain is
  added or changed outside any fight: a reviewed change to the book is its promotion.
- **The bar's cards.** The tooltips read at the start give each skill's rank, mana, cast, range and
  cooldown; `learning/knowledge/shaman-skills.jsonl` (44 rows for levels 1-20, from a web search on
  25 Sept, client build 1.60.1.70009) adds the level it is learned at and where its sources disagree
  with a live tooltip (Lightning Bolt 14-17 live against 15-17, Earth Shock 17-20 against 19-22,
  Rockbiter +45 against +49, on client 1.60.1.69977). The tooltip wins.
- **The shock.** An instant damage spell with a cooldown on the bar is now a role (Earth Shock on the
  24 Sept bar). It is offered while its own hotkey digit is white and its tooltip cooldown has run,
  and the live shell waits out a cast in flight, taps it once, and reads its mana drop or a new red
  error. A cast that did not go off while the game's facing error shows turns with F9 and retries once,
  for the bolt and the shock alike (`turnAndRetry`); a chain then judges the step by the retry.
  Earth Shock's digit is a muted red (about 125, 80, 75) over a yellow icon, which the bolt's
  dark-red rule missed on every 24 Sept frame; `mutedRedDigit` reads it. On the 24 Sept frames (Earth
  Shock on key 3) it reads red on none of the 407 without a target and on 30 of the 518 with one, all
  while the creature was still being approached; two red and three white were checked by eye. Below
  30% health the screen's red tint reads as red too (26 frames on 23 Sept, all at 29% or less): the
  shock is then left out, and in combat only HEAL is offered there anyway.
- **Calculations.** Measured from the frames, per skill: uses this fight, the target's and the mana's
  percentage change per use, uses affordable and uses to kill; melee's target percentage per second;
  the shock's time to ready; the character's health lost per second since combat began. A value no
  frame has shown yet is null, never a guess.
- **Quest runs read the bar.** A quest run's fight back (M4i) pressed the default keys: the 23 Sept
  bar's heal on key 3 (Earth Shock by 24 Sept) and buff on key 4 (Healing Wave). `--quests` now reads
  the tooltips first, as a hunt does. `--quests` and `--hunt` take `--fight-graph PATH`.

Proof, simulation only: 66 new fight checks (207). In SimFight the chain fight kills and loots in 5
Jev decisions and 3 unasked steps, against 8 decisions for the legacy policy; a fast health loss breaks
a chain and Jev can heal; a long fight checks in and Jev can go on; below 30% only HEAL is offered;
a melee step until contact waits for the swings to land before shock-melee's shock;
an unoffered reply is JEV_STOP and a throwing client JEV_ERROR. `tools/sdlc motor` runs the chain
dry-run in the gate. Not built: reading the character's level (the portrait badge defeats Vision OCR;
the portrait's tooltip is next) and the frame's absolute health and mana numbers; fight experience
that proposes candidate chains; several attackers. Nothing here has run live.

**Range digits read the digit alone (25 Sept).** The bolt's digit box took in the slot's left edge,
which a held key lights orange, and read it as red: mid-cast, with the bolt plainly in range, the
fight saw it out of range (one 24 Sept fight walked in on it), and a chain's second bolt would have
broken to Jev. Both digit boxes now cover the digit's own 16 columns. On the perception set 77 frames
stop reading the bolt out of range, all checked by eye, the "2" white on each: 74 with the key held
(one of them with no target), 3 with neither (two under the low-health tint). On 24 Sept the bolt
now reads out of range on exactly the 9 frames whose "2" is red by eye, and never while the shock
(20 yd) reads in range. One more fight check (208). Proof: offline, on saved frames.

## M3c — hit again after a kill: fight the attacker, the corpse waits (28 Sept)

Live run 90: a walk was attacked, and SAFETY's fight back killed a Scrawny Ursera. After a kill the fight offered only
LOOT_CORPSE, HEAL and WAIT ("a kill must be looted first"). So it spent 30 s hovering for the corpse while a second
Scrawny Ursera attacked, and the character died ("You died." in chat, 0/98). The run read the quests and walked on
before it saw the death.

- **`hitAfterKill`** (`runFight`, RULE): after a kill seen on an earlier frame, in combat, with nothing alive selected,
  another creature is attacking when either:
  - the character's health fell since the previous observation; or
  - combat is still on `FightLimits.combatAfterKill` (8 s) after the kill. The ring lingers only a few seconds after the
    last attacker dies, and a heal each step can hide every fall, but not the combat an attacker keeps up.

  The kill is set aside, SELECT_TARGET is offered again, and the attacker is fought. That corpse, the attacker's, is looted
  when it falls; the first is left. The dying creature's own last hit, on the kill frame, does not count. Logged
  `reflex`.
- **The corpse search** (LiveHost `hoverCorpse`) and the walk to a still-selected corpse (Interact With Target) both stop
  as soon as the character's health falls. LOOT_CORPSE then answers "not looted: hit while …". That is not "no corpse",
  which would end the fight with the attacker still on.
- **Evidence:**
  - Sim: `FightTests` checks the predicate: a fall, and combat kept up past the linger, versus a lingering ring, out of
    combat, a live target, and once looted.
  - Sim: a whole `runFight` against `SimFight` with a second attacker and a 2.5 s heal: the kill is set aside once, the
    attacker selected, killed and looted (`KILLED_AND_LOOTED`).
  - Live: not yet run.

### M3c's corpse at the start (28 Sept)

Live run 93: the fight began with a corpse in view (`oldCorpse`, counted as killed so it can be looted), and the kill's
clock started then. The creature being fought died more than 8 s later, with the combat ring still on, and that read
as "hit again after the kill". Its own kill was set aside. Then 30 SELECT_TARGETs out of combat found nothing, and the
fight, the hunt and the run ended DECISION_LIMIT.

- Only our own kill counts: a corpse seen at the start neither starts the clock nor makes a kill "before".
- `SimFight` now ends combat 3 s after its last creature dies (it lingered forever), and bolts can take time
  (`boltSeconds`).
- Sim: a fight that starts on a corpse, with a live target and 1.5 s bolts, is killed and looted with nothing set aside.
  Without the fix it ends DECISION_LIMIT, as run 93 did.

## Reproduce

```sh
tools/sdlc motor   # builds and checks M0, M1/M2 and M3 with no live effect
```

The fight's reflexes are the engine's reflex table since #88 (`engine/Controller.swift`, `ReflexTable.standard`; the
entries are listed in [the engine's README](../engine/README.md)): the owner's takeover, the start's enchant (once, and in a
fight back only at 60 % health or more), the heal floor (`admissible` offers HEAL alone under 30 % in combat) and the stop
out of combat (`SAFETY_STOP_PLAYER_BELOW_30`) are its; `FightLimits.playerSafety`, `healMana` and `buffAtHealth` alias
`ReflexLimits`. `BUFF_WEAPON` is no longer offered to Jev (the fight graph and `FightTactics.offerNames`); the tactics
(`hitAfterKill`, the chains, target selection) stay the fight's. Every build with `Fight.swift` includes `engine/World.swift`
and `engine/Controller.swift` (`$R` below).

```sh
V=experiments/002_wow_visual
C=experiments/001_wow_fishing/probes/background-click
R="$V/runtime/Runtime.swift $V/runtime/Input.swift $V/runtime/DecisionGraph.swift $V/runtime/Experience.swift $V/engine/World.swift $V/engine/Controller.swift"
swiftc -parse-as-library $V/m0/Motor.swift $V/m1/Plate.swift $V/m3/Fight.swift $V/m3/Tactics.swift $V/m3/FightTests.swift $R \
  -o /tmp/fight-tests && /tmp/fight-tests   # from the repo root: the checks load the fight graph and its files
swiftc -O -parse-as-library -D SEEK -D FIGHT $V/m0/Motor.swift $V/m0/Probe.swift $V/m1/Seek.swift \
  $V/m1/Plate.swift $V/m1/SeekProbe.swift $V/m3/Fight.swift $V/m3/Tactics.swift $V/m3/FightProbe.swift $R \
  $C/Adapter.swift $C/NativeWindowServerPreparation.swift $C/NativeBackgroundClickTransport.swift -o /tmp/m3-fight
/tmp/m3-fight --preflight   # JSON facts only
/tmp/m3-fight --dry-run     # SimFight + a scripted chooser: no capture, input or network
/tmp/m3-fight --dry-run --graph $V/runtime/skyborne-fight.graph.json   # M3b's chains, canned graph replies
```

`--execute --keys wqe` runs a live episode. It needs the owner's current authority, WoW running
but not frontmost, and `TYPESAFE_API_KEY` in the environment; the key is never printed or written.
Recovery after a crash: `m0-probe --release --keys wqe`, then tap 1–4 and Tab in WoW.
