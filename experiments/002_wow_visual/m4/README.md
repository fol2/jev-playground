# M4a — Jev chooses the moves of a supervised walk

Issue [#5](https://github.com/fol2/jev-playground/issues/5). M3 let Jev choose the actions of a
fight. M4a applies the same split to walking to a point on the zone map. Local code reads the
screen, offers only the moves that are admissible here, runs each move as a bounded skill and
stops on safety rules. Jev chooses every move. The owner supervises every live walk.

```text
2560x1320 window frames -> minimap arrow (facing) + coordinates OCR (position) + M3 HUD (combat, health)
                                                   |
     state: position, destination, the last six moves and what each achieved, headings blocked near here
                                                   |
                 Jev (jev-1.13.0) chooses one admissible move -> walk skill -> fresh observation
```

| File | Role | Proof |
|---|---|---|
| `Nav.swift` | Pure core: arrow and coordinate readers, map geometry, moves, admissibility, state packet, the walk skill, `runNav`, `SimNav`, argument parsing | `NavTests.swift` |
| `NavProbe.swift` | Native shell: capture, coordinates OCR, pid keys, Jev HTTP, run files; `--replay` and `--sim-jev` rehearsals | `--preflight`, `--dry-run` in `tools/MotorProof.swift` |
| `NavTests.swift` | Counted offline checks on synthetic arrows, rules, rejections and simulated walks | Focus Gate `motor-offline` |

Shared with M3: the question/response helpers remain in `m3/Fight.swift`; the input
owner now lives in `runtime/Input.swift`. The integrated evidence and decision boundary
is described in [the runtime decision record](../../../docs/changes/2026-09-24-runtime-boundaries.md).

- **The generic Jev question and reply validation** (`JevAction`, `actionQuestion`, `parseChoice`).
- **`LiveKeys`**, the pid-targeted key state that M3's review hardened:
  - a key's watchdog grant is taken before its key-down is posted;
  - key events are posted under one lock;
  - a watchdog releases held keys;
  - a key-up that fails every attempt is retried by the next sweep, and no later grant can
    postpone that retry;
  - events are logged after the key lock is released, so a blocked log write cannot hold up the
    exit sweep;
  - no key goes down after the exit sweep.

  Before M4a this logic lived inside M3's live shell and ran only live. Its rules now have 13
  offline checks against a fake key sink. The walk skill is also in the core, so `SimNav` runs
  the same walk code and key rules that the live shell runs.

## Why Jev chooses the detours

A scratch walker steered by the same perception walked open ground well. In the village, its
fixed recovery failed four times in a row against a tree and a ramp. That recovery was: back
off, turn 70°, and alternate sides. Choosing a detour needs the history of what was tried and
what it achieved, which is what a decision model is for.

An earlier scratch fight loop showed the opposite risk. Offered an uncapped turn and no history,
Jev chose that turn 40 times in a row. So M4a gives Jev the history and keeps the caps local.

## What Jev decides, and what it does not

| Move | What it does (the criterion Jev reads) |
|---|---|
| `GO_TOWARD` | Runs straight at the destination for up to 3 s, re-aimed each tick. Ends early on arrival or when blocked. |
| `DETOUR_LEFT_45`, `DETOUR_RIGHT_45` | Runs up to 3 s on a heading 45° left or right of the destination's bearing. |
| `DETOUR_LEFT_90`, `DETOUR_RIGHT_90` | The same, at 90°. |
| `BACK_TRACK` | Runs up to 3 s directly away from the destination. |

Each decision sends a state and one `choice` question. The state holds:

- the position and facing;
- the destination: its label, distance, bearing and the signed turn needed;
- progress: the best distance so far and decisions since it improved;
- the last six moves, each with its heading, time, distance moved, distance before and after,
  and whether it was blocked;
- the headings blocked near here;
- a note on the units used.

The question asks which move is most likely to get the character to the destination.

Local code keeps what must not wait on a model or be left to it:

- **Admissibility.**
  - A move is not offered if its heading lies within 25° of a heading that was blocked within
    0.5 map units of here.
  - The same move is not offered a fourth consecutive time without a new best distance.
- **The walk skill.**
  - Steering uses Q/E pulses at a measured turn rate, with a 20° deadband. Errors over 100° stop
    running before the turn.
  - W stays held under a 1.5 s watchdog grant.
  - A move is **blocked** when W was held for 1.5 s with under 0.1 units of movement. An
    unreadable frame does not reset that window. A move that
    ends by time with W held for at least 1 s and no movement is also blocked: it spent its time
    turning.
  - A move that runs its full time leaves W held, so the next move continues without a stop.
- **Stops.**
  - `ARRIVED` (within the arrival radius).
  - Safety: `COMBAT` (the portrait ring), `LOW_HEALTH` (below 30 %), `OWNER_TOOK_FOCUS` (WoW
    frontmost).
  - `HUD_UNREADABLE` (six frames in a row).
  - `NO_PROGRESS` (10 decisions without a new best distance) and `NO_ADMISSIBLE_MOVE`.
  - 40 decisions or 180 s.
  - A failed Jev call or an invalid reply ends the walk. There is no rules fallback.

**Jev is not offered STOP.** With STOP in the set, Jev chose it the moment the first move was
blocked, in all 10 rehearsals across three phrasings of the question and of STOP's
description. On one blocked state, Jev put 0.54 on STOP as first sent, and 0.42 even with
structured criteria saying it never reaches the destination. With STOP removed, it put 0.32 and
0.27 on the two 45° detours.

A walk has no danger that the local stops miss. Ending a walk is therefore local, and the owner
can take over at any time by bringing WoW to the front.

## Perception, calibrated on this layout

All boxes are capture pixels of the 2560×1320 window.

- **Facing: the minimap arrow** (x 2406–2440, y 182–212). The arrow is a silver cone with a navy
  dot at its tail.
  - The first live walk showed why the scratch rule failed. That rule took the bearing from the
    navy dot to the farthest silver pixel. Quest icons often sit beside the arrow, and their
    highlights are silver too: whenever an icon was next to the arrow, the "farthest silver
    pixel" belonged to the icon.
  - The rule now counts only silver connected to the navy dot. The facing is the ray from the
    dot along which that silver runs longest, which is the cone's axis. An icon adds a short
    blob, never an 8–10 px run.
  - Where the navy beside silver falls in several parts and two or more are dot-sized (within
    7 × 7 px, 9 px at least), the tail is the part silver rings on most sides. Live run 36
    (27 Sept): a quest area's blue band crossed the arrow's tip, its pixels beside the tip pulled
    the "dot" there, the facing read 258–344° for 131°, and the walk turned on the spot until
    `NO_PROGRESS`. Otherwise every part counts, as before: over water the dot joins the water's navy.
    - On that run's frames the rule reads 113–124°. A synthetic band is a check.
    - On the regression set, 107 of 2,453 facings moved. 64 moved 10° or less. Of the 25 that
      moved more than 30°, the author checked 7 by the arrow's pixels (m2 turns, a water frame,
      two walks), and in each the new reading lies along the cone and the old one did not.
    - A first rule, the largest compact part of all the box's navy, moved 846 facings: over water it
      picked a stray fleck, and it was not kept.
  - On eight lossless (PNG) captures turning in place beside three quest icons, it was within
    12° of the author's labels. Successive readings stepped 46–59° per 300 ms Q press.
  - Saved JPEGs do not replay the live frames faithfully. The same frame decoded two ways
    differed by up to 69 per channel inside the arrow box. Through the live decode path, one of
    16 labelled JPEG frames read 56° off. Calibrate on PNG captures.
- **Position: the coordinates text under the minimap** (x 2322, y 300, 200×34). It is OCR'd
  after a ×3 upscale and parsed as `44.8,28.1`, `44.8, 28.1` or `44.7.27.9`.
  - It was read on all 61 saved frames at this layout.
  - It was never unreadable in 99 live looks.
  - 25 Sept, the first live `--quests` run: 0.46 from a quest giver, its orange name covered the
    text ("43.0, 23к7 Eнн") for six looks, and the walk stopped `HUD_UNREADABLE`. Two changes:
    - A move that sees the arrival radius now ends the walk `ARRIVED` without one more reading.
    - When the raw text does not parse, it is read again with coloured pixels blanked, under two
      masks, and counts only when both agree. On 2,410 saved frames at this layout, the masks agreed
      with each other 1,762 times where the raw text parsed, and never with a point other than the
      raw one. Either mask alone disagreed with the raw text 81 times, mostly a 4 read as 1 or 9 (once
      the raw text was the one wrong), so neither is used alone.
      The raw reading, which parsed on 2,396 frames, is unchanged.
- **Geometry.** The zone map is 3:2, so one x unit covers 1.5 y units of ground. Distances are
  in y units.
  - Running covers about 0.2 per second: 0.63–0.78 per move of 3.0–3.3 s.
  - A 700 ms turn pulse turned 119°, about 170°/s against the assumed 150°/s. The overshoot
    stays inside the deadband.
