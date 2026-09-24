# Class-agnostic mechanics (WoW Forever / Classic baseline)

Facts a questing agent can reason from, not instructions. One mechanic per line. Trust order: **[owner-live]** > Forever client / owner-adjacent Forever guides > Classic baseline > Forever videos > Classic videos. Unverified or transferred Classic rules are marked.

---

## Perception cues

- A hostile with no nameplate is beyond nameplate range (~40 yd on the owner client). [owner-live] owner-demo-play; wow-shaman-capabilities
- A red nameplate means the mob is aggressive (will attack on proximity). [owner-live] wow-shaman-capabilities
- A yellow nameplate means the mob is neutral (attacks only if damaged or otherwise provoked). [owner-live] wow-shaman-capabilities
- A grey nameplate bar is a mob already tapped by someone else: no kill credit, leave it. [owner-live] owner-demo-play
- Selecting a quest mob at range enlarges its plate and adds a white outline. [owner-live] owner-demo-play
- Neutral target-frame nameplate bar is yellow and turns red once the target is hostile; the portrait ring turns red in combat. [owner-live] wow-shaman-capabilities
- Target-frame / nameplate **level-text** colours are a separate system from plate hostility: red ≥ player+5, orange +3/+4, yellow ±2, green below yellow but still giving XP, grey = zero XP. [classic-baseline] leveling_fundamentals §10; Warcraft Wiki Mob experience
- A skull on the level indicator means world-boss or (authentic 1.12) a mob 10+ levels above the player. [classic-baseline] leveling_fundamentals §1; Warcraft Wiki Aggro radius
- Grey **level text** (no XP) is not the same signal as a grey **tapped** plate. [owner-live + classic-baseline] owner-demo-play; leveling_fundamentals §10
- Players 1–5 have no grey-XP threshold; from 6–39 grey level is `player − 5 − floor(player/10)`. [classic-baseline] leveling_fundamentals §10
- Each action-bar hotkey digit turns red when the current target is beyond that ability’s range, and white when in range. [owner-live] owner-demo-play; wow-shaman-capabilities
- Range colour on a hotkey can lag a target change by up to ~1 s. [owner-live] wow-shaman-capabilities
- No plate at all means the target is outside nameplate range, not merely out of a given spell’s range. [owner-live] owner-demo-play
- Plate height on screen is a weak distance cue because terrain and mob height vary. [owner-live] owner-demo-play
- Screen-edge red flash is a low-health warning (seen when player health fell to about 30%). [owner-live] owner-demo-play
- Red error text appears centre-top (e.g. “You are facing the wrong way!”) and lingers ~3 s. [owner-live] owner-demo-play; wow-shaman-capabilities
- Caster mobs show their own cast bar under the nameplate and tend to stay at range. [owner-live] owner-demo-play
- A large grey floating name (OCR box ≥ 22 px) marks a corpse; the last-seen selection circle is stale once the mob reached melee. [owner-live] wow-shaman-capabilities
- Quest-tracker text sits on the right; hovering a quest in the log highlights its area on the world map. [owner-live] owner-demo-play
- World map shows quest-giver bubbles, not objective areas, until a quest is hovered or selected. [owner-live] wow-shaman-capabilities
- Minimap quest icons beside the player arrow carry silver highlights; silver connected to the navy dot and the longest silver ray indicate facing toward the objective. [owner-live] wow-shaman-capabilities
- “Classic” install UI can hide overhead quest markers while map markers still work. [video-forever] videos_low `2S0MlYfmkxA` 00:09:50–00:12:09
- Elite creatures show a gold dragon on the **portrait**, not reliably on vanilla-style nameplates. [classic-baseline] leveling_fundamentals §8
- Saved JPEGs do not replay live frames faithfully (decode can differ by up to 69 per channel); calibrate pixels on PNG. [owner-live] wow-shaman-capabilities

---

## Aggro and pulling

