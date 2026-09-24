# Class-agnostic leveling fundamentals (Classic / Forever)

Human-facing rules for moving through the world, pulling fights, recovering, and questing efficiently. **Class-specific** rotations, interrupts, and crowd control are out of scope; this document is what every class must respect regardless of spec.

---

## 1. Aggro radius (proximity aggro)

**What it is:** Distance at which a hostile mob stops idling and attacks you without being damaged first.

**Documented Classic behaviour (community testing, aligned with Blizzard’s 1.12 comparisons):**

| Rule | Approximate value |
|------|-------------------|
| Same level as player | ~**20 yards** |
| Level difference modifier | ~**±1 yard per level** (higher player level → smaller radius; lower player level → larger) |
| Floor (minimum) | ~**5 yards** (combat reach); you can often brush very grey mobs without pulling |
| Ceiling (maximum) | ~**45 yards** when the mob is **≥25 levels** above the player |
| Vertical bias | **Height difference weighs heavily**; a mob on a ledge may not aggro at the same horizontal distance that would pull on flat ground |
| Front vs back | Pull distance **may be slightly larger in front** of the mob (movement / hit-box effects); do not rely on “safe from behind” without margin |

**Skull icon vs colour:** On target frames, **red** means mob level ≥ player+5; **orange** ≥ player+3; **yellow** within ±2; **green** below that but still giving XP; **grey** at or below the grey XP threshold (see §10). A **skull** on the level indicator means **world boss** or, in authentic 1.12, a mob **10+ levels** above you (Classic Era had a temporary bug showing skull for +3; fixed per Blizzard). Source: [Warcraft Wiki — Aggro radius](https://warcraft.wiki.gg/wiki/Aggro_radius), [Blizzard forum — Mob aggro proximity](https://us.forums.blizzard.com/en/wow/t/mob-aggro-proximity/177453).

**Special cases (same rules, higher risk):** Mobs with **“Starving”** in the name, some **mechanical** types, and certain dungeon mobs are reported to **aggro farther** than equal-level normals. Source: [Warcraft Wiki — Aggro radius § Speculation](https://warcraft.wiki.gg/wiki/Aggro_radius).

**Mounted:** Classic beta testing reported **no difference from 1.12** in radius formulas; high-level characters could ride past low-level mobs with tiny aggro bubbles. Source: [Mob aggro proximity — Kaivax](https://us.forums.blizzard.com/en/wow/t/mob-aggro-proximity/177453).

---

## 2. Pulling a single mob (solo fundamentals)

**Goal:** Start combat with **one** intended target while avoiding proximity aggro on neighbours.

**Techniques (class-agnostic concepts):**

1. **Ranged pull** — Stand at **maximum safe range** (just inside your attack range, **outside** their proximity bubble). First **damaging** hit establishes tag and usually fixes aggro on you.
2. **Non-damage pull (niche)** — Some mobs aggro on **proximity** at a shorter range than they react to **non-damaging** debuffs (e.g. Faerie Fire-style pulls in groups). Entering one mob’s bubble pulls it; friends may **not** join if that mob takes **no damage** yet. Source: [Warcraft Wiki — Pull § Body pulling](https://warcraft.wiki.gg/wiki/Pull).
3. **Body pull / face pull** — Walking into aggro radius; fine when alone in the open, dangerous near packs.
4. **Safety margin** — In dense camps, pull from **~30+ yards** so you can **abort** (run away, reset leash) if extras join. Source: [Warcraft Wiki — Pull § Safety pull](https://warcraft.wiki.gg/wiki/Pull).

**Forever note:** Design still targets **slow fights** (~**10–15 seconds** per solo mob) and **small packs** (tanks meant for ~**3–4** enemies, not whole rooms). Pull sizing assumptions from Classic still apply. Source: [WoWSoD Pro — Forever vs Classic](https://wowsod.pro/articles/wow-forever-vs-classic-every-key-change), [But Why Tho — Forever deep dive](https://butwhytho.net/2026/09/world-of-warcraft-forever-everything-to-know/).

---

## 3. Line-of-sight (LOS) pulls

**When:** Mob group has **casters or shooters** that would otherwise stand at range and shoot the puller.

**Method (corner pull):**

1. Tag from range or body pull.
2. Run **behind solid geometry** (building wall, dungeon corner, cliff face).
3. Wait for mobs to **path to you**; only then does the party **damage** or heal (healers need LOS to the tank).
4. Optional: tank drops short-range AoE on the corner so mobs gain threat as they round it.

Source: [Warcraft Wiki — Pull § LOS pull](https://warcraft.wiki.gg/wiki/Pull).

**Open-world LOS quirks (critical for an AI reading the screen):**

- **Trees, small rocks, thin props** often **do not** block spell LOS; casters may keep shooting through them. Source: [Blizzard forum — Why can't I LoS mobs in the open world?](https://us.forums.blizzard.com/en/wow/t/why-cant-i-los-mobs-in-the-open-world/571375).
- **Buildings, ruins, thick walls** usually work; behaviour is **inconsistent** outdoors. Dungeons are more reliable. Source: [EU forum — Line of Sight](https://eu.forums.blizzard.com/en/wow/t/line-of-sight/80808).
- After LOS break, **caster mobs tend to run toward the player** until they regain LOS (Blizzlike pathing fix vs older emulator sideways skirting). Source: [AzerothCore PR #7472](https://github.com/azerothcore/azerothcore-wotlk/pull/7472).

**Patrol + LOS failure mode:** LOS-pulling a **moving patrol** too early can leave the mob **still on patrol path** while in combat, walking into other packs. Video example at **1:03**: [YouTube `zO6QsCXK8Zk`](https://www.youtube.com/watch?v=zO6QsCXK8Zk&t=63). Community advice: do not break LOS on patrols too soon. Source: [Reddit — patrol continues walking](https://www.reddit.com/r/classicwow/comments/16j5uzn/why_does_this_patrol_continue_walking_after_being/).

---

## 4. Patrols

**Behaviour:** Many mobs follow **fixed paths**. A skilled pull **times** the pull between patrol cycles so adds are not in **assist** or **proximity** range.

**After combat:** On reset, mobs typically return toward **spawn / last patrol point** and fully reset. Source: [Warcraft Wiki — Leash](https://warcraft.wiki.gg/wiki/Leash).

**While in combat:** Patrols already walking may **continue along their route** and **social-aggro** anything they pass. Treat patrols as **moving aggro bubbles**.

---

## 5. Social aggro, assist, and linked groups

Three distinct mechanisms:

| Mechanism | Behaviour |
|-----------|-----------|
| **Proximity aggro** | Idle mob attacks when you enter its radius (§1). |
| **Assist / co-aggro** | A mob **already fighting you** enters another idle mob’s **assist radius** → second mob joins. Common with **same faction/type** (e.g. pirates with pirates). Fear/root/kite paths cause **chain assists**. Source: [Warcraft Wiki — Aggro radius § Co-aggro](https://warcraft.wiki.gg/wiki/Aggro_radius). |
| **Linked group aggro** | Predetermined set: **damaging one member pulls the whole link** regardless of distance. Often **asymmetric** (boss + room pack linked; minions sometimes pullable separately). Source: same wiki § Group aggro. |
| **Shout / Call for Help** | Active ability: alerts allies in a **radius** (AI parameterised on emulators as `ACTION_T_CALL_FOR_HELP`). Source: [CMaNGOS EventAI.txt](https://github.com/cmangos/mangos-classic/blob/master/doc/EventAI.txt). |

**Assist radius ≠ aggro radius:** Assist range is **separate** and varies by mob; expect **~15–20 yards** as a planning figure for dense camps, not a guaranteed constant. Source: [Warcraft Wiki — Aggro radius](https://warcraft.wiki.gg/wiki/Aggro_radius).

**Leashing vs splitting (2019 Classic fix):** **Linked combat groups** with leash timers now **leash together** like 1.12; you cannot always peel one member off a linked pack by kiting. Non-linked proximity packs may still be splittable with timing/Feign Death-style tricks. Source: [Wowhead — Group combat leashing fix](https://www.wowhead.com/classic/news/group-combat-leashing-fix-and-eyes-of-the-beast-threat-bug-295811).

---

## 6. Casters and shooters

**Threat pattern:** They **stand at range** and cast; melee mobs may stack on the player while casters shoot from behind.

**Counterplay (class-agnostic):** LOS pull (§3), close distance after corner, **interrupt** or **silence** where available, kill caster first in mixed packs.

**Open world:** Do not assume trees will stop bolts; prefer **hard corners** or closing to melee range.

---

## 7. Runners (flee at low health)

**Who:** Mostly **humanoids**; emote **“attempts to run away in fear!”** Source: [Warcraft Wiki — Runner](https://warcraft.wiki.gg/wiki/Runner).

**When:** Typically around **~10–15% health** (Blizzlike reference; some emulator bugs used ~30%). Source: [AzerothCore issue #17300](https://github.com/azerothcore/azerothcore-wotlk/issues/17300), video: [YouTube `r4UtC-h9IOs`](https://www.youtube.com/watch?v=r4UtC-h9IOs).

**Danger:** Runner paths **randomly** at first, then may reach another mob and **pull it into combat**. In crowded areas, treat low-health humanoids as **imminent chain pulls**.

**Mitigation:** Burst before flee threshold, **snare/root/stun**, or let them run only if the area is **clear** (runner as “free fear”). Source: [Warcraft Wiki — Runner](https://warcraft.wiki.gg/wiki/Runner), [Blizzard forum — runners](https://us.forums.blizzard.com/en/wow/t/is-there-a-way-to-know-which-enemies-are-runners/1790619).

**Separate from flee:** **Call for Help** can fire without running; humanoids (e.g. Defias, raptors) may do both. WeakAura/community lists flag dangerous abilities including **Call for help**. Source: [Wago — Classic Mob Abilities](https://wago.io/HJ5QPxCON).

---

## 8. Elites

**Identification:** **Gold dragon** on portrait (Classic target frame); rares **silver**; rare-elites **winged silver** in authentic Classic. Many **vanilla enemy nameplates did not** show dragons on the plate itself—only on target/focus. Source: [Warcraft Wiki — Elite creature](https://warcraft.wiki.gg/wiki/Elite_creature), [Blizzard forum — Enemy nameplates](https://us.forums.blizzard.com/en/wow/t/enemy-nameplates-are-outrageous/194875).

**Power:** Rule of thumb for **outdoor elites**: ~**+30% health and DPS** vs same-level normal mobs; **instance, rare, and named elites** can be far higher. Source: [Vanilla WoW Archive — Elite creature](https://vanilla-wow-archive.fandom.com/wiki/Elite_creature).

**Levelling rule:** At **intended level**, assume **group content** or **large level advantage** (often cited **5–8+ levels** for solo, class-dependent). Elite **quest** mobs sometimes have quest items or tactics to soften them.

**XP:** Elites grant more XP; grey elites still grant **zero** XP.

---

## 9. Respawn timers

**Highly variable** by mob type, zone pressure, and Blizzard dynamic tuning.

| Mob type | Typical timer (guidance) |
|----------|---------------------------|
| Normal open-world | **~15 minutes** baseline in many wiki tables; **~5 minutes** widely reported in **Classic launch/beta** for ordinary mobs |
| Fast-respawn mode | When an area is **farmed empty**, respawns can drop to **~1 minute** or less (dynamic) |
| Named / quest | Often **~5 minutes** for quest names; rare spawns **hours** |
| Dungeon trash | **~2 hours** (instance reset governs bosses) |

Sources: [Warcraft Wiki — Spawn](https://warcraft.wiki.gg/wiki/Spawn), [Vanilla WoW Archive — Spawn](https://vanilla-wow-archive.fandom.com/wiki/Spawn), [Reddit — layering respawn](https://www.reddit.com/r/classicwow/comments/c44dtv/layering_and_mob_competition_what_are_respawn/), [Reddit — spawn rate](https://www.reddit.com/r/classicwowtbc/comments/oc6olu/spawn_rate_of_mobs/).

**Levelling implication:** Camping one quest mob may mean **waiting**; competing players shorten effective wait via dynamic respawn. **Looting does not** change respawn rules.

**Forever:** Realmless sharded world may change **competition** for spawns; no public confirmation that base respawn constants differ from Classic **(unverified)**.

---

## 10. Tagging, kill credit, and grey “plates”

### Tagging (open world, ungrouped)

- **First damaging hit** tags loot/XP rights (DoTs tag on **first tick**, not on cast). **Aggro alone does not tag.** Source: [Blizzard forum — Mobs in non party's](https://us.forums.blizzard.com/en/wow/t/mobs-in-non-partys/196075).
- **Ungrouped helper** who would get **no XP** (mob **grey** to them) → tagger often receives only a **tiny fraction** of XP, regardless of damage split. Source: [Blizzard forum — Mob tagging / boosting](https://us.forums.blizzard.com/en/wow/t/mob-tagging-boosting/167929).
- **Grouped** players share XP by group rules; outsiders damaging your mob reduces XP (Classic behaviour debated vs pure vanilla, but accepted on Classic servers). Source: [Blizzard forum — less XP when someone helps](https://us.forums.blizzard.com/en/wow/t/mobs-giving-less-experiencce-when-someone-outside-of-my-group-help-kill-it/306467).

### Grey level (zero XP) — con colour on target / nameplate level text

Mob level text turns **grey** when the mob is at or below the **grey level**:

| Player level | Grey level (mob at or below = 0 XP) |
|--------------|-------------------------------------|
| 1–5 | None (all mobs give XP) |
| 6–39 | `player − 5 − floor(player/10)` |
| 40–59 | `player − 1 − floor(player/5)` |
| 60 | **51** |

Examples: level **24** player → grey at **17** and below; level **60** → **51** and below.

**Con colours (target frame):** Red ≥ +5; orange +3/+4; yellow ±2; green below that but above grey; grey = no XP. Source: [Warcraft Wiki — Mob experience](https://warcraft.wiki.gg/wiki/Mob_experience) (also archived in [WoWWiki Formulas:Mob XP](https://wowwiki-archive.fandom.com/wiki/Formulas:Mob_XP)).

**Aggro interaction:** Grey mobs have **tiny proximity aggro** (~5 yd floor); high-level players walk through low zones with minimal pulls. Source: [Aggro radius](https://warcraft.wiki.gg/wiki/Aggro_radius).

---

## 11. Resting, food, and drink thresholds

**Spirit regen (mana):** After **5 seconds** without spending mana on a cast, mana regenerates from Spirit every **2 seconds** (“five-second rule”). Source: [Warcraft Tavern — Mana management](https://www.warcrafttavern.com/wow-classic/guides/mana-management-optimization/).

**When to drink (mana users):** Between pulls, drink if mana is low enough that the **next fight** risks going OOM—community practice often **~70–80%** or lower; **3–5 seconds** of drink can be enough mid-dungeon without finishing the bottle. Must **remain seated**. Source: [Blizzard forum — dungeon drink](https://us.forums.blizzard.com/en/wow/t/dungeon-oom-drink-what/104818).

**When to eat (health):** Eat when missing enough health that the next mob would force **defensive cooldowns** or death; sitting eats **out of combat** only (except bandages/tactics). **Stat food** requires **10+ seconds** seated for “Well Fed” buff. Source: [Wowhead — Classic best food](https://www.wowhead.com/classic/guide/wow-classic-best-food).

**Solo levelling efficiency:** Killing mobs on travel **spends** health/mana so regeneration is not wasted at full bars; then eat/drink while relatively safe. Source: [Reddit — kill mobs on the way](https://www.reddit.com/r/classicwow/comments/ance5x/how_critical_is_it_to_kill_every_mob_in_my_way/), video comparison: [YouTube `_6QvouurFMo`](https://www.youtube.com/watch?v=_6QvouurFMo) (cited in thread).

**Forever:** Healer gear grants **partial spell damage** from healing stats, so healers may **kill quest mobs** more comfortably between rests **(design intent)**; rest thresholds may be **lower** for hybrid healing specs. Source: [WoWSoD Pro — Forever vs Classic](https://wowsod.pro/articles/wow-forever-vs-classic-every-key-change).

---

## 12. Quest efficiency (human patterns)

**Hub loops:** Pick up **8–12** quests pointing the **same direction**; complete in a **geographic loop**; return for **batch turn-ins**—avoid one-quest trips across the zone. Source: [BoostRoom — leveling efficiency](https://boostroom.com/blog/leveling-efficiency-rules-travel-cuts-quest-stacking-and-rested-xp).

**Kill while travelling:** Kill **yellow/green** mobs **on the path**; skip detours, grey mobs, and slow elites. Empirical Classic test: quest+travel kills ≈ **+20% XP** for ~**2 minutes** extra time in one cited run. Sources: [Reddit — kill on the way](https://www.reddit.com/r/classicwow/comments/ance5x/how_critical_is_it_to_kill_every_mob_in_my_way/), [PixelNitro — 1–60 route 2026](https://pixelnitro.com/wow-classic-era-1-60-speedrun-route-solo-leveling-guide-for-2026/).

**Grouping quests:** Share kill/collect objectives in the same pocket; **breadcrumb** quests only if they open a **dense cluster** immediately.

**Infrastructure:** Grab **flight paths** on natural routes; set **Hearthstone** where the next **long return** ends; repair and dump bags at hub before loops.

**Rested XP:** Prefer spending rested on **kill-heavy** segments (dense areas, dungeons), not on pure travel. Source: [BoostRoom — rested XP](https://boostroom.com/blog/leveling-efficiency-rules-travel-cuts-quest-stacking-and-rested-xp).

**Forever:** **~1000 new quests** and hubs such as **Zephras Isle** add routes but do not change the **loop logic**. **No zone scaling**—fixed zone levels like Classic. Source: [Wowhead — Everything about Forever](https://www.wowhead.com/forever/news/everything-we-know-about-wow-forever-382827), [WoWSoD Pro](https://wowsod.pro/articles/wow-forever-vs-classic-every-key-change).

---

## 13. Death, corpse run, and penalties

**On death:** Corpse left at death site; **6 minutes** before spirit auto-releases (release can be delayed by “resurrection timer” after repeated deaths). Source: [Warcraft Wiki — Death (gameplay)](https://warcraft.wiki.gg/wiki/Death_(gameplay)) (summary also in [Vanilla WoW Archive — Death](https://vanilla-wow-archive.fandom.com/wiki/Death)).

**Durability on death:** **10%** loss on **equipped** gear only (not inventory).

**Release spirit:** Ghost spawns at **nearest graveyard** in zone; **125%** run speed; can walk on water; night elves faster with Wisp Spirit.

**Corpse resurrect (preferred):** Run to corpse → **Resurrect Now** → **50%** health and mana; **no extra** durability penalty beyond the initial 10%.

**Corpse unreachable:** Instances may teleport corpse to entrance; extreme terrain may relocate corpse. Source: [Vanilla WoW Archive — Death](https://vanilla-wow-archive.fandom.com/wiki/Death).

---

## 14. Spirit Healer

**Use when:** Corpse run is unsafe, too long, or impossible.

**Cost:**

- **+25% durability** on **all equipped and inventory** items (stacks with death’s 10% on equipped).
- **[Resurrection Sickness](https://warcraft.wiki.gg/wiki/Resurrection_Sickness):** **−75%** to attributes and damage dealt; Spirit Healer dialog cites **60 seconds** in the confirmation window. Level **10 and under** historically exempt from sickness on some rulesets—verify on Forever **(unverified)**.
- Spirit Healer resurrection returns you to the **graveyard where your ghost first spawned**, not an arbitrary GY you ran to. Source: [Warcraft Wiki — Spirit Healer](https://warcraft.wiki.gg/wiki/Spirit_Healer), [Wowhead — Spirit Healer NPC comments](https://www.wowhead.com/npc=6491/spirit-healer).

**Hardcore / Forever rulesets:** Permadeath or restricted resurrection may override this **(ruleset-specific, unverified for beta)**. Source: [WoWSoD Pro — Hardcore ruleset](https://wowsod.pro/articles/wow-forever-vs-classic-every-key-change).

---

## 15. Leash and reset (kiting literacy)

Classic leashing is **timer-driven**, not “infinite chase until zone edge”:

- Outside a small **~10–15 yd** “home” pocket, a **~11–16 s** leash timer (level-scaled) tends to control reset.
- Timer **resets** on player **hostile actions** and on certain **melee hits** after kiting.

Source: [Warcraft Tavern — Leash behaviour](https://www.warcrafttavern.com/wow-classic/guides/leash-behavior/), [Warcraft Wiki — Leash](https://warcraft.wiki.gg/wiki/Leash), reference video: [YouTube `xnrUkbEbiJk`](https://www.youtube.com/watch?v=xnrUkbEbiJk) (cited in emulator issue [#25670](https://github.com/azerothcore/azerothcore-wotlk/issues/25670)).

---

## 16. WoW: Forever differences (vs Classic Era)

| Area | Forever (public / beta reporting) | Classic baseline |
|------|-------------------------------------|------------------|
| UI | Modern UI, built-in **damage meter**, CD manager, swing timer | Addon-dependent |
| World structure | **Realmless** rulesets (Normal / PvP / RP / Hardcore later); **fixed zone levels**, **no flying** | Per-realm Classic |
| Combat pace | Stated **10–15 s** per solo mob; **CC** still required; tanks ~**3–4** mobs | Same philosophy |
| Pull sizing | Some AoE (e.g. Consecration) **caps effective targets** (e.g. first **4**) | Full-room pulls still bad; tuning differs per spell **(Forever-specific)** |
| Aggro / patrol / social | **No announced changes**; Blizzard Classic team validated 1.12 aggro | §1–§5 |
| Questing | **+1000 quests**, new zones (**Zephras Isle**, etc.) | Original graph |
| Death / spirit | Assumed **Classic death model** until beta proves otherwise **(unverified)** | §13–§14 |
| PvP while leveling | **PvP ruleset** auto-flags in contested zones (~**15+**); Normal needs `/pvp` | Same broad idea |

Sources: [Wowhead Forever roundup](https://www.wowhead.com/forever/news/everything-we-know-about-wow-forever-382827), [WoWSoD Pro](https://wowsod.pro/articles/wow-forever-vs-classic-every-key-change), [Icy Veins — Forever PvP](https://www.icy-veins.com/wow-forever/pvp-overview), [Windows Central — Forever team interview](https://www.windowscentral.com/gaming/blizzard/i-spoke-to-the-world-of-warcraft-forever-team-about-balance-competing-with-retail-adding-classic-style-player-housing-and-more).

---

## Most useful for an AI agent

1. **Estimate pull distance** as `20 + (mobLevel − playerLevel)` yards, clamped **[5, 45]**, with extra caution uphill/downhill and “starving” mobs.
2. **Read target frame level colour** (red/orange/yellow/green/grey) before committing; **grey = skip** unless quest-forced.
3. **Prefer one mob** via max-range first hit; re-evaluate if others enter **assist** range (~15–20 yd planning margin).
4. **Detect linked pulls** (whole pack enters combat at once); abort early if pack size exceeds safe threshold (~2 solo, ~3–4 with tank/healer).
5. **For casters in pack**, plan **corner LOS** using **walls**, not trees; wait until movers **stop at corner** before DPS/heal.
6. **Track patrol vectors**; avoid LOS pulls on **moving** patrols until combat anchor is stable.
7. **Humanoid below ~15% health**: prioritise **kill or CC** before social chain from flee.
8. **Elite / gold-dragon portrait**: downgrade to “group or skip” unless level advantage is large.
9. **Between fights**: if not full HP/mana and safe, **sit**; drink sub-max if timeboxed (~3–5 s sip).
10. **On death**: default policy **corpse run**; Spirit Healer only if corpse path risk > durability + sickness cost; parse graveyard vs corpse minimap arrows.

---

## Sources

- [Warcraft Wiki — Aggro radius](https://warcraft.wiki.gg/wiki/Aggro_radius)
- [Warcraft Wiki — Pull](https://warcraft.wiki.gg/wiki/Pull)
- [Warcraft Wiki — Leash](https://warcraft.wiki.gg/wiki/Leash)
- [Warcraft Wiki — Runner](https://warcraft.wiki.gg/wiki/Runner)
- [Warcraft Wiki — Elite creature](https://warcraft.wiki.gg/wiki/Elite_creature)
- [Warcraft Wiki — Spawn](https://warcraft.wiki.gg/wiki/Spawn)
- [Warcraft Wiki — Mob experience](https://warcraft.wiki.gg/wiki/Mob_experience)
- [Warcraft Wiki — Death (gameplay)](https://warcraft.wiki.gg/wiki/Death_(gameplay))
- [Warcraft Wiki — Spirit Healer](https://warcraft.wiki.gg/wiki/Spirit_Healer)
- [Blizzard US — Mob aggro proximity (Kaivax, 1.12 validation)](https://us.forums.blizzard.com/en/wow/t/mob-aggro-proximity/177453)
- [Blizzard US — LoS in open world (trees)](https://us.forums.blizzard.com/en/wow/t/why-cant-i-los-mobs-in-the-open-world/571375)
- [Blizzard EU — Line of sight](https://eu.forums.blizzard.com/en/wow/t/line-of-sight/80808)
- [Blizzard US — Mob tagging / boosting](https://us.forums.blizzard.com/en/wow/t/mob-tagging-boosting/167929)
- [Blizzard US — Mobs in non party's (tag rules)](https://us.forums.blizzard.com/en/wow/t/mobs-in-non-partys/196075)
- [Blizzard US — Runners thread](https://us.forums.blizzard.com/en/wow/t/is-there-a-way-to-know-which-enemies-are-runners/1790619)
- [Wowhead — Group combat leashing fix](https://www.wowhead.com/classic/news/group-combat-leashing-fix-and-eyes-of-the-beast-threat-bug-295811)
- [Wowhead — Forever everything we know](https://www.wowhead.com/forever/news/everything-we-know-about-wow-forever-382827)
- [Wowhead — Classic best food guide](https://www.wowhead.com/classic/guide/wow-classic-best-food)
- [WoWSoD Pro — Forever vs Classic](https://wowsod.pro/articles/wow-forever-vs-classic-every-key-change)
- [Warcraft Tavern — Leash behaviour](https://www.warcrafttavern.com/wow-classic/guides/leash-behavior/)
- [Warcraft Tavern — Mana management](https://www.warcrafttavern.com/wow-classic/guides/mana-management-optimization/)
- [CMaNGOS — EventAI (Flee / Call for Help)](https://github.com/cmangos/mangos-classic/blob/master/doc/EventAI.txt)
- [Vanilla WoW Archive — Elite creature](https://vanilla-wow-archive.fandom.com/wiki/Elite_creature)
- [Vanilla WoW Archive — Spawn](https://vanilla-wow-archive.fandom.com/wiki/Spawn)
- [Wago — Classic Mob Abilities](https://wago.io/HJ5QPxCON)
- Video: [`e9nA1bp9fnM`](https://www.youtube.com/watch?v=e9nA1bp9fnM) — Maraudon aggro leeway (forum reference)
- Video: [`r4UtC-h9IOs`](https://www.youtube.com/watch?v=r4UtC-h9IOs) — flee timing/speed
- Video: [`zO6QsCXK8Zk` @ 1:03](https://www.youtube.com/watch?v=zO6QsCXK8Zk&t=63) — patrol + LOS
- Video: [`xnrUkbEbiJk`](https://www.youtube.com/watch?v=xnrUkbEbiJk) — leash timer behaviour
- Video: [`_6QvouurFMo`](https://www.youtube.com/watch?v=_6QvouurFMo) — quest vs quest+kill XP (community test)