- **Destinations**, read by hand in this slice from the world map (M):
  - Each "?" or "!" pin's pixel offset from the player arrow is divided by about 7.42 px per
    x unit and 4.99 px per y unit, then added to the map's "Player: x, y" line.
  - On the minimap, one y unit is about 19 px, so its 97 px radius covers about 5 units.
  - Hovering a pin names its quest.

## Perception regression set

Each reader above was calibrated once, on its own frames. Nothing re-ran them afterwards, so a later
change to one threshold could shift readings elsewhere without anyone seeing it. `m4-nav --pixels DIR`
now runs every pixel reader on every saved frame at this layout: the M3 bars and flags, the target
plate and the ground under it, the facing, the quest area, nameplates, red names, minimap icons, world
map pins and quest marks, and (M3b) the shock's range digit. It writes one line per frame. [perception.jsonl](perception.jsonl) holds the
accepted readings: the frame's path under `runs/002_wow_visual/`, the SHA-256 of its bytes, and numbers
only.

- **The set.** 2397 frames at 2560×1320 from 83 saved runs, 22–24 Sept. The half-size demo frames are
  skipped. Hits on these frames:
  - facing on 2286 frames; target plate on 1080;
  - quest area on 815; minimap icons 1162 on 794 frames;
  - red names 711 on 555 frames; nameplates 684 on 376 frames;
  - map pins 652 on 186 frames; quest marks 90 on 79 frames.

  The replay takes about 8 s here and printed identical bytes on two runs.
- **The gate.** In the local gate, the motor proof replays the set from the clone's `runs/`, from any
  worktree. It holds on any reader that reads a frame differently, and on a missing or changed frame.
  Each hold names the reader and up to three example frames. After reviewing those frames, accept the new
  readings with `tools/sdlc motor --update-perception`, and commit the file with the change.
  The file's diff is then the review record: it shows which frames each reader now reads differently.
- **Proof.** Loosening the red-name cell threshold from 4 to 3 pixels held on 122 frames' red names.
- **What CI can check.** The frames are private captures and stay local, so a hosted runner checks less:
  - that the accepted file is well formed and still has at least 2397 frames;
  - that a black frame reads nothing, and that a frame of the wrong size is skipped;
  - that the comparer finds a changed reading, changed frame bytes and a missing frame planted in the
    accepted set.
- **Not in the set, and why:**
  - These are the readings that were accepted, not labels. A fix and a regression both show up as a
    change, and a reviewer decides which one it is.
  - The OCR readers (coordinates, tracker, target, names and tooltips) are left out. Their text can
    carry names, and a macOS Vision update can change them. Add them when an OCR change lands.
  - Saved JPEGs are not live frames (see facing above). The set catches code changes, not calibration.

## Rehearsals and live walks, 23 September 2026

**Rehearsals** (`--sim-jev`): the real Jev against a simulated map, before any live walk. On the
final code, with STOP not offered:

| Scenario | Outcomes | Jev's pattern |
|---|---|---|
| A fence across the direct line | Arrived twice (12 and 16 decisions) | Straight until blocked; both 45° detours were blocked; 90° along the fence until clear, then straight |
| A U-shaped pocket open behind | `NO_PROGRESS` twice (12 decisions) | 45°, then 90° left and right along the closed end; never `BACK_TRACK` |

**Live walks.** Supervised; window-only capture; WoW not frontmost; the destination was Yala
Windwatcher, the Elemental Unrest turn-in. The runs are kept locally under
`runs/002_wow_visual/`.

| Run | Start → target (radius) | Jev's moves | Outcome |
|---|---|---|---|
| 1 | 43.2, 23.8 → 47.1, 21.8 (1.0) | Go ×2; detour right 45°, left 45°, right 90°, left 90° ×2; back ×2 | `NO_ADMISSIBLE_MOVE` at 43.4, 23.4 after 9 decisions |
| 2 | 43.4, 23.4 → 47.1, 21.8 (1.0) | Go ×8 | **Arrived** at 46.5, 21.7: 8 decisions, about 26 s, 84 looks, none unreadable |
| 3 | 46.5, 21.7 → 47.2, 21.7 (0.4) | Go ×2 | **Arrived** at 47.0, 21.7 |

**Run 1.** The straight line ran into a merchant's tent and bench. The first reader then misread
the facing whenever quest icons touched the arrow, so a detour turned the wrong way (E once,
then Q three times). That pocket, and the waste of a move that spent its time turning, led to
the ray reader and the late-block rule before run 2.

**After run 2**, Yala stood about 20 px ahead on the minimap, behind a tree; run 3 closed the
gap. A Click-to-Move right-click on her then opened the dialogue. Elemental Unrest was handed in,
and the character reached level 3.

Jev was then asked whether to accept her follow-up quest, "Agitators", and declined it (0.79).
The owner overruled: taking quests is the owner's policy. The state had lacked the owner's goal,
and it described declining as free. That is the same draw towards a safe exit that STOP showed.
The quest was accepted by hand.

Across the three walks there were 19 Jev calls, about 18.7k input and 1.4k output tokens.
Latency p50 was 0.52–0.60 s and p95 0.58–0.98 s. Each walk ended with every key released.

## M4b — Jev chooses how to hunt for quest creatures

`Hunt.swift` (pure core, `SimHunt`), `HuntProbe.swift` (live shell) and `HuntTests.swift`.

- **Question.** A hunt reads:
  - the objectives tracker (upscaled OCR);
  - the selected quest's ring on the minimap;
  - the nameplates in view;
  - the target frame.

  It offers Jev only the admissible actions:
  - fight the selected creature;
  - Tab to the next target;
  - look around;
  - walk (towards a creature that counts, towards the area, detours, or compass headings);
  - rest;
  - eat and drink.

  Each fight is one M3 episode. The state carries costs as facts, not rules: fight length, health
  cost, mana per Lightning Bolt, cast pushback and the chase. Skysight's +10% run speed is given
  with its numbers.
- **From the owner's recorded demo (23 Sept).** Changes made after watching the owner play:
  - no mana gate before a pull (29 fights, often started at 10-30% mana);
  - EAT_DRINK below 80% health or 50% mana;
  - grey (tapped) plates are skipped.

  `Tabletop.swift` holds 13 demo situations as choices. Live Jev agreed on 13/13, re-run on 24 Sept
  after the chase fact changed. Offline, `--check` only validates the scenarios.
- **Missing evidence is never completion or calm** (from the peer review of 24 Sept).
  - An objective is finished only when its own line reads done >= need, or when "Ready for turn-in"
    appears straight under its quest title with no unfinished line of that quest. That is how the
    demo's tracker shows a finished quest; seeing both is treated as a misread.
  - A line that has merely vanished stays remaining. That covers an OCR miss, a title-only read and
    a collapsed tracker.
  - `vitals()`, `look()` and `survey()` return nil when there is no frame, or when the newest frame
    is older than 1 s by capture PTS. REST then stops and LOOK_AROUND does not turn. M3's live frames
    use the same bound, so a stalled capture in a fight reads as no frame (a safety stop).
  - After each Jev reply the hunt re-reads a fresh frame, or does nothing:
    - attacked meanwhile, a non-combat action is recorded as not done;
    - a pull starts as a fight already in combat.
- **UI.** The owner's UI changed on 23 Sept, and the readers were re-calibrated on live PNGs:
  - fixed 186x15 plates;
  - the tracker box;
  - health read at row 990 and mana read under the new number text.

**Live hunts, 23 Sept, before these fixes and the UI change.** Nine supervised hunts near Yala, all
labelled live:

| Outcome | Runs |
|---|---|
| NO_TARGET_FOUND | 1 |
| JEV_FAILED (two request timeouts, one HTTP 529) | 3 |
| Ended without a summary | 2 |
| FIGHT_SAFETY_STOP_PLAYER_BELOW_30 | 1 |
| FIGHT_LIMIT | 1 |
| DEAD | 1 |

- The FIGHT_LIMIT run killed a Roiling Winds and an Al'Aketh Convert.
- The DEAD run was attacked from behind, out of Tab's reach. LOOK_AROUND now turns and Tabs for
  the attacker.
- No hunt has run live on the current UI or with these fixes. The SimHunt checks are
  **simulation only**.

## M4c — hand in a quest at its NPC

`m4-nav --turn-in --keys wqe --quest NAME`, run within reach of the quest's NPC (M4a walks there).
Every step is a script (controller RULE); there is no Jev call.