- Same-level proximity aggro is ~20 yd; each level the mob is above the player adds ~1 yd, each level below subtracts ~1 yd. [classic-baseline] leveling_fundamentals §1; Warcraft Wiki Aggro radius
- Aggro radius clamps to a ~5 yd floor (combat reach) and a ~45 yd ceiling when the mob is ≥25 levels above the player. [classic-baseline] leveling_fundamentals §1
- Planning formula used by the research brief: `20 + (mobLevel − playerLevel)` yards, clamped [5, 45]. [classic-baseline] leveling_fundamentals “Most useful”
- Height difference weighs heavily: a mob on a ledge may not aggro at the horizontal distance that would pull on flat ground. [classic-baseline] leveling_fundamentals §1
- Front-of-mob pull distance may be slightly larger than from behind; “safe from behind” is not a reliable margin. [classic-baseline] leveling_fundamentals §1
- Some named “Starving” mobs, mechanicals, and dungeon types are reported to aggro farther than equal-level normals. [classic-baseline] leveling_fundamentals §1
- Mounted radius follows the same 1.12 formula; high-level characters can ride past low-level mobs with tiny bubbles. [classic-baseline] leveling_fundamentals §1; Blizzard Kaivax
- First **damaging** hit tags loot/XP; aggro alone does not tag. [classic-baseline] leveling_fundamentals §10
- DoTs tag on first tick, not on cast. [classic-baseline] leveling_fundamentals §10
- Combat can start with no health loss: gate “engaged” on the combat ring or the mob closing, not on target-health drop. [owner-live] wow-shaman-capabilities
- Assist / co-aggro: a mob already fighting you that enters another idle mob’s assist radius pulls that second mob; planning figure ~15–20 yd, not a constant. [classic-baseline] leveling_fundamentals §5
- Linked-group aggro: damaging one member pulls the whole predetermined set regardless of distance, and the link is often asymmetric. [classic-baseline] leveling_fundamentals §5
- Linked combat groups leash together (2019 Classic fix); you cannot always peel one member by kiting. [classic-baseline] leveling_fundamentals §5
- Call for Help is an active mob ability that alerts allies in a radius, distinct from flee. [classic-baseline] leveling_fundamentals §5, §7
- Patrols follow fixed paths and remain moving aggro bubbles; a patrol already walking may continue its route in combat and social-aggro anything it passes. [classic-baseline] leveling_fundamentals §4
- LOS-pulling a moving patrol too early can leave it on its patrol path, walking into other packs. [classic-baseline] leveling_fundamentals §3; YouTube `zO6QsCXK8Zk` @ 1:03
- Caster and shooter mobs stand at range and cast; trees and thin props often do **not** block spell LOS outdoors. [classic-baseline] leveling_fundamentals §3, §6
- Buildings, ruins, and thick walls usually block LOS; dungeons are more reliable than open world. [classic-baseline] leveling_fundamentals §3
- After LOS break, caster mobs tend to run toward the player until they regain LOS. [classic-baseline] leveling_fundamentals §3
- Safety-margin pulls from ~30+ yd leave room to abort if extras join. [classic-baseline] leveling_fundamentals §2
- Forever design still targets slow solo fights (~10–15 s per mob) and small packs (tanks meant for ~3–4 enemies). [forever-guide] leveling_fundamentals §2; WoWSoD Pro; But Why Tho
- Forever has no announced change to aggro, patrol, or social rules versus Classic 1.12. [forever-guide] leveling_fundamentals §16
- Humanoid runners typically flee around ~10–15% health (emote “attempts to run away in fear!”) and can chain-pull whatever they reach. [classic-baseline] leveling_fundamentals §7
- Outdoor elites are roughly +30% health and DPS versus same-level normals; instance, rare, and named elites can be far higher. [classic-baseline] leveling_fundamentals §8
- Grey elites still grant zero XP. [classic-baseline] leveling_fundamentals §8
- Classic leash is timer-driven: outside a ~10–15 yd home pocket an ~11–16 s leash timer (level-scaled) tends to control reset, and the timer resets on player hostile actions. [classic-baseline] leveling_fundamentals §15
- Tab does not move off an already-selected target (including a friendly NPC); clear with Esc first, then Tab. [owner-live] wow-shaman-capabilities
- Esc with nothing selected opens the Game Menu; after any Esc, check for “Game Menu” and close it with one more Esc. [owner-live] wow-shaman-capabilities
- Other players’ in-progress fights are occupied tags; walking through a corpse field does not take those mobs. [video-forever] z1_part1_techniques 02m27s–02m41s, 09m31s; z1_part2_techniques 13m54s–17m20s

