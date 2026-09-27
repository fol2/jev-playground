# Zephras Isle — Cirrusfly Queen, Windstones, Skysight (web research)

**Game:** World of Warcraft: Forever (2026) · **Zone:** Zephras Isle (`zone` **16593**, Thendal Grove / Thendal Village) · **Faction context:** Windshaper (Horde) Skyborne for *The Gift of Skysight*.

**Method:** Wowhead Forever via `https://nether.wowhead.com/forever/tooltip/{type}/{id}?data={type}` (same source as [zephras_services_route.md](./zephras_services_route.md)); third-party guides/videos where cited. Full HTML quest pages returned **403** from this environment (CloudFront); item reward IDs were recovered from an earlier successful HTML fragment for quest **92463**.

**Legend:** a private live run's observation is always **unverified** here, whatever else it matches. **verified** = directly from Wowhead nether tooltip/map JSON or named primary guide quote. **unverified** = not on Wowhead, conflicting guides, or beta/live-only evidence not in Wowhead.

---

## 1. The Cirrusfly Queen

### 1.1 Quest

| Field | Value | Status |
| --- | --- | --- |
| Quest | [The Cirrusfly Queen](https://www.wowhead.com/forever/quest=92463/the-cirrusfly-queen) | **verified** (ID **92463**) |
| Objective | Destroy the **Cirrusfly Queen** in Thendal Grove (1× kill credit) | **verified** (tooltip) |
| Prerequisite | [Infestation Investigation](https://www.wowhead.com/forever/quest=92462/infestation-investigation) (**92462**) — offered immediately on turn-in per [AllThings guide](https://allthings.how/infestation-investigation-in-world-of-warcraft-full-quest-guide/) | **verified** (chain); XP on prior step **unverified** if retuned |
| Quest giver / turn-in | [Elatrell Featherlight](https://www.wowhead.com/forever/npc=251368/elatrell-featherlight) — **43.4, 24.8** (Zephras) | **verified** (NPC map) |
| Quest level | ~3 in player reports; side quests often show **level 4** in beta logs | **unverified** on nether tooltip |
| Rewards (choice) | [Exterminator's Vest](https://www.wowhead.com/forever/item=263408/exterminators-vest) **263408**, [Gardening Pants](https://www.wowhead.com/forever/item=263409/gardening-pants) **263409**, [Watcher's Mail Chest](https://www.wowhead.com/forever/item=263410/watchers-mail-chest) **263410** (ilvl 5 cloth/leather/mail) | **verified** (item IDs from Wowhead gatherer on quest page) |
| XP / money | Local beta log: **320 XP**, ~**1 silver** on complete (a private live run) | **unverified** vs launch tuning |
| Map pin (in-game) | User report **~48.3, 27.9** | **unverified** (client pin; not Wowhead) |

**Guide / video:** [Infestation Investigation walkthrough](https://allthings.how/infestation-investigation-in-world-of-warcraft-full-quest-guide/) (FocustaGuides clips); [Blizzplanet Thendal order](https://warcraft.blizzplanet.com/blog/comments/world-of-warcraft-forever-zephras-isle-quests) lists Queen as step 8 after Infestation.

### 1.2 NPC — Cirrusfly Queen

| Field | Value | Status |
| --- | --- | --- |
| NPC | [Cirrusfly Queen](https://www.wowhead.com/forever/npc=251404/cirrusfly-queen) | **verified** ID **251404** |
| Level | **3** | **verified** (tooltip: “Level 3 Beast **(Normal)**”) |
| Elite | **No** (Normal) | **verified** |
| Wowhead spawn coordinates (all listed) | **47.6, 28.9** (single point) | **verified** |
| Patrol / flies | Not documented on Wowhead; only one mapper point | **unverified** |
| Respawn | Not listed on Wowhead | **unverified** |
| Related spawns | [Cirrusfly Soldier](https://www.wowhead.com/forever/npc=251402/cirrusfly-soldier) **251402** — level not in nether snippet; **10** mapper points (see below). [Cirrusfly Hive](https://www.wowhead.com/forever/npc=251407/cirrusfly-hive) **251407** — **no coords** on Wowhead | **verified** IDs; soldier coords **verified** |

**Cirrusfly Soldier — Wowhead coords (verified, zone 16593):**

`47.0, 27.6` · `47.4, 26.4` · `47.4, 27.2` · `47.4, 29.0` · `47.6, 26.8` · `47.6, 28.0` · `47.8, 28.6` · `47.8, 29.6` · `48.6, 28.4` · `48.6, 28.8`

**Compare — [Pesky Cirrusfly](https://www.wowhead.com/forever/npc=251169/pesky-cirrusfly) (251169):** Level **1** Beast **(Normal)** — **verified**. Wowhead coords (**verified**, partial list; 25 points in API):

`42.8, 26.6` · `43.2, 28.6` · `43.4, 28.4` · `44.2, 28.6` · `44.4, 25.2` · `44.4, 26.0` · `44.4, 27.2` · `44.4, 28.4` · `44.6, 27.4` · `45.0, 25.6` · `45.0, 28.2` · `45.2, 24.2` · `45.2, 25.2` · `45.4, 28.6` · `45.8, 25.0` · `45.8, 29.0` · `46.2, 29.8` · `46.4, 26.4` · `46.4, 26.8` · `46.4, 28.0` · `46.6, 25.2` · `46.6, 26.6` · `46.6, 28.2` · `46.6, 28.6` · `46.8, 26.2` · `47.6, 26.8`

**Appearance (size / colour vs Pesky):** Wowhead nether tooltips give **no model/colour text**. Guides describe Pesky flies as routine swarm mobs; the Queen is a **named** follow-up kill in the **same grove**, with **higher level (3 vs 1)** and soldiers nearby — **unverified** for exact model scale/colour (no Wowhead screenshot text pulled).

### 1.3 Tricks / gotchas

| Claim | Status |
| --- | --- |
| Summon item / cave / hill required | **No** evidence in Wowhead quest text or [AllThings](https://allthings.how/infestation-investigation-in-world-of-warcraft-full-quest-guide/) — open-world kill in Thendal Grove | **verified** (no special mechanic listed) |
| Location | East/south-east grove near soldier spawns; queen mapper point **47.6, 28.9** aligns with user pin **48.3, 27.9** within ~1 map unit | **verified** (Wowhead coords); pin **unverified** |
| Hive object | Cirrusfly Hive NPC entry exists but **no coordinates** on Wowhead | **unverified** |
| Soldiers | Queen area has multiple **Cirrusfly Soldier** spawns; expect adds | **verified** (mapper) |

---

## 2. Harvesting Windstones

### 2.1 Quest

| Field | Value | Status |
| --- | --- | --- |
| Quest | [Harvesting Windstones](https://www.wowhead.com/forever/quest=93552/harvesting-windstones) | **verified** ID **93552** |
| Objective | Collect **15× Windstone Cluster** from **Raw Windstones** in Thendal Grove | **verified** (tooltip) |
| Quest giver / turn-in | [Dalia the Collector](https://www.wowhead.com/forever/npc=251363/dalia-the-collector) **251363** at **43.2, 24.0** | **verified** (Wowhead). [AllThings](https://allthings.how/harvesting-windstones-in-world-of-warcraft-full-quest-walkthrough/) names “**Dale** the Collector” — likely outdated/typo | **verified** Dalia on Wowhead |
| Objective area | NW of Thendal Village (blue zone on map) | **verified** (AllThings + FocustaGuides / PazarGamingGuides clips linked there) |
| User map pin | **~43.3, 26.1** | **unverified** (client; no Wowhead quest pin API) |
| Rewards (guide) | **Windstone** item, **Pet Collecting for Beginners** | **verified** (AllThings). Beta log also shows **Mining for Dummies** + **Windstone ×3**, **360 XP**, **75 copper**, **+50 Windshapers rep** (a private live run) — **unverified** vs guide book name / amounts |

**Videos / guides:** [Harvesting Windstones — AllThings](https://allthings.how/harvesting-windstones-in-world-of-warcraft-full-quest-walkthrough/) (FocustaGuides, PazarGamingGuides).

### 2.2 Object — Raw Windstone / Windstone Cluster

| Field | Value | Status |
| --- | --- | --- |
| Object name (quest text) | **Raw Windstone** → loot **[Windstone Cluster](https://www.wowhead.com/forever/item=258772/windstone-cluster)** (item **258772**) | **verified** (quest **93552** tooltip + item nether scan **200000–269999**) |
| Turn-in reward item (related) | **[Windstone](https://www.wowhead.com/forever/item=255663/windstone)** **255663** (same scan; also **Pilfered** / **Depleted** / **Cracked** windstone items for other quests) | **verified** (item IDs only; quest reward link **unverified** on HTML page) |
| Wowhead **object ID** | Not found | **unverified** — exhaustive nether scans **520000–569999** and name search for “Raw Windstone” / “Elemental Convergence” returned **no** Forever object entries with Zephras `zone` **16593** |
| Wowhead spawn coordinate list | **None listed** | **verified** (absent from database API) |
| Interaction | AllThings: **interact** with ground nodes (“Looting one awards a Windstone Cluster”); no cast bar unless combat | **verified** (guide). Classic-style **right-click** gather is **unverified** on Wowhead (not stated) |
| Node behaviour (guide) | Light-blue crystal at mountain edge, open grass, treeline, cliff paths; **respawns** on second lap | **verified** (AllThings); **unverified** on Wowhead |
| Interrupt mobs (guide) | **Juvenile Vuldren**, **Ensnared Ursa** | **partially verified:** [Juvenile Vuldren](https://www.wowhead.com/forever/npc=250873/juvenile-vuldren) **250873** level **1** with mapper coords in grove — **verified**. “Ensnared Ursa” — **no** matching NPC name in Zephras nether scan **250000–252500** | **unverified** for Ursa name |

---

## 3. The Gift of Skysight

### 3.1 Quest

| Field | Value | Status |
| --- | --- | --- |
| Quest | [The Gift of Skysight](https://www.wowhead.com/forever/quest=92598/the-gift-of-skysight) | **verified** ID **92598** |
| Objective | Use **Skysight** racial at the **Elemental Convergence** in Thendal Grove | **verified** (tooltip) |
| Faction | Windshaper (Horde) — Skysight racial | **verified** ([Wowhead Skyborne overview](https://www.wowhead.com/forever/guide/skyborne-race-overview)) |
| Prerequisite chain | [The Windshapers](https://www.wowhead.com/forever/quest=92595/the-windshapers) **92595** — listen to [Illaya Amberwind](https://www.wowhead.com/forever/npc=251902/illaya-amberwind) **251902** @ **43.4, 44.8** / **43.6, 44.8** (Shen'dar band on Zephras). Alliance: [The High Order](https://www.wowhead.com/forever/quest=92596/the-high-order) **92596** — [Rathiril Sunlance](https://www.wowhead.com/forever/npc=251903/rathiril-sunlance) **251903** @ **45.0, 46.4** | **verified** (quest tooltips + NPC map); auto-offer edge **92595 → 92598** not in nether tooltip | **partially verified** |
| Quest giver / turn-in | **[Ventaari Brightwish](https://www.wowhead.com/forever/npc=251487/ventaari-brightwish)** **251487** at **42.6, 24.4** — hand-in pin in beta logs **~42.7, 24.1** | NPC location **verified**; quest start/end link **unverified** on Wowhead (403 HTML); hand-in **unverified** (a private live observation only) (**unverified** for launch) |
| After use | Return to Ventaari; beta: **180 XP**, **+100 Windshapers rep** (a private live run) | **unverified** tuning |

**Skysight mechanic (not the quest pin):** [Wowhead Skyborne guide](https://www.wowhead.com/forever/guide/skyborne-race-overview) — 10% move speed; **30 s** default, **15 min** near convergence; **0.5 s** cast, **2 min** CD; not in combat — **verified** (guide). [Warcraft Tavern](https://www.warcrafttavern.com/forever/guides/skyborne-racials/) — convergences track on minimap when using Skysight — **verified** (guide, not Zephras-specific coords).

### 3.2 Elemental Convergence — coordinates

| Source | Result | Status |
| --- | --- | --- |
| Wowhead object/NPC named “Elemental Convergence” | **No** entry with mapper coords (API scan **250000–256000** NPCs/objects by name; object ID sweeps) | **verified** (absent) |
| Quest text | “in **Thendal Grove**” only | **verified** |
| Logical area (quest design) | Same early grove arc as [Agitators](https://www.wowhead.com/forever/quest=92465/agitators) **92465** — **Thendal Standing Stones** / north-west grove ([AllThings Agitators](https://allthings.how/world-of-warcraft-agitators-full-quest-guide-ammen-vale/) describes converts + rolling winds at standing stones; Zephras version uses **Roiling Winds** in tooltip) | **unverified** exact convergence point |

**Do not treat any single `/way` as Wowhead-verified for the Convergence itself** — none published in the API at research time.

### 3.3 Hostiles near the convergence / standing-stones band

Wowhead lists these **Normal** mobs with mapper points in the **~46.6–47.9, 18.9–20.9** band (north-west grove), consistent with Agitators objective area:

| NPC | ID | Level (Wowhead) | Wowhead coords (all listed) | Status |
| --- | --- | --- | --- | --- |
| [Al'Aketh Convert](https://www.wowhead.com/forever/npc=251160/alaketh-convert) | **251160** | **2–3** Humanoid (Normal) | `46.7, 20.4` · `47.0, 18.9` · `47.3, 20.7` · `47.8, 20.1` · `47.9, 19.3` | **verified** |
| [Roiling Winds](https://www.wowhead.com/forever/npc=251143/roiling-winds) | **251143** | **2–3** (Normal) | `46.6, 20.0` · `47.1, 19.1` · `47.4, 20.9` · `47.6, 20.0` · `47.7, 19.4` | **verified** |

**Note:** Agitators requires destroying **Roiling Winds** (wind elementals), not only killing humanoids — **verified** (quest **92465** tooltip). A private live run (48) saw **Al'Aketh Converts** at **level 3** near the Convergence — **unverified** vs Wowhead “2–3” band.

**Not convergence-specific:** [Juvenile Vuldren](https://www.wowhead.com/forever/npc=250873/juvenile-vuldren) and cirrusfly mobs sit **farther south/east** (25–29 Y) — **verified** by coords; do not assume they guard the convergence unless you are walking through the whole grove.

---

## 4. Cross-reference — the client's map pins (private live runs)

| Quest | Client pin (private live run, unverified) | Wowhead / research |
| --- | --- | --- |
| Cirrusfly Queen | **48.3, 27.9** | Queen **47.6, 28.9**; soldiers include **48.6, 28.4** / **48.6, 28.8** — consistent direction, **not** identical coords |
| Harvesting Windstones | **43.3, 26.1** | Giver **43.2, 24.0**; Juvenile Vuldren spawns include **43.2–43.8, 25.4–28.6** — pin plausibly in gather band; **no** node list on Wowhead |

---

## 5. Source index

| Source | URL |
| --- | --- |
| Wowhead Forever (quests/NPCs) | https://www.wowhead.com/forever/ |
| Nether tooltips (method) | `https://nether.wowhead.com/forever/tooltip/{quest\|npc\|object\|item}/{id}?data=…` |
| Infestation / Queen chain | https://allthings.how/infestation-investigation-in-world-of-warcraft-full-quest-guide/ |
| Harvesting Windstones | https://allthings.how/harvesting-windstones-in-world-of-warcraft-full-quest-walkthrough/ |
| Agitators / standing stones pattern | https://allthings.how/world-of-warcraft-agitators-full-quest-guide-ammen-vale/ |
| Blizzplanet quest order | https://warcraft.blizzplanet.com/blog/comments/world-of-warcraft-forever-zephras-isle-quests |
| Skyborne / Skysight | https://www.wowhead.com/forever/guide/skyborne-race-overview |

*Generated: 27 Sep 2026. No repository files were modified except this research note.*
