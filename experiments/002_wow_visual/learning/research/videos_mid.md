# Shaman levelling (levels 10–30): video research — mid-game band

Research scope: English YouTube guides and live-stream VODs for **World of Warcraft: Forever** (beta, Classic-era rules + modern UI) and **Classic-era** Shaman play at roughly levels **10–30**, with commentary on rotations, totems, pulls, mana, and early dungeon tank/heal behaviour.

**Method:** English auto-captions fetched with `yt-dlp --skip-download --write-auto-subs --sub-langs en` into `subs/` (no full video downloads). **Skipped** (already covered elsewhere): `IWhilIN2R1A`, `gETjq4-k4qU`, `RFDpkq6svWE`.

**Subtitle fetch note:** Nine videos yielded usable `.en.vtt` files. Several Forever-specific uploads (`YsQlxIftAXU`, `NsSilW92IWs`, `PEl2g51lKIY`, `i08Y9vqCMsQ`) returned HTTP 429 from YouTube during this run; tips from those IDs are **not** included below.

---

## Class-agnostic (any levelling character)

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| Quest routing (Classic Horde) | TGN’s 10–20 route: finish a zone band, hit **level 15**, move on; example milestone **level 17 in Westfall** on Alliance side of that guide’s run. | `hWk2GpV1rfA` 7:56, 12:30, 13:44 |
| Ghost Wolf constraints (Classic) | **Ghost Wolf** defaults to a **3-second cast** and **outdoor-only** in vanilla-style rules—cannot panic-cast instantly indoors (relevant pre-Forever indoor buff). | `mVp2TQ_m920` 3:25–3:38 |
| UI for melee timing | Enable **swing timer** / cooldown manager in the modern default UI when learning melee weave timing. | `WIwyNfxRiFU` 11:28; `lR26ojxv-Sg` 9:36 (totem bar placement) |
| Group communication | If you off-heal dungeons as a DPS spec, tell the group and still get **weapon swings** for Enhancement weapon skill. | `mVp2TQ_m920` 3:19–3:24 |

---

## Shaman-specific — WoW Forever (beta; mark `(unverified)` where tuning may change)

### Levelling feel & resources

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| Mana regeneration model | In Forever, mana after casting tends to **regenerate continuously** on the client rather than Classic’s **block/tick** recovery after you stop casting—less need to sit and drink while levelling. | `UeZ6P86snOo` 1:41–2:15 |
| Food / drink | Streamer reports **not eating once** while reaching **level 10** on Forever Shaman, attributing it to regen changes. `(unverified)` for later levels and mana-heavy AoE. | `UeZ6P86snOo` 2:42–2:44 |
| Enhancement + melee mana | On Skyborne / early Forever, **auto-attacks** are described as part of getting **mana back** for Enhancement. `(unverified)` exact mechanic name in build. | `WIwyNfxRiFU` 12:44–12:53 |
| Relative mana pool | Levelling stream notes **more mana than before** but still burning through it quickly during regen downtime. `(unverified)` | `lR26ojxv-Sg` 29:32–29:34 |
| Rockbiter duration | **Rockbiter** weapon buff cited as lasting **1 hour** in Forever (vs shorter Classic durations)—less re-application while questing. `(unverified)` | `lR26ojxv-Sg` 47:54–47:57 |

### Rotations & open world (10–20 band)

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| Caster weave | Open-world pull pattern described: **Lightning Bolt** (or opener cast) then **melee**, needing **Earth Shock** when shocks are off cooldown. | `lR26ojxv-Sg` 40:44–46:23 |
| Self-rotation label | Player calls **Lightning Bolt → Earth Shock** loop their **“new rotation”** in the teens. | `lR26ojxv-Sg` 54:49–54:54 |
| Mana burn before travel | Before a long run, **spend remaining mana** on damage rather than logging out with a full bar. | `lR26ojxv-Sg` 49:03–49:06 |
| Fire Nova / Elemental `(unverified)` | Q&A: **Fire Nova** expected as main **PvE AoE**, but concern Elemental still lacks a big “impact” button without **Lava Burst** tuning. | `UeZ6P86snOo` 7:00–7:13 |
| Gear → tanking | **Strength + large Intellect** on gear discussed as feeding **Attack Power** for **tanking** via Forever stat conversions. `(unverified)` | `UeZ6P86snOo` 11:43–11:50 |