---

## Fight economy

- Owner demo (level 4, Thendal Grove, 15 min): 29 fights in 891 s, about 10 s each, ~32% of time in combat, ~15 s between fights (loot and walk). [owner-live] owner-demo-play
- Same-level starter mobs often die without a rest; the owner rested rarely on those pulls. [owner-live] owner-demo-play
- After a hard named fight (Malduko Cloudcrush, health ~30%, red-screen warning) the owner healed, then sat to drink Refreshing Spring Water and eat, full again in about 20 s. [owner-live] owner-demo-play
- A melee mob that runs as fast as the player: backing off only gives it free hits; a Windshaper's Skysight blessing (+10% run speed, when active) gains under 1 yard a second, too little to open range. [owner-live] owner-demo-play (tabletop)
- Each incoming hit pushes a cast back 0.5–1 s. [owner-live] owner-demo-play (tabletop)
- Classic Spirit mana regen: after 5 s without spending mana, mana regenerates from Spirit every 2 s (“five-second rule”). [classic-baseline] leveling_fundamentals §11; Warcraft Tavern Mana management
- One Forever beta stream claims mana after casting regenerates continuously on the client rather than Classic block/tick recovery. [video-forever] videos_mid `UeZ6P86snOo` 1:41–2:15 — see conflicts.md
- Community Classic drink practice is often ~70–80% mana or lower before the next fight; 3–5 s seated can be a mid-dungeon sip; the character must remain seated. [classic-baseline] leveling_fundamentals §11
- Eating is out of combat only (except bandages / special tactics); “Well Fed” from stat food needs 10+ s seated. [classic-baseline] leveling_fundamentals §11
- Forever healer gear grants partial spell damage from healing stats, so hybrid healers may kill quest mobs more comfortably between rests (design intent). [forever-guide] leveling_fundamentals §11; WoWSoD Pro
- Auto-loot: a corpse click with auto-loot loots; without it, Click-to-Move walks on the first corpse click and loots on the second. [owner-live] wow-shaman-capabilities
- Chat line “You receive loot: […]” confirms a successful loot. [owner-live] wow-shaman-capabilities
- Loot is typically a glance (tooltip or one-second window), then the character turns away rather than standing on the corpse. [video-forever] z1_part1_techniques 02m53s; z1_part2_techniques 18m58s
- Level-up visually restores bars (full again within ~2 s of the ding on the Zerocks level-2 clip). [video-forever] z1_part1_techniques 06m43s–06m45s
- Normal open-world respawn is highly variable (~15 min wiki baseline; ~5 min widely reported in Classic launch; farmed-empty areas can drop to ~1 min). [classic-baseline] leveling_fundamentals §9
- Looting does not change respawn rules. [classic-baseline] leveling_fundamentals §9
- Forever realmless sharding may change spawn competition; no public confirmation that base respawn constants differ from Classic. [unverified] leveling_fundamentals §9

---

## Questing

