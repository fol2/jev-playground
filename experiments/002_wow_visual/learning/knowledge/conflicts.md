# Source conflicts

Every disagreement found while synthesising the scratchpad research. **Owner-live is highest trust.** A live check is the cheapest observation that would settle the row. Unsettled rows stay marked; do not collapse them into one “truth” in general.md or shaman.md.

Trust ladder used here: owner-live (demo + capabilities memory) > Forever client datamine (wowforevertalents / foreverchanges, build 1.60.1.69893) > Forever written guides > Forever video (what the pixels show) > Classic baseline / Classic video.

---

## Combat pattern

### Earthbind kite vs bolt-then-melee
- **Guides** (shaman_class, Warcraft Tavern Classic, wowforeverbuilds, multiclass_framework): from 6, drop Earthbind and kite, entering melee only for swing windows; Lightning Bolt is a pull, not a mid-fight cast.
- **Owner-live** (owner-demo-play, wow-shaman-capabilities, tabletop): buff → 1–2 bolts while it closes → melee on contact; a melee mob matches your run speed so backing off gives it free hits; a bolt in melee is pushback plus wasted mana.
- **Forever videos**: Zerocks fire-totem VOD and z1 parts 1–2 match the owner (bolt, then melee, no kite). Tiqqle (stream_techniques) says kiting is possible but not ideal at low level; focus threat and AoE.
- **Higher trust:** owner-live for *this* character at 1–4 on Zephras. Guide kite is a later-level option once Earthbind exists and pulls are harder.
- **Live check:** At 6, pull a same-level melee on flat ground, drop Earthbind, and compare time-to-kill and incoming damage versus standing in melee. If the mob’s run speed still matches yours inside the slow, owner-live still wins for same-level trash.

### Lightning Bolt in melee
- **Owner-live tabletop:** each hit pushes a cast 0.5–1 s; a bolt in melee wastes ~15% mana.
- **Guides:** do not hard-cast Lightning Bolt during the Enhancement melee phase (wowforeverbuilds, Leprestore, shaman_class).
- **z1_part3_techniques** (same Zerocks VOD, minutes 20–30): several solo pulls are already in melee, then a yellow cast bar (bolt visual) while standing on the mob.
- **Higher trust:** owner-live for cost/pushback; z1_part3 shows a human sometimes still pressing bolt in contact.
- **Live check:** Start a bolt at <5 yd on a melee mob and record whether the cast completes, how much it is pushed, and mana spent versus an auto-only finish.

### Heal threshold
- **Owner-live:** Healing Wave after a named fight that dropped the owner to ~30% (red-screen warning), then sit.
- **zerocks_frames:** Healing Wave when player health drops below ~50%, mid-combat.
- **multiclass_framework example policy:** heal if <40% after the fight, or <50% in the level-4 summary sentence (the YAML and the prose do not match).
- **Higher trust:** owner-live for when *this* player spends the heal; the 40/50% guide numbers are untested on Forever Zephras.
- **Live check:** Log HP% at each Healing Wave press on live PNGs for 20 fights.

---

## Mana and rest

### Five-second rule vs continuous regen
- **Classic baseline** (leveling_fundamentals §11, Warcraft Tavern, multiclass_framework regen_rules, shaman_class Lightning Shield note): after 5 s without a mana spend, Spirit ticks every 2 s.
- **Forever video** (videos_mid `UeZ6P86snOo` 1:41–2:15): mana after casting tends to regenerate **continuously** on the Forever client; streamer reports not eating once while reaching 10 (`UeZ6P86snOo` 2:42).
- **Owner-live:** pulled at 10–30% mana on many trash fights (melee carries damage); after Malduko, sat to drink and eat, full in ~20 s. Tabletop later added a heal-then-drink recovery with mana/time facts (not numeric in the memory file).
- **z1_part1 / z1_part2:** no sit, eat, or drink in 20 minutes of levels 1–3; mana recovered while walking; health stayed full.
- **z1_part3:** mana ran empty in a camp pile, then recovered to ~three-quarters in ~23 s of running (20m51s → 21m14s), not seated.
- **Tiqqle** (stream_techniques IWhilIN2R1A 0:45:36): “don’t sit between mobs — mana sustain is so good.”
- **jFvfFfI9J5w** (videos_mid 50:46): still sits when out of mana and low health after heavy questing.
- **Higher trust:** owner-live for *when this player drinks* (after a hard named, not after every trash pull). The regen **model** (5 s gate vs continuous) is unset.
- **Live check:** Empty mana, stand still out of combat with no food/drink, screenshot mana at 0, 2, 5, 6, 10, 20 s. If the bar moves before 5 s, Forever is not Classic 5-second. Repeat while running. Repeat after one Lightning Bolt.

