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
  - **Learned too (M5, 27 Sept).** Beside the Elemental Convergence (live run 52) the rule read 350 and 316 where the
    arrow faced about 150, then nothing. A walk or hunt now takes `fusedFacing` of the rule and the learned
    `FacingReader` (m5/README.md, "The facing"):
    - the rule's bearing where it reads;
    - the reader's at 0.7 confidence or more where the rule has none;
    - the reader's over the rule only where a turn test (below) showed the rule wrong.
    - Until the evening of 27 Sept a disagreement gave no bearing. Live runs 54 and 58-62 then showed the rule right
      and the reader wrong at up to 1.00: in run 62 it read 320, 270 and 150 where the arrow faced 42 and 68, and the
      walk ended `HUD_UNREADABLE` in 10 s. Until the reader is retrained on these runs' frames, it only fills the
      rule's gaps.
  - A walk that cannot read its place for three looks turns right once on the spot (0.15 s of E, about 25°): an icon
    beside the arrow stays where it is while the arrow turns off it. In live run 54 (27 Sept), standing still, the rule
    read 130 and the reader 250 on every frame (the arrow faced about 130), and the walk ended `HUD_UNREADABLE`.
    A hunt does the same before its last unread survey with nothing to offer: in live run 55 the walks got to the
    Windstones' area this way (seven turns), and the hunt there then ended `HUD_UNREADABLE` on an unread facing.
  - The turn is also a turn test (`turnTest`). The reader whose bearing followed the turn (about 25° right, within 20°)
    while the other's did not is trusted where the two disagree, until they agree again (`facing_trust` in the log).
    Since the rule leads, only a trust in the reader changes a bearing.
    In live run 58 (27 Sept), standing still, the rule read 222 and the reader 150 (0.93). The turn moved the rule to
    254 and the reader to 118, so the rule was right. Before this, the walk had no bearing to act on; with it, the walk
    takes the rule's. A trust lapses after 10 s, and a test with no verdict clears it (review of #67).
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
4. (Until M4x, #80, which wears an upgrade by right-click.) For an upgrade, `/equip NAME` in chat, then open the character pane (C), rest the pointer on the
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
Jev's STOP included, ends the run as `FIGHT_<outcome>`: walking on while still attacked would only be attacked
again. (Since #76, STOP is not offered in combat, and SELECT_TARGET turns round to find an attacker behind.) The exit
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
  - No step starts after 20 minutes (the envelope allows 30; 25 until the review of #72), and a hunt gets
    what is left of them, at most its own 15. A run takes up to twelve steps.
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
  units of the goal: the shortest by ground distance. The places are then simplified (Douglas-Peucker, 0.15 since M4q, was 0.3
  units) to where the road bends, so a straight road is one leg.
- **The consumer: the quest run** (`skyborne-quest-tools-v5`; v6 adds USE_1, M4m).
  - `ROAD_1` and `ROAD_2` are offered only when nothing is left within one walk: the owner's order, this
    zone first, stays a rule of admissibility.
  - Each goes to a quest beyond one walk, in the owner's order, that the roads reach. Its criterion gives
    the distance, the road's length and its legs.
  - `walkRoad` walks each leg as a quest walk (`walkLegs`: Jev's moves; a red name ahead stops it, an attack
    is fought back). A leg may be longer than one walk, as the road does not bend on it (`walkStart`). No leg
    starts after the run's 20 minutes (`ROAD_TIME_LIMIT`). Arriving (`BY_ROAD`) lets
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
the hunt there (`huntStartsNear`): the hunt reads each plate's name, fights only what counts, and fights back. That was a
script's decision; since M4o it is Jev's (`FROM_HERE`).

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
  walked toward them. For a kill objective a plate now counts only if each word of four letters or more in the
  objective's creature name shares a four-letter run with it. A collect objective names an item the creature drops, so
  it kept the looser rule, until M4ae (below) made it whole words.

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
| 48 | A plate over the coordinates: one turn and the place read (`position_turn`). Windstones and the Cirrusfly Queen: no creature to count. Skysight: the walk stopped `DANGER_AHEAD` 1.8 from the Elemental Convergence at real red names (Al'Aketh Converts, level 3; the learned reader kept them), so Skysight was never cast; Jev chose `RETREAT` and the run ended `NOTHING_TO_HAND_IN_OR_TAKE`. No death |

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
  - The evidence is the objective's count rising in the tracker, or its quest turning "Ready for turn-in", within 8 s
    (15 s since M4af).
  - An attack ends the wait, as does no count by then, and a tap of forward stops Click-to-Move. A pick-up that
    counts is progress, as a fight is, for the hunt's search limit.
- **Without the detector's model** no object is seen, PICK_UP_OBJECT is never offered, and the hunt is as before.
  The HUNT offer tells Jev so.

Proof (sim): `SimHunt` has objects on the ground whose tooltip is their name. It checks that PICK_UP_OBJECT is offered
only in the cases above; that two Windstone Clusters in view make two pick-ups and complete the objective with no
fight; that an object whose tooltip names no objective is not clicked, nor hovered more than twice between walks;
that a unit's tooltip or a kill objective is never picked up; and that Jev's state lists the objects. The live hover, click and tracker read are
not observed yet (F3).

## M4o — Jev chooses to start a stopped step from where it stands (27 Sept)

Run 48 stopped Skysight's walk 1.8 from the Elemental Convergence at real red names, and the quest was never done. A
script rule would have cast it there, as `huntStartsNear` started a hunt near its area since run 35. The owner's line
(27 Sept): the engine is Jev-driven, and a script does not make gameplay choices. So both are now one option for Jev.

- **`FROM_HERE`** (quest graph `skyborne-quest-tools-v7`). A walk to a hunt's area, or to the place where an ability
  is used "near", may stop for a red name ahead within 3 map units (`HuntLimits.startNear`) of that place, as the
  next quest read measures it (`stepStartsNear`). The next request then offers the step again from here, beside
  `RETREAT` and whatever else is open.
- **What it runs.** The same step with no pin, so the host does not walk: the hunt starts where the character
  stands, or the ability is cast there. Its criterion says why the walk stopped and how far from the place.
- **What is not offered.** A stop further away, a hand-in's or accept's walk, or a bag item's use (it has no place).
- **Evidence (sim).** `HuntTests` checks the offer and its absence, and a run in which Jev chooses it for Skysight
  and the ability is used with no walk.
- **Evidence (live, 27 Sept, runs 50-51 on a local build of this PR with #59 and #60).**
  - Run 50: the Cirrusfly Queen's walk stopped 1.3 from its area, and FROM_HERE was offered. Jev chose the
    Windstones hunt instead.
  - Run 51: Jev chose FROM_HERE for the Queen (a hunt from there found no Queen), and for Skysight. Skysight was
    cast 1.9 from the Convergence's pin; the quest did not complete. So "near" for the Convergence is nearer than
    3 map units, and a use from there spends the step for nothing. A use-at's `startNear` is a candidate to narrow
    once the Convergence's reach is measured.

## M4p — Jev may fight what stands in the way (27 Sept)

Live runs 48-56 stopped at red names on nearly every walk round Thendal: level 2-3 Roiling Winds and Al'Aketh Converts,
with the character at level 2. The engine offered only a retreat, a start from where the character stood, or another
quest, and the character did not level. The owner's goal is to level like a human, and a human fights what stands in
the way, for its experience too.

- **`FIGHT_AHEAD`** (quest graph `skyborne-quest-tools-v8`). It is offered beside `RETREAT` after any walk that a red
  name stopped.
- **What it runs.** One M3 fight from out of combat (`LiveQuestHost.fightAhead`, logged `controller: JEV`). It starts
  only at the fight's start health, 90%. The fight's own Jev selects the creature (Tab) and pulls it; the fight's
  limits and safety are M3's.
- **After the fight.**
  - A kill offers the stopped step again: its failure from the stop is forgotten.
  - A fight that did not start (`HOLD_PLAYER_HEALTH`), or that Jev stopped (`JEV_STOP`), leaves the stop standing:
    `RETREAT` is offered again, and this fight and the stopped step are not (review of #66).
  - A creature that has come to the character since the stop makes it a fight back (start health 0). One that Jev
    left fighting the character after a `JEV_STOP` is fought back at once, as SAFETY's, not handed to a quest decision.
    A fight in combat then follows M4i: only a kill goes on, and any other outcome ends the run.
  - Any other outcome ends the run, as a lost fight back does.
- **Bounds.** It is offered only straight after a stop, so a kill does not offer another fight. Each walk that stops
  again offers it again, within the run's 12 steps and 20 minutes.
- **Evidence (sim).** `HuntTests` checks that there is no offer without a stop, and that a kill offers the hunt again.
  It also checks that a loss ends the run, and that a held fight leaves the hunt failed. Live: not yet run.

## M4q — a straight walk that leaves the roads goes by them (27 Sept)

The owner (27 Sept, watching run 59): the walker is "particular bad on handling obstacles and cliffs, which might have
bigger issue when leaving the newbie zone". The walker has no height and no ground reading: a wall stalls the
coordinates and is detoured, but a lip does not, and a straight walk steps off it. The learned roads (M4k) go round
the ridge M4d's straight walk stopped at, but a quest walk inside one leg (12 units) never asked them.

- **`straightLeavesRoads`** (Roads.swift). Some point every half unit on the straight line to the pin is farther than
  3 units (`RoadLimits.reach`) from every place players walked, and the roads give a route.
- **The walk** (`LiveQuestHost.walk`, logged `road_gap`). A walk to a pin that leaves the roads goes by the route's
  legs, the last one to the walk's own arrival. A retreat goes straight back over the ground it crossed, and a road's
  own leg is already on the road.
- **Legs keep the trail's jogs.** A route is simplified at 0.15 (`RoadLimits.lip`, about 0.75 s of running), not
  0.3, so a leg does not cut across what the players walked round.
- **Evidence.** Sim only: `NavTests` has a road round a gap, a village walk that stays straight, no roads, and a
  0.2 jog kept; the committed file's route from Thendal still passes west of x 40. Live: not yet run.
- **Not in this slice** (the side-task design note of 27 Sept ranks them next):
  - a memory of blocked cells shared by a step's legs;
  - one jump when blocked (Space, once the owner confirms it);
  - a learned "ground ends ahead" reader.
## M4r — a run's end leaves the danger zone (27 Sept)

Between live runs 56 and 57 the character stood idle among level 2-3 hostiles by the Elemental Convergence and was
killed. The owner, 27 Sept: "error exit should still try best to leave danger zone".

- **`leaveDanger`** (LiveQuestHost). Before a quest run exits, the character walks to the nearest safe place within
  25 units (`safePlace`, `QuestLimits.safeReach`; 12 until M4ag), logged `leave_danger` as SAFETY's. The safe places are the Zephras villages (Thendal,
  Shen'dar, Valanaar), by their NPCs' places in the town research.
- **When.** Every end walks, errors included (`HUD_UNREADABLE`, `JEV_FAILED`), except:
  - the owner's takeover, whatever step it stopped;
  - keys held;
  - a failed input handoff;
  - death.
- **How** (`leaveDangerRounds`):
  - In combat, SAFETY fights back first (one M3 fight, as in M4i). No fresh HUD counts as combat.
  - Out of combat, it walks. A walk that meets combat is fought, then walked again, for at most four walks. The last
    walk's combat is fought too.
  - A walk that ran out of its time is walked on too (M4ag). A lost fight, or any other walk end, stops it.
- **Time.** Everything ends inside the envelope's 30 minutes from the run's start. A fight starts only with its whole
  150 s left. A walk gets what is left, at most 180 s, and none starts with less than 20 s left.
  - So that a fight is always left for it, the run starts no step after 20 minutes, not 25. The last step's walk and
    its fight back end by 25:30.
- **The walk.**
  - It makes no model call, so a run that ended on a failed Jev call still walks. Its moves were a fixed preference
    (straight, then the detours); since M4ac it is the steering walk, by the roads where they lead there.
  - It walks on past a red name ahead, and at low health out of combat (`toSafety`): stopping among hostiles is what
    it leaves. Live run 65 met combat at once, ended, and the character died where it stood.
- **Steps.** SAFETY's fights back no longer use Jev's twelve steps. Run 65 spent them on five attacked walks and their
  fights, and ended `STEP_LIMIT` in combat.
- **Evidence.** Sim only.
  - `HuntTests` covers which ends walk, the nearest village, the fights and walks, their time and the steps.
  - `NavTests` covers a walk to safety past a red name, at low health, and within its seconds.
  - Live: not yet run.

## M4s — death recovery at the Spirit Healer (27 Sept)

The character died twice on 27 Sept: once between runs 56 and 57, and once after run 65. The owner, the same day, made
recovery part of the envelope: resurrect at the Spirit Healer, automatically. Below level 10 it costs nothing. Each
death is still reported.

- **`reviveIfDead`** (LiveQuestHost) is SAFETY's. It runs twice in a quest run:
  - at the start: dead there, the run starts only once the character is resurrected;
  - at the end, after `leaveDanger`: death in the run or on the way to safety.
- **Clicks** (`deathStep`, `revive`), each found by its text:
  1. "Release Spirit" in the top popup;
  2. "Return me to life." in the Spirit Healer's gossip. After run 65 it opened by itself about 6 s after the release.
     After run 66 it did not, so when the gossip is not open and a "Spirit Healer" name is in view, the healer is
     right-clicked seven name heights below its name (TALK). Only the dead see a Spirit Healer, so that name also finds a
     ghost at the start of a run. The whole line must be its name (a chat bubble that mentions one is no ghost), and the
     click stays in the view above the bars;
  3. "Accept", only on the popup that says "resurrect", beside Cancel, and only after step 2. The button's whole line must
     read "Accept". Another popup's Accept is never taken: a party invite, a summons, or another player's offer to
     resurrect (Accept and Decline).
- **Checks.**
  - Every read is on a frame captured after the last click. A frame that does not come is no read.
  - Text is read in Latin letters: Vision read that Accept with a Cyrillic A.
  - No click while any of the run's keys is held (walk, fight or hunt).
- **Limits.**
  - A step still shown is clicked again, at most six clicks in all.
  - `REVIVED` needs two fresh frames in a row with nothing left to click after Accept (`deathSeen`). A quiet capture, or
    a single read, is `DEATH_AFTER_ACCEPT`, not a resurrection (review of #73).
  - Anything else stops where it stands (`DEATH_AFTER_…`). A ghost is not attacked.
  - The owner's takeover stops it.
- **Time.** One clock from the run's start: the quest steps get what setup and a revive at the start left of their 20
  minutes, and the way to safety (M4r) ends 90 s early for the revive at the end. Six clicks, each waiting at most
  12.5 s, take at most 78 s.
- **Not in this slice:** a corpse run, and the hunt mode's deaths.
- **Evidence.**
  - Sim: `HuntTests` covers:
    - the steps on the OCR lines of the live frames;
    - the other popups;
    - the post-click reads (`deathSeen`);
    - the loop's ends;
    - the clock.
  - Replay: the live frames of 27 Sept, through the crop OCR, gave Release at (1209, 221), then TALK at (1281, 411) on the
    healer's robe on the frame before its gossip opened, Return at (101, 307) and Accept at (1212, 249). The frames after
    Accept gave none.
  - Live, by hand after run 66: Release Spirit; no gossip; a right-click on the healer 7 name heights below its name
    opened it; Return; Accept; resurrected with no penalty.
  - Engine live: not yet run.

## M4t — a hostile plate stops the walk too (27 Sept)

The owner, 27 Sept, after live run 67: "you straight go into danger zone. you obviously can see red names (even red
namepages that means very close) you should be awared that and take caution, means the normal pathfinding should stop,
goes to danger zone pathfinding / hunting". The owner had said so on 24 Sept too ("danger not only red plates but also red
names … the time you see plate means they are already in your danger zone"), but M4h stopped only for red names.

- **The miss.** In run 67 the walk to use Skysight met a Roiling Winds in combat. `nameplates`, replayed on that walk's
  frames, read its hostile plate nearly straight ahead from `walk2/f122` on: ten frames, about 5 s, before combat.
  A plate's name is white, so `redNames` read nothing, and the walk went on.
- **Now** (`walkWarnings`): every hostile (red) plate in view warns the walk as a red name does. One within 30° of the
  heading ends the walk `DANGER_AHEAD`, and the quest loop's danger choices follow (M4h, M4o, M4p): Jev picks `RETREAT`,
  `FIGHT_AHEAD` (pull that one creature, only at 90% health or more), or `FROM_HERE`. Neutral (yellow) and friendly plates
  do not warn. The way to safety (M4r) still walks on through danger. Every frame with a hostile plate is kept, and the
  look logs `hostile_plates`; `--replay` prints them.
- **Replay** (offline, `nameplates` on today's saved quest-walk frames, runs 58-67):
  - no hostile plate on any walk inside Thendal Village (for example run 67's walks 1 and 4, and a 104-frame walk of
    run 58);
  - plates on the walks near the Elemental Convergence and the Al'Aketh camp;
  - six of the flagged frames, cropped and checked by eye, were all Roiling Winds plates (level 2-3, one casting).
- **Not yet:** a detour round a plate, and the hunt's own walks (their quest creatures carry plates too).
- **Evidence.** Sim: `NavTests` (a hostile plate from run 67 warns; a neutral one does not). Live: the next run.

## M4u — the town stop: sell the junk, learn the class's spells (27 Sept)

The owner's goal (26 Sept): level from 1 to 20 "just like human do, upgrade skills, buy/sell, upgrade gears". A human
leaves the field now and then to empty the bags at a vendor and to learn new spells at the class trainer.

- **Observed live first** (27 Sept, by direct control, frames kept privately):
  - **Trainer** (Windshaper Boro, Thendal Village). Right-click opens his gossip, and "I'd like training!" opens the
    trainer window at the left. Each row has a name "(Rank N)" and, when not yet allowed, "Requires: Level N" with the
    number in red; the price sits beside it. Train stays grey until a row is clicked. Rockbiter Weapon was learnt
    for 10 copper: chat "You have learned a new spell", 35 → 25 copper, and the row left the list.
    **The client put the new spell in the first empty bar slot by itself** (slot 4). This contradicts the research's
    inference (Classic places nothing), so no bar step is needed.
  - **Vendor** (Uualia Suncrest). Right-click opens the merchant's window and the bags. The coin bag under the grid
    is "Sell All Junk Items". It asks to confirm ("…will not be able to buy them back…"); Yes sold every grey item,
    25 → 63 copper.
  - The money is the bottleneck: at level 3 Earth Shock needs level 4 and 1 silver.
- **Offers** (`townOffers`, Jev's choice as for any step; quest graph `skyborne-quest-tools-v9`), each within one walk
  and once a run:
  - `TRAIN` at the class trainer, when the level read is above the level of the last visit. The level comes from the
    character's own portrait tooltip ("Level N"). The last visit's level is kept in `runs/002_wow_visual/memory/character.json`
    (private), written only when a spell was learnt. A lower level read is a new character with the same name, and forgets it.
  - `SELL_JUNK` at a vendor, when the bags hold 8 items or more, or were not read this step (they are read only for a
    use-at quest; review of #77). Jev weighs it.
  - The NPCs and where to stand are knowledge: `learning/knowledge/zephras-town.json`.
- **A visit** (`LiveQuestHost.visit`):
  - It walks to the stand point, then finds the NPC by its name. The name is read at twice its size (the full-size
    read misses it), turning in place if needed.
  - The NPC is hovered until the game's tooltip names it (`onUnit`, the M4c rule), then right-clicked.
  - Vendor: the Sell All Junk tooltip is read before the click, the confirmation is answered Yes, and the money after it
    is the evidence (`SOLD n`, `NO_JUNK`).
  - Trainer: "I'd like training!", then, only while the trainer's own window shows (`trainerOpen`: its title, no gossip
    "Goodbye", a "Rank" or "Requires" line; review of #77), each row the level allows is clicked and Train pressed, at most six
    (`trainerRows`; a misread level is tried, since the game refuses what it does not allow). The chat's "You have learned"
    is the evidence (`TRAINED n`, `NOTHING_TO_TRAIN`).
  - Each window is closed with Esc only while it shows: its title and a line only such a window has (`npcWindowOpen`: the
    gossip's "Goodbye", a trainer row, the merchant's "Buyback" or "Page N of M"). An NPC's name standing in the world at
    the left is no window (review of #77). The owner's takeover and the run's time stop every turn and click of a visit:
    the search by name, each sell click, the gossip click, each row and each Train (Train only after the window is read
    again).
- **Also here:** Jev's danger criteria say "red name or plate" (review of #75); a corpse search that finds nothing logs what
  its points showed (`corpse_hover_miss`; live run 68 looted once by tooltip and missed twice, saying nothing).
- **Not in this slice:** buying food, drink or gear; repair; the gear upgrade rule at a vendor; other villages' NPCs.
- **Evidence.** Sim: `HuntTests` covers the level, the money, the rows (on the live OCR lines), the offers, and one run
  that trains and sells. Live: the next run.
- **Fix, live run 78:** the view search took a player's longer name ("aria Darkwina Darkbloom") for "Windshaper Boro": the
  name match was a share of letters in order, bounded only from below in length. `townNameHit` bounds it both ways (within
  3 letters); the hover's own check had already refused to click the player, and the visit ended `NPC_NOT_OPENED`.

## M4v — quest enders from the wiki (27 Sept)

The owner's goal names "ref, wiki" beside ML vision. Live runs 67, 68 and 69 each offered the ready quest "Agitators", and each
hand-in failed (`DIALOGUE_NOT_OPEN`, `NO_QUEST_MARK_IN_VIEW`). From the village the map showed no pin for it, so the hand-in
sought its "?" where the character stood. Its ender is Yala Windwatcher in Thendal Grove, where she gave the quest (M4a).

- **Knowledge** (`learning/knowledge/zephras-quests.json`): each quest's ender and where they stand, from warcraft.wiki.gg
  (read by a research subagent; URLs per quest). Agitators → Yala Windwatcher (47.3, 21.9); Harvesting Windstones → Dalia the
  Collector (43.2, 24.0); The Gift of Skysight → Ventaari Brightwish (42.6, 24.4).
- **The log** (`withEnders`): each quest is named with its ender. Only a quest ready to hand in (or a delivery) with no map
  pin takes its ender's place; one in progress keeps its own area (review of #78). A map pin stays, since it is what the
  game shows now. Jev's hand-in offer names the ender.
- **The hand-in** (`turnIn(ender:)`): with the ender's name known, the NPC is opened by its name first (`openByName`, M4u:
  the name read at twice its size, the tooltip naming it). The completion page follows as before (a quest list's entry,
  Continue). Another quest's page or the NPC's greeting is closed (`panelOpen` or `npcWindowOpen`), and the "?" is sought
  after, as before. The search by name stops at the run's time.
- **Also here (review of #77):** the trainer's level is remembered only when a spell was learnt, so a visit short of money
  is offered again at the same level; the run's deadline is read again just before Train; a player's tooltip met while
  hovering for an NPC is logged as "(a player)", never by name.
- **Evidence.** Sim: `HuntTests` (the pin filled, a map pin kept, an unknown quest left alone; the offer names the ender).
  Live: the next run.
## M4w — heal before walking on (27 Sept)

The owner, 27 Sept: buff and heal "are not in the skills chain but they are needed when needed". Live run 70: a hunt ended out
of combat under 30% health, the way to safety set off at once, got stuck on the ground, and the character died there.

- `recover` (pure): out of combat and under 60% health, the bar's heal is cast on the character, at most three casts, until
  60%; not in combat (the fight answers that), not with mana under 20%, not without a fresh HUD.
- `LiveQuestHost.healBeforeWalking` runs it before every quest walk but a retreat (which leaves the danger first), and before
  each walk on the way to safety (M4r). Logged as `recover`, controller RULE.
- Review of #79: a heal goes to the selected unit, which after a talk is a friendly NPC, so F1 (the default Target Self)
  selects the character before the first cast, and Esc drops it after, only while a target shows. Checked live: F1 put the
  character in the target frame (read 0.99), and Esc cleared it (0.0) without the Game Menu. The owner's takeover stops each
  cast, and the heal's time comes out of the safety walk's own seconds.
- Also here: the town stop's name search covers the view but the tracker (live run 73: Windshaper Boro's name stood right of
  the first box, and the visit ended `NPC_NOT_OPENED`), and each look logs `town_search`.
- Evidence: sim (`HuntTests`: healed in two casts; not hurt; in combat; no mana; still hurt after three; aimed and cleared
  once; the owner stops the casts). Live: the next run.

## M4x — wear the better gear (27 Sept)

The owner, 27 Sept: "i don't see you equip?", then "you can right click on the inventory to quick equip/swap gears. and we
should always wear better gear first when non-battle". The bags held a belt for an empty waist and shoes better than the
character's, and Sell All Junk had sold such grey gear before.

- Observed live by direct control: a bag item's tooltip shows the equipped item's box with the game's stat changes without
  Shift ("If you replace this item, the following stat changes will occur: +5 Armor"), drawn to the tooltip's left by the
  screen's right edge; an item for an empty slot shows no such box (its own armour is the gain).
- `parseReward` reads both layouts: the equipped box bounds the item's lines only when it is to the right; the name is
  `tooltipName`'s, the top of the lines that climb from the footer at its left edge (the backpack's title, world text and an
  NPC's subtitle above the tooltip are not the name); OCR's "- 3 Armor" is -3. `bagTooltip` reaches y 1300, as a bottom
  row's stat changes stood at y 1181.
- `equipChoices` (pure) applies the owner's reward rule of 24 Sept to the bags: a usable item with a slot and a gain, the best
  of each slot. `QuestRun.wearUpgrades` right-clicks each, only while its tooltip still names it (Click-to-Move), and counts it
  worn when its slot then shows another item or none. Never with an NPC's window open (`npcWindowShown`): a right-click at a
  merchant sells.
- `LiveQuestHost` runs it as a RULE out of combat at the run's first log read and after each fight or hunt, so before a town
  stop too, and the bag read of a use-at quest reuses its names. Logged as `equip` and `equip_item`.
- A quest reward chosen as an upgrade is no longer typed as `/equip NAME` (M4c): live run 77 read no "Say:" after Enter,
  `command` returned with the chat box still open, and the box took the map's key (`LOG_INCOMPLETE`) and the walk's
  (`WALK_NO_PROGRESS`). The hand-in returns `COMPLETED_TO_WEAR` and marks the gear unchecked, and the next log read's
  right-click RULE puts it on. `command`, `wearing` and the character pane's boxes are gone.
- Review of #80: a check that leaves an upgrade unworn is tried once more, and until it is worn (or while the gear is
  unchecked) the read offers no vendor (`gearSettled`), and a vendor stop would return `GEAR_UNSETTLED` before walking, so Sell
  All Junk never sells it; `--turn-in` puts its reward on too. MotorProof holds both: the NPC-window guard before the right-click, and the vendor refusal.
- Also here (live run 75): OCR dropped the brackets of a ready quest's title beside its "?" ("4 Return to Rorian"), the log read
  2 of 3 quests and the run stopped `LOG_INCOMPLETE`. `readQuestLog` reads again with bare levels (a level before a capital)
  only when a read falls short of the log's own count, and takes it only when it then matches (review of #80: an objective
  such as "8 Cirrusflies Slain" reads that way too, and would overshoot).
- Also here (live run 78): the portrait's level read "Level 5" alone for a level-4 character, an NPC's tooltip still showing;
  `tooltipLevel` takes the level only from the "(Player)" line.
- Evidence: sim (`HuntTests`: the belt, shoes and bracers tooltips as Vision read them live; the cloak with an NPC's subtitle
  above it; the log lines of runs 75 and 76). Live run 76: the shoes (+5, the old boots back in their bag slot) and the belt
  (+18, the slot then empty) were worn; the cloak was not (its name read as world text, fixed above); the bracers (-3) were
  left. Live run 77: the cloak (+3) was worn, the old boots (-5) left, all three quests read, and Return to Rorian handed in
  at level 4. Live run 78: the reward cloak of run 77 (+2) was worn, the Ragged Cloak back in its slot; after a hunt and a
  hand-in the check read `NO_UPGRADE`.

## M4y — each step's record across runs (27 Sept)

**Since 28 Sept:** a store like this is working memory, not learning. Learning needs provenance and evaluation (the learning loop, #93; the world model, #89); see `docs/solutions/architecture-patterns/fix-engine-capability-not-goal-patches.md`.

The owner, 27 Sept: "Btw can the engine self-improve? Eg path finding, hunt, etc…". Live runs 77 and 78 each chose the
Harvesting Windstones hunt first, and each ended `HUNT_NO_TARGET_FOUND` (Windstones are objects to pick up, not creatures):
the in-run `failed` set is forgotten when a run ends.

- `recordStep` (pure): a step's outcome updates its record, by the step's key. A success (`COMPLETED`, `HUNTED`, `SOLD`,
  `TRAINED`...) forgets its failures; an outcome that says nothing about the step (the owner's takeover, the clock, combat or
  danger on the way, nothing to sell or learn, gear unsettled) leaves them; any other adds one, with the outcome and the level.
  A retreat or a fight ahead is not recorded: it is about the creature there; nor an accept, whose key is where its "!"
  showed. Review of #81: the takeover is silent however the host prefixes it (`WALK_`, `HUNT_`, `OWNER_OR_TIME`), and so are
  the engine's own faults (keys held, a handoff, a HUD unread).
- `withHistory`: `runQuests` adds a step's record to its criterion ("Earlier runs: this step failed 2 times since it last
  worked, the last time as HUNT_NO_TARGET_FOUND at level 4; a step that failed the same way rarely works unless something has
  changed since"). Jev still chooses: knowledge, not a rule, and no step is removed.
- `LiveQuestHost.remember` keeps the records in the character's memory (`runs/…/memory/character.json`, private) beside the
  level last trained, and logs `step_memory`. A level read below any remembered one is a new character of the same name: the
  memory is forgotten.
- The owner's gear rule of 27 Sept joins `owner-rules.md`.
- Evidence: sim (`HuntTests`: two failures counted, the takeover, the clock and nothing to sell leave them, a success forgets
  them; a run's Jev reads the record in the hunt's criterion and the outcome is remembered). Live run 79: `step_memory` logged
  "HUNT Foul Matriarch" failed once (`WALK_NO_PROGRESS`, the walk west stopped against a boulder at 40.7,22.9, as in run 78)
  and "HUNT Harvesting Windstones" once (`HUNT_HUD_UNREADABLE`, now silent: that record was dropped), and the character's
  memory held them. Live run 80: the Foul Matriarch hunt's criterion read run 79's record ("Earlier runs: this step failed
  once … WALK_NO_PROGRESS at level 4"), and Jev chose another step first.

## M4z — where walks stopped, remembered (27 Sept)

**Since 28 Sept:** a store like this is working memory, not learning. Learning needs provenance and evaluation (the learning loop, #93; the world model, #89); see `docs/solutions/architecture-patterns/fix-engine-capability-not-goal-patches.md`.

The owner, 27 Sept: "can the engine self-improve? Eg path finding". Live runs 78 and 79 each walked west from Thendal
Village towards Foul Matriarch's pin (39.6, 23.9) and each stopped `NO_PROGRESS` against the same boulder on a steep slope
(40.4-40.7, 22.9-23.8). The straight line stays within 3 units of the learned roads there, so `straightLeavesRoads` never
sent it by road; the roads players walked go south round the ridge (42.5, 24.3; 41.6, 25.6; 41.0, 25.7; then north).

- A quest walk (not a retreat) that ends `NO_PROGRESS` keeps where it stopped (`stuck_point`) in the private
  `runs/…/memory/stuck.json`: the world's, not a character's, the latest 64.
- `passesStuck` (pure): a straight walk passing within `stuckNear` (1 unit) of a remembered stop goes by the learned roads
  instead, and its `route` (`avoid`) ends at the reachable place nearest the pin whose own place, and whose walk off the road
  to the pin (all but its last unit), lie clear of every stop, within 4.5 units: the cheapest end lay across the boulder.
  Review of #83: the committed place nearest the log's pin (39.6, 23.9) is the boulder itself (40.7, 23.8), and the nearest
  clear of it (41.72, 23.43) walks back across it; the route now ends at 40.6, 25.9, south of it, by the south road.
- Evidence: sim (`NavTests`: the committed roads route Thendal Village to the pin round the south once the two stops are
  remembered; a walk elsewhere does not pass them). Live run 80, with the two stops of runs 78 and 79 in the memory (put
  there from those runs' own `NO_PROGRESS` places): the walk to Foul Matriarch (pin 36.2, 24.1) logged `road_gap` with
  `stuck_ahead` (13 legs, 18.4 units by road against 10.8 straight) and set off south; its first leg stopped at 41.9, 25.4 for
  a hostile ahead (`WALK_DANGER_AHEAD`), so the far side is still to be reached live.
## M4ab — reads only when a step made them stale (27 Sept)

The owner, 27 Sept: "the cache memory also had issues... it keep updating inventory and quest, even there're no related
events. just waste of time." Live run 80: 8 steps took 7 world-map scans (21 pin hovers), 7 bag reads (93 slot hovers) and 8
level reads, 9-20 s before each decision, though most steps (danger stops, retreats) changed none of them. The log's own
memory (M4d) is keyed by the zone's name and the tracker's text, which change with the subzone and OCR, and held once.

- `staleAfter` (pure): the reads a step's outcome makes stale. A hand-in: the log, the bags (its reward) and the level (its
  experience); an accept or a use: the log and the bags; a fight, or a hunt that reached its area (one that fought may still end
  NO_TARGET_FOUND: live run 39): all three; a sale: the bags;
  a walk that stopped, a retreat or a road: none.
- `LiveQuestHost` keeps the last log (with the minimap's givers), the bags' names and the level, and reads each again only
  when stale; the log also after a walk of 3 units or more, as the givers change with the place. The place is read each step.
  A fight back or ahead and a worn upgrade make their reads stale too. The gear check of M4x follows the same events: after a
  hunt only when it fought, after a hand-in only when it completed (live run 81: a hunt with no fight re-read the bags).
- Evidence: sim (`HuntTests`: each step's stale reads). Live run 81 (two steps, each after a walk of more than 3 units): the
  level was read once for two steps; the bags twice, the second by the gear check this now leaves out.

## M4ac — the steering walk (27 Sept)

The owner, 27 Sept, watching walks stop against a boulder, spin round and climb cliffs: "rethink the entire pathfinding ... depth
map and pre-calculate the pathfinding realtime, then the input is to adjust for the path finding. jev can interrupt but it
should be optional. think deeper, think harder, think smarter." The walker made a Jev call before each 3 s move, tried fixed
45 and 90 degree detours blind, walked straight lines across unknown ground, and spun to read its place.

What robots do. A tuned classical pipeline (a map and a planner on a GPS and compass) does very well in cluttered 3D places,
and even walking straight at the goal gets 40-50% SPL there (Mishkin, Dosovitskiy and Koltun 2019, "Benchmarking Classic and
Learned Navigation in Complex 3D Environments"); a reactive planner scores headings by how open they are and how near the goal
(the vector field histogram, Borenstein and Koren 1991; follow the gap); per image column, what stands up from the ground is
the free space (stixels; the horizon approach to monocular obstacles); and a planner caught by an obstacle follows it on one
side until the way opens (Bug2, Lumelsky and Stepanov 1987). Our place (coordinates) and compass (the arrow) are read each tick.

- The path: by the learned roads whenever they lead there (the owner's "roads by preference"; players walked round the cliffs
  and rocks), round the places walks stopped (M4z), for any walk farther than 2 units; straight otherwise and for a retreat.
- `runSteer`: the path in one go, with no model call: each tick (0.25 s) pure pursuit of a point 1 unit on along it; the aim
  bent by `steerAim` toward the view's clearest column near it (20 columns of Depth Anything V2 small, 25 ms), a column costing
  its nearness past 0.6 and none past 0.8 taken; W held and Q/E pulses. A block (W down 1.5 s, under 0.1 moved) keeps that
  heading off near there, and the walk keeps to the more open side, along the obstacle, until 0.8 from where it was blocked
  (Bug2); nothing open in view turns 60 degrees to a side, never round; a view near in every column (a slope or wall across)
  is a block seen: W is let go, the walk turns in place and keeps to a side as after a bump, and a wanted bearing behind is not
  turned back to while it keeps to that side. Each column counts as near as its nearer neighbour (VFH+, Ulrich and Borenstein
  1998), so the aim keeps off an obstacle's edge. A walk starts at its path's nearest leg, not a waypoint behind; the way to
  safety plans each round from where it starts (a fight between rounds moves the character); an unread arrow gets runNav's
  unstick turn (review of #86).
- Bumps remembered (the owner: "self-improve"; live walk 3, 27 Sept: six bumps among Thendal Village's standing stones): each
  bump's place and heading, and the side that got the walk clear of it (0.8 units on), go to the private
  `runs/…/memory/bumps.json` (the world's, the latest 256). A walk near a known bump keeps off its heading (0.4 units), and
  about to take it again keeps to the learnt side first; a block near the last one keeps the side it was gone round on (Bug2
  goes round an obstacle one way), else the side toward the goal. The nav tool needs no key when it steers. It stops for combat, low health, the owner, a red name on the aim, the clock, 6 blocks, or 15 s
  without progress along the path since the last block (NO_PROGRESS, which M4z remembers).
- Quest walks and the way to safety steer; `JEV_WALKER=jev` walks as before, for a side-by-side comparison. The nav tool's
  `--execute` steers too, round M4z's stops.
- Jev: none per move. The quest-level steps remain Jev's.
- Evidence. Offline, the heading's depth column predicted a block at AUC 0.67-0.69 over 350 live moves: a steering bias, the
  block watch its guard. Sim (`NavTests`, SimNav's keys and boxes, depth cast as rays): open ground straight; a wall seen in
  depth walked round with no block (net turn 20-24 degrees); blind, round it with 2 blocks and no spin (net 23 degrees); a road
  path round a box in one go; a wall right ahead turned from in place with no bump; shut in, ended at the sixth bump; combat,
  low health, the owner, a red name on the aim and an unread HUD each stop it with the keys released, the way to safety walking
  on at low health and past a red name; a walk's bumps come back with the side that got it clear, and the next walk does not
  bump one again there that way. Live walk 1 (27 Sept, nav tool, village to Foul Matriarch's pin 39.6, 23.9): it took the south
  road (41.6, 25.6; 41.0, 25.7; 40.3, 26.5) with no model call and no spin, bumped 3 times at the end, ran up the slope under
  the pin, and stopped for combat (a level-4 Scrawny Ursera). The slope read 0.81-0.93 across the view and the road 0.45-0.7,
  where only 1.0 was out of bounds then: now 0.8 is, and a view near across stops W and turns in place. Live walk 2 (back to
  the village, 0.5 units): arrived. Live walk 3 (village to Yala Windwatcher, by the road east): six bumps among the village's
  standing stones, whose gaps are finer than the roads' 1-unit places, and NO_PROGRESS; on two it kept to the side away from
  the goal. The bump memory, the side rules and the dilation above follow from it. Live walk 4 (the same route, the bump
  memory holding walk 3's six): arrived at Yala in about 50 s by the road south-east round the stones, one bump in its first
  second (where walk 3 had stopped), net turn -39 degrees, no model call. Live walk 5 (Yala back to the village, the way a
  straight walk used to go into the village's tower and circle in it): arrived in about 32 s by the north, no bump. Live run
  84 (a quest run): three steering walks; one stopped for a hostile on the south road (DANGER_AHEAD), one arrived at the
  vendor with one bump; no model call per move, no death.

## The session loop (#87, opt-in `--quests --session`; 27 Sept)

The first slice of [the decision architecture](../../../docs/architecture.md): `runSession` in `Session.swift` runs the quest
loop inside the engine's `PlayLoop` (`engine/Controller.swift`). Jev's part is unchanged (the same offers, graph and criteria);
what changes is what happens around a decision and what a failure does. `runQuests` stays the qualified baseline until a live
session has run.

- **A failure is an outcome, not an end.** Every step's code is a `TaskOutcome` (`taskOutcome`): the codes that worked, the codes
  that found nothing to do, and the rest as failures of one kind (perception, knowledge, plan, execution, environment, safety,
  budget; `failureKind(forCode:)`), each logged as `task_failed`. The loop records it and plans again without that step.
- **An unread frame holds.** No fresh frame, an unreadable position or an incomplete log read waits half a second and reads
  again; five in a row record one perception failure and back off ten seconds. Nothing ends.
- **Reflexes, every tick, before any plan** (`ReflexTable.standard`, each logged `reflex` with its controller and name): the
  owner's takeover pauses the loop with no input (held for two minutes, the session ends `OWNER_TOOK_FOCUS`); stale vision holds;
  death is revived (M4s) and counted; combat is fought back (M4i, SAFETY); low health out of combat is recovered (M4w, RULE), or
  rested; after a stop, M4am's walk past and M4ak's fight are the table's `walk_past` and `blocker_fight` (#88, below).
- **Modes** (`session_mode`): dead, recovering, idle-safe, in town, questing, paused. With nothing within reach the loop is
  idle-safe: it walks to the nearest village (M4r), forgets this session's failed steps, and reads again two minutes later.
  The walk's real end is recorded (review of #96): keys held on the way end the session; a fight not won, combat or death
  on the way is the next tick's reflex after a settle, not after the two minutes; no safe place within reach, or a stuck
  walk, is read again after the backoff.
- **Only the envelope ends it** (`EnvelopeBudget`, defaults in `SessionLimits`): its time; a death (after the revive), as a
  run's; 120 graph calls, a run's budget; the second walk that makes no progress (`NO_PROGRESS_TWICE`), as a run's; or eight
  planned steps failed in a row with no success between (a fight back won or a walk to safety is not progress). The defaults
  are the owner's standing run envelope, so the first live session changes what happens between the ends, not when the owner
  is asked; widening them is the owner's decision. The end walks to safety and checks for death itself; the engine's own
  faults (keys held, a failed handoff) end it at once, as before.
- **Live** (`questsExecute`): `LiveQuestHost` is the session's host through M4r, M4s and M4w; the steps' window is the run's
  (no step after 20 minutes), the end has the envelope's rest.
- **The run loop's danger-stop rules, kept in step** (28 Sept): what stopped the walk (`stopped_by`, M4ah, M4ai) goes into
  Jev's state, a lone creature no higher than the character is fought by RULE (M4ak), and an unaggressive one with no
  threat in view is walked past (M4am), as in `runQuests`.
- **Evidence.** Sim only: `SessionTests.swift` (31 checks) on scripted reads, vitals and outcomes: the holds, the recorded
  failures, the reflexes' order and controllers, death and recovery as modes, the owner's pause and its limit, a failed call, the
  call, death and stuck-walk limits, keys held, a danger stop's retreat and fight ahead, M4ak's and M4am's rules, and `--session`. Live: not yet run; the first
  announced session is its qualification, and its `events.jsonl` (`task_failed`, `reflex`, `session_mode`, `session_end`) the
  evidence.

## The reflex layer (#88; 28 Sept)

Buff before the fight, heal under the floor, fight back when attacked, stop for a hostile ahead, heal before walking, release
and revive, and the way to safety were each first offered to Jev, each failed live, and each came back as a RULE or SAFETY
reflex in its own pull request (#72, #73, #76, #79, #107, #109). They now live in one place, `ReflexTable.standard`
(`engine/Controller.swift`; the order and each entry's controller are in [the engine's README](../engine/README.md)), and
every loop asks it each tick, building a `WorldState` from what it already reads:

- **The run loop** (`runQuests`): the owner's takeover before the quest read (`ReflexTable.ownerTakeover`); after a stop,
  `walk_past` (M4am) then `blocker_fight` (M4ak) over the `ahead` belief (`Ahead.belief`: the creature knowledge stays here,
  in m4, and the table judges a belief) and the log's level. The codes are the run's, unchanged.
- **The session loop**: as before, plus the two stop rules from the table instead of its own copy.
- **The fight** (`runFight`, `admissible`): the owner on the last frame, the start's enchant (`buff_before_fight`, with the
  review of #79's 60 % rule), the heal floor (`combat_low_health`: HEAL alone, WAIT in a cast) and the stop out of combat
  (`fight_stop_hurt`: `SAFETY_STOP_PLAYER_BELOW_30`). `BUFF_WEAPON` is no longer Jev's offer (the fight graph and
  `FightTactics.offerNames` lost it; a chain may still cast it). The tactics are the fight's.
- **The hunt** (`runHunt`, `huntAdmissible`): the owner before the survey; death (`DEAD`); in combat FIGHT alone (or
  LOOK_AROUND and FIGHT); under 60 % out of combat no walk or pick-up (REST and EAT_DRINK stay Jev's choices).
- **The walks** (`runSteer`, `runNav`, `walk()`): the owner; combat (`COMBAT`); under 30 % out of combat (`LOW_HEALTH`,
  `walk_low_health`); a red name or hostile plate within 30° of the heading (`DANGER_AHEAD`, `hostile_ahead`), never on the
  way to safety nor during an armed walk past (`walk()` now honours the pass too, as `runSteer` did).
- **Recovery and the way to safety**: `recover()` (M4w) asks the table whether a heal is due; `leaveDanger` asks it about the
  owner and `leaveDangerRounds` about combat.
- **Evidence.** Sim only: `EngineTests` (the order, each entry, combat over recovery and buffing, the #79 rule, the stop
  floors, the owner's takeover), and the old suites unchanged in what they assert: a walk stops for a hostile ahead and at low
  health, a hurt character heals before walking, a dead one releases and revives, the enchant is cast at a fight's start, the
  hunt fights when attacked; `BUFF_WEAPON` is asserted absent from Jev's offers. Live: the next run's `events.jsonl` shows each
  reflex as `reflex` with `controller` and `reflex` (its name).

## M4ad — the hunt walks as the steering walk (28 Sept)

The owner, 27 Sept: "you are climbing cliffs... this is failed failed failed", and "don't stuck and 360 screen". Live run 84:
the Windstones hunt's own moves (GO_TO_QUEST_AREA, the compass moves, detours), each a blind 3 s run on a heading, climbed
the rock slopes west of Thendal Village; and LOOK_AROUND, offered out of combat, turned the character round on the spot.

- `walkOn`, every walking move of the hunt, is a short steering walk that way (runSteer: 1.5 units, 10 s at most), with the
  view's depth, a walled view turned from, and the bumps remembered (the live hunt host reads the depth and the bump memory).
  The hunt's body reads no red names, as before: what attacks on the way is fought by the hunt. Each bump is kept where it
  happened, so the hunt does not offer that heading there again; a walk that could not get on at all is blocked where it
  ended. The steps share one key set: runSteer's `keepKeys` lifts W, Q and E at its end instead of retiring
  the set (in the sim the second walk pressed nothing).
- LOOK_AROUND is offered only in combat (an attacker behind): out of combat the hunt finds creatures by walking on, as Tab and
  the plates see what is ahead.
- Evidence: sim (`HuntTests`: the field hunt round its ridge to a fight; attacked from behind, a look round then the fight;
  no look round out of combat; the ridge's bump kept where it happened). Live run 85: the Windstones hunt fought and killed
  four creatures (its fight limit) on the grove's flat ground among the trees, none of its frames on a rock slope; the run
  retreated three times from danger ahead and fought one creature back (killed and looted); no death.

## M4ae — a creature counts for something to collect only if it drops it (28 Sept)

Live run 85: the Windstones hunt fought four Roiling Winds, and each ended `KILLED_NO_CORPSE`. That result was correct: an
elemental leaves no corpse. The fault was the choice. `counts` said a Roiling Wind counts for "Windstone Cluster", because
the two names share two runs of four letters ("wind", "inds"). So Jev saw a creature that counted, and chose GO_TO_QUEST_CREATURE over
PICK_UP_OBJECT, while the detector held a cluster at the character's feet.

- **Collect objectives:** a creature now counts for one only if a whole word of its name (four letters or more) is a word
  of the objective ("Scrawny Ursera" for "Scrawny Ursera Claw"), or two neighbouring words of the objective joined, where
  OCR read one word apart ("Urs'anah" for "Head of Urs anah"). A junk tail on the plate does not stop the match; a short read ("Winds", "Wind") never matches
  "Windstone".
- **Kill objectives:** unchanged.
- **Jev's walk facts:** the hunt's walking moves now describe what they are since M4ad: up to 1.5 y units, 10 s at most,
  steering round what they meet. The old text said "about 3 s". The run's `hunt_limits` records `walk_s` as the step's
  seconds.
- **Evidence:** sim only. `HuntTests` checks Roiling Winds, full or short, against "Windstone Cluster", and that it
  is no quest creature for it; it also checks Urs'anah, with a tail or without, against her head. The live
  proof is the next Windstones hunt.

## M4af — a pick-up that worked is counted (28 Sept)

Live run 86, after M4ae: the Windstones hunt chose PICK_UP_OBJECT twice. Both hovers read "Raw Windstone / Harvesting
Windstones / 3/15 Windstone Cluster".
- The first right-click walked the character to a far cluster by Click-to-Move, which took about 8.5 s.
- The second started the gathering cast in reach. The chat said "You receive loot: [Windstone Cluster]x2", and the tracker
  showed 5/15.

Both were still recorded as "its count did not rise within 8 s". As the tracker changed, OCR missed the quest's title, so
"5/15 Windstone Cluster" was read under the quest above it (Foul Matriarch). The check needed the same quest and the same
text. After two such results the hunt stops offering PICK_UP_OBJECT, so the run walked on and fought instead.

- **The count check (`pickedUp`):** a pick-up's count is found by the objective's own text; the quest title is not needed.
  The "Ready for turn-in" check still goes by quest, since that line has no text of its own.
- **The wait:** a pick-up now waits up to 15 s (`HuntLimits.pickUpSeconds`) for the walk, the cast and the count. It was
  8 s, and it still ends at once on success or an attack.
- **Evidence:**
  - Sim: `HuntTests` parses run 86's tracker with the title unread and finds the rise; an unchanged count finds none.
  - Live: run 86's recording (121–143 s) shows the first click's walk cut at 8 s, just short of the cluster. It shows the
    second click's cast bar, the loot line (x2) and 5/15. The next Windstones hunt is the proof that a pick-up is
    counted.
- **Also:** the count before the click is read from a frame taken just before it, not from the survey. The owner's
  takeover ends the wait with no key pressed, and `hunt_limits` records `pick_up_s`. Jev's PICK_UP_OBJECT facts
  say the new wait (15 s at most), not "a few seconds".

## M4ag — a run's end walks home from farther (28 Sept)

Live run 86 ended at (36.7, 33.5), where its Foul Matriarch walk had stopped for danger and its retreat had come back
to. Thendal Village was 13.6 units away, beyond `safeReach` (12). So `safePlace` found none, and the run exited with no
`leave_danger`. The character stood there for the seven minutes before run 87, and run 87 began with it as a ghost by
the Spirit Healer: killed while idle, then released by the game.

- **The limit:** `QuestLimits.safeReach` is now 25 units. The way home is steered (M4ac), by the learned roads where they
  lead there, else straight at the village. It stays inside the run envelope's reserve, as before.
- **A longer way:** a walk to safety that ran out of its time (`TIME_LIMIT`, one walk at most 180 s) is now walked on
  from where it stopped, as one that met combat is. It is still at most four walks (`safeWalks`), all by the envelope's
  end.
- **Evidence:**
  - Sim: `HuntTests` checks that run 86's end point walks to Thendal Village, and that a point 42 units from any village
    still walks nowhere. It also checks that a timed-out walk is walked on to arrival.
  - Live: the next run that ends away from a village.

## M4ah — Jev is told what stopped the walk (28 Sept)

Live run 89: four walks stopped for a red name ahead (`WALK_DANGER_AHEAD`), and Jev chose RETREAT each time (0.87–0.98),
over FIGHT_AHEAD. That included both walks towards Foul Matriarch, whose objective is those very Ursera Scavengers. Jev's
state said nothing of what stood ahead, and the owner's rules say a red name is danger.

- **`stoppedBy`** (`QuestHost`, live in `LiveQuestHost`): after a stop, Tab selects the nearest enemy in front, as a player
  looks before choosing, and the target frame's name is read. That is usually what stopped the walk; Tab takes the
  nearest. It follows the hunt's own key sequence (`selectNearest`):
  - Esc only while the target frame names something;
  - a Game Menu that opened anyway is closed;
  - then Tab, each key given time to show.

  The selection is dropped the same way after, since Tab does not move off a selection and FIGHT_AHEAD's fight selects
  its own. Selecting starts no fight. It runs only out of combat, and never while the owner has the game; logged
  `stopped_by`.
- **Jev's state:** while the stop stands (RETREAT or FIGHT_AHEAD on offer), the quest state has
  `"stopped_by": {"name", "counts_for_objective"}`. M4ai adds `level` and `character_level`. The objective is matched against the log's objectives
  (`logObjectives`, `objective(for:)`), or "none". Nothing is added when the name did not read. No criterion or graph
  changed: the choice stays Jev's.
- **Evidence:**
  - Sim: `HuntTests` checks the quarry named with its objective, another creature with "none", an unread name with
    nothing, and nothing before a stop or after the retreat; also the log's two objectives for Foul Matriarch.
  - Live: the next run whose walk stops for a red name.

## M4ai — Jev is told the level of what stands ahead (28 Sept)

Live run 91: a walk stopped for a red name, `stopped_by` read "Scrawny Ursera" (it counts for no objective), and Jev chose
RETREAT. A level 4 character retreated from a creature of level 3 or 4, a fight a player takes for its experience.

- **`stoppedBy`** now returns an `Ahead` (a name and a level). After Tab reads the name, the pointer rests on the target
  frame's portrait (`QuestHUD.targetPortrait`, the mirror of the character's own). The level comes from its unit tooltip
  (`unitLevel`: "Level 3"; nil for "??"). It counts only when the tooltip's first line names the Tab target; a
  "Requires Level" line and a player's line are ignored. The pointer moves only while the game is the engine's and out
  of combat. Once attacked, the target is not dropped, so the fight back has it.
- **Jev's state:** `stopped_by` has `level` and `character_level` beside the name and the objective. No criterion changed.
- **Evidence:**
  - Sim: `HuntTests` checks the level in the state, and `unitLevel` on run 90's tooltip ("Scrawny Ursera", "Level 3",
    "Beast") and on an elite's "??".
  - The portrait's place was checked on run 91's fight frame: the portrait is centred at (1795, 993), with the level
    badge below it.
  - Live, run 92: `stopped_by` read "Scrawny Ursera", level 3, at character level 4. Jev still chose RETREAT, but
    FIGHT_AHEAD rose from 0.02–0.13 (run 89) to 0.19. The information is Jev's; whether to fight such a blocker is a
    policy question for the reflex table (#88).

## M4aj — the hunt remembers where it picked things up (28 Sept)

**Since 28 Sept:** a store like this is working memory, not learning. Learning needs provenance and evaluation (the learning loop, #93; the world model, #89); see `docs/solutions/architecture-patterns/fix-engine-capability-not-goal-patches.md`.

Live runs 85–89: the Windstones' clusters were found round Thendal Grove, but the minimap shows no ring for that quest.
So every hunt searched by compass (run 87 wandered south and east among Vuldren and Cirrusflies, and found none).

- **Remembered:** a pick-up that counts records where the character stood, under its objective (`HuntHost.remember(place:
  for:)`; live in the private `runs/002_wow_visual/memory/places.json`, the newest 32 per objective; logged
  `place_remembered`).
- **Used:** with no ring on the minimap, the nearest remembered place for an open collect objective is the hunt's area
  (`readSurvey`, `rememberedArea`). It is inside within 3 units, since the two seeded pick-ups were 3.3 apart. So
  GO_TO_QUEST_AREA and the area detours are offered as for a ring. Jev's state says `"on_minimap": false, "remembered_from_pick_ups": true`.
- **Seeded:** from the two pick-ups that worked, (41.6, 26.8) in run 86 (its recording's minimap) and (43.8, 26.5) in
  run 89.
- **Evidence:**
  - Sim: `HuntTests` checks the two pick-ups remembered under their objective; the nearest place as the area (not
    inside, at its distance); GO_TO_QUEST_AREA offered; the state's flags; no area without places; inside within the
    radius.
  - Live, run 93: Jev chose GO_TO_QUEST_AREA twice by the remembered area (south-west, to the grove). It picked up a
    cluster there (10/15), and the place was remembered at (41.4, 26.9); `places: 2` shows the seeded file was read.
    It ended SAFE, with no death.
- **Also:** the places of every open collect objective are pooled, so with two such quests the nearest of either leads.

## M4ak — a lone creature no higher than the character is fought, not asked about (28 Sept)

**Since 28 Sept:** this RULE stands in for a fact Jev lacked: which creatures are aggressive. The capability is creature knowledge learned from what creatures did, with provenance, in Jev's state (#89), which the reflex table's hostile-ahead entry would use (#88); see `docs/solutions/architecture-patterns/fix-engine-capability-not-goal-patches.md`.

Live runs 89–94: Jev chose RETREAT at every red-name stop (0.77–0.98). With `stopped_by` it knew what stood there and
at what level (M4ah, M4ai), and it still retreated, from a level 1 Juvenile Vuldren at level 4 too (run 94). The
walks to Foul Matriarch, Skysight and the Windstones' grove stood still, and so did the levelling.

- **The rule** (`fightsBlocker`, RULE, in `runQuests`): after a stop, a creature whose level reads no higher than the
  character's, with no other hostile red name or plate in view (`Ahead.others`), is fought: FIGHT_AHEAD, with no Jev
  call. It is logged `quest_step` with `controller: RULE` and the rule's words.
- **Everything else stays Jev's:** a higher level, company, an unread level or an unread character level.
- **Unchanged:** the fight is M3's, with its own start health (90%) and safety. A kill offers the stopped step again
  (M4p).
- **Counting company** (`aheadCompany`, live after Tab): the untargeted hostile plates, plus every red name. The
  target's own plate is white-outlined and is not among them; a near target's name is on its plate, not red. A far
  target's red name counts as company, and so does a red that is not a creature, or no frame at all. So the rule never
  takes a creature for alone that may not be. The cost is that a far creature is Jev's, not the rule's. Jev's
  `stopped_by` carries the count as `other_hostiles_in_view`.
- **Off switch:** `JEV_BLOCKER_FIGHT=off`.
- **Evidence:**
  - Sim: `HuntTests` checks that a lone level 1 at level 4 is fought by rule and the stopped hunt offered again. A level
    5, company and an unread level go to Jev (RETREAT in the script). On synthetic plates, an untargeted hostile plate
    beside the white-outlined target counts as company, the target alone as none, and a red name always as one
    (reviews of #107: the larger of the two less one missed a companion, and so would taking a red name off whenever
    the target's plate went unread).
  - Live, run 95 (the first count): the rule fought a lone level 1 Juvenile Vuldren that stopped the walk to Skysight
    (`controller: RULE`), killed it, and the run went on. No death; it ended SAFE.

## M4al — the backpack is closed after a read, whoever opened it (28 Sept)

Live runs 87–98: the Combined Backpack stood open through whole runs. `readBags` closed it only when that read had
opened it, so once it was open (from an earlier step or session) it stayed open. With it open, the game draws unit
tooltips beside it, outside the tooltip box. The recording of run 98 shows "Scrawny Ursera / Level 3 / Beast" drawn by
the backpack. So M4ai's target levels read null at most stops, and M4ak's rule seldom fired. PICK_UP_OBJECT's hovers also
read "nothing" four times in run 98.

- **The fix:** a read with `close` (the quest run's bag reads) now closes the backpack whenever its title still shows
  after the read. Before, it did so only if it had opened it.
- **Evidence:** a source check in `tools/MotorProof.swift`. Run 98's recording is the cause. Live: the next run's
  `stopped_by` levels.

## M4am — an unaggressive creature in the way is walked past (28 Sept)

**Since 28 Sept:** this RULE stands in for a fact Jev lacked: which creatures are aggressive. The capability is creature knowledge learned from what creatures did, with provenance, in Jev's state (#89), which the reflex table's hostile-ahead entry would use (#88); see `docs/solutions/architecture-patterns/fix-engine-capability-not-goal-patches.md`.

The owner, 28 Sept: "Juvenile Vuldren is unagreesive. Need to separate aggressive or non aggressive". Their names are red,
like any hostile's (run 99's frame), so the walks stopped for them, Jev retreated, and M4ak's rule fought them. Only
knowledge tells them apart.

- **Knowledge:** `learning/knowledge/zephras-creatures.json` lists the creatures that do not attack first, by the
  owner's word (Juvenile Vuldren); the owner's rules have it for Jev too. A read name matches when most of the known one
  is in it (`mostlyIn`), so "luvenile Vuldren ЛОРAУ" matches.
- **The rule** (`runQuests`, RULE `WALK_PAST`): when a walk stops for one with no hostile in view that may attack, there
  is no retreat and no fight. A walk stops for a far red name, and Tab usually selects that creature, so its own red name
  is among M4ak's company (`Ahead.others`). So `stoppedBy` reads each red name's text (`aheadThreats`, OCR x3): the
  threats are untargeted hostile plates and red names that are not an unaggressive creature's, an unread one included
  (`Ahead.threats`; the event `stopped_by` logs it). The rule needs none (review of #109). The stopped step stays open, and when it is taken again its first walk goes past red names ahead
  for its first 30 s (`QuestLimits.passSeconds`, `NavDestination.passUntil`, `QuestHost.passNext`). The pass is that
  step's alone: another step taken first drops it, and a walk that never starts or comes 30 s late does not take it. An
  attack still stops that walk and is fought back (M4i). It happens once a step per run; a second stop on that step is Jev's.
- **M4ak's rule** no longer fights an unaggressive creature.
- **Evidence:**
  - Sim: `HuntTests` checks one Vuldren stop walked past (no RETREAT offered, the hunt offered again), the second stop
    Jev's, another step taken first not walking past, a threat or unread company beside it leaving the stop to Jev, the
    far creature's own red name no threat (and another's, an unread one or a hostile plate one), the OCR-mangled name
    matched, a Scrawny Ursera not matched, and M4ak's rule not fighting a Vuldren.
  - Not shown offline: that Vision reads a live red name well enough; an unread one only keeps the stop Jev's.
  - Sim: `NavTests` checks that a steering walk with a red name ahead stops, and does not while it walks past.
  - Live: the next Vuldren stop.

## Limits of the first walks (M4a)

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
  $V/m4/Hunt.swift $V/m4/HuntProbe.swift $V/m4/Quest.swift $V/m4/QuestProbe.swift $V/m4/Roads.swift $V/m4/Session.swift \
  $V/m5/Marks.swift $V/m5/Reader.swift $V/engine/World.swift $V/engine/Controller.swift \
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
  experiments/002_wow_visual/m4/Session.swift experiments/002_wow_visual/m4/SessionTests.swift \
  experiments/002_wow_visual/engine/World.swift experiments/002_wow_visual/engine/Controller.swift \
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
