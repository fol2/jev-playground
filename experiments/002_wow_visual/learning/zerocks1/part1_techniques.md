# Zerocks Shaman, part 1 (00:00–09:59) — low-level play from frames

Sheets `s000`–`s099` viewed in order. Each sheet is six consecutive seconds. The character is a pale elf in third person on a custom starting isle (Zephras Isle / Skyborne). Level 1 until 06m43s, then level 2. Health stays full for the whole grind. No food, drink, or sit appears.

## 1. Camera and looking around

- 00m00s–00m09s: Zerocks title card only; no gameplay camera.
- 00m10s–01m05s: scripted flyover, not the player camera. Wide establishing shots, then a push through trees into the village. A Lua error window sits on the cinematic from 00m10s.
- 01m07s: gameplay starts in third person, behind and slightly above the character, zoomed out enough to see the whole body plus a wide ring of the square. Never switches to first person in this part.
- 01m07s–01m40s: camera holds a steady look down the cobbled path while the player stands in the spawn crowd.
- 01m41s–01m47s: view yaws right and pitches up the ramp into the tree hall, following the walk rather than snapping.
- 01m59s: hard yaw back over the shoulder to look out of the hall at the crowd before leaving.
- 02m21s–02m29s: yaw off the tents and down the dirt path, then a left sweep across the beast field.
- 02m45s–04m40s: while casting, the camera stays planted and pitched slightly down at the target; between pulls it yaws along the lakeshore.
- 04m45s: large left swing while walking, checking the bank behind them.
- 05m57s–06m05s: wide sweep from the kill spot across the field, to the lake, then back onto the uphill path.
- 07m30s–07m35s: slow pan across the corpse-covered hillside and back to the water, looking for a live mob.
- 08m33s: yaw off the dead field toward the cliff base.
- 08m58s and 09m09s: after kills, the view swings across the path before the feet move to the next pull.
- Zoom barely changes. Pitch stays a little downward whenever they are picking mobs out of the grass.

## 2. Target choice and distance

- 01m07s–02m20s: no hostile target. Town is players and quest NPCs only. They do not click random players.
- 02m27s–02m41s: they walk through a field of small beasts and corpses where other players are already fighting, and do not take those tags.
- 02m45s: first pull is one small beast alone by a fallen root. Red selection circle, then a lightning bolt. The mob is a short cast away, not under their feet and not at the far edge of the screen.
- 03m19s, 03m38s, 03m53s, 04m27s: same pattern along the shore. One beast at the foot of a tree. Neighbours a few yards further are left alone.
- 05m03s and 07m08s: the mob is allowed to walk into the selection circle while they finish the cast. They do not backpedal.
- 06m10s: on the hill they take the nearest single beast and leave the busier pack further up.
- 07m19s–07m37s: the hillside is a carpet of red crawler corpses. They walk through it and pull one live crawler on the fringe (07m23s, 07m38s), not a cluster.
- 08m35s and 08m46s: once the field is stripped, they move to crawlers against the cliff wall, still one at a time.
- 09m31s and 09m49s: a crawler another player is already hitting is skipped. The next bolt goes to a different crawler (09m32s, 09m51s).
- Opener is always the lightning cast. No pull with a melee swing. Healing Wave is on the spellbook from 03m29s and is never the opener.
- Nameplates get a mouse-over before some pulls (04m06s–04m11s, tooltip over a nearby creature).

## 3. Fight rhythm

- Casts show a thin yellow cast bar above the action bar and a blue-white bolt. The character stands still for the cast.
- A typical kill is about five to eight seconds: 02m45s–02m52s, 03m19s–03m31s, 03m53s–04m03s, 04m27s–04m35s, 05m44s–05m53s, 06m10s–06m19s, 07m38s–07m46s, 08m15s–08m20s, 08m35s–08m43s, 09m22s–09m26s.
- Small yellow numbers (4–6) show on the first moments of a pull; later bolts hit for about 13–16. One finishing hit is 22 (04m35s) and the level-up hit is 23 (06m43s). Exact spell split beyond the lightning visual is unreadable (unsure).
- 08m48s: a bolt prints "Miss". They keep casting at the same crawler rather than swapping target or running in.
- Fights stay single-target. No second mob is tagged while the first is alive.
- Health stays full, so no heal is woven in. Healing Wave is only read, at 03m27s–03m34s, with the spellbook open during a live fight.
- They also cast with the guild window covering the left of the screen (04m54s–05m05s).
- XP is 50 a kill at level 1 and 40 a kill after the ding.
- Loot is a short tooltip or window (02m53s, 05m54s, 06m19s), then they turn away. They do not stand on the corpse.
- From about 07m48s, once the side resource bar is visibly shorter than health, they stand or walk for several seconds between some kills (07m48s–07m56s, 08m03s–08m14s) instead of chaining every global.

## 4. Extra enemies

- No caster mobs and no runners show up. Hostiles are small shore beasts, then larger red crawlers on the hill.
- Other players are thick from the spawn through the grind. Their fights are treated as occupied and walked around.
- 07m03s: while the keybind dialog is up, a crawler walks in beside the character. It is not pulled until the dialog is closed (07m08s). It does not bring friends.
- Live crawlers a few yards from the current target do not aggro (07m23s, 08m16s, 09m22s). Packs are avoided by position, not by an AoE.
- Grey corpses are ignored as targets. Yellow ground sparkles and a blue crystal on the hill (09m18s) are walked past.

## 5. Recovery