### Rest thresholds (70–80% vs 10–30% vs never)
- **Classic community** (leveling_fundamentals §11): drink around 70–80% or when the next fight risks OOM.
- **zerocks_frames:** sit 20–40 s every 2–3 kills; next pull at ~70–90% health; never pull <40% health.
- **Owner-live:** same-level trash at 10–30% mana with no sit; drink only after a hard fight.
- **Tiqqle / z1 parts 1–2:** almost never sit in the first levels.
- **Higher trust:** owner-live for this character and this zone band.
- **Live check:** Record mana% and health% at pull start for 30 consecutive Thendal Grove kills on the owner bar, and whether a sit occurred.

### Enhancement melee “returns mana”
- **videos_low / videos_mid `WIwyNfxRiFU` 12:44–12:53:** auto-attacks are described as part of getting mana back for Enhancement (mechanic name unverified).
- **Classic / Forever written:** no Enhancement “mana on swing” talent in the 10–20 `0/11/0` list; regen is Spirit + drink + (later) Healing Stream / Mana Spring.
- **Higher trust:** written talent list. The stream wording may be “I am not spending mana while I melee, so the bar comes back.”
- **Live check:** Full melee fight with no casts after the opener; overlay mana at pull and at kill with the 5 s / continuous test above.

---

## Spell numbers

### Lightning Bolt cast time
- **Forever client** (shaman_class / wowforevertalents): R1 **1.5 s**, 15 mana, 30 yd.
- **Owner-live** (wow-shaman-capabilities): ~**2 s** cast bar OCR; landed ~**3.2 s** after press at range (includes travel / GCD / latency).
- **Tiqqle** (stream_techniques IWhilIN2R1A 4:13:52): Lightning Bolt **2.5** base versus Chain Lightning 3.0 — likely a later rank or Classic-era memory; Chain Lightning is not trained before 32.
- **Higher trust:** Forever client for tooltip rank-1; owner-live for what the bar and travel look like in this beta.
- **Live check:** Open spellbook tooltip and cast-bar OCR on rank 1 at 30 yd and at 10 yd; note rank currently trained.

### Healing Wave mana
- **Forever client** (shaman_class): R1 **25** mana, 1.5 s, 40 yd.
- **multiclass_framework** Classic example: R1 **35** mana (Wowhead Classic spell 331).
- **Higher trust:** Forever client for this build.
- **Live check:** Tooltip OCR on the owner’s current Healing Wave rank.

### Fire Nova cooldown
- **Forever client / shaman_class / foreverchanges / Icy Veins:** **10 s**, instant, around the active fire totem.
- **Tiqqle** (stream_techniques IWhilIN2R1A 0:44:02): **6 s**, “comparable to Paladin Consecration in TBC.”
- **Higher trust:** Forever client tooltip.
- **Live check:** Train Fire Nova at 12 and read the tooltip / cooldown swipe.

### Totemic Projection cooldown and cost
- **shaman_class** (wowforevertalents / Wowhead 66842 area): **30 yd**, **1 min** CD, **25% base mana**.
- **multiclass_framework** (WoWSoD Pro spellbook notes): **30 yd**, **10 s** CD, cost listed as 0 in the YAML example.
- **videos_mid `lR26ojxv-Sg`:** chat mixed Recall (refund / threat) with Projection (relocate).
- **Higher trust:** neither is owner-live; treat as **unverified** until the spell exists on this character (level 22, past the 20 cap).
- **Live check:** When Projection is in the book, read tooltip CD and mana; do not use stream chat names.

### Totemic Recall vs Projection (what the button does)
- **shaman_class / foreverchanges:** Recall **destroys** totems and refunds 25% mana; Projection **moves** them.
- **videos_mid `lR26ojxv-Sg` 1:31:28:** stream wording said Recall relocates (that is Projection’s job).
- **Higher trust:** Forever client / shaman_class.
- **Live check:** Drop a totem, press each button once, watch whether the totem vanishes or jumps.

### Earth Shock cooldown and cost
- **shaman_class “Most useful”:** shocks **6 s**; Fire Nova 10 s.
- **multiclass_framework YAML:** Earth Shock R1 Classic Wowhead 8042, cost 25, cooldown **0** (GCD only) — Classic shocks share a 6 s cooldown; the YAML omitted it.
- **Higher trust:** 6 s family cooldown from the Forever/Classic shock design; confirm on tooltip.
- **Live check:** Press Earth Shock and read the swipe; try Flame Shock immediately.

### Lightning Bolt / Healing Wave ranks at low level
- **videos_low `ThVlyymiLfI` 01:52:33 and `WIwyNfxRiFU`:** trainer visit at 8 for Lightning Bolt + Lightning Shield — implies Bolt was not used, or they meant a **rank**.
- **Forever client / owner-live:** Lightning Bolt is on the bar from level 1 (owner slot 2).
- **Higher trust:** owner-live + Forever trainer table (R1 at 1, R2 at 8).
- **Live check:** Spellbook ranks at 1, 4, and 8.