- A hub loop picks up many quests pointing the same direction, completes them geographically, and batches turn-ins. [classic-baseline] leveling_fundamentals §12; BoostRoom
- Forever adds ~1000 new quests and hubs (including Zephras Isle) but does not change loop logic; zones have fixed levels, no scaling. [forever-guide] leveling_fundamentals §12; Wowhead Forever roundup
- Overlapping objectives in one region beat single-quest trips: the owner stood ~40 s in Thendal Village, opened Map & Quest Log (quest levels [3]–[5]), and chose Thendal Grove south where several quests overlapped. [owner-live] owner-demo-play
- Kill whatever counts for any unfinished objective along the path, not only the selected quest. [owner-live] owner-demo-play
- In 15 min the owner had three quests ready for turn-in and a fourth half done by overlapping grove kills. [owner-live] owner-demo-play
- A “!” NPC met on the way (Hanaa Nightwind) was picked up without a return to town (Al'Aketh Thugs). [owner-live] owner-demo-play
- Turn in “?” NPCs when they lie on the current path; do not treat every “!” as mandatory. [video-forever] z1_part2_techniques 18m20s–18m24s (on-path “?”); 28m56s–28m58s (“!” opened and left)
- Interact only with objects that increment an objective: Raw Windstones are glowing cyan crystals, ~3 s right-click cast, loot window, then a “Windstone Cluster: n/15” banner. [owner-live] owner-demo-play
- Identical-looking gather nodes are not all mandatory once the counter is done or the node is off-route. [video-forever] z1_part3_techniques 25m44s vs 25m48s
- Ensnared Ursa near windstone nodes can interrupt gathering. [forever-guide] zephras_walkthrough; AllThings Harvesting Windstones
- Quest items drop in a loot window with an “Objective Complete: …” banner (e.g. Signet of Akir 1/1). [owner-live] owner-demo-play
- Blue quest-area outlines on the minimap are a direction cue. [owner-live] owner-demo-play
- Quest log does not always auto-track a newly accepted quest the way retail addons do. [video-forever] videos_low `2S0MlYfmkxA` 00:00:24
- Hub discipline in Forever streams: grab available hub quests before grinding, to avoid extra trips. [video-forever] videos_low `ThVlyymiLfI` 00:44:37; `4UiOoQ7uKpI` 00:04:10
- Coming of Age (92460) is the Windshaper spawn talk-quest (Ailee Farheart 42.8, 23.4 → Rorian 42.0, 23.4; 40 XP). [forever-guide] zephras_walkthrough
- Harmony in Balance (92461) is 8 Juvenile Vuldren around 43.2, 25.6. [forever-guide] zephras_walkthrough
- Agitators (92465) is 7 Al'Aketh Converts (~46.4, 18.0) plus 6 Roiling Winds destroyed (~47.0, 21.4), not “Rolling Winds”. [forever-guide] zephras_walkthrough
- Foul Matriarch (92470) and Aggressive Encroachment (92473) overlap in west Thendal Grove (scavengers / Urs'anah ~35.8, 23.2; scrawny claws ~37.0, 24.6). [forever-guide] zephras_walkthrough; owner-demo-play
- Al'Aketh Thugs (92544) is given by Hanaa Nightwind at 38.2, 30.2 (6 Brutes, 4 Neophytes, Malduko Cloudcrush ~36.4, 33.2). [forever-guide] zephras_walkthrough
- Reading the Ley Lines is Alliance / High Order only and should be absent on Windshaper. [forever-guide] zephras_walkthrough
- The Anchors of Zephras (94414) stays 0/1 unless the dialogue “Halaan, please lend me your gift.” is chosen. [forever-guide] zephras_walkthrough; AllThings
- Blizzplanet routing treats Wowhead prerequisite chains as the gate if a quest is greyed out, and treats Blizzplanet order as travel efficiency. [forever-guide] zephras_walkthrough
- Zephras Isle is a U-shaped 1–12 starter (Thendal → Shen'dar → Falaath → Valanaar); exit ship is The Earthen Ring (95349) at the Valanaar dock to Mulgore. [forever-guide] zephras_walkthrough; Blizzard Meet the Skyborne
- Kill yellow/green mobs on the travel path; skip detours, grey-XP mobs, and slow elites unless quest-forced. [classic-baseline] leveling_fundamentals §12
- Rested XP is more valuable on kill-heavy segments than on pure travel. [classic-baseline] leveling_fundamentals §12
- Default UI exposes quest map coordinates. [video-forever] videos_low `_8biJBbaZNQ` 00:08:28
- Beta public cap at research time is level 20 (September 2026); a level-30 test phase and 4 November 2026 launch are advertised. [forever-guide] shaman_class; videos_low `_8biJBbaZNQ` 00:11:03; multiclass_framework §2.4

---

## Movement / camera

- Owner camera: low pitch looking toward the horizon (horizon about a third down the view so the ground ahead is visible), zoomed out near the old maximum; closer in a cave. [owner-live] owner-demo-play
- Owner steers while running in smooth arcs (no stop-to-turn); after each kill the next target is picked at once, often far (plate near the horizon, top 12–23% of the view). [owner-live] owner-demo-play
- Owner preference: not too top-down (misses too much); zoom out as far as possible (mouse wheel); prefer hotkeys over mouse. [owner-live] wow-shaman-capabilities
- Camera Following Style and Click-to-Move camera both “Always adjust camera” keep the camera behind the character, so screen centre ≈ facing. [owner-live] wow-shaman-capabilities
- Click-to-Move ON: a background right-click on ground walks there. [owner-live] wow-shaman-capabilities
- Pitch Up / Pitch Down default to Insert / Delete (Mac forward-delete 117); Next/Previous View End/Home; minimap zoom Num Pad +/−; camera zoom has no default key. [owner-live] wow-shaman-capabilities
- Max zoom CVar `cameraDistanceMaxZoomFactor` 2.6 on the owner client. [owner-live] wow-shaman-capabilities
- Running speed on Zephras was measured at about 0.2 zone y-units per second. [owner-live] wow-shaman-capabilities
- Minimap scale ~19 px per zone y-unit (radius 97 px ≈ 5 units); world map ~7.42 px per x unit, 4.99 px per y unit; the “Player: x, y” line lets pins be read by offset. [owner-live] wow-shaman-capabilities
- Owner follows roads and paths between areas rather than cutting blindly through aggro. [owner-live] owner-demo-play
- Zerocks field camera is medium-far, slightly above, with yaw between pulls and a planted camera during casts; indoors they zoom in. [video-forever] z1_part1_techniques; z1_part2_techniques
- Zerocks opened the full island map whenever the route was unclear (eight times in one ten-minute stretch). [video-forever] z1_part2_techniques
- Corpse-covered ground is treated as “already done”: cross it and pull on the fringe or a clear road, not the remaining clump. [video-forever] z1_part1_techniques 07m19s–07m37s; z1_part2_techniques 13m54s–18m30s
- Forever has no flying; PvP ruleset auto-flags in contested zones (~15+); Normal needs `/pvp`. [forever-guide] leveling_fundamentals §16

---

## Death / recovery

- On death a corpse is left at the death site; 6 minutes before spirit auto-releases (release can be delayed by a resurrection timer after repeated deaths). [classic-baseline] leveling_fundamentals §13
- Death costs 10% durability on **equipped** gear only (not inventory). [classic-baseline] leveling_fundamentals §13
- Released ghost spawns at the nearest graveyard, runs at 125% speed, and can walk on water. [classic-baseline] leveling_fundamentals §13
- Corpse resurrect returns 50% health and mana with no extra durability loss beyond the death 10%. [classic-baseline] leveling_fundamentals §13
- Spirit Healer costs +25% durability on equipped **and** inventory items, plus Resurrection Sickness (−75% attributes and damage; dialog cites 60 s); resurrection is at the graveyard where the ghost first spawned. [classic-baseline] leveling_fundamentals §14
- Level 10-and-under exemption from sickness is historical on some rulesets and unverified for Forever. [unverified] leveling_fundamentals §14
- Forever death/spirit is assumed Classic until beta proves otherwise; Hardcore ruleset may override. [unverified] leveling_fundamentals §16
- Corpse-run pathing to dungeon entrances is the observed Forever-stream recovery after a wipe, not Spirit Healer as default. [video-forever] stream_techniques IWhilIN2R1A (dungeon runs)

---

## Count

119 facts.
