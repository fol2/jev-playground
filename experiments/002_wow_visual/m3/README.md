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
| `FightProbe.swift` | Native shell: capture, keys, held-key watchdog, background loot click, Vision OCR, Jev HTTP, run files | `--dry-run` and argument refusals in `tools/motor_offline.py` |
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
- Labels are the author's, from the saved frames and chat lines.
- The fixed-script and Jev runs were not compared on the same episodes, so nothing here
  claims Jev beats rules.

## Reproduce

```sh
python3 -m tools.motor_offline   # builds and checks M0, M1/M2 and M3 with no live effect
```

```sh
V=experiments/002_wow_visual
C=experiments/001_wow_fishing/probes/background-click
swiftc -parse-as-library $V/m0/Motor.swift $V/m1/Plate.swift $V/m3/Fight.swift $V/m3/FightTests.swift \
  -o /tmp/fight-tests && /tmp/fight-tests
swiftc -O -parse-as-library -D SEEK -D FIGHT $V/m0/Motor.swift $V/m0/Probe.swift $V/m1/Seek.swift \
  $V/m1/Plate.swift $V/m1/SeekProbe.swift $V/m3/Fight.swift $V/m3/FightProbe.swift \
  $C/Adapter.swift $C/NativeWindowServerPreparation.swift $C/NativeBackgroundClickTransport.swift -o /tmp/m3-fight
/tmp/m3-fight --preflight   # JSON facts only
/tmp/m3-fight --dry-run     # SimFight + a scripted chooser: no capture, input or network
```

`--execute --keys wqe` runs a live episode. It needs the owner's current authority, WoW running
but not frontmost, and `TYPESAFE_API_KEY` in the environment; the key is never printed or written.
Recovery after a crash: `m0-probe --release --keys wqe`, then tap 1–4 and Tab in WoW.