---

## Action bar and UI (same character, same day)

### Slot 3: Healing Wave vs Earth Shock
- **wow-shaman-capabilities** (morning, level 2, M3): slot 3 = Healing Wave (cast-bar OCR, healed to 100%).
- **owner-demo-play** (evening, level 4): slot 3 = new yellow icon, **likely Earth Shock**; slot 8 = green, **likely Healing Wave**.
- **Higher trust:** both are owner-live at different hours; the bar **changed** after Earth Shock was trained and the owner remapped.
- **Live check:** Cast-bar OCR on slots 3 and 8 at session start. Do not keep morning pixel constants after a UI or bind change (owner already warned: nameplates 5×, swing timer, second bar — all pixel boxes stale).

### Range-digit reading
- **wow-shaman-capabilities:** slot-2 hotkey digit turns red out of Lightning Bolt range (box x 708–734, y 1270–1292).
- **owner-demo-play:** slot-2 red digit on **upscaled demo JPEGs** was unreliable; re-calibrate on live PNGs. Bands intended: slot 1 ~5 yd, slot 3 ~20 yd, slot 2 ~30 yd; `2 white + 3 red` = 20–30 yd bolt-pull sweet spot.
- **Higher trust:** the mechanic (digits go red OOR) is owner-live; the JPEG reading is not.
- **Live check:** Select a mob, walk in from 40 yd, screenshot when slot 2 and slot 3 flip white, on PNG.

---

## Grey, red, yellow — two colour systems

### Grey plate vs grey level
- **Owner-live:** grey **plate bar** = tapped by someone else, no credit.
- **leveling_fundamentals §10:** grey **level text** = mob at or below the grey-XP formula, zero XP.
- These can both be true on one frame (a grey-level mob can also be tapped).
- **Live check:** Target an untapped grey-level critter and an in-level mob another player has already hit; compare plate fill colour versus level-text colour.

### Red / yellow plate vs red / yellow con
- **Owner-live:** red plate = aggressive; yellow plate = neutral.
- **leveling_fundamentals:** red/orange/yellow/green/grey on the **level number** are difficulty, not hostility.
- **Live check:** A yellow-plate beast one level below the player should still show green or yellow **level text**; a red-plate convert of equal level should show yellow level text.

---

## Weapons and dual wield

### Dual wield at 4
- **Tiqqle** (stream_techniques IWhilIN2R1A 0:35:49, 0:47:07): Dual Wield quest “Requires level four.”
- **shaman_class / zockify / BlizzCon notes:** no dual wield in the BlizzCon demo; Enhancement tree changes do not list a low-level DW quest.
- **videos_mid `lR26ojxv-Sg` 23:03:** stream chat told the player to confirm DW at the trainer (unverified).
- **Higher trust:** absence on the owner’s level-4 bar and the written Forever class page. Tiqqle auto-captions are noisy.
- **Live check:** At the Windshaper trainer and in the spellbook, search Dual Wield at 4, 10, and 20.

### Two-hand baseline
- **Zockify:** 2H axes/maces baseline (unverified).
- **Wowhead Forever class page:** still mentions the old talent (may be stale).
- **Forever tree:** Two-Handed Axes and Maces talent **removed**.
- **Higher trust:** none until a weapon master is spoken to (shaman_class already says this).
- **Live check:** Speak to Horde 2H axe / 2H mace masters; see whether the skill can be bought without a talent.

---

## Racial names and numbers

### Skysight vs Windborne vs Wind Blast
- **Blizzard / Icy Veins / shaman_class / owner bar slot 9:** **Skysight** = +10% move/mount speed; **Walk on Air** = glide; **Wind Blessed** = +1% haste; **Elemental Insight** = +5% vs elementals. Skysight 30 s, or 15 min near a convergence; not in combat.
- **videos_low `4UiOoQ7uKpI` 00:02:25–00:03:25:** names it **Windborne** (same 30 s / 15 min numbers) and **Wind Blast** as +1% **spell and melee range** (auto-caption).
- **Higher trust:** Blizzard article + Icy Veins + owner keybind name “Skysight.”
- **Live check:** Open the racial tooltips on the owner character; quote the title strings.

### Trainer name
- **zephras_walkthrough / Wowhead 92484:** Windshaper **Boro** 42.8, 23.6.
- **videos_low `lFeEAUvK9fY` 04:23:31:** Windshaper **Borro**.
- **Higher trust:** Wowhead / zephras_walkthrough spelling.
- **Live check:** Target-frame name OCR.