### Totems & Forever systems

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| UI | Use dedicated **totem bar** slots for repeated drop patterns. | `lR26ojxv-Sg` 9:36; 19:08–19:10 |
| Totemic Recall | **Totemic Recall** relocates active totems; chat notes it can **transfer threat to the totem** (tank nuance). `(unverified)` | `lR26ojxv-Sg` 1:31:28–1:31:30; 1:32:49–1:32:51 |
| Multi-totem drop | **Totem bar** can place up to **four** configured totems; **3-second** deploy mentioned in stream `(unverified)` cast time. | `lR26ojxv-Sg` 1:31:53–1:31:57 |
| Level 30 utility | **15-minute Hearthstone** at **level 30** called out on stream. `(unverified)` vs Classic 1-hour baseline. | `lR26ojxv-Sg` 1:33:39–1:33:41 |
| Dual wield | Stream chat/tests: confirm **dual wield** availability at class trainer (Forever may differ from Classic quest gate). `(unverified)` | `lR26ojxv-Sg` 23:03–23:05 |

### Dungeon tanking (Forever, ~14–20)

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| Viability summary | Creator tanked **six dungeons** on a **1–20** Forever tank Shaman run; often **top damage**, sometimes healer had to **heal** them; overall **smooth** levelling and tanking. `(unverified)` for post-beta tuning. | `eZQGn3iUi3g` 0:03–0:35 |
| Entry level | Felt confident tanking after **level 14** and completing the **fire totem** quest line. | `eZQGn3iUi3g` 1:12–1:18 |
| Gear | Mostly **one-hand + shield**; also staff / **two-handed mace** tested; **Enhancement** talents mostly in **“Improvement”** branch. | `eZQGn3iUi3g` 1:04–1:11 |
| AoE threat opener | **Fire Nova** (auto-caption: “Fire”) after **fire totem** down; for **Scorch Totem** dungeon pulls, drop totem then nova for **initial aggro** on packs—not best for dragging aggro to a mage, but enough to grab everyone. | `eZQGn3iUi3g` 1:18–1:29; 2:16–2:28 |
| Single-target threat | After pack aggro: **Earth Shock on primary target**; keep **three ranks of Earth Shock** on action bar and pick rank by **current mana pool**. | `eZQGn3iUi3g` 2:32–2:39 |
| Mana on tank | **Mana is a big issue** while tanking, but aggro maintenance still described as **easy** overall. | `eZQGn3iUi3g` 2:38–2:44 |
| Support tools | **Healing Stream Totem** (auto-caption “Heating Totem”) mentioned alongside self-heals when healers struggle. | `eZQGn3iUi3g` 2:13–2:14 |
| PvP bracket check | At **level 17**, tank build held against **level 20 players** in world PvP clip context. `(unverified)` | `eZQGn3iUi3g` 1:32–1:35 |
| Lightning Shield | **Lightning Shield before** pulls highlighted in tank discussion segment. | `eZQGn3iUi3g` 6:00–6:01 |
| Threat tooling | Stream discusses **threat generation** for **Shaman tank** using **Lightning Shield** and **fire totems**; UI **threat** display praised for learning. | `lR26ojxv-Sg` 1:01:59–1:02:31; 1:06:28–1:06:29 |

### Dungeon / group healing (Forever teens)

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| Emergency heals | At **level 14–15**, player **heals up** between hard pulls; plans **mana** before engaging distant targets. | `jFvfFfI9J5w` 23:44; 28:54–29:06 |
| Downtime | Will **sit** when **out of mana** and low health after heavy questing. | `jFvfFfI9J5w` 50:46–50:49 |
| Group role | Party fill: **tank / healer / DPS** flex; queues **new dungeon** content while levelling teens. | `jFvfFfI9J5w` 57:06–57:07; 1:30:52–1:30:54 |
| Lightning Shield talents | Around **level 20+** stream considers **Improved Lightning Shield** for upcoming content. `(unverified)` | `jFvfFfI9J5w` 1:01:12–1:01:13 |

---

## Shaman-specific — Classic-era (levels 10–30; transfer carefully to Forever)

### Talents & specs (10–30)

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| Paths | Three levelling archetypes: **Elemental**, **two-hand Enhancement**, **one-hand + shield Enhancement** (latter can **tank dungeons**). | `wp-1np_ZDwQ` 2:04–2:09; `hhJ78qfgrK4` 0:54–0:59 |
| Enhancement crit | **Thundering Strikes** commonly prioritised for weapon crit in early Enhancement levelling (SoD video contrasts with shield/Lightning Shield builds). | `hhJ78qfgrK4` (talent discussion); cross-ref SoD `i08Y9vqCMsQ` *(subs unavailable this run)* |
| TGN 10–20 talents | At **level 20**, picks talents that add **mana regen while casting Lightning Bolt** and lightning spells; **Healing Spring Totem** unlocked with slow mount tier. | `hWk2GpV1rfA` 14:49–15:12 |
| Level 20–30 bracket | Guide flags **20–30** as when **Ghost Wolf** travel and extra totem tools materially change pacing. | `hhJ78qfgrK4` 2:50–2:54 |

