# Multiclass knowledge model for WoW Classic / Forever questing agents

Design research for a **class-agnostic** knowledge layer an AI agent can fill per class, while sharing one combat-and-sustain playbook. Facts below assume **solo open-world questing** (levels 1–30 beta cap, then 60 at launch) unless noted. **Forever-specific** deltas are called out; where only Classic 1.12 data exists, behaviour is marked **(Classic baseline; Forever may differ)**.

---

## 1. Scope and split: class-agnostic vs class-specific

| Layer | Agent uses it for |
| --- | --- |
| **Class-agnostic** | Target selection, leash rules, facing, loot, quest UI, mount speed, camp/rest triggers, 5-second rule, bandage timing, pull safety bands (melee / spell / pet), add detection, flee heuristics |
| **Class-specific** | Resource type, opener, rotation priority, totem/seal/stance bars, emergency buttons, rest profile (eat/drink/life tap), optimal pull range per ability |

Forever global systems that affect **every** class: unified hit/crit, healing gear granting +⅓ spell damage, baseline Kings / Divine Spirit / Improved Mark of the Wild, 51 talent points with **16-point** gold talents, camping profession buffs, ~10–15 s single-mob kill pacing target, Skyborne starter zone on Zephras Isle. Sources: [Inven Deep Dive](https://www.invenglobal.com/articles/25897/world-of-warcraft-forever-details-revealed-major-overhaul-for-gear-and-classes), [Blizzard race/class article](https://news.blizzard.com/en-us/article/24304075/create-the-hero-you-want-to-be-in-world-of-warcraft-forever), [LFCarry class tracker](https://lfcarry.com/guides/wow-forever-class-changes).

---

## 2. World of Warcraft: Forever — classes, races, systems

### 2.1 Classes and new combinations

- **Nine classes only** (no Death Knight / Monk / etc. at announcement): Warrior, Mage, Hunter, Priest, Rogue, Warlock, Paladin, Druid, Shaman. Source: [Blizzard](https://news.blizzard.com/en-us/article/24304075/create-the-hero-you-want-to-be-in-world-of-warcraft-forever).
- **New race: Skyborne** (shen’dorei), faction choice at creation:
  - **Windshapers (Horde)**: Druid, Hunter, Rogue, Shaman, Warrior; **Shaman exclusive** to this Skyborne branch.
  - **High Order (Alliance)**: Druid, Hunter, Mage, Rogue, Warrior; **Mage exclusive** to this branch.
- **New race/class combos** (examples): Human Hunter, Dwarf Shaman (Alliance’s only Shaman), Gnome Priest, Orc Mage, Troll Warlock, Undead Paladin (Horde’s only Paladin). Source: [Blizzard tables](https://news.blizzard.com/en-us/article/24304075/create-the-hero-you-want-to-be-in-world-of-warcraft-forever), [Inven](https://www.invenglobal.com/articles/25897/world-of-warcraft-forever-details-revealed-major-overhaul-for-gear-and-classes).

### 2.2 Racial redesign (agent-relevant)

Each race: **two actives + two passives**, tuned for comparable power. Examples documented by Blizzard: Orc **Blood Fury** (+10% AP/SP 15 s), Undead **Will of the Forsaken** changed to **break** Charm/Fear/Sleep (not long immunity), **Cannibalize**, **Touch of the Grave**; Dwarf **Stoneform** (cleanse + physical damage reduction); Windshaper **Skysight** (+10% run speed), **Walk on Air** (glide 10 s), **Wind Blessed** (+1% haste), **Elemental Insight** (+5% vs elementals). Source: [Blizzard racials](https://news.blizzard.com/en-us/article/24304075/create-the-hero-you-want-to-be-in-world-of-warcraft-forever).

### 2.3 Combat / item globals

- Hit and crit **merged** across melee, ranged, and spell. Weapon skill retained with smaller per-item values. Source: [Inven](https://www.invenglobal.com/articles/25897/world-of-warcraft-forever-details-revealed-major-overhaul-for-gear-and-classes).
- **Bonus healing → +⅓ bonus spell damage** on same item. Source: [Inven](https://www.invenglobal.com/articles/25897/world-of-warcraft-forever-details-revealed-major-overhaul-for-gear-and-classes), [MMOJUGG](https://www.mmojugg.com/news/wow-forever-gear-stats.html).
- **Paladin** is the only class with a full public overhaul write-up at research time: **Holy Strike** (melee, level 6), **Judgement no longer consumes Seals**, **Seal of Wrath** (Prot ranged taunt via Judgement), baseline **Consecration** themes, 16-point talents per tree. Source: [Inven Paladin section](https://www.invenglobal.com/articles/25897/world-of-warcraft-forever-details-revealed-major-overhaul-for-gear-and-classes).
- Other classes: largely Classic skeleton + global baselines; **Shaman** has substantial spell/totem tooling documented in beta datamine (see §5). Full Forever changelists for remaining eight classes: **(unverified / pending official posts)** per [LFCarry tracker](https://lfcarry.com/guides/wow-forever-class-changes).

### 2.4 Beta timeline (agent training windows)

- Beta from **17 Sep 2026**, initial **level 20** cap rising toward **30**; launch **4 Nov 2026**. Source: [Inven announcement](https://www.invenglobal.com/articles/25876/wow-classic-details-announced-titled-world-of-warcraft-forever).

---

## 3. Per-class questing profiles (levels 1–~30 focus)

Ranges and costs are **Classic rank-1 / early ranks** unless Forever notes are given. Cooldowns from Classic tooltips.

### 3.1 Warrior

| Field | Value |
| --- | --- |
| **Resource** | **Rage** (0–100): generated by dealing/taking damage; decays out of combat. No mana. Source: [Icy Veins warrior leveling](https://www.icy-veins.com/wow-classic/arms-warrior-leveling-guide-1-60). |
| **Regen** | Combat-only via white hits and damage taken; **Bloodrage** converts HP → rage (cooldown). |
| **Pull** | **Charge**: **8–25 yd**, Battle Stance, **out of combat**, stun ~1 s, generates rage (9 at rank 1). Source: [Wowhead Charge](https://www.wowhead.com/classic/spell=100/charge). Body-pull if already in combat. |
| **Range band** | Opener **8–25 yd**; sustained **melee ~5 yd**. |
| **Core rotation (low)** | Charge → **Rend** → **Heroic Strike** only with excess rage (replaces rage-generating swing) → **Execute** &lt;20% HP. Stances: Battle for Charge/Overpower; Berserker for Intercept later. Source: [Icy Veins](https://www.icy-veins.com/wow-classic/arms-warrior-leveling-guide-1-60). |
| **Defensive / escape** | **Shield Wall**, **Last Stand**, **Intimidating Shout** (later); low level: **Hamstring** kite, run. **Berserker Rage** breaks fear/incap (later). |
| **Rest** | **Eat** between pulls; no drink. **Bandage** when safe. High downtime if under-geared. |
| **Pitfalls** | Rage starvation on bad pulls; Heroic Strike starving auto-attacks; no ranged pull without Charge CD; slow until Arms talents; multi-mob without Sweeping Strikes (later). Community tier: slowest solo leveler. Source: [Wowhead tier list](https://www.wowhead.com/classic/news/best-classes-for-leveling-wow-classic-best-class-tier-list-294562). |

**Forever:** no detailed warrior changelog at research time **(unverified)**.

---

### 3.2 Mage

| Field | Value |
| --- | --- |
| **Resource** | **Mana**; **5-second rule** after last cast before spirit regen in combat. |
| **Regen** | Spirit + drink; **Evocation** (later); Forever casters get more SP on weapons **(unverified per-item)**. |
| **Pull** | **Frostbolt** / **Fireball** **30 yd**; pull with bolt then kite. **Frost Nova** root when mob closes. Source: Classic mage leveling convention; [Wowhead Frostbolt 30 yd](https://www.wowhead.com/classic/spell=116/frostbolt). |
| **Range band** | **25–30 yd** safe; **8–10 yd** Nova zone; avoid melee. |
| **Core rotation (low)** | Frost: Bolt until low HP → **Wand** finish to preserve 5s rule → Nova + repeat on multi. AoE farming (higher): Blizzard/Cone **(not low-level)**. |
| **Defensive / escape** | **Frost Armor**, **Ice Barrier** (later), **Blink**, **Polymorph** CC, **Frost Nova**. |
| **Rest** | **Conjured water/food** (major advantage); drink every 1–3 pulls if casting constantly. |
| **Pitfalls** | OOM without wand finish; no pet; fragile; cloth; wrong school on resistant mobs. Fastest *if* AoE path; otherwise drink-heavy. Source: [Blizzard forums discussion](https://us.forums.blizzard.com/en/wow/t/hardest-classes-to-level/166858). |

**Forever:** conjure + global SP/healing item rules still apply; no mage-specific overhaul doc **(unverified)**.

---

### 3.3 Hunter

| Field | Value |
| --- | --- |
| **Resource** | **Mana** for shots/abilities; **Focus** not in Classic (pet uses focus in later expansions only). |
| **Regen** | Spirit + drink (moderate); **Aspect of the Viper** N/A in Classic. |
| **Pull** | **Pet Attack** from **~30–35 yd** (ranged auto band); **Concussive Shot** slow; **Misdirection** only level **70** in Classic — **not in 1–30 band**. Source: [Warcraft Wiki Misdirection](https://warcraft.wiki.gg/wiki/Misdirection). |
| **Range band** | **8–35 yd** sweet spot (dead zone **≤8 yd** without melee); pet holds aggro front. |
| **Core rotation (low)** | Send pet → **Serpent Sting** → **Arcane Shot** dump → **Auto Shot** timer; **Mend Pet** between fights. **Feign Death** drop aggro (emergency). Source: [Wowhead hunter tier](https://www.wowhead.com/classic/news/best-classes-for-leveling-wow-classic-best-class-tier-list-294562). |
| **Defensive / escape** | **Feign Death**, **Disengage** (later), pet tank, **Concussive** kite. |
| **Rest** | Light drink; **bandage self**; **mend pet** costs mana. Pet **eat** happy buff (Classic pet happiness). |
| **Pitfalls** | Pet pathing/delay aggro **(Classic quirk)**; dead zone; ammo/gun repair; multi-mob without trap CD. Source: [Blizzard pet delay thread](https://us.forums.blizzard.com/en/wow/t/hunter-warlock-pet-delay-aggro-range/279822). |

**Forever:** Human Hunter new combo; racials may alter burst windows **(unverified)**.

---

### 3.4 Priest

| Field | Value |
| --- | --- |
| **Resource** | **Mana**; Spirit Tap (Shadow, ~40+) changes rest profile. |
| **Regen** | Spirit + drink; wand phase for 5s rule; Shadow: **Vampiric Embrace** later. |
| **Pull** | **Mind Blast** / **Holy Fire** **30 yd**; low Disc/Holy: **SW:P** → **wand**. Source: [Icy Veins priest leveling](https://www.icy-veins.com/wow-classic/classic-priest-leveling-guide). |
| **Range band** | **20–30 yd** pull; **wand ~30 yd**; melee only if forced. |
| **Core rotation (low)** | **SW:P** once → **wand** to death; add **Mind Blast** on CD when Shadow. **Psychic Scream** for adds. |
| **Defensive / escape** | **Power Word: Shield**, **Psychic Scream**, **Fade** (later), fear undead **(situational)**. |
| **Rest** | Low: frequent drink; Shadow 40+: minimal downtime with Spirit Tap + wand. **No eat** if shield/heal efficient. |
| **Pitfalls** | Cloth; no pet; Shadow mana-hungry before 40; wand DPS dependency; boring but safe Disc wand spec. Source: [Icy Veins](https://www.icy-veins.com/wow-classic/classic-priest-leveling-guide). |

**Forever:** healing gear gives quest damage via +⅓ rule — helps Holy/Disc outdoor. Gnome Priest new **(unverified power)**.

---

### 3.5 Rogue

| Field | Value |
| --- | --- |
| **Resource** | **Energy** (100, regenerates ~20/s in combat); **Combo points** on target. |
| **Regen** | Energy fixed rate; **Adrenaline Rush** later; out of combat full energy. |
| **Pull** | **Stealth** → **Garrote** / **Ambush** (positional); or **Throw** / **Shoot** (limited). Melee **≤5 yd** openers. |
| **Range band** | Stealth approach **0–5 yd**; ranged pull weak. |
| **Core rotation (low)** | **Sinister Strike** builder → **Eviscerate** at 4–5 CP; maintain **Slice and Dice** (later); **Evasion** on tough pulls. Combat swords preferred for leveling (no backstab facing). Source: [Wowhead tier](https://www.wowhead.com/classic/news/best-classes-for-leveling-wow-classic-best-class-tier-list-294562). |
| **Defensive / escape** | **Evasion**, **Sprint**, **Vanish**, **Blind**; **Gouge** bandage setup. |
| **Rest** | **Eat** + **bandage**; no drink. Stealth reset between camps. |
| **Pitfalls** | Weapon DPS gates progression; 2+ mobs deadly; positional specs weak; slow without updated weapons (e.g. Maraudon Thrash Blade meme). Source: [Wowhead](https://www.wowhead.com/classic/news/best-classes-for-leveling-wow-classic-best-class-tier-list-294562). |

**Forever:** no rogue changelog **(unverified)**.

---

### 3.6 Warlock

| Field | Value |
| --- | --- |
| **Resource** | **Mana**; **Soul Shards** inventory for many utilities; **Life Tap** converts HP→mana. |
| **Regen** | **Life Tap** + **Drain Life**; drink optional; **Dark Pact** (later) from pet mana. |
| **Pull** | **Curse of Agony** / **Immolate** **30 yd**; pet **Charge** (felguard later) or send imp. |
| **Range band** | **25–30 yd** cast; pet melee front. |
| **Core rotation (low)** | **Corruption** + **CoA** + **Drain Life** (sustain) or **Shadow Bolt** burst; pet on attack. **Wand** finish to save mana **(Classic baseline)**. |
| **Defensive / escape** | **Fear**, **Voidwalker Sacrifice**, **Soulstone** (bank one), **Drain Life** kite. |
| **Rest** | **Life Tap** reduces drink; still **eat** or Drain Life; shard farming between camps. |
| **Pitfalls** | Shard bag space; Fear adds into patrols; pet happiness; threat in dungeons. Source: [YouTube warlock guide discussion](https://www.youtube.com/watch?v=9dfxA5NK1aQ) (soul shard economy, timestamps vary). |

**Forever:** Troll Warlock combo; Undead also Warlock — racials alter sustain **(unverified)**.

---

### 3.7 Paladin

| Field | Value |
| --- | --- |
| **Resource** | **Mana**; seals/judgements interact with 5s rule. |
| **Regen** | Spirit + drink; **Blessing of Wisdom**; bandage between pulls. |
| **Pull** | **Judgement** / **Exorcism** (undead/demon) **10–30 yd** depending on spell; default **melee walk-in** Classic. |
| **Range band** | **0–5 yd** melee; occasional **10 yd** Judgement range **(Classic)**. |
| **Core rotation (low Classic)** | **Seal** up → **Judgement** on CD → auto-attack; **SoC** if weapon **≥3.5 speed** else **SoR**; **Hammer of Wrath** &lt;20%. Source: [Warcraft Tavern paladin](https://www.warcrafttavern.com/wow-classic/guides/paladin-leveling-guide/). |
| **Defensive / escape** | **Divine Shield** → bandage; **Lay on Hands**; **Hammer of Justice** stun. |
| **Rest** | **Drink** heavily if judging often; **bandage** under shield; low kill speed = long time-to-kill. |
| **Pitfalls** | Slowest DPS; no interrupt; mana if over-casting Consecration on singles; weapon speed wrong seal. |

**Forever:** **Holy Strike** at **level 6** (melee holy damage); **Judgement does not remove Seal**; Prot **Seal of Wrath** ranged taunt; more mana tools in Holy tree **(beta)**. Agent should prefer documented Forever rotation when client detects Forever build. Source: [Inven](https://www.invenglobal.com/articles/25897/world-of-warcraft-forever-details-revealed-major-overhaul-for-gear-and-classes).

---

### 3.8 Druid

| Field | Value |
| --- | --- |
| **Resource** | **Mana** for spells; **Rage** in Bear; **Energy** in Cat (from level 20). |
| **Regen** | **Innervate** (later); out-of-combat **spirit regen**; Cat/Bear **no mana** during form — shift to caster to heal. |
| **Pull** | **1–9:** **Moonfire** (instant DoT) + **Wrath** **30 yd**. **10+:** **Bear** melee pull or Moonfire. Source: [Warcraft Tavern druid](https://www.warcrafttavern.com/wow-classic/guides/druid-leveling-guide/). |
| **Range band** | **20–30 yd** caster; **melee 5 yd** bear/cat. |
| **Core rotation (low)** | **10–19 Bear:** **Maul** dump, **Demoralizing Roar** on multi. **20+ Cat:** **Rake**, builders, **Rip/FB**. Caster heal between fights. |
| **Defensive / escape** | **Bear** tankiness; **Bash**; **Dash** cat; **Regrowth/Rejuv** HOT kiting. |
| **Rest** | **Drink** in caster form; can **Heal** instead of eat mid-tier; low downtime once Cat online. |
| **Pitfalls** | Pre-10 weak caster; form shifting mana tax; hybrid gear confusion; Forever healing→damage helps resto/balance **(unverified numbers)**. |

**Forever:** no detailed druid changelog **(unverified)**.

---

### 3.9 Shaman (Horde + Dwarf + Windshaper)

| Field | Value |
| --- | --- |
| **Resource** | **Mana**; weapon imbues/totems cost mana; **5-second rule** critical. |
| **Regen** | Spirit + drink; **Healing Stream Totem** (20+); Forever **Mana Spring** longer duration **(beta)**. |
| **Pull** | **Lightning Bolt** **30 yd** body-pull or single-target; **run leash** to split packs **(Classic technique)**. Source: [Legacy-WoW](https://legacy-wow.com/vanilla-shaman-guide/). |
| **Range band** | **10–30 yd** opener; **5 yd** melee after bolt phase; **Earthbind** between you and mob. |
| **Core rotation (low)** | **Enhancement (recommended 1–40):** **Rockbiter** + **Lightning Shield** → pull Bolt (rank 1 if OOM) → **Earth Shock** once → **melee**; optional **Flame Shock** / **Searing Totem** if mana allows. **Do not** refresh shocks/shields every GCD if it breaks regen. Source: [Icy Veins shaman](https://www.icy-veins.com/wow-classic/classic-shaman-leveling-guide), [Wowhead Lightning Shield comments](https://www.wowhead.com/classic/spell=324/lightning-shield). |
| **Defensive / escape** | **Stoneclaw Totem** (taunt), **Earthbind**, **Ghost Wolf** (outdoor run, 20+), **Healing Wave** self-heal. |
| **Rest** | **Drink** often if casting; melee-heavy Enh reduces drinks; **bandage** between pulls. |
| **Pitfalls** | OOM from Lightning Shield uptime + Searing + shocks; multi-mob without Earthbind; slow without weapon upgrades; Zephras Isle elemental theme fits **Elemental Insight** racial. |

**Forever Shaman highlights:** Totem GCD **1.0 s**; **Totemic Projection** (relocate totems **30 yd**, CD **10 s**); **Totemic Recall** (25% mana back); **Call of the Elements** (3 s cast, 4 totems); **Fire Nova** = instant pulse around fire totem (**10 s CD**, **10 yd** radius) not a separate totem; weapon buffs **60 min**; many totem buff radii **30 yd / 5 min**; spell coefficients retuned (lower per-hit, faster casts). Sources: [Icy Veins Forever Enhancement](https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-guide), [ForeverChanges spellbook](https://foreverchanges.pro/spellbook/shaman), [WoWSoD Pro spellbook notes](https://wowsod.pro/wow-forever/spellbook/shaman).

---

## 4. Common schema (every class implements)

Use a single JSON-shaped document per `(game_build, class, spec_optional, level_bracket)`. Field types are intentional for agent planners.

```yaml
schema_version: "1.0"
game_build: "forever-beta" | "classic-era"
class: string
level_bracket: { min: int, max: int }

resource:
  primary: enum [mana, rage, energy, none]
  secondary: [soul_shards, combo_points, ...]
  regen_rules: [text]          # e.g. "5s rule", "life_tap", "rage_from_damage"

range_bands:
  preferred_pull_yd: [min, max]
  melee_yd: float
  safe_kite_yd: [min, max]
  dead_zone_yd: [min, max] | null

pull:
  method: enum [charge, stealth, pet, spell, melee_walk, totem_pull]
  opener_priority: [ability_id]   # ordered
  in_combat_opener: [ability_id]  # if pull failed

sustain:
  rotation_priority: [{ ability_id, condition, notes }]
  filler: enum [auto_attack, wand, shoot, none]
  mana_policy: enum [aggressive, balanced, stingy]  # maps to rank downrank

emergency:
  defensive_cooldowns: [{ ability_id, cd_s, triggers }]
  escape_cooldowns: [{ ability_id, cd_s, triggers }]
  cc: [{ ability_id, target, cd_s }]

rest:
  eat: boolean
  drink: boolean
  bandage: boolean
  life_tap: boolean
  typical_pause_s: [min, max]   # observed human pacing
  camp_synergy: text            # Forever campfires

key_abilities:
  - id: string                  # stable internal key
    name: string
    unlock_level: int
    range_yd: [min, max] | self | melee
    cost: { type, amount }
    cast_time_s: float
    cooldown_s: float
    gcd_s: float
    tags: [pull, interrupt, heal, snare, ...]
    forever_only: boolean
```

### 4.1 Class-agnostic hooks the schema references

- **`ability_id`**: map to client action bar slot + spell ID from a build-specific table.
- **`condition`**: small DSL (`target.hp_pct < 20`, `in_combat == false`, `mana_pct < 30`, `mob_count >= 2`).
- **`tags`**: let the vision agent choose buttons without parsing tooltips every frame.

---

## 5. Worked example: Windshaper Shaman (level 1–12, Forever beta)

Context: **Level 4 Skyborne Shaman**, Zephras Isle, Windshapers (Horde). Beta cap and spell ranks may stop before level 20 abilities.

```yaml
schema_version: "1.0"
game_build: "forever-beta"
class: shaman
faction: horde
race: skyborne_windshaper
level_bracket: { min: 1, max: 12 }

resource:
  primary: mana
  secondary: []
  regen_rules:
    - "After last mana spend, wait 5s before next cast for full spirit regen (Classic rule; assume Forever unless proven otherwise)."
    - "Forever: Totemic Recall returns 25% totem mana when resetting (level 20+)."

range_bands:
  preferred_pull_yd: [18, 30]
  melee_yd: 5
  safe_kite_yd: [8, 25]
  dead_zone_yd: null

pull:
  method: spell
  opener_priority: [lightning_bolt_r1]
  in_combat_opener: [earth_shock_r1, earthbind_totem]

sustain:
  mana_policy: balanced
  rotation_priority:
    - { ability_id: rockbiter_weapon, condition: "not buffed", notes: "Forever 60 min buff at higher ranks; refresh out of combat." }
    - { ability_id: lightning_shield, condition: "mana_pct > 50 and level >= 8", notes: "Skip if OOM risk; breaks 5s rule each refresh." }
    - { ability_id: lightning_bolt, condition: "pull or mob_count == 1 and range >= 10", notes: "Rank 1 pull; stop casting when mob enters melee unless fleeing." }
    - { ability_id: earth_shock, condition: "casters interrupt or opener", notes: "Rank 1 for interrupt; Forever rank 1 damage retuned lower." }
    - { ability_id: auto_attack, condition: "melee range", notes: "Primary damage levels 1-12 Enh." }
    - { ability_id: searing_totem, condition: "mana_pct > 60 and stationary fight", notes: "Optional; drop near target." }
    - { ability_id: earthbind_totem, condition: "mob_count >= 2 or kiting", notes: "10 yd slow radius around totem." }
  filler: auto_attack

emergency:
  defensive_cooldowns:
    - { ability_id: stoneclaw_totem, cd_s: 0, triggers: "adds or low hp", notes: "8 yd taunt pulse; Classic tooltip." }
    - { ability_id: healing_wave, cd_s: 0, triggers: "hp_pct < 40", notes: "Post-pull heal then resume regen." }
  escape_cooldowns:
    - { ability_id: ghost_wolf, cd_s: 0, triggers: "outdoor and level >= 20", notes: "Not at level 4." }
  cc:
    - { ability_id: earthbind_totem, target: ground, cd_s: 0 }

rest:
  eat: false
  drink: true
  bandage: true
  life_tap: false
  typical_pause_s: [15, 35]
  camp_synergy: "Forever campfires: profession buff objects; use when human would rest (unverified exact buff IDs)."

key_abilities:
  - id: lightning_bolt_r1
    name: Lightning Bolt
    unlock_level: 1
    range_yd: [30, 30]
    cost: { type: mana, amount: 15 }
    cast_time_s: 1.5
    cooldown_s: 0
    gcd_s: 1.5
    tags: [pull, nuke]
    forever_only: false
    source: "Classic rank 1 baseline; Forever retunes damage/cast at max rank — see ForeverChanges."

  - id: earth_shock_r1
    name: Earth Shock
    unlock_level: 4
    range_yd: [20, 20]
    cost: { type: mana, amount: 25 }
    cast_time_s: 0
    cooldown_s: 0
    gcd_s: 1.5
    tags: [interrupt, instant]
    forever_only: false
    source: "https://www.wowhead.com/classic/spell=8042/earth-shock"

  - id: healing_wave_r1
    name: Healing Wave
    unlock_level: 1
    range_yd: [40, 40]
    cost: { type: mana, amount: 35 }
    cast_time_s: 1.5
    cooldown_s: 0
    gcd_s: 1.5
    tags: [heal]
    forever_only: false
    source: "https://www.wowhead.com/classic/spell=331/healing-wave"

  - id: earthbind_totem
    name: Earthbind Totem
    unlock_level: 6
    range_yd: self
    cost: { type: mana, amount: 17 }
    cast_time_s: 0
    cooldown_s: 0
    gcd_s: 1.0
    tags: [snare, cc]
    forever_only: false
    notes: "Forever totem drop GCD 1.0s per Icy Veins Forever guide."
    source: "https://foreverchanges.pro/spellbook/shaman"

  - id: totemic_projection
    name: Totemic Projection
    unlock_level: 22
    range_yd: [0, 30]
    cost: { type: mana, amount: 0 }
    cast_time_s: 0
    cooldown_s: 10
    gcd_s: 1.0
    tags: [totem_manage]
    forever_only: true
    source: "https://wowsod.pro/wow-forever/spellbook/shaman"

  - id: fire_nova
    name: Fire Nova
    unlock_level: 12
    range_yd: [30, 30]
    cost: { type: mana, amount: "ranked" }
    cast_time_s: 0
    cooldown_s: 10
    gcd_s: 1.5
    tags: [aoe]
    forever_only: true
    notes: "Requires active fire totem; 10 yd around totem."
    source: "https://foreverchanges.pro/spellbook/shaman"

racial:
  - { id: skysight, effect: "+10% run speed", tags: [mobility] }
  - { id: walk_on_air, effect: "glide 10s", tags: [fall_safe] }
  source: "https://news.blizzard.com/en-us/article/24304075/create-the-hero-you-want-to-be-in-world-of-warcraft-forever"
```

**Level 4 agent policy (summary):** Pull with **Lightning Bolt** at ~20–28 yd; apply **Rockbiter** pre-fight; at melee use **auto-attack**; **Earth Shock** only for casters or finish before running; heal with **Healing Wave** if &lt;50% HP after fight; **drink** to full before next pull. Avoid **Lightning Shield** until level 8 and unless mana stable. Use **Skysight** passive for shorter travel between objectives.

---

## 6. Forever vs Classic: agent detection

| Signal | Action |
| --- | --- |
| Build string `1.60.x` **(unverified in agent)** | Load `forever-beta` ability table |
| Spell **Totemic Projection** in book | Enable totem relocation planner |
| **Judgement** without seal fade | Paladin Forever rules |
| Talent point at **16** in a tree | Expose 16-point gold talent in planner |
| No **Misdirection** in book at 30 | Hunter still pre-MD Classic |

---

## 7. Data quality and gaps

- **High confidence:** race/class matrix, global item/talent rules, Paladin Forever kit, Shaman Forever totem/Fire Nova changes (datamine + Icy Veins Forever).
- **Medium:** per-class low-level numeric costs (Classic 1.12; Forever retuned shocks/bolts).
- **Low / unverified:** exact level-4 mana pools on Zephras Isle, remaining eight class Forever changelists, camp object buff IDs, Legacy talent effects on combat agent.

---

## Most useful for an AI agent

1. Treat **pull range** and **in-combat range** as separate policies; store both in `range_bands` and never reuse one number for all abilities.
2. Encode the **5-second rule** in `mana_policy: stingy` for Shaman, Mage, Priest, Paladin, Druid caster — finish with **wand/auto** where applicable.
3. **Warrior** and **Rogue** need **rage/energy empty-hand** detection; do not queue Heroic Strike without excess rage.
4. **Hunter/Warlock** must model **pet aggro delay** and pet HP; pull commands precede DPS keys.
5. **Forever Shaman** should plan **totem sets** once level ≥20: Projection before re-dropping totems on moving packs.
6. Switch **Paladin** schema file when Judgement no longer consumes Seals (Forever build flag).
7. **Rest** is a first-class state: `eat/drink/bandage` booleans prevent the agent from spam-casting into OOM loops.
8. **Emergency** abilities need **vision triggers** (hp_pct, mob_count, casting_detected) not rotation priority alone.
9. **Racial actives** belong in `emergency` or `sustain` with their own cooldowns (Stoneform, Will of the Forsaken, Walk on Air).
10. Keep **CLASS-AGNOSTIC** leash/add logic outside class YAML so Shaman mastery does not fork the whole agent.

---

## Sources

1. [Create the Hero You Want to Be in World of Warcraft: Forever — Blizzard News](https://news.blizzard.com/en-us/article/24304075/create-the-hero-you-want-to-be-in-world-of-warcraft-forever) — classes, Skyborne, racials, race/class tables.
2. [World of Warcraft: Forever Details Revealed — Inven Global](https://www.invenglobal.com/articles/25897/world-of-warcraft-forever-details-revealed-major-overhaul-for-gear-and-classes) — camping, stats, talents, Paladin overhaul, combat pillars.
3. [WoW Classic+ / Forever announcement — Inven Global](https://www.invenglobal.com/articles/25876/wow-classic-details-announced-titled-world-of-warcraft-forever) — Zephras Isle, beta dates, Skyborne classes.
4. [Skyborne — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Skyborne) — Windshapers / High Order lore and factions.
5. [WoW Forever class changes tracker — LFCarry](https://lfcarry.com/guides/wow-forever-class-changes) — global talent/stat changes, Paladin detail status.
6. [WoW Forever Gear and Stats — MMOJUGG](https://www.mmojugg.com/news/wow-forever-gear-stats.html) — hit/crit merge, healing→damage arithmetic.
7. [Shaman spellbook Forever vs Classic — ForeverChanges](https://foreverchanges.pro/spellbook/shaman) — Fire Nova, totem durations, mana costs, beta build id.
8. [Forever Enhancement Shaman — Icy Veins](https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-guide) — totem GCD, element unlock levels in beta.
9. [Classic Shaman Leveling — Icy Veins](https://www.icy-veins.com/wow-classic/classic-shaman-leveling-guide) — Enh vs Ele, rotation, Ghost Wolf.
10. [Vanilla Shaman Guide — Legacy-WoW](https://legacy-wow.com/vanilla-shaman-guide/) — pull leashing, Flame Shock vs Lightning Shield efficiency.
11. [Charge — Wowhead Classic](https://www.wowhead.com/classic/spell=100/charge) — 8–25 yd, rage on charge.
12. [Arms Warrior Leveling — Icy Veins](https://www.icy-veins.com/wow-classic/arms-warrior-leveling-guide-1-60) — Charge opener, Rend, rage dumping.
13. [Best Classes for Leveling — Wowhead](https://www.wowhead.com/classic/news/best-classes-for-leveling-wow-classic-best-class-tier-list-294562) — hunter/warlock/mage/warrior tier context.
14. [Priest Leveling — Icy Veins](https://www.icy-veins.com/wow-classic/classic-priest-leveling-guide) — wand focus, Shadow respec timing.
15. [Paladin Leveling — Warcraft Tavern](https://www.warcrafttavern.com/wow-classic/guides/paladin-leveling-guide/) — seals, wisdom, judgement loop.
16. [Druid Leveling — Warcraft Tavern](https://www.warcrafttavern.com/wow-classic/guides/druid-leveling-guide/) — pre-10 caster, bear at 10, cat at 20.
17. [Hardest Classes To Level — Blizzard Forums](https://us.forums.blizzard.com/en/wow/t/hardest-classes-to-level/166858) — mana drink patterns, shaman/ele vs enh.
18. [Lightning Shield — Wowhead Classic](https://www.wowhead.com/classic/spell=324/lightning-shield) — mana cost, 5s rule player comments.
19. [WoW Forever Shaman spellbook notes — WoWSoD Pro](https://wowsod.pro/wow-forever/spellbook/shaman) — Totemic Projection 30 yd, Fire Nova behaviour.
20. [Hunter pet delay — Blizzard Forums](https://us.forums.blizzard.com/en/wow/t/hunter-warlock-pet-delay-aggro-range/279822) — pet aggro timing quirk.
21. [Misdirection — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Misdirection) — level 70 Classic requirement context.
22. [Classic WoW Warlock Leveling — YouTube `9dfxA5NK1aQ`](https://www.youtube.com/watch?v=9dfxA5NK1aQ) — soul shard economy (subtitle timestamps vary).
