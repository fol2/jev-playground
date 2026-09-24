# Shaman (Forever beta, levels 1–20)

Shaman-only mechanics. Trust order: **[owner-live]** > Forever client datamine > Forever guides > Forever videos > Classic transfer. Beta cap **20**; ranks and costs above 20 are listed only where they unlock at 20.

Schema shape is the common multiclass block (`resource`, `range_bands`, `pull`, `sustain`, `emergency`, `rest`, `key_abilities`) so other classes can copy it. Numbers that conflict across sources stay in conflicts.md; the schema prefers owner-live where the owner observed the fact, else Forever client 1.60.1.69893.

---

## Class schema

```yaml
schema_version: "1.0"
game_build: "forever-beta"
class: shaman
faction: horde
race: skyborne_windshaper
level_bracket: { min: 1, max: 20 }

resource:
  primary: mana
  secondary: []
  regen_rules:
    - "Mana is the binding resource; owner fights often start at 10-30% mana because melee does most of the damage. [owner-live] owner-demo-play"
    - "Classic 5-second rule (no mana spend for 5s, then Spirit ticks every 2s) is the documented Classic baseline; Forever streams claim continuous regen — see conflicts.md."
    - "Weapon imbues and totems spend mana; Totemic Recall (20) returns 25% of spent totem mana. [forever-client] shaman_class; wowforevertalents"

range_bands:
  preferred_pull_yd: [20, 30]   # slot 2 Lightning Bolt white + slot 3 Earth Shock red [owner-live]
  melee_yd: 5                   # slot 1 Attack [owner-live]
  earth_shock_yd: 20            # slot 3 when trained [owner-live + forever-client]
  lightning_bolt_yd: 30         # slot 2 [forever-client + owner-live]
  nameplate_yd: 40              # no plate beyond this [owner-live]
  healing_wave_yd: 40           # [forever-client]
  safe_kite_yd: [8, 25]         # guide figure; owner does not kite same-speed melee [multiclass_framework]
  dead_zone_yd: null

pull:
  method: spell
  opener_priority: [weapon_buff, lightning_bolt]
  in_combat_opener: [auto_attack, earth_shock]
  observed_owner: "Buff (green glow) → 1-2 Lightning Bolts while the mob closes → melee once in contact; kill ~10-15 s. [owner-live] owner-demo-play; wow-shaman-capabilities"

sustain:
  mana_policy: stingy_on_casts   # spend mana on pull/buff/heal; melee is the filler
  rotation_priority:
    - { ability_id: rockbiter_weapon, condition: "not buffed", notes: "Forever 60 min imbue; owner presses before every fight. [owner-live]" }
    - { ability_id: lightning_bolt, condition: "out of melee and pulling", notes: "One or two bolts; mid-melee bolt is pushback + wasted mana. [owner-live]" }
    - { ability_id: auto_attack, condition: "melee range", notes: "Primary damage at 1-20 Enhancement. [owner-live]" }
    - { ability_id: earth_shock, condition: "interrupt or instant nuke", notes: "Trained at 4; owner L4 bar slot 3 is yellow, likely this. [owner-live + forever-client]" }
    - { ability_id: lightning_shield, condition: "level >= 8 and mana stable", notes: "Trained at 8. [forever-client]" }
    - { ability_id: searing_totem, condition: "level >= 10 and durable/stationary", notes: "Needs Fire Totem relic. [forever-client]" }
    - { ability_id: earthbind_totem, condition: "level >= 6 and kiting or 2+ mobs", notes: "Guide pattern; owner L4 demo does not use it. [forever-client]" }
    - { ability_id: flame_shock, condition: "level >= 10 and full duration will tick", notes: "[forever-client]" }
  filler: auto_attack

emergency:
  defensive_cooldowns:
    - { ability_id: healing_wave, cd_s: 0, triggers: "hp_pct low or post-named-fight", notes: "Owner healed after Malduko (~30% HP, red screen) then drank. [owner-live]" }
    - { ability_id: stoneclaw_totem, cd_s: 0, triggers: "adds or low hp, level >= 8", notes: "Needs Earth Totem relic. [forever-client]" }
  escape_cooldowns:
    - { ability_id: ghost_wolf, cd_s: 0, triggers: "outdoor and level >= 20", notes: "40% speed, 3 s cast, 100 mana; Improved Ghost Wolf talent enables indoor. [forever-client]" }
    - { ability_id: walk_on_air, cd_s: 0, triggers: "fall", notes: "Skyborne racial, ~10 s glide. [forever-guide]" }
  cc:
    - { ability_id: earthbind_totem, target: ground, cd_s: 15, notes: "10 yd slow aura from 6. [forever-client]" }
    - { ability_id: frost_shock, target: enemy, cd_s: 0, notes: "From 20; runners. [forever-client]" }

rest:
  eat: true
  drink: true
  bandage: true
  life_tap: false
  typical_pause_s: [0, 20]       # owner: rare on same-level; ~20 s eat+drink after a hard fight
  camp_synergy: "Forever campfires exist as profession buff objects (unverified IDs). [multiclass_framework]"
  observed_owner: "No 60% mana gate; pull on cost facts. Heal then eat/drink after a hard fight. [owner-live]"

key_abilities:
  - id: attack
    name: Attack
    unlock_level: 1
    range_yd: melee
    cost: { type: none, amount: 0 }
    cast_time_s: 0
    cooldown_s: 0
    gcd_s: 0
    tags: [melee, filler]
    owner_slot: 1
    forever_only: false
  - id: lightning_bolt_r1
    name: Lightning Bolt
    unlock_level: 1
    range_yd: [0, 30]
    cost: { type: mana, amount: 15 }
    cast_time_s: 1.5            # Forever client R1; owner observed ~2 s bar, land ~3.2 s — see conflicts.md
    cooldown_s: 0
    gcd_s: 1.5
    tags: [pull, nuke]
    owner_slot: 2
    forever_only: false
  - id: healing_wave_r1
    name: Healing Wave
    unlock_level: 1
    range_yd: [0, 40]
    cost: { type: mana, amount: 25 }   # Forever client; Classic rank 1 is 35 — see conflicts.md
    cast_time_s: 1.5
    cooldown_s: 0
    gcd_s: 1.5
    tags: [heal]
    owner_slot_l2: 3            # morning M3 OCR
    owner_slot_l4: 8            # evening demo, green; re-verify live
    forever_only: false
  - id: rockbiter_weapon
    name: Rockbiter Weapon
    unlock_level: 1
    range_yd: self
    cost: { type: mana, amount: "ranked" }
    cast_time_s: 0
    cooldown_s: 0
    gcd_s: 1.5
    tags: [imbue, prep]
    owner_slot: 4
    notes: "Instant; 60 min Forever; +49 AP R1 Forever; owner green-glow before every fight."
    forever_only: false
  - id: earth_shock_r1
    name: Earth Shock
    unlock_level: 4
    range_yd: [0, 20]
    cost: { type: mana, amount: 25 }
    cast_time_s: 0
    cooldown_s: 6               # shock family CD cited for agent UI in shaman_class
    gcd_s: 1.5
    tags: [interrupt, instant, nuke]
    owner_slot_l4: 3            # evening demo yellow; re-verify live
    forever_only: false
  - id: stoneskin_totem
    name: Stoneskin Totem
    unlock_level: 4
    range_yd: [0, 30]
    cost: { type: mana, amount: 30 }
    cast_time_s: 0
    duration_s: 300
    tags: [totem, earth, mitigation]
    notes: "Requires Earth Totem relic from Call of Earth."
    forever_only: false
  - id: earthbind_totem
    name: Earthbind Totem
    unlock_level: 6
    range_yd: self
    cost: { type: mana, amount: 17 }   # Classic/framework figure; confirm Forever
    cast_time_s: 0
    cooldown_s: 15
    duration_s: 45
    tags: [snare, totem, earth]
    forever_only: false
  - id: lightning_shield
    name: Lightning Shield
    unlock_level: 8
    range_yd: self
    cost: { type: mana, amount: "ranked" }
    duration_s: 600             # 10 min on trainer readout in videos_low
    tags: [buff]
    forever_only: false
  - id: flame_shock
    name: Flame Shock
    unlock_level: 10
    range_yd: [0, 20]
    tags: [dot, instant]
    forever_only: false
  - id: searing_totem
    name: Searing Totem
    unlock_level: 10
    tags: [totem, fire, dps]
    notes: "Requires Fire Totem relic from Call of Fire."
    forever_only: false
  - id: fire_nova
    name: Fire Nova
    unlock_level: 12
    range_yd: [0, 30]
    cooldown_s: 10              # Forever client; Tiqqle said 6 s — see conflicts.md
    tags: [aoe]
    notes: "Instant pulse around an active fire totem, ~10 yd from that totem."
    forever_only: true
  - id: ghost_wolf
    name: Ghost Wolf
    unlock_level: 20
    cost: { type: mana, amount: 100 }
    cast_time_s: 3
    tags: [travel]
    notes: "40% speed; tooltip outdoors; Improved Ghost Wolf talent allows indoor."
    forever_only: false
  - id: frost_shock
    name: Frost Shock
    unlock_level: 20
    tags: [snare, instant]
    forever_only: false
  - id: call_of_the_elements
    name: Call of the Elements
    unlock_level: 20
    tags: [totem_manage]
    notes: "Places up to four bar-configured totems."
    forever_only: true
  - id: totemic_recall
    name: Totemic Recall
    unlock_level: 20
    tags: [totem_manage]
    notes: "Destroys totems and refunds 25% of their mana cost."
    forever_only: true

racial:
  - { id: walk_on_air, effect: "glide ~10 s, fall-safe", tags: [fall_safe] }
  - { id: skysight, effect: "+10% run/mount speed; 30 s default, 15 min near elemental convergence; not in combat", tags: [mobility] }
  - { id: wind_blessed, effect: "+1% haste", tags: [passive] }
  - { id: elemental_insight, effect: "+5% damage vs elementals", tags: [passive] }
```