### Rotations & weapon choices

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| Hybrid opener (general) | **Lay down totems**, apply weapon imbue, **Lightning Shield** before/after combat; optional **Flame Shock** for max damage; otherwise **pull with max-rank Lightning Bolt**. | `wp-1np_ZDwQ` 21:00–21:09 |
| Shock weaving | Alternate **Earth Shock** / **Frost Shock** by **which rank does more damage** at your level; at full mana use higher ranks. | `wp-1np_ZDwQ` 20:47–20:55 |
| Mana-efficient shock | **Rank 1 Earth Shock** called out as the **most mana-efficient** shock weave filler while meleeing. | `wp-1np_ZDwQ` 21:34–21:35 |
| Pre-25 Enhancement | Before **level 25** / **Flurry**, rotation emphasises **melee + shocks**; **Lightning Shield** upkeep is mana-intensive. | `wp-1np_ZDwQ` 19:10–19:11; 23:16–23:23 |
| TGN open world | Keep **Searing Totem** on cooldown as part of personal rotation while questing 10–20. | `hWk2GpV1rfA` 9:32–9:41 |
| Tank weapon | **Slow two-hander + Rockbiter** (not Windfury+Rockbiter pairing) for **Shaman tanking** threat testing. | `hhJ78qfgrK4` 15:46–15:50; 18:27–18:28 |
| Shield build | **Flametongue + shield** path for safer hybrid levelling. | `hhJ78qfgrK4` 4:07–4:08 |
| Buff uptime | Refresh **Rockbiter** and **Lightning Shield** with several minutes to spare before expiry. | `hhJ78qfgrK4` 26:14–26:17 |

### Totems, pulls & positioning

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| No totem recall (Classic) | In vanilla-style Classic, you **cannot pick up totems** (no Totemic Recall on nameplate); a misplaced totem **stays** until duration ends—watch **patrol paths**. | `mVp2TQ_m920` 0:30–1:06 |
| Patrol counter | If a totem is in a bad spot, **place a new totem** elsewhere to overwrite/stop pulling patrols (Classic workaround). | `mVp2TQ_m920` 1:04–1:06 |
| Totem aura range | Default totem buff radius **20 yards**; kite mobs **back to totems**; Restoration talent can raise to **30 yards** (usually skipped while levelling). | `mVp2TQ_m920` 1:43–2:05 |
| Fire totem at 10 | At **level 10** you get **Fire Totem**; use **Searing Totem** for single target; on **multiple mobs** Searing is still preferred in guide’s priority. | `wp-1np_ZDwQ` 22:04–22:08 |
| Mana Spring trade-off | **Mana Spring Totem** can return **mana spent** to place it if you stand in range—competes with **Searing** damage. | `wp-1np_ZDwQ` 22:47–22:53 |
| Earthbind kiting | **Earthbind Totem** + melee kiting like a Hamstring for safe multi-mob pulls (mana permitting). | `hhJ78qfgrK4` 4:21–4:33; 5:32–5:34 |
| Level 20 dungeon tools | **Earth Binding Totem** and **Cleanse Spirit** enter toolkit around **level 19–20** in TGN run. | `hWk2GpV1rfA` 11:29–11:31 |

### Mana management

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| Core constraint | **Mana management** is the constant Shaman levelling skill; plan shocks/casts around **regen ticks** (Classic). | `hhJ78qfgrK4` 6:01–6:05 |
| Elemental trade-off | Elemental levelling = high damage but **mana inefficient** and slower than Enhancement in guide’s ranking. | `wp-1np_ZDwQ` 13:32–13:34; 16:47–16:48 |
| Shield tax | Running **Lightning Shield** while casting will **burn mana**—factor into pull length. | `wp-1np_ZDwQ` 19:18–19:19 |
| Five-second rule | Caster rotation advice: avoid clipping **mana regen** with unnecessary casts between pulls. | `wp-1np_ZDwQ` 19:10–19:11 |
| Rank discipline | Use **lowest shock rank** that still holds threat/damage when mana-tight. | `wp-1np_ZDwQ` 21:34–21:35 |

### Dungeon tanking & healing (Classic, sub-30)

| Topic | Concrete tip | Source |
|--------|----------------|--------|
| Off-tank role | One-hand + shield Enhancement can **off-tank** or **emergency tank** in dungeons with Rockbiter threat. | `wp-1np_ZDwQ` 12:58–13:00 |
| Heal as DPS spec | Enhancement can **heal dungeons** through **Wailing Caverns / RFK** tier if the group is not over-pulling; viable until roughly **Scarlet Monastery** pace. | `mVp2TQ_m920` 2:55–3:17 |
| Party totem range | Stay within **20 yards** of party for totem buffs in dungeon corridors. | `mVp2TQ_m920` 2:10–2:14 |
| Tank toolkit | Shamans **can tank** with self-heals, Tremor, Earthbind, Searing—niche but functional at low levels. | `hhJ78qfgrK4` 4:55–5:03; 5:54–5:55 |