1. If the quest dialogue is not already open, find the NPC's yellow "?": an upright yellow blob
   with a green name below it, within 50 px or 2.5 mark heights, whichever is more, and never below
   the world box. The mark's height stands for the NPC's distance: a small mark's name is UI text of
   fixed size, a tall one's sits 1.7-2.4 heights below (25 Sept: at the owner's zoom a 33 px "?" had
   its name 54-63 px below, and the hand-in read `NO_QUEST_MARK_IN_VIEW`). Calibrated zoomed fully out, where the "?" is small and dim, so
   the test is the hue (the camera has stayed at the owner's closer zoom since 25 Sept). A neutral
   nameplate bar is flat and a glowing Cirrusfly has no green name. Right-click the NPC's body,
   2.4 mark heights below its name: with Click-to-Move the character walks to the NPC and opens the
   dialogue. The dialogue box is read every 0.5 s until a panel's own button shows, or until the
   position has stayed within one 0.1 step for 2 s, at most 15 s. Attacked on the way (the portrait
   ring, read even when a name covers the coordinates), the step ends `WALK_COMBAT` and a `--quests` run fights back (M4i; `--turn-in` alone stops there). Another NPC's panel is closed with Esc, and only a
   panel: text in the box without a button is the world behind it.
   - 25 Sept, live `--quests` run 3: both hand-ins read `DIALOGUE_NOT_OPEN`. The box was read at a
     fixed 2.5 s. Dalia's right-click was still walking her way; a vendor's green name had come into
     the box as the camera turned, was taken for her dialogue, and Esc was pressed. The character
     ended beside Dalia. Ventaari's right-click targeted him, but the walk had ended wedged between
     two standing stones and Click-to-Move did not move (not fixed here).
   - Live run 4: The Gift of Skysight was handed in (`COMPLETED`: Click-to-Move took 4.8 s to
     Ventaari, the panel opened, 180 XP). Harvesting Windstones read `DIALOGUE_NOT_OPEN`: the three
     clicks below Dalia's "?" landed on the ground 30 px to her right, beside another player, and
     nothing moved. The "?" need not stand over the body.
   - So, as a human does, the pointer rests on the NPC before the click.
     - The name is read by OCR, on the line level with the green name's top that starts nearest left of
       its centre; a neighbour at the same depth is not it. The name's centre is taken from its own
       line only, so a subtitle below does not pull it. On run 4's frame it was 1900, while Dalia's
       body was about 1884.
     - The pointer then rests on up to 16 points, in the mark's own scale: below the name's centre at
       the chest, the waist and the legs; then half a mark height and a whole one to each side; last,
       below the "?".
     - At each point the game's unit tooltip (bottom right) is read, on a frame captured after the move.
     - A point counts only when a line of the tooltip is that NPC's name (up to two letters lost at the
       ends; a part of the name does not count). The tooltip must also go when the pointer leaves (two
       fresh reads in a row without the name), and name the NPC again when it returns: a tooltip still
       fading from the last point cannot confirm this one.
     - One sweep starts no point after 12 s. Where an unconfirmed click has already gone, there is no
       second sweep.
     - With no point confirmed, the point below the "?" is clicked, but never again at the same place
       (within half a mark height). A new mark after Click-to-Move is a new place.
     - Each click's frame is saved as `clickN.jpg`, and the perception set now records each mark's name
       centre and top.
   - Live run 5 (26 Sept): the first point, below the name's centre at the chest, raised Dalia's
     tooltip. It faded for about 2 s after the pointer left, and came back on return. The click
     opened her dialogue after 3.2 s of Click-to-Move. OCR then read the title, drawn in a decorative
     capital face, as "HARVEStinG WinostonES". The page was taken for another quest's and closed
     with Esc. The title now matches with one letter in eight misread, as an edit (`sameTitle`; a
     title under eight letters must match exactly). A clear now allows ten reads, not six.
   - Live run 6: beside Dalia, the step read `NO_QUEST_MARK_IN_VIEW`. At that range her "?" was a
     27 x 30 hook, wider than the 24 px cap, and its 11 x 9 dot sat 18 px below, beyond the 13 px that
     joins blobs. The dot alone had no name within its reach. Now:
     - A small round blob, at most a third of a hook's pixels and no wider than it, joins the hook as
       its dot when it lies under it within the hook's height (`withDots`).
     - Only a blob with a dot may be wider than 24 px, up to 0.6 of its height. A spell's tall glow has
       no dot: without this rule a Lightning Bolt read as a 288 px "?".
     - The green under a mark must be a line of text, at least twice as wide as tall. A Cirrusfly's
       striped body over its green glow read as a "?" with its dot.
     - On the 2,449 saved frames, 17 frames gained true near marks (Dalia's "?" and "!", Rorian,
       Boros, Yala's neighbours), checked by eye. Three false marks went: a character's green shirt, a
       spell's glow and a Cirrusfly. A known false mark on flowers changed its height.
   - **Live run 7 (26 Sept): Harvesting Windstones was handed in** (`COMPLETED`: 360 XP, 75 copper).
     - The near "?" read as one mark (h 55).
     - Among four players round Dalia, the first point confirmed her. Her tooltip went after 2.4 s
       and came back on return.
     - Click-to-Move took 0.6 s, the progress page's Continue was pressed, and Complete Quest
       finished it.
     - With runs 4 and 7, both of Thendal Village's hand-ins have now been done live by a Jev-chosen
       `--quests` run.
     - Two readings were wrong:
       - The first reward's name read "Binds when picked up" (a profession book; all sold for 0, so
         the rule's pick did not matter).
       - The log after the hand-in read empty. OCR had read "[5]" as "[51" and the "?" icon before
         "[6]" as ")", so the run ended `NOTHING_TO_HAND_IN_OR_TAKE` instead of
         `NEXT_ZONE_NEEDS_ROADS`.
     - A title may now start with up to three stray characters that are not letters, digits or "-" (an
       objective's text before a bracket is not a title). Its closing bracket may read as 1, l, I or |
       when a space follows (`questTitle`). A title with a stray prefix keeps the clean titles' column
       for its objectives.
2. Check the dialogue's title is the quest. Hover each reward (a two-column grid 37 px below "Choose
   your reward:"), read its tooltip and the game's own comparison with the equipped item ("+2 Armor").
   Lines are kept by alignment with the tooltip's footer, because the quest text shows through; a
   line drawn red (such as "Mail" for a Shaman) makes the item unusable.
3. The owner's rule (24 Sept): "choose if it benefit (eg armor better than now, take and equip). or
   take the highest value (take and sell)." Click that reward, then Complete Quest.
4. For an upgrade, `/equip NAME` in chat, then open the character pane (C), rest the pointer on the
   slot and read the item's name, as a human checks. Letters are only typed once the chat box shows
   "Say:" (read after a x3 upscale): outside it they are game keys. The engine uses no `/run`: it
   raises the client's "Allow custom scripts?" prompt, which is the owner's security choice.

Calibrated on the 24 Sept live exploration of The Cirrusfly Queen (Elatrell Featherlight, Thendal
Village): the minimap "?" tooltip named the quest when the world-map pin was hidden under the player
arrow, M4a arrived in 4 decisions (one blocked step, two left detours), and one right-click opened
the completion page. Offline: the three real reward tooltips parse to Exterminator's Vest (+2, taken
and equipped), Gardening Pants (-8) and Watcher's Mail Chest (red Mail, 14 copper); on 14 saved
frames only the two real "?" marks are found.

Live, 24 Sept (the dialogue was already open from the exploration): the rule took Exterminator's Vest;
chat read "The Cirrusfly Queen completed.", 320 experience and 1 silver; `/equip` worked, and the
character pane then showed the vest (33 Armor) in the chest slot. The first build's `/run` check
raised the "Allow custom scripts?" prompt instead; I clicked No (no setting changed) and replaced the
check with the pane. The third reward was read as "Equipped" because OCR missed "If you replace this
item" in that frame; the equipped item's box is now bounded by its label too. An NPC's quest list and
the "Continue" page were added in M4e. A follow-up quest offered on completion is accepted by its "Accept"
button (the owner: always accept quests; RULE, not yet seen live). A quest from a "!" giver is M4g.
Not yet handled: silver or gold in a sell price.

## M4d — plan the quests zone by zone

`m4-nav --plan --keys wqe` reads the Map & Quest Log and prints the order (controller RULE, read-only):
the log's titles, levels and objectives; each quest's pin from the minimap's quest icons (their tooltips
name the quest; a hub's hand-ins sit together under the world map's player arrow) and then from the world
map's pins; each objective's kind (hand in, kill, collect, use at a place, travel to someone).