- No sit, eat, or drink in the whole ten minutes. No eating or drinking buff appears.
- The next pull always starts at full health, including 02m45s, 06m37s after the reload, 06m47s just after ding, and 09m51s at the end.
- Mana is the resource that moves. The side bar looks full on the first pulls, shorter by 05m26s, short while the character sheet is open at 08m20s, and only partly recovered after the long walk at 09m12s–09m20s (unsure of exact percents).
- Recovery is walking and standing between bolts, not a consumable. They still start a new pull at 09m22s without drinking.
- 06m43s level-up restores them visually; bars look full again at 06m45s before the next bolt.

## 6. Quest flow

- 00m10s–01m05s: they let the lore cinematic play out (Zephras Isle, Skyborne, the elements). They do not reach gameplay until 01m07s.
- 01m12s–01m14s: first parchment quest is opened and accepted in the spawn crowd.
- 01m28s–01m32s: quest log opened, glanced at, closed. No turn-in.
- 01m42s–01m53s: they walk up into the hall and accept a quest from the NPC there. The name Aethon of the Gales is on screen at 01m42s. Quest title text is too small to read (unsure).
- 02m12s–02m20s: another quest is accepted at the blue tents outside, then the window is closed and they leave.
- 03m09s: world map opened for a moment, then closed. They do not path to a turn-in.
- 04m14s–04m23s: quest log opened again in the middle of the shore grind, a quest detail clicked, then the list. Still no turn-in.
- 06m43s: "Level 2" and the congratulations text. Chat also says a new spell was learned. They do not open a trainer or the talent window.
- No quest-complete turn-in, no quest object clicked, and no hand-in NPC after leaving town. The tracker stays up with kill-style lines through 09m59s.

## 7. Route and navigation

- 01m07s–01m40s: standing in the packed square, reading, before any travel.
- 01m42s: off the cobbles, up the wooden ramp, into the hall, then back down at 02m00s.
- 02m06s–02m11s: they take the side of the path past the mossy stones instead of pushing the densest part of the crowd.
- 02m12s–02m23s: blue tents, quest, then off the path into the grass.
- 02m24s–02m41s: dirt track out of camp, through the already-camped beast field, toward the lake. A glowing blue wisp on the path at 02m26s is passed.
- 02m42s–06m05s: grind under the lakeside trees, moving along the bank rather than back to town.
- 06m06s: uphill away from the water into the crawler field.
- 06m32s–06m35s: loading screen after a video-options change, then they are back in the same field at 06m36s and pull again.
- 07m18s–08m32s: circuits of the corpse hill.
- 08m33s–08m53s: down to the cliff wall when the hill is mostly corpses, two kills there, then back.
- 09m00s–09m59s: path along the cliff and back through the field. Minimap stays visible the whole time; the world map is only opened once (03m09s). They are not following a road after the village.

## 8. UI and keys

- Standard layout: portrait and bars bottom left, target frame to the right of it when something is selected, minimap top right, action bar along the bottom, bags at the far right, combat log lower left, quest tracker lower right early on.
- The main bar has a few early icons on the left (a lightning icon is visible) and many empty slots. Exact key labels are not readable (unsure).
- 02m56s–03m01s: Escape menu, then the Controls window. They are checking binds before the second pull.
- 03m09s: world map.
- 03m27s–03m34s: spellbook, General tab then Restoration. Healing Wave is the listed heal. Book stays open until the mob is dead.
- 04m14s–04m23s: quest log.
- 04m52s–05m14s: guild finder, including a recruitment page, open across two kills.
- 05m32s–05m41s: mouse held on an action-bar icon so the tooltip stays up while they walk.
- 06m21s–06m23s: tooltips on the bar again between pulls.
- 06m26s–06m31s: video options. 06m32s the client reloads.
- 06m51s–07m06s: Controls again, then the keybinding list and the quick-keybind dialog, right after the new level-2 spell. The dialog is still up at 07m05s.
- 08m20s–08m28s: character sheet opened on the kill, stats page, then closed.
- A red script-error banner (same family as the 00m10s Lua error) pops at 08m20s, 09m04s, 09m23s and 09m24s. They leave it and keep playing.
- Chat is left on. Spawn chat is noisy; later lines include loot-to-appearance and the level-up.

## Surprises

- They watch the whole intro cinematic, Lua error and all, instead of rushing the first quest.
- The first minutes in the world are UI literacy: quest text, quest log, a look around the hall, then a second quest, and only then a mob. A bot that pulls the first red nameplate never does this.
- They open keybinds, the map, the spellbook, the guild finder, video options, and the character sheet during the opening grind, including mid-cast and mid-pull.
- Changing video settings is allowed to hard-reload the client (06m32s). They resume the same camp afterwards rather than re-planning the route.
- Healing Wave is read during a fight and then never pressed, because nothing is hurting them. Mana is saved for bolts.
- They keep a lightning cast going with the guild window over a third of the screen, and they stand in the keybind dialog while a crawler walks up to them.
- After ding they throw one more bolt before they go bind the new spell. Training and talents wait.
- Target choice is social. Mobs other people are already hitting are skipped, even when they are the nearest red health bar (09m31s, 09m49s).
- A field of corpses is a reason to move to the cliff, not a reason to pull the remaining clump.
- Low mana is handled by standing and walking, not by drink or by sitting. Full health is never "fixed".
- Loot is a glance. Other people's sparkles, a blue crystal, and a path wisp are left alone.
- A miss does not change the plan. The same crawler gets the next bolt (08m48s).
- The recurring red error banner is ignored. Casting continues through it.
- The camera is a scanning tool: big yaws between pulls, pitched down at the grass, steady only while the cast bar is running.