---

## Forever vs Classic — deltas an agent should not assume

| Classic rule (videos) | Forever observation (videos) | Sources |
|------------------------|---------------------------------|---------|
| Totems cannot be recalled; 20-yard buff radius | **Totemic Recall**, totem bar, longer **Rockbiter**, smoother mana regen | `mVp2TQ_m920` 0:30; `lR26ojxv-Sg` 1:32:49; `UeZ6P86snOo` 2:00 |
| Ghost Wolf 3s cast, outdoors only | Forever streams treat **Ghost Wolf** as major travel tool `(unverified)` indoor rule | `mVp2TQ_m920` 3:25; `lR26ojxv-Sg` 1:32:34 |
| Earth Shock threat weaving | Forever tank clip: **Fire Nova + Earth Shock** priority; multiple shock ranks on bar | `eZQGn3iUi3g` 2:16–2:39 |

---

## Most useful for an AI agent

1. On **Forever**, treat **mana as continuously recovering** after casts; do not assume Classic five-second **block regen** without on-screen verification (`UeZ6P86snOo` 1:57–2:11).
2. **Open-world pull loop (teens):** establish totems if used → **Lightning Bolt** or melee engage → **Earth Shock** on cooldown (`lR26ojxv-Sg` 40:44–54:54).
3. **Classic totem placement is permanent** until expiry; avoid patrol lanes; **kite back within 20 yards** (`mVp2TQ_m920` 0:30–2:05).
4. **Dungeon tank opener (Forever):** fire totem → **Fire Nova** for pack snap aggro → **Earth Shock** primary; rank shocks by **mana pool** (`eZQGn3iUi3g` 1:18–2:39).
5. **Mana-tight shock:** prefer **Rank 1 Earth Shock** between melee swings in Classic hybrid rotation (`wp-1np_ZDwQ` 21:34–21:35).
6. **Pre-pull buffs:** **Lightning Shield** and weapon imbue (**Rockbiter** tank / **Flametongue** hybrid) before combat (`wp-1np_ZDwQ` 21:02–21:05; `hhJ78qfgrK4` 26:14–26:17).
7. **Searing Totem** is the default fire stick for single-target questing; refresh on cooldown in 10–20 band (`hWk2GpV1rfA` 9:32–9:41; `wp-1np_ZDwQ` 22:04–22:08).
8. If **mana and health** bottom out, **sit to drink/eat**—even Forever streams still do this on hard pulls (`jFvfFfI9J5w` 50:46–50:49).
9. In low-level dungeons, a DPS Shaman may **off-heal**—communicate role and stay in totem range (`mVp2TQ_m920` 2:55–3:17).
10. Use **swing timer + totem bar** UI to separate melee timers from totem/shock globals (`WIwyNfxRiFU` 11:28; `lR26ojxv-Sg` 9:36).

---

## Sources

| Video ID | Title (as on YouTube) | Used for |
|----------|------------------------|----------|
| `eZQGn3iUi3g` | Do Not Sleep On Tank Shaman For Leveling... (WoW Forever) | Forever dungeon tank 1–20 |
| `lR26ojxv-Sg` | WoW Forever Beta: Leveling Shaman | Forever rotation, totems, tank experiments |
| `UeZ6P86snOo` | Your Questions Answered! WoW Forever Shaman Beta First Impressions | Forever mana regen, Fire Nova, tank stats |
| `WIwyNfxRiFU` | How High Tonight? — Skyborne Shaman Level 1 Start (WoW Forever) | Forever Enhancement mana on swings, UI |
| `jFvfFfI9J5w` | Can We Escape The Teens? — Enhancement Skyborne Shaman Part 2 (WoW Forever) | Forever levels 14–15+ mana/heal/dungeon queue |
| `hWk2GpV1rfA` | ★ WoW Leveling Guide - Shaman Levels 10-20! - TGN | Classic route 10–20, Searing rotation, level 20 spells |
| `hhJ78qfgrK4` | Classic WoW: Shaman Leveling Guide (Talents, Rotation, Weapon Progression...) | Classic tank/rotate/mana 10–30 |
| `wp-1np_ZDwQ` | Classic WoW Advanced Shaman Leveling Guide | Classic rotations, totem priority, shocks |
| `mVp2TQ_m920` | 10 Things To Know Before Leveling SHAMAN in FRESH WoW Classic | Classic totem range, Ghost Wolf, dungeon heal |

**URLs:** `https://www.youtube.com/watch?v=<id>`

**Not subtitled this run (429):** `YsQlxIftAXU`, `NsSilW92IWs`, `PEl2g51lKIY`, `i08Y9vqCMsQ` — retry later for additional Forever 10–20 commentary.