### Hub name
- **owner-live / zephras_walkthrough / Blizzard:** **Thendal** Village / Grove.
- **videos_low `4UiOoQ7uKpI`:** **Tendo** Village (same region).
- **Higher trust:** owner-live and Wowhead.
- **Live check:** Minimap / zone text.

---

## Totem quest availability at 4

- **shaman_class:** Skyborne Earth walkthrough with coordinates “not found”; agent should open the trainer pin (unverified).
- **zephras_walkthrough:** full 3-part Call of Earth (92466–92468) with Boro and Rise of Spirits 49.6, 24.0.
- **owner-demo-play:** Call of Earth (Signet of Akir) was on the owner’s planned grove loop at 4.
- **Higher trust:** owner-live + Wowhead IDs in zephras_walkthrough. shaman_class is stale on this point.
- **Live check:** Quest log for 92466/92467/92468 and whether Stoneskin is usable before the quartz turn-in.

---

## Camera

- **Owner-live:** horizon about a third down, zoomed out near maximum, low pitch so the ground ahead is visible; closer in caves.
- **zerocks_frames:** elevated pitch, lots of sky, medium ~35–40 yd zoom.
- **z1_part3:** steeply down in forest (horizon gone), shallower in the open.
- Not a mechanic conflict: three humans, three habits. For Jev, owner-live is the camera this agent is meant to copy.
- **Live check:** none required for “truth”; only if matching the owner view.

---

## Fight length

- **Forever design copy** (leveling_fundamentals, WoWSoD Pro): ~10–15 s per solo mob.
- **Owner-live demo:** ~10 s average (29 fights / 891 s combat-share).
- **z1_part1** (level 1 beasts): 5–8 s.
- **zerocks_frames** (later, fire-totem quest): 15–25 s.
- Compatible if read as “scales with level and named/quest mobs,” not as one constant.
- **Live check:** Already have an owner timeline; re-time a level-10 quest mob if the band changes.

---

## Chain Lightning on low-level footage

- **Forever client:** Chain Lightning trainer **32**.
- **zerocks_frames:** claims Chain Lightning on the bar / in multi-mob situations on a low-level Zephras fire-totem video.
- **Higher trust:** Forever client. The contact-sheet likely misread Lightning Bolt or a later clip.
- **Live check:** Spellbook at 12 and 20 for Chain Lightning.

---

## Ghost Wolf indoors

- **Base tooltip** (wowforevertalents datamine): outdoors.
- **Improved Ghost Wolf** (Enhancement 15–16): Faster cast **and** indoor use (wowforeverbuilds, shaman_class).
- Not a true contradiction if both are right: the talent changes the rule.
- **Live check:** At 20, cast Ghost Wolf inside a building with and without the talent.

---

## Nameplate range

- **Owner-live:** no plate ≈ beyond ~40 yd (owner figure).
- **zerocks_frames:** pulls at ~25–35 yd with plates visible “not at screen edge.”
- Compatible (25–35 is inside 40). Do not treat 40 as pull range.
- **Live check:** Walk toward an aggressive mob from far; note yards (hotkey colours) when the plate appears versus when slot 2 turns white.

---

## Classic totem rules transferred to Forever

- **Classic video `mVp2TQ_m920`:** cannot pick up totems; 20 yd aura; overwrite a bad totem by dropping another.
- **Forever client:** Totemic Recall, Projection, 30 yd / 5 min many totems, Call of the Elements from 20.
- **Higher trust:** Forever client for this build. Classic totem-permanence is false once Recall exists (level 20).
- **Live check:** At 4–19, drop Stoneskin and walk 25 yd away: does the buff drop at 20 or 30? At 20, press Recall.

---

## Stream caption quality (do not promote these without a tooltip)

- Healing potions “learnt from First Aid trainer” (stream_techniques IWhilIN2R1A 0:26:06) — Classic First Aid is bandages; treat as caption noise until seen in-game.
- “Al'Akirith Convert” in z1_part3 OCR versus Wowhead **Al'Aketh**.
- Tiqqle Relic-slot defensive quest reward at 10 (stream_techniques 0:26:37) versus the four **element totem items** in shaman_class — possibly two different “relic” meanings.
- **Live check:** Only if the agent would press a button on that fact.

---

## What is settled enough to act on

- Owner bar and fight rhythm at 1–4: buff, bolt pull, melee, skip grey taps, drink after hard fights, no mana-percent gate.
- Forever trainer table for *which* spells appear at 1/4/6/8/10/12/16/18/20.
- Two colour systems (hostility plate vs level con vs tapped grey) must stay separate.
- Unsettled and dangerous to hard-code: regen model, Projection numbers, Dual Wield, Fire Nova 6 vs 10, morning vs evening slot 3 without a live OCR.