---

## Spells by level (1–20, beta cap)

- Lightning Bolt R1 is a starter spell: 15 mana, 1.5 s cast, 30 yd on Forever client 1.60.1.69893. [forever-client] shaman_class; wowforevertalents
- Healing Wave R1 is a starter spell: 25 mana, 1.5 s cast, 40 yd on Forever client. [forever-client] shaman_class; wowforevertalents
- Rockbiter Weapon R1 is a starter imbue: 60 min duration, +49 AP Forever. [forever-client] shaman_class
- Lightning Bolt further ranks in the 1–20 band: R2 at 8, R4 at 20 (R3 at 14). [forever-client] shaman_class
- Healing Wave further ranks in the 1–20 band: R2 at 6, R3 at 12, R4 at 18. [forever-client] shaman_class
- Earth Shock R1 trains at 4 (20 yd, instant); R2 at 8. [forever-client] shaman_class
- Stoneskin Totem R1 trains at 4: 30 yd, 5 min, 30 mana, and requires the Earth Totem relic. [forever-client] shaman_class
- Earthbind Totem trains at 6: 45 s duration, 10 yd slow aura, 15 s cooldown. [forever-client] shaman_class; videos_low `ThVlyymiLfI` 01:37:49
- Stoneclaw Totem R1, Lightning Shield R1, Lightning Bolt R2, Earth Shock R2, and Rockbiter R2 train at 8. [forever-client] shaman_class
- Lightning Shield duration was read as 10 minutes on a Forever trainer tooltip. [video-forever] videos_low `ThVlyymiLfI` 01:52:33
- Flame Shock R1, Searing Totem R1, Flametongue Weapon R1, and Strength of Earth Totem R1 train at 10 and need the Fire Totem relic. [forever-client] shaman_class
- Fire Nova R1 trains at 12: instant, 30 yd to the fire totem, 10 s cooldown; it is a spell, not a totem. [forever-client] shaman_class; foreverchanges.pro
- Purge R1, Healing Wave R3, and Ancestral Spirit R1 also train at 12. [forever-client] shaman_class
- Cure Poison, Rockbiter R3, and Lightning Shield R2 train at 16. [forever-client] shaman_class
- Tremor Totem (30 yd, 5 min Forever), Stoneclaw R2, Flame Shock R2, and Healing Wave R4 train at 18. [forever-client] shaman_class
- Ghost Wolf (40% speed, 3 s, 100 mana, outdoors tooltip), Frost Shock R1, Call of the Elements, Totemic Recall, Healing Stream Totem R1, Lesser Healing Wave R1, Lightning Bolt R4, Searing Totem R2, Frostbrand Weapon R1, and Rockbiter R4 train at 20 with the Water Totem relic. [forever-client] shaman_class
- Chain Lightning is **not** in the 1–20 kit (trainer 32). [forever-client] shaman_class
- Owner live OCR (level 2, morning): slot 1 Attack, slot 2 Lightning Bolt (~2 s cast bar, landed ~3.2 s at range), slot 3 Healing Wave (healed to 100%), slot 4 weapon buff (instant, costs mana, no health change). [owner-live] wow-shaman-capabilities
- Owner live bar (level 4, evening demo): 1 Attack, 2 Lightning Bolt, 3 new yellow (likely Earth Shock), 4 weapon buff, 8 green (likely Healing Wave), 9 Skysight, 0 water, − bread, = meat — re-verify live. [owner-live] owner-demo-play
- One owner fight of 3 bolts + heal + buff took mana from ~87% to ~20%. [owner-live] wow-shaman-capabilities
- One Lightning Bolt on a level-1 Juvenile Vuldren was ~35% of its health; another bolt did ~1% (likely a miss). [owner-live] wow-shaman-capabilities
- Multi-rank Healing Wave and Earth Shock on the bar (low rank for mana, high rank when needed) is a Forever-stream mana habit from the teens upward. [video-forever] videos_low `bm4xGcBj-DQ` 01:28:02; videos_mid `eZQGn3iUi3g` 2:32–2:39