The owner's rules, 24 Sept: "finish all available quests in the same zone, accumulate all quests in next
zone for the next priority", and routes "first put higher priority to walk on road, especially zone to zone
travel". Pins within 12 y units form a zone; the player's zone comes first, walked nearest-first; a quest
without a pin counts as here (a finished quest's NPC is usually at this hub). Routing along roads is not
built yet: a greedy walk from Thendal Village towards Shen'dar Village ended NO_PROGRESS against a ridge
after 33 decisions, and colour alone did not separate the map's ridges, sea and flat land.

**Working memory** (the owner, 25 Sept: remember what was read, to cut rescans). Opening the map and
resting on each pin took 3-4 s of each 5-6 s read (live run 4). The log is kept in
`runs/002_wow_visual/memory/quest-log.json`, which is private.
- **The key.** The zone's name above the minimap, by its letters (the clock beside it changes each
  minute), and the objective tracker's lines, by letters and digits. Both are read after a x3 upscale on
  the frame taken with the pointer parked, before any minimap icon's tooltip can cover the zone's name.
- **When it is not saved.** A read is remembered only when it is complete: not empty; nothing the minimap
  named is missing from it; and the tracker and the log agree both ways (every quest in the tracker, and
  every tracker line in a title or an objective). A collapsed or filtered tracker, one too long for its
  box, or a parse that caught one quest of four would otherwise let a wrong plan stand for the hour.
- **What changes it.** A hand-in, a quest taken or an objective's count ("12/15" to "13/15") changes the
  key, and so does another zone, whose coordinates are its own. An unread box gives no key.
- **When it is used.** While the key is the same and the memory is under an hour old, the next read keeps
  the quests and pins without opening the map. The minimap's givers are still read each time, as they
  change with where the player stands.
- **What clears it.** A `COMPLETED` or `ACCEPTED` step removes the file, in `--quests` and `--turn-in` alike.
  A kept quest whose pin the last read missed takes one from this read's minimap, if it shows one.
- **Why the hour.** A quest left out of the tracker could change unseen for at most that hour.
- **On saved frames.** The tracker OCR of runs 5 and 6 differs only by an apostrophe ("Shen' dar" and
  "Shen dar"), which the key drops. Run 7, after the hand-in, gives another key.

Live, 24 Sept (read-only): the log read five quests; after three fixes (a "- Ready for turn-in" line at
the title's x is an objective; "Bring X to NPC" is a delivery; a pointer left on a pin leaves a yellow
tooltip that reads as pins) the order was Harvesting Windstones and The Gift of Skysight (hand-ins here),
Call of Earth (bring the Rough Quartz to Windshaper Boros, 43.2, 22.4), then The Adventurer and The Next
Step in Shen'dar. Three minimap "?" 14 px apart are now split by shape (a dot joins the hook above it),
and their tooltips run over the minimap, so the reading box does too.

Two live faults under the plan. The live capture draws a minimap "?" as (239, 236, 116) where a
screenshot shows (248, 246, 58), so yellow is a hue test calibrated on the probe's own saved frame. And
the capture stopped whenever a caller held two frames: FrameFeed decoded CGImages that share the stream's
buffers, and with queueDepth 3 two held by a caller stall it outright (a diagnostic counted 0 frames while
two were held, 28-30 per second otherwise, with or without background pointer moves). That was every
"no fresh frame" of the day, including fight 1's false safety stop after looting. `latestFrame` now
returns a byte copy; with it, the diagnostic ran at full rate while holding two frames, and the live plan
read all three minimap icons with no frame wait: The Gift of Skysight, Call of Earth (to Windshaper
Boros) and Harvesting Windstones here, then The Adventurer and The Next Step in Shen'dar.

## M4e — deliver this zone's quests

The first `--quests` walked the plan's quests in order: an M4a walk to the pin (each walk has its own
key set, because a walk's exit sweep ends its keys for good), then the M4c hand-in, clicking through a
delivery's "Continue" page. The script chose every step (RULE).

