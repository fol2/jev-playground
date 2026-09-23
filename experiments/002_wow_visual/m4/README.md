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
| `NavProbe.swift` | Native shell: capture, coordinates OCR, pid keys, Jev HTTP, run files; `--replay` and `--sim-jev` rehearsals | `--preflight`, `--dry-run` in `tools/motor_offline.py` |
| `NavTests.swift` | Counted offline checks on synthetic arrows, rules, rejections and simulated walks | Focus Gate `motor-offline` |

Two pieces now shared with M3 live in `m3/Fight.swift`:

- **The generic Jev question and reply validation** (`JevAction`, `actionQuestion`, `parseChoice`).
- **`LiveKeys`**, the pid-targeted key state that M3's review hardened:
  - a key's watchdog grant is taken before its key-down is posted;
  - key events are posted under one lock;
  - a watchdog releases held keys;
  - no key goes down after the exit sweep.

  Before M4a this logic lived inside M3's live shell and ran only live. Its rules now have ten
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
  - A move is **blocked** when W was held for 1.5 s with under 0.1 units of movement. A move that
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
  - On eight lossless (PNG) captures turning in place beside three quest icons, it was within
    12° of the author's labels. Successive readings stepped 46–59° per 300 ms Q press.
  - Saved JPEGs do not replay the live frames faithfully. The same frame decoded two ways
    differed by up to 69 per channel inside the arrow box. Through the live decode path, one of
    16 labelled JPEG frames read 56° off. Calibrate on PNG captures.
- **Position: the coordinates text under the minimap** (x 2322, y 300, 200×34). It is OCR'd
  after a ×3 upscale and parsed as `44.8,28.1`, `44.8, 28.1` or `44.7.27.9`.
  - It was read on all 61 saved frames at this layout.
  - It was never unreadable in 99 live looks.
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

## Limits

- Three supervised walks in one village. These are trials, not a success rate.
- The pocket rehearsal shows that Jev does not leave a dead end by moving away from the goal.
- Destinations were read from the world map by hand. Reading pins, and interacting with an NPC
  on arrival, belong to the next slice.
- One layout and window size. The boxes move with UI scale, Edit Mode or window size.
- Labels are the author's, from the saved frames.

## Reproduce

```sh
swiftc -parse-as-library experiments/002_wow_visual/m0/Motor.swift experiments/002_wow_visual/m1/Plate.swift \
  experiments/002_wow_visual/m3/Fight.swift experiments/002_wow_visual/m4/Nav.swift \
  experiments/002_wow_visual/m4/NavTests.swift -o /tmp/nav-tests && /tmp/nav-tests
python3 -m tools.motor_offline   # builds and checks M0, M1/M2, M3 and M4 with no live effect
```

`--replay DIR` needs saved frames. `--sim-jev` and `--execute` need `TYPESAFE_API_KEY` in the
environment; the key is never printed or written. A live walk also needs the owner's current
authority, and WoW running but not frontmost.