---

## Totems and relic quests

- Shamans use a ranged Totem relic slot; four totem **items** (Earth, Fire, Water, Air) must stay in bags to cast that element’s totems. [forever-guide] shaman_class; Wowhead Forever class=7
- Only one active totem per element at a time. [forever-guide] shaman_class
- Totem attunement gates: Earth ~4, Fire ~10, Water ~20, Air ~30. [forever-guide] shaman_class; Warcraft Tavern dwarf totem quests
- Windshaper Call of Earth is a 3-part chain via Windshaper Boro (42.8, 23.6): 92466 Signet of Akir drop → 92467 drink Earth Sapta at Rise of Spirits (manifestation 49.6, 24.0) → 92468 deliver Rough Quartz; completes the earth rite and enables Earth totems. [forever-guide] zephras_walkthrough
- Owner at level 4 planned Call of Earth (Signet of Akir, Al'Aketh) in the same grove loop as Ursera quests. [owner-live] owner-demo-play
- Embracing the Elements (92484) is the level-2 class intro (Humming Recall Crystal → Boro). [forever-guide] zephras_walkthrough
- Skyborne Call of Fire: defeat Kuramaa in Shen'dar Highlands for a mask (97245), then ritual with Olariaan Swiftburn and a timed torch run to Valanaar (97257) for Fire Totem + Searing Totem. [forever-guide] shaman_class; Wowhead 97245 / 97257
- Water and Air Forever walkthroughs were unpublished at research time; Classic Horde Call of Water / Call of Air are the unverified templates. [unverified] shaman_class
- Forever totems are often 30 yd and 5 min (Classic 20 yd / 2 min). [forever-client] shaman_class; wowforevertalents
- Totemic Recall (20) destroys totems and refunds 25% of their mana; Totemic Projection (22) relocates active totems 30 yd. [forever-client] shaman_class — Projection CD/cost conflict in conflicts.md
- Refreshing a totem may despawn existing totems. [video-forever] videos_low `bm4xGcBj-DQ` 03:31:20
- Totems can pull aggro; fire totems placed on patrol paths will add packs. [video-forever] stream_techniques IWhilIN2R1A 0:11:33, 0:31:11
- Fire Nova requires an active fire totem and enemies within ~10 yd of **that totem**, not of the player. [forever-client] shaman_class; foreverchanges.pro; Icy Veins Elemental Forever

---

## Weapon enchants

- Forever weapon imbues last **60 min** (Classic 5 min). [forever-client] shaman_class; foreverchanges.pro
- Rockbiter is the default Enhancement leveling imbue (threat + AP); owner applies the green-glow buff before every fight. [owner-live + forever-client] wow-shaman-capabilities; shaman_class
- Flametongue Weapon trains at 10 (extra fire per swing by weapon speed). [forever-client] shaman_class
- Frostbrand Weapon trains at 20 (frost + slow; situational vs runners). [forever-client] shaman_class
- Windfury Weapon trains at **30** (20% extra-attack chance) — outside the beta-20 cap. [forever-client] shaman_class
- Some Forever streams claim imbues now scale with spell power. [video-forever] stream_techniques IWhilIN2R1A 0:29:42
- Two-Handed Axes and Maces talent is **removed** from the Forever Enhancement tree; whether 2H is baseline is contradictory (see conflicts.md). [forever-guide] shaman_class; zockify; Wowhead
- No dual wield in the BlizzCon demo write-up; a Tiqqle caption claims a Dual Wield quest at level 4 (see conflicts.md). [forever-guide + video-forever] shaman_class; stream_techniques IWhilIN2R1A 0:35:49

---

## Pull / fight / finish (videos and demo)

- Owner rhythm: select at range (large white-outline plate) → weapon buff → one or two Lightning Bolts while it closes → melee (Main Hand swing bar) on contact → kill ~15 s (demo fights averaged ~10 s) → auto-loot → move on. [owner-live] owner-demo-play
- Owner does not mid-fight hard-cast once the mob is in melee, because casts are pushed back or interrupted. [owner-live] wow-shaman-capabilities; owner-demo-play tabletop
- A Lightning Bolt in melee wastes its mana share (~15% of the bar in the tabletop fact) and eats the swing. [owner-live] owner-demo-play
- A caster that stays at range and trades bolts spends your mana while its bolts hit you. [owner-live] owner-demo-play
- Facing must match the mob: “You are facing the wrong way!” appeared in the cave while other players were present; the owner turned and continued. [owner-live] owner-demo-play
- Grey tapped plates are skipped even in a multi-player cave. [owner-live] owner-demo-play
- Enhancement community pull (guides): optional Lightning Bolt as **pull only**, then Earthbind kite from 6, Flame Shock / Earth Shock, Searing on durable targets. [forever-guide] shaman_class; wowforeverbuilds; Warcraft Tavern Classic
- Zerocks (Skyborne, Zephras, fire-totem video): Lightning Bolt from ~25–35 yd → Searing Totem → close to melee; fights 15–25 s; sit 20–40 s every 2–3 kills; heal when below ~50%. [video-forever] zerocks_frames
- Zerocks part 1 (levels 1–2): bolt-only pulls, 5–8 s kills, full health, **no sit/eat/drink**; mana recovered by walking; skipped contested tags; a “Miss” did not change target. [video-forever] z1_part1_techniques
- Zerocks part 2 (to level 3): mixed melee-first and short bolt; chained kills at full health with no food; on-path “?” turn-in in ~4 s. [video-forever] z1_part2_techniques
- Forever tank clip (teens): fire totem → Fire Nova for pack snap → Earth Shock on primary; Lightning Shield before pulls; mana is the tank limiter. [video-forever] videos_mid `eZQGn3iUi3g` 1:18–2:44

---

## Mana, talents 10–20 (Enhancement), racials, Forever deltas

- Community Enhancement 10–20 is `0/11/0`: Thundering Strikes 5/5 (10–14, +5% crit), Improved Ghost Wolf 2/2 (15–16, faster cast + indoor wolf), Mental Dexterity 3/3 (17–19, ~99% Intellect → Attack Power), Shamanistic Focus 1/1 (20, −45% mana on Shocks and Lightning Shield). [forever-guide] shaman_class; wowforeverbuilds beta-20; Icy Veins Enhancement Forever
- Elemental 10–20 alternative is `11/0/0` (Concussion → Call of Flame → Warding/Convection → Elemental Focus); more drinks than Enhancement. [forever-guide] shaman_class; Leprestore
- Lava Burst is a 40-point Elemental talent — not in the 1–20 kit. [forever-guide] shaman_class
- Owner intent: drop a 60% mana gate in favour of cost facts; melee carries same-level kills. [owner-live] owner-demo-play
- Skyborne Walk on Air is a ~10 s glide and is the Falling with Style (92474) racial tutorial (jump from Myriaal’s tower 43.6, 24.0). [forever-guide] zephras_walkthrough; multiclass_framework; Icy Veins Skyborne
- Skyborne Skysight is +10% move/mount speed (30 s, or 15 min near an elemental convergence) and is not usable in combat; owner bound it to slot 9. [forever-guide + owner-live] icy-veins Skyborne; owner-demo-play; Blizzard Meet the Skyborne
- Skyborne Wind Blessed is +1% haste; Elemental Insight is +5% versus elementals. [forever-guide] shaman_class; Blizzard; Icy Veins
- Forever Shaman deltas vs Classic Era: squished spell numbers, 60 min imbues, 30 yd / 5 min totems, Fire Nova as an instant around the fire totem, Call of the Elements / Totemic Recall / Totemic Projection, Enhancement loses Two-Handed Axes and Maces and Shield Specialization, Tranquil Air Totem absent. [forever-client] shaman_class; foreverchanges.pro; zockify
- Totem drop GCD is cited as 1.0 s in Forever Enhancement guides (Classic 1.5). [forever-guide] multiclass_framework; Icy Veins Forever Enhancement
- Spell Power on weapons and healing-stat → +⅓ spell damage are Forever globals that make hybrid shaman gear deal damage. [forever-guide] multiclass_framework; Inven; MMOJUGG
- Owner client is `_classic_beta_` with Issue Reporter and Defense skill; Click-to-Move ON; F is Assist Target so Interact With Target was left unbound (later F9 with consent). [owner-live] wow-shaman-capabilities

---

## Count

43 facts after the schema (schema is the copy-shape, not counted).