Live, 24 Sept: the engine walked to Windshaper Boros and handed in Call of Earth (+360 experience,
level 6, Stoneskin Totem learnt). The next run read one quest of four from the log (only The Adventurer,
in Shen'dar), although the minimap's tooltips had just named Harvesting Windstones and The Gift of
Skysight. The plan's first zone was then Shen'dar, 20 units south, and the walk ended NO_PROGRESS near a
cliff. The frame the log was read from was not kept, so the cause of the short read is unknown. Now:

- The frame the log is read from is saved as `quest-log.png`.
- A quest named by a minimap "?" tooltip but missing from the log read stops the run as `LOG_INCOMPLETE`.
  A giver's "!" names a quest not yet taken, so it does not count (M4g).
- A walk is offered only to a pin within 12 y units (a hub is smaller); farther is zone travel, which
  waits for road routing.

## M4f — Jev chooses the quest steps

The owner, 24 Sept: the engine's skeleton is Jev-driven. `m4-nav --quests --graph
experiments/002_wow_visual/runtime/skyborne-quest.graph.json --keys wqe` replaces the RULE loop with
`runQuests` in `Quest.swift`:

1. Read the log, the minimap's quest icons and the position (M4d); `LOG_INCOMPLETE` stops here.
2. Offer `HAND_IN_1` to `HAND_IN_4`: quests a hand-in can finish (ready, or a delivery to someone) with
   a pin within one walk, not yet failed this run, in the owner's zone-first order. Each criterion names
   the quest, its level, distance and objective.
3. Jev walks the graph: it may `READ:quest_log` (every quest, in the owner's order, with kind, distance
   and zone), `READ:recent` (the steps so far) or `READ:owner_rules` (the owner's rules in
   `learning/knowledge/owner-rules.md`), then `DO` one offer. At most four calls per step within 20 s,
   120 a run; no HTTP retry, no rules fallback.
4. Run it: the M4a walk (Jev's moves) and the M4c hand-in (the reward is the owner's RULE). Read again,
   because a hand-in changes the log.

Stops: no offer left (`NOTHING_TO_HAND_IN_OR_TAKE`, or `NEXT_ZONE_NEEDS_ROADS` while deliveries remain out of reach);
a walk stopped for health, the owner or the HUD (combat: M4i); a walk whose key release is unconfirmed
(`WALK_KEYS_HELD`: that key set is kept, never replaced); the second `WALK_NO_PROGRESS`; twelve steps, or 25
minutes (M4j).
A failed hand-in is not offered again. Offline, 8 checks (M4g adds 4) run the loop on the live Thendal values of
24 Sept with canned graph replies and a fake host: Shen'dar's quests are not offered, the owner's rules
reach only the request after the READ, and the one-quest log read stops before any Jev call. They do not
show what the real Jev chooses, or live hand-ins.

## M4g — take quests from a "!" giver

The owner: always accept quests. The minimap's quest icons are now told apart by shape: a "!" (a quest to
take) is a bar 2-5 px wide, a "?" hook 6-7 px. Only a "?" tooltip counts towards `LOG_INCOMPLETE`: a "!"
names a quest the log cannot hold yet, so without the split any giver in view would have stopped the run.
Each "!" within one walk is offered as `ACCEPT_1` to `ACCEPT_3`, nearest first, after the hand-ins. The
skill walks to it, right-clicks the NPC under a quest mark and presses the dialogue's whole-line "Accept"
button (RULE). A giver's quest list is clicked through only when the minimap's tooltip named the entry.
The chat's "accepted" line gives `ACCEPTED`, otherwise `ACCEPTED_UNCONFIRMED`; the next log read is the
proof. A giver that failed is not offered again this run. The dialogue opening (the nearest three marks,
Esc only on an open dialogue, looking again after Click-to-Move) is now one function shared with the
hand-in. An Accept already on screen is pressed only when its page names one of the giver's tooltip
lines; otherwise it is closed and the giver's mark is clicked.

Offline: the classifier replayed on the real frames found 8 "!" on three 23 Sept Thendal frames and 7 "?"
on three 24 Sept scans, all classified correctly. Two "!" pressed under the player arrow were not found; the
next read, after a step, sees them. The 23 Sept frames are JPEG, not the live decode path. 4 more nav checks:
a real-shaped "!" and "?" stamp, the split of their tooltips (only a "?" can make the log incomplete),
`ACCEPT_1` taken then nothing left, a failed giver not offered again.
Not seen live: a "!" tooltip's text (the giver's or the quest's name), the Accept flow and the chat line.

## M4h — stop before a red name ahead

The owner, 24 Sept, after M4a walked into the centre of a Cirrusfly nest: survive first, and "danger
not only red plates but also red names (even we can't read); the time you see plate means they are
already in your danger zone". In this UI a plate's name is white; a hostile creature beyond plate range
shows only its name, in red. `redNames` finds that text without OCR: red whose green stays near its blue
(`g - b <= r / 6`), in thin lines of short strokes with a dark outline. Each name's compass bearing is
the facing plus its angle off the view's centre. A walk's move stops when one lies within 30° of its
heading, and the walk ends `DANGER_AHEAD`: a local stop, as for combat. Every frame with a red name is
saved. The hunt's own walks do not look for red names yet: their quest creatures are red names too.

In the quest loop, `WALK_DANGER_AHEAD` fails only that step (not offered again this run). `RETREAT` is
then offered first: it walks back to where that walk began, which the walk had just passed. A retreat
that does not get back (a red name that way too) ends the run as `RETREAT_<outcome>`. Jev chooses
between it and the other steps; the owner's rules, a READ, now include the red-name rule. The quest
graph is `skyborne-quest-tools-v3`. A position unreadable before a walk is now `WALK_HUD_UNREADABLE`, not
an arrival.

Offline replay of the Swift classifier on 975 saved M4 frames (23-24 Sept, JPEG; 690 walk, 285 hunt),
labelled by the author from crops: 81 hits in 55 frames. 70 are red names, 1 a red plate bar and 8 the
red selection circle under a hostile creature already targeted (hunt frames only). 2 are a dim Juvenile
Vuldren, a neutral red-brown creature, in the walk frames of one 23 Sept run. The green-blue rule was set
on these same frames (it removed 6 of 8 Vuldren frames), so this is calibration, not a held-out result.
Misses were not counted over every frame; one name over bright cloud fails the outline test. On the nest
walk of 24 Sept the first hit is f128, at (46.3, 27.3): the name lies at 109°, the walk's heading to the
"Cirrusfly Queen area" is 109°, so it would have stopped there, 15 s before it reached the nest's centre.
The scan takes at most 2 ms a frame. 8 nav checks: a real-shaped red name and its bearing, a plate bar, the
Vuldren's colour and outline-less strokes are not names; a name ahead stops the move and ends the walk
`DANGER_AHEAD`, one 33° off does not; in the quest loop RETREAT follows and the run goes on, and a
retreat that meets a red name ends the run. A move's check runs while it walks: during a Jev call W
may still run on under its 1.5 s grant, and the next move's first look stops it.
Not seen live: raw (not JPEG) frames, a real stop, a real retreat, names over snow or sky.

## M4i — fight back when a quest walk is attacked

The owner, 24 Sept: "those reactions should be written in jev engine ... how to handle / avoid / engage
aggressives, intentionally or unintentionally". A quest walk attacked on the way used to end the run
with its keys released, leaving the character standing under attack. Now `WALK_COMBAT` hands over at once
to one M3 fight in combat (controller SAFETY, no quest-graph call: in combat the only choice is to fight
back, as in the hunt). The fight's own decisions are Jev's, on a child of the run's own key set, its frames
in `fightN/` (and each walk's in `walkN/`: run 3 of 25 Sept overwrote its first walk's frames with the second's). A kill lets the run go on, and the interrupted step may be offered again; any other outcome,
Jev's STOP included, ends the run as `FIGHT_<outcome>`. Unlike the hunt, M3 cannot select an attacker
behind the character (Tab looks ahead), so walking on after a STOP would only be attacked again. The exit
sweep and the key check cover the fight's keys as well as the walk's. (Until 25 Sept the child was taken
from the walk's set, which the walk's own exit sweep had already retired: no fight could have started. Found
in review before any live fight back.) 2 nav checks replace "combat ends
the run": a won fight goes on and re-offers the step; a stopped fight ends the run. Not seen live.

## M4j — hunt from the quest run; the engine's zoom; a new character (26 Sept)

- **Hunts.** The quest graph (`skyborne-quest-tools-v4`) offers `HUNT_1` and `HUNT_2` for kill and collect
  quests within one walk, in the owner's order.
  - The skill walks to the quest's area, or starts from here when the map showed none, then runs one M4b
    hunt, as `--hunt` does, in its own `huntN/` folder.
  - A hunt fights for every unfinished objective the tracker shows, so quests that share a place finish
    together. Objects on the ground are not picked up.
  - `HUNTED` (objectives complete) and `HUNTED_SOME` (a limit ended it after a count rose or a quest became
    ready) let the run go on; the latter may be offered again.
  - A limit with nothing counted fails the step. Any other hunt code ends the run: death, the owner, the
    HUD, Jev, a lost fight, or keys held.
  - `--hunt-graph PATH` gives each hunt a fresh session of the hunt graph; without it a hunt is the legacy
    flat choice.
  - No step starts after 25 minutes (the envelope allows 30), and a hunt gets what is left of them, at most
    its own 15. A run takes up to twelve steps.
- **Zoom.** A new character starts at the client's near zoom, and the owner wants the engine's own. At
  the start of `--quests` and `--hunt`, `setZoom` holds F10 (Camera Zoom Out) to the widest view from any
  zoom, then F11 (Camera Zoom In) back for `FightLimits.zoomInSeconds`.
  - Both are owner-consented binds of 24 Sept.
  - The owner found 0.5 s too far and chose 0.75 s. Two runs at 0.5 s landed at the same distance.
  - `m4-nav --zoom --keys wqe [--seconds S]` sets it alone and saves the frame, to calibrate.
- **Live runs 10-13 (26 Sept), a new level-1 character at Thendal Village.**
  - Run 10 held at the start: a level-1 Shaman has no weapon enchant, and the bar check required one
    (see the M3 README).
  - Run 11: Windshaper Boro's "!", 20 yards away, was drawn under the player's arrow on the minimap, so no
    giver was read. With no "!" on the minimap, a yellow mark in view is now offered as `ACCEPT`, whose
    criterion says so.
  - Run 12: Jev chose it. The hover confirmed Ailee Farheart under the mark, and Click-to-Move walked to
    her, but no dialogue opened. The next frame found no mark, so there was no second click. A look after
    such a click now tries three frames.
  - Run 12 also ended with the Map & Quest Log open, and the next run's L would have closed it. L is now
    pressed only while the panel is not as wanted, checked by its title after each press.
  - The new character's map opened on Thendal Village, not Zephras Isle, so the fixed pixel-to-zone
    transform did not hold. A pin's coordinates now come from the map's own "Cursor: x, y" line while the
    pointer rests on it.
  - Run 13: the mark in view was found on one frame and not on the next. The near "!" draws the lower part
    of its bar orange, so the yellow bar and its dot did not join.
  - The owner then asked whether patching the rules frame by frame is the right way. It is not: world
    objects move to a learned detector with a VLM as labelling teacher, and fixed HUD boxes to anchors.
    That work comes next, and no further mark patch was made here.
  - Four quest runs, no quest taken; no fight, no death.
- **Review of #47 (Grok, fresh context).** Four major findings, all fixed:
  - The run's time budget is a deadline, checked again after Jev's decision. A hunt's budget is counted
    after its walk, and a hunt with none left does not start. A decision could end past 25 minutes, and a
    walk of up to 180 s came before the budget.
  - The map counts as open only when its title is read, and as closed only when two fresh frames in a
    row lack it. A missing frame proves neither: an empty read had passed for closed. A map not known to
    be as wanted stops the run (`LOG_INCOMPLETE`).
  - A pin whose cursor line was not read has no pin. It is not placed by the fixed transform, which held
    on one map only.
  - A mark in view keeps one key, so a failed one is not offered again after the player moves. It is not
    offered beside a quest to hand in, where it is most likely that quest's "?".
- The cursor line parses 0-100 with any decimals. The proof pins `zoomExecute`'s signal trap and exit
  sweep, and F10 and F11 in every key set that can press them. Offline, M4j adds 14 nav checks (286 to
  300) and 2 fight checks.

## M4k — roads learned from players' videos (26 Sept)

The owner, 24 Sept: "first put higher priority to walk on road, especially zone to zone travel". A straight
walk from Thendal Village to Shen'dar Village ended against a ridge (M4d), so a quest run stopped at its zone's
edge (`NEXT_ZONE_NEEDS_ROADS`). The game could not run on 26 Sept, and published videos of Zephras Isle show
where players walk: the zone coordinates under the minimap, on every frame.

- **Trails** (`m5-perceive --trails`). Vision reads the minimap's corner of each video frame: the top right,
  360 px wide and 30% of the height. The coordinates are found by their pattern (`parseCoords`), because the
  corner's layout differs between videos. The subzone's name, the line above them, is kept too; the lines
  below them are the quest tracker's.
  - A trail breaks where a reading lies more than 2 y units from the one before: a flight, a hearthstone,
    a misread, or frames the OCR lost. Of 14,467 steps between readings, 97% are under one unit,
    210 are 1-2 units, 41 are 2-6 and 201 are longer.
- **Roads** (`m5-perceive --roads`, [zephras-roads.json](../learning/knowledge/zephras-roads.json)).
  - A place is a square y unit of ground, at the mean of the readings in it; players on one road share
    its places.
  - A way joins the places of two readings in a row. It is directed, as walked: a drop from a ledge may
    not climb back. Each way counts the videos that walked it.
  - One map (`oneMap`). The map changes only across a jump, which breaks a trail, so the subzones one
    trail walks through share a map. Joined trail by trail, the group with most readings is Zephras Isle;
    trails through none of its subzones are left out. No list of subzones is written in.
  - Parts of the roads with fewer than 10 places are pruned (`pruned`).
  - The file holds the places' map coordinates, the ways, the subzone names read and the videos' run names:
    no frame, character name or label.
- **Routes** (`route`). From any place within 3 units of the player, along the ways, off at a place within 3
  units of the goal: the shortest by ground distance. The places are then simplified (Douglas-Peucker, 0.3
  units) to where the road bends, so a straight road is one leg.
- **The consumer: the quest run** (`skyborne-quest-tools-v5`; v6 adds USE_1, M4m).
  - `ROAD_1` and `ROAD_2` are offered only when nothing is left within one walk: the owner's order, this
    zone first, stays a rule of admissibility.
  - Each goes to a quest beyond one walk, in the owner's order, that the roads reach. Its criterion gives
    the distance, the road's length and its legs.
  - `walkRoad` walks each leg as a quest walk (`walkLegs`: Jev's moves; a red name ahead stops it, an attack
    is fought back). A leg may be longer than one walk, as the road does not bend on it (`walkStart`). No leg
    starts after the run's 25 minutes (`ROAD_TIME_LIMIT`). Arriving (`BY_ROAD`) lets
    the run go on; a road that fails is not offered again this run.
  - `--quests` loads the roads at the start and logs a `roads` event. A file that does not decode stops the
    run before any walk; with no file the run ends at the zone's edge as before.

Rebuild from the repository root, with `/tmp/m5-perceive` built as in the [M5 README](../m5/README.md):

```sh
(cd runs/002_wow_visual && find . -path './yt_*' -name '*.jpg' | sort) | /tmp/m5-perceive --trails  # resumable
/tmp/m5-perceive --roads  # writes learning/knowledge/zephras-roads.json; each video held out
```

**Results, 26 Sept (sim, offline; no road walked live).**
- **Sources.** Seven published Zephras Isle videos (16,786 frames). Six are those of the M5 stage four; the
  seventh is a 5 h 53 min run through the whole starting zone at 1-14 (7063 frames, 16:9, one frame in 3 s).
  - Coordinates were read on 14,543 frames. The two low-resolution 21:9 videos read poorly (zerocks1 and 4:
    the digits blur); the others read 80-100%.
  - 10 of 199 trails (250 readings) were left off this map: the full-zone video's last hour in Dalaran and
    Stormwind, trails in Rohashi Spires that never walked on into another subzone, and rare misreads of a name.
- **The roads.** 1082 places and 2073 ways; 423 ways were walked in more than one video. 15 places in parts of
  fewer than 10 were pruned: readings that lost a digit (x 0.2 to 6.3, far off the island's roads).
- **Each video held out against the roads of the others:** those roads are made as the committed ones, and which
  trails lie on this map is decided without the held-out video too.

| Held out | Readings within a place of the others' roads | Walks over 12 units routed |
|---|---|---|
| Full starting zone (1-14) | 4334 / 6359 | 12 / 15 |
| Shaman, episode 2 (Thendal to Valanaar) | 3933 / 4864 | 6 / 8 |
| Hunter | 974 / 987 | 1 / 1 |
| Druid | 1044 / 1044 | 2 / 2 |
| Story playthrough | 601 / 601 | 0 / 0 |
| Shaman, episodes 1 and 4 | 159 / 162, 79 / 157 | none |

  Before the full-zone video was added, the Shaman's episode 2 held out had 1 of 8 long walks routed.
- **Thendal Village to Shen'dar Village.** The route goes west round the ridge, through (38.3, 30.3): 10
  legs and 28.1 units by road, where the straight line is 20.9. To The Next Step's pin it is 14 legs and 32.6
  units. `NavTests` pins that the committed roads give this route round the ridge.
- **No way back yet.** No route leads from Shen'dar back to Thendal. The ways are directed, and the videos
  walk the zone in quest order. A run that must go back ends at the zone's edge, as before.


- **Not yet walked live.** A route through places other players walked is a candidate: the first announced
  `--quests` run that offers a road is its qualification.
- No map check: the run envelope is Zephras Isle, where the roads were learned. The subzone names are in
  the file for the check a run beyond it will need.

## M4l — take the quest an NPC's greeting lists (live run 14, 26 Sept)

- **Live run 14** (26 Sept, about 23:17, main 548f98c): the level-1 character at Thendal Village.
  - Jev chose `ACCEPT_1` on the "!" in view. The hover confirmed Ailee Farheart, and Click-to-Move opened
    her panel.
  - It was her greeting, "Hello, shaman." above "! Coming of Age", not the quest's offer. No Accept button
    was read, so the panel was closed as someone else's.
  - The step ended `DIALOGUE_NOT_OPEN`, and the run `NOTHING_TO_HAND_IN_OR_TAKE`: one step, no fight, about
    25 s.
- **The fix** (`offeredEntry`). A greeting lists an NPC's quests, each after an icon. OCR reads the yellow "!"
  of a quest to take as a leading "!". `accept` clicks the entry the minimap's tooltip named, else the first
  such entry, then looks for Accept as before. A mark in view has no tooltip, so run 14 had nothing to click.
- **M5 in shadow, first seen live** (#50). The learned reader loaded in 110 ms. At each of three looks (in
  view, at the click, and in view after), it read the one "!" the rules read, and it changed no action.
- Offline: one nav check, on run 14's lines.

### Live runs 15-33, unattended (26-27 Sept)

The owner authorised unattended runs; each was announced, recorded (the screen, beside the engine, by ffmpeg) and
studied frame by frame before the next. Recordings are private and kept off the repository. Every row is live.

| Run | What went wrong | The fix |
|---|---|---|
| 15 | A "Speak with" objective was planned as `USE_AT` | "speak with" and "talk with" are travel (`questKind`) |
| 16 | A minimap tooltip left over the arrow: no facing, `WALK_HUD_UNREADABLE` | the pointer is parked after the log read |
| 17 | A garbled green name was never confirmed by the hover | a tooltip with a level line and no "(Player)" is an NPC (`npcTip`) |
| 18-19 | The walk to a platform's NPC ended under it (the owner: "you walked under the bridge") | stands learned from the video trails: walk first to where players came from (`walkBeside`, `approach`) |
| 20 | A log read with a quest unpinned was remembered | a log is remembered only with every pin; a pinless hand-in is offered at the player's place |
| 21 | A logged quest's icon was taken for a giver; the rules missed a near "?" | givers whose tooltip names a logged quest are dropped; the learned reader adds click targets, hover-confirmed |
| 22 | The first unattended hand-in: "Experience gained: 40", and the follow-up accepted | then "[1]" before the tracker's title (`parseTracker`) |
| 23 | Jev wandered between ENTER and BACK to `GRAPH_callLimit` | a decision's last call offers every offered skill flat, so it commits |
| 24-26 | Plate flicker, a misread target name, and the target cue changing ended fights | sightings merged at revalidation, `mostlyIn`, `targetCue` |
| 27-28 | FIGHT_TARGET hidden at the root; Jev walked to the area instead of fighting | a retained subgoal's path offers its ancestors' skills; the goal allows counting creatures anywhere; `targetInRange` |
| 28-29 | Whole-number coordinates read ("4.9, 23"): 40 units off | both decimals required again; the position read retries five frames |
| 30 | All eight Juvenile Vuldren killed, three hunts, seven fights, no death; Elatrell's stand missed | the earliest in-range approach reading, stand chains, a stand within 0.7 |
| 31 | The hand-in clicked a giver's "!" ahead (the "?" was 90° left); a greeting's "!" read as "?"; one unread position ended the hunt | see below |

Run 31 (27 Sept, about 01:00) took Infestation Investigation from Elatrell Featherlight, then:
- **Hand-in.** The approach walk ended facing the way it went, and Ventaari Brightwish's "!" was the only mark in
  view. Now the character turns to face the pin on arriving (`face`), and a hand-in clicks only "?" marks, a quest
  taken only "!" marks, as the learned reader names each rule mark's kind (`glyphKind`, `clickMarks(want:)`).
  - On saved frames the kind was right for 20 of 20 marks of 6 px and more. Far marks of 3-5 px were not: one "!"
    read as "?" at confidence 1.00. A mark under 6 px keeps its place (`kindMinHeight`). `m5-perceive --kinds`
    prints the kinds.
- **Greeting.** OCR read Ventaari's "! The Gift of Skysight" as "? ...". A "?" entry hands in a quest of the log,
  so one whose quest is not in the last log read is an offer (`offeredEntry(_:ours:)`); its page must still show Accept.
- **Hunt.** "42,2,23.7" did not parse, and after LOOK_AROUND nothing was admissible without a position; the empty
  request ended the hunt `HUD_UNREADABLE`. `parseCoords` takes a decimal comma, and such a survey is read again
  (the sim check fails without the fix).

Run 32 (27 Sept, about 01:25) turned to the pin and handed in Harmony in Balance: `COMPLETED`, 80 XP, Vuldren Hide
Bracers chosen as the larger upgrade (+15 against +7).
- The NPC's greeting then listed two new quests and stayed open; the character pane was read under it, so the equip
  was `UNCONFIRMED`. Now the offers a completion shows are taken in turn, and the panel is closed first.
- A "!" tooltip names NPCs, and the panel's title is the NPC's name: Ventaari's title was clicked, not his offer.
  `namedEntry` takes only a quest entry.
- "42.G,24.3" on every frame for 3 s stopped a walk: "G" and a Cyrillic "З" read as 6 and 3.

Run 33 (27 Sept, about 01:30) accepted Embracing the Elements, The Gift of Skysight and Harvesting Windstones.
- Rorian's "!" read as "g": an entry is one icon character and a capitalised title (`questEntry`), and one whose
  quest is not in the log is an offer.
- While standing, 43.3 read as 48.3 and as 3.3 on single frames, and a hunt walk "moved 59.55". `PositionTrack`
  drops a reading further from the last than a character can move; three that agree are the place.
- The world map drew Infestation Investigation as "..." on a dark disc, which `mapPins` did not find: no pin, no
  area, and twelve hunt decisions found no Cirrusfly. The dots are now found as a flat row and hovered.

Run 34 (27 Sept, about 01:47) found the "..." pins and read their tooltips, but no cursor line parsed, so again no pin
and `HUNT_NO_TARGET_FOUND`. OCR of the run's recording gave "Cursor: 45.8. 27.1" and "42.G. 22.9": `mapCursor` now takes a
dot between numbers of one decimal each, and "G" for 6. `map_pin` events log the cursor's text.

Run 35 (27 Sept, about 01:57) read every pin, the hunt's at 45.8, 27.1. The walk there stopped `DANGER_AHEAD` 1.9 from
it: two level-1 Juvenile Vuldren, one's red-brown body read as a red name. Only RETREAT was offered, and the run ended.
Near a kill quest's pin red names are most likely its creatures, so a hunt's walk stopped by one within 3 units starts
the hunt there (`huntStartsNear`): the hunt reads each plate's name, fights only what counts, and fights back.

Run 36 (27 Sept, about 02:04) walked to 2.8 from the hunt's pin. There the quest area's blue band crossed the minimap
arrow's tip, the facing read 258-344° for 131°, and the walk turned on the spot until `NO_PROGRESS`. The arrow's tail
is now its compact navy dot (see Perception above).

Run 37 (27 Sept, about 02:15) hunted Pesky Cirrusfly where run 36 had stopped, and three fights started, each against
a Cirrusfly selected in front of the character. None landed a blow.
- The fight's revalidation cue was the target frame's raw name, whose OCR tail changes every frame ("Pesky Cirrusfly
  AOРAU", "Pesky Cirrusfly 4845"). FACE_TARGET was chosen 26 times and each was refused `target_cue_changed`; Jev
  then chose STOP. A hunt's fights now take the hunt's cue (`targetCue`): every reading of a creature that counts is its
  objective. A fight back on a walk keeps the raw name.
- After 24 walks, LOOK_AROUND left nothing admissible on a readable frame, and the empty request ended the hunt
  `HUD_UNREADABLE`. It now ends `MOVE_LIMIT` (or `NO_ADMISSIBLE_SKILL`), which fails the step, not the run.
- A creature that counts for nothing kept the raw cue, and run 48 (27 Sept) rejected 6 of 12 hunt decisions
  `target_cue_changed` while one Pesky Cirrusfly stayed selected ("Pesky Cirrusfly Л Л4О", "Pesky Cirrusfiy 4 84О").
  Its cue is now its name's Latin words only.
- In the same run the hunt for the Cirrusfly Queen read every Pesky Cirrusfly as counting ("Cirrusfly" shared) and
  walked toward them. A plate now counts only if each word of four letters or more in the objective's creature name
  shares a four-letter run with it.

Run 38 (27 Sept, about 02:25) started the hunt near its pin at a red name (`hunt_near`): four fights, Pesky Cirrusfly
slain 3 of 8 to 7 of 8 (run 37's three fights had killed too). The hunt ended `FIGHT_LIMIT`, and the step counted as
failed: the last tracker read "12] Infestation Investigation", so the quest's name changed and its kills counted for
nothing. `parseTracker` now drops a marker ("** ", "› ") and a level tag whose bracket read as "1".

Run 39 (27 Sept, about 02:31) killed the eighth Cirrusfly: Infestation Investigation read "Ready for turn-in".
- The hunt still ended `NO_TARGET_FOUND`: its tracker read "3 12] Infestation Investigation", a finished quest's "?"
  icon as "3". The tracker now drops leading icons of one or two characters on title lines, never on a count line.
- The hunt's failure was remembered by the quest's title, which was also its hand-in's key, so the hand-in was never
  offered. A hunt now fails by its own key (`stepKey`).
- Jev was offered only a hunt for Harvesting Windstones, whose 15 Windstone Clusters are objects on the ground. The
  hunt cannot take objects, and found nothing. Taking objects is not built yet.

Run 40 (27 Sept, about 02:42) turned to the hand-in's pin and clicked the only "?" in view: Windshaper Boro's, which
is another quest's. His panel was closed, no mark was left, and the step ended `DIALOGUE_NOT_OPEN`. A search now
remembers each NPC whose panel it closed as someone else's, skips a mark over one (never clicking it blind), and looks
round when no mark is left.

Run 41 (27 Sept, about 02:48) turned to the pin and handed in Infestation Investigation: `COMPLETED`, "Experience
gained: 170", 35 copper, and its follow-up, The Cirrusfly Queen, accepted on completion. The Queen's walk stopped at a
red name 3.6 units short of her pin, and Jev chose RETREAT.

**Where runs 14-41 leave the character** (live, unattended, from the runs' chat lines):
- **Handed in:** Ancient Heirloom (run 22), Harmony in Balance (run 32) and Infestation Investigation (run 41).
- **Taken:** Coming of Age, Harmony in Balance, Infestation Investigation, Embracing the Elements, The Gift of Skysight,
  Harvesting Windstones and The Cirrusfly Queen.
- **Killed:** 8 Juvenile Vuldren and 8 Pesky Cirrusflies, with no death.
- **Left in the log:**
  - The Cirrusfly Queen: one stronger creature.
  - Harvesting Windstones: objects on the ground.
  - The Gift of Skysight and Embracing the Elements: use an item or ability at a place.
  - None of the last three has a skill yet.

## M4m — use the item or ability a quest names; enter the world again (27 Sept)

After run 41 the character stood idle for 70 minutes, and the game logged out to the character select screen.
Runs 42-45 were unattended, as before.

- **Entering the world.** At the character select screen, the run (and `--bags`) reads "Enter World" below the
  selected character, presses Enter, and waits up to 90 s for the minimap's coordinates
  (`enterWorldIfAtSelect`).
  - The selected character is the one last played. Its name is never read or logged.
  - Live: in the world 16 s after Enter.
- **The bags.** `readBags` opens the Combined Backpack with B when its title is not in view. It places the slots
  from the title's position: the first 94 px below, 10 a row, 45 px apart. It hovers each slot in the order the
  bag fills, until two in a row are empty.
  - An item's name is the topmost line in its tooltip's column, above the game's item footer (`bagItemName`).
  - Live: all seven items were read, and the slots fell within 2 px of the recon's measure.
  - `m4-nav --bags --keys wqe` lists the items. Nothing is clicked.
- **USE_1** (quest graph `skyborne-quest-tools-v6`). A use-at quest whose objective names a bag item or a bar
  ability is offered as a use (`questItem`: the longest name its objective holds).
  - An item is right-clicked, after its slot is hovered again and still names it. A text panel that names it is
    closed with Esc, and Esc is pressed only then. The use counts (`USED`) only when that panel opened.
  - An ability is used by its key on the bar. The run first walks to the quest's pin when the objective says
    "near" (`usesNear`). There is no evidence at the key, so it never makes its quest a hand-in (`USED_ABILITY`).
  - A use is not offered again that run.
  - A used quest whose objective then sends the player to someone ("... then speak with Windshaper Boro") is
    offered as a hand-in (`talksAfterUse`). Its log line does not change.
- **Tracking.** After the logout no quest was tracked. The objectives tracker was empty, and a hunt read no
  objective (run 42: `HUD_UNREADABLE`). The quest read now ticks each empty tracking checkbox
  (`questTracked`: 29-33 yellow pixels in a ticked box on the saved logs, none in an empty one).
- **A partial log stops the run.** The "..." icon of a quest in progress read as "..• " before its level.
  - Two of three quests went unread, and run 43 ended with nothing left to do. Five characters are now allowed
    before "[".
  - The log's own count ("Quests: 3/40") is read, and a parse that finds fewer quests stops the run
    `LOG_INCOMPLETE`.
- **A neutral creature's body is no red name.** A hostile's name is drawn red only beyond plate range. A red
  "name" whose centre lies within 30 px of a neutral plate's span and up to 80 px under it is that creature's body
  (`dangerNames`; the review of #54 narrowed it from 60 and 160).
  - Runs 35 and 44 had stopped at a Juvenile Vuldren's red-brown body.
  - The 24 Sept nest's real red name, level with a plate beside it, stays a danger.

| Run | Outcome (live) |
|---|---|
| 42 | USED the Humming Recall Crystal: its text panel opened ("As you touch the glowing crystal a draft of wind stirs around you...") and Esc closed it. The next hunt read no objective: no quest was tracked |
| 43 | Ticked four quests, used the crystal, and handed in Embracing the Elements to Windshaper Boro: COMPLETED, "Experience gained: 85" |
| 44 | Walks to the Elemental Convergence (Skysight, key 9) and its retreat stopped `DANGER_AHEAD` at a Vuldren's body |
| 45 | With the body filter, the same walks still stopped `DANGER_AHEAD`: small red detections far off, too small to read, in the Vuldren field |
| 46 | With the learned red-name reader (M5): Jev chose to hunt for Harvesting Windstones, a collect-from-the-ground quest; the hunt found no creature to count (`HUNT_NO_TARGET_FOUND`). The next quest read ended the run `POSITION_UNREADABLE`: a Pesky Cirrusfly's nameplate lay over the coordinates under the minimap |
| 47 | After the quest read turned when a plate hid the coordinates (#56): the read found the place, then the hunt's walk to Harvesting Windstones read the coordinates once, under the same Cirrusfly's plate, and was refused `WALK_HUD_UNREADABLE`, which ends a run |

**Limits of M4m.**
- The walk's red-name check still stops walks through the Vuldren field. It sees far red detections that are too
  small to read, and some are real names (M4h's 70). OCR cannot tell them apart. A learned classifier trained on
  the saved walk frames, which keep every red name, is the next step. It followed on 27 Sept: the walk now drops
  the candidates a learned reader reads as no text (`redDanger`; ../m5/README.md, "Red names the walk may pass").
- Objects on the ground (Harvesting Windstones) still have no skill.
- The bags are read on every quest read that has a use-at quest, about 0.9 s a filled slot.
- **A plate over the coordinates.** After runs 46 and 47, when five fresh frames give no position, a quest run turns
  in place 45° at a time, up to three times, and reads three frames after each turn (`position_turn` in the log):
  before a quest read and before a walk starts (`QuestRun.position`). A turn needs a fresh frame, no combat and no
  owner takeover (review of #57). A retreat, and the hunt's start beside a danger, read five
  frames and do not turn.
  A standing creature's plate does not move by itself. `--plan` does not turn.

## M4n — objects on the ground, Jev's choice (27 Sept)

The hunt could only fight, so a collect quest of objects on the ground was never done: Harvesting Windstones ended
`HUNT_NO_TARGET_FOUND` in live runs 46 and 48. The owner's check of 27 Sept set the terms: the engine is Jev-driven,
so the pick-up is a choice Jev makes, not a script's loop; and it sees through a learned model, not a pixel rule.

- **PICK_UP_OBJECT**, a hunt skill in the search node of `skyborne-hunt-tools-v3`. The survey reads the objects in
  view with the M5 object detector (`ObjectReader`, m5/README.md) only while a collect objective is open. The
  detector runs beside the survey's other reads, not after them (the `look` event logs each survey's ms): live run 51
  (27 Sept) read the tracker, target, position and plates in 0.34-0.49 s, and a detector after them was skipped as too
  old on every frame, so PICK_UP_OBJECT was never offered.
- **Admissibility (the script's part):** offered only with an object in view, an open collect objective (its text
  names no defeat), health for walking and no combat. After two pick-ups that picked nothing up it is not offered
  again until a walk: a Tab or a look around does not make a false object worth hovering again.
- **Jev's view:** the state lists the objects in view (screen place, confidence), and the goal says what a pick-up does.
- **The skill:** the object nearest the character's feet is hovered, as a human rests the pointer.
  - Before that, the pointer waits off every unit until two fresh frames show no tooltip (`tooltipGone`, at most 4 s).
  - The pointer jumps to the object (one move event). Two fresh tooltip reads there must name one open collect
    objective, and neither may be a unit's ("Level" line, `confirmedObject`). Only then, with no combat read just
    before, is it right-clicked. Click-to-Move walks there and picks it up.
  - The evidence is the objective's count rising in the tracker, or its quest turning "Ready for turn-in", within 8 s.
  - An attack ends the wait, as does no count by then, and a tap of forward stops Click-to-Move. A pick-up that
    counts is progress, as a fight is, for the hunt's search limit.
- **Without the detector's model** no object is seen, PICK_UP_OBJECT is never offered, and the hunt is as before.
  The HUNT offer tells Jev so.

Proof (sim): `SimHunt` has objects on the ground whose tooltip is their name. It checks that PICK_UP_OBJECT is offered
only in the cases above; that two Windstone Clusters in view make two pick-ups and complete the objective with no
fight; that an object whose tooltip names no objective is not clicked, nor hovered more than twice between walks;
that a unit's tooltip or a kill objective is never picked up; and that Jev's state lists the objects. The live hover, click and tracker read are
not observed yet (F3).

## Limits

- Three supervised walks in one village. These are trials, not a success rate.
- The pocket rehearsal shows that Jev does not leave a dead end by moving away from the goal.
- Destinations were read from the world map by hand. Reading pins, and interacting with an NPC
  on arrival, belong to the next slice.
- One layout and window size. The boxes move with UI scale, Edit Mode or window size.
- Labels are the author's, from the saved frames.

## Reproduce

Native build and no-effect graph rehearsal (macOS, from the repo root):

```sh
V=experiments/002_wow_visual
C=experiments/001_wow_fishing/probes/background-click
swiftc -O -parse-as-library -D SEEK -D FIGHT -D NAV \
  $V/m0/Motor.swift $V/m0/Probe.swift $V/m1/Seek.swift $V/m1/Plate.swift $V/m1/SeekProbe.swift \
  $V/m3/Fight.swift $V/m3/Tactics.swift $V/m3/FightProbe.swift $V/m4/Nav.swift $V/m4/NavProbe.swift \
  $V/m4/Hunt.swift $V/m4/HuntProbe.swift $V/m4/Quest.swift $V/m4/QuestProbe.swift $V/m4/Roads.swift $V/m5/Marks.swift $V/m5/Reader.swift \
  $V/runtime/Runtime.swift $V/runtime/Input.swift $V/runtime/DecisionGraph.swift $V/runtime/Experience.swift \
  $C/Adapter.swift $C/NativeWindowServerPreparation.swift $C/NativeBackgroundClickTransport.swift \
  -o /tmp/m4-nav
/tmp/m4-nav --hunt-dry-run --graph "$V/runtime/skyborne-hunt.graph.json" \
  --experience /tmp/skyborne-hunt-experience.json
```

The opt-in [tool graph](../runtime/README.md) organises Jev's information, retained
experience and skill choices. The command above records local synthetic episodes; a
later run can choose `READ:experience`. It uses canned replies and SimHunt, not live
Jev or WoW, and it does not prove that retrieval improves gameplay.
Omit `--graph` for the existing flat-policy rehearsal. No current or historical
live result below/above certifies the new graph policy.

```sh
swiftc -parse-as-library experiments/002_wow_visual/m0/Motor.swift experiments/002_wow_visual/m1/Plate.swift \
  experiments/002_wow_visual/m3/Fight.swift experiments/002_wow_visual/m3/Tactics.swift experiments/002_wow_visual/m4/Nav.swift \
  experiments/002_wow_visual/m4/NavTests.swift experiments/002_wow_visual/m4/Hunt.swift \
  experiments/002_wow_visual/m4/HuntTests.swift experiments/002_wow_visual/m4/Quest.swift experiments/002_wow_visual/m4/Roads.swift \
  experiments/002_wow_visual/runtime/Runtime.swift experiments/002_wow_visual/runtime/Input.swift experiments/002_wow_visual/runtime/DecisionGraph.swift \
  experiments/002_wow_visual/runtime/Experience.swift -o /tmp/nav-tests && /tmp/nav-tests
swiftc -parse-as-library experiments/002_wow_visual/m4/Tabletop.swift experiments/002_wow_visual/runtime/JSON.swift \
  -o /tmp/tabletop && /tmp/tabletop --check   # offline; without --check it asks live Jev
tools/sdlc motor   # builds and checks M0, M1/M2, M3 and M4 with no live effect
tools/sdlc motor --update-perception   # accept the pixel readers' new readings on the saved frames
```

`--replay DIR` needs saved frames. `--sim-jev` and `--execute` need `TYPESAFE_API_KEY` in the
environment; the key is never printed or written. A live walk also needs the owner's current
authority, and WoW running but not frontmost.
