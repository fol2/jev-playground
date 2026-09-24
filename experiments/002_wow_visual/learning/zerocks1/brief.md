# Brief: learn a human's low-level Shaman play from video frames (read-only)

Do NOT edit any repository file. Write only the two output files named in your task.

## Source
YouTube "Skyborne Shaman: Zephras Isle | WoW Forever Beta Launch Day — No Commentary #1" (player Zerocks),
a brand-new level-1 Skyborne Shaman on Zephras Isle. Frames at 1 per second, 640x270 (ultra-wide).
Each sheet is a 3x2 grid of consecutive seconds; each frame's top-left label is its time (e.g. 04m03s).
Open and look at every sheet in your folder, in order. If you cannot view images, write that in the
output and stop.

## Why
We are teaching an AI agent ("Jev") to level a Shaman by questing like a skilled human. The agent sees
only the screen and presses keys. We already know: weapon buff then Lightning Bolt pull then melee,
loot, eat/drink when low, skip grey (tapped) nameplates, hotkey digits turn red when out of range,
plan quests in the quest log.

## Output 1: techniques (Markdown)
One line each, UK English, with frame times, under these headings; mark guesses "(unsure)":
1. Camera and looking around (pitch, zoom, swinging the view while moving, first person)
2. Target choice and distance (how far when pulled, what they skip, which spell opens)
3. Fight rhythm (cast bars, melee, heals, fight length, mobs at once)
4. Extra enemies (adds, patrols, casters, runners)
5. Recovery (sit, eat/drink, health/mana when the next pull starts)
6. Quest flow (NPC ! and ?, turn-ins, quest log/map, objects used, class/trainer visits, level-ups)
7. Route and navigation (roads, minimap, how they find quest targets)
8. UI and keys (action bar slots and what is in them when visible)
Then "Surprises": anything a careful human does that a naive bot would not.

## Output 2: decision points (JSON Lines)
One JSON object per line for each moment the player makes a visible choice (new target, pull, spell,
retreat, eat, loot, turn-in, route change, look around...). Aim for 60-150 lines. Fields:
{"t": "04m03s", "state": {short facts visible just before: level, health/mana if readable, in_combat,
target name/level/distance guess, enemies in view with rough distance and whether hostile/neutral/grey,
quest objectives shown, where (village/field/cave/road)}, "options": [3 plausible actions a bot could
take, as short UPPER_SNAKE names with a one-line meaning each, e.g. {"PULL_WITH_BOLT": "..."}],
"human": "<the option name the player actually took>", "evidence": "what in the next frames shows it"}
Only include moments where the next frames make the human's choice clear.
