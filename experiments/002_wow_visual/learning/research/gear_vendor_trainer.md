# Gear, vendor, and trainer decisions (WoW: Forever, levels 1–20)

> **Candidate research, not engine policy.** Nothing here runs until a trainer, vendor or gear slice adopts a rule
> with its own consumer and tests. The imperative wording below is the report's; read every rule as a proposal.

Read-only decision knowledge for a screen reader and a decision graph. The reader OCRs tooltips, bags, the vendor window, the character panel, the spellbook, and the trainer window. The graph may only pick an option that passes the gates below. A script afterwards checks the effect (money, bag count, durability, spellbook). It does not decide.

Scope: solo questing, levels 1–20, on the 2026 Forever client. The worked weights are for a **caster/melee hybrid shaman** (Lightning Bolt to pull, melee to kill, Healing Wave to recover), which is the Skyborne Windshaper pattern in the local notes. Another class reuses section 1 and replaces section 2.

Numbers the client prints win over this file. Forever is still in beta; Blizzard’s own recap says item values can change. Where a Classic 1.12 rule is the only public rule and Forever has not announced a change, it is marked **Classic baseline**. A rule with no source is marked **inference**.

Local context, not treated as a client observation: `learning/knowledge/shaman.md`, `learning/knowledge/general.md`, `learning/research/leveling_fundamentals.md`, `learning/research/multiclass_framework.md`, `learning/skyborne_training.md`.

---

## 0. What the reader must return

Money is one integer in copper (1 silver = 100, 1 gold = 10,000). A missing field is `null`, not zero. Red requirement text is its own boolean; it overrides a parsed number.

| Field | Where | Used by |
| --- | --- | --- |
| `name`, `quality` (poor / common / uncommon / rare / epic) | tooltip name colour | sell, score |
| `bind` | Soulbound, Binds when picked up, Binds when equipped, Quest Item | gates, sell |
| `slot` | Head, Neck, Shoulder, Back, Chest, Wrist, Hands, Waist, Legs, Feet, Finger, Trinket, Main Hand, Off Hand, Two-Hand, Ranged, Shirt, Tabard | which equipped piece it replaces |
| `armor_class` | Cloth, Leather, Mail, Plate, Shield, or empty for cloak/jewelry | shaman gate |
| `weapon_type` | Mace, Axe, Staff, Dagger, Fist Weapon, Sword, Polearm, Bow, Gun, Crossbow, Wand, Thrown, Off-hand, Shield | shaman gate |
| `hands` | 1H or 2H | whether the off-hand is emptied |
| `damage_min`, `damage_max`, `speed`, `weapon_dps` | the white-hit block, “X.X damage per second” | score |
| `bonus_str/agi/sta/int/spi`, `attack_power`, `armor` | “+N Strength” and the Armor line | score |
| `spell_damage`, `healing`, `mp5` | see the two different sentence shapes in §2.2 | score |
| `hit_pct`, `crit_pct` | percent lines; usually absent at 1–20 | score |
| `req_level` | “Requires Level N” | gate |
| `classes` | “Classes: …” or empty | gate |
| `durability`, `durability_max` | “Durability A/B” | repair |
| `sell_price` | “Sell Price” | vendor |
| `red_requirement` | any red line on the tooltip | gate; fail closed |
| `unit_price`, `stack_count` | vendor row | buy |
| `repair_all_price` | Repair All button | repair |
| `trainer_row` | spell name, rank, copper price, already-known | train |
| `spellbook_rank` | highest rank of that name in the spellbook | confirm learn |
| `weapon_skill`, `weapon_skill_max` | character Skills pane | weapon swap |
| `mental_dexterity_rank` | talent pane, 0 if the row is empty | intellect weight |

**Unreadable is not a negative.** If `quality` or `name` is null, do not sell and do not equip. If a weapon’s `weapon_dps` parsed and the stat lines are simply absent, a weapon may be scored on DPS alone. If a stat line is present but garbled, `value` is null and the item is not chosen.

---

## 1. Class-agnostic rules

These apply to every class. Section 2 only fills the shaman gates and the weights.

### 1.1 Admissibility gates (before any score)

An item is inadmissible when any line is true. Inadmissible items are not equipped and are not picked as a quest reward if any admissible option or a coin reward exists.

1. `red_requirement` is true. Red wins even if the parsed level or class looks legal. **Source:** client tooltip behaviour, Classic baseline.
2. `req_level` is null, or `req_level` > player level. Item level is not required level.
3. `classes` is non-empty and does not list this class.
4. The class profile marks `armor_class` or `weapon_type` illegal at this level (§2.1 for shaman).
5. `bind` is Quest Item. Quest items are not gear. **Source:** [Warcraft Wiki — Quest item](https://warcraft.wiki.gg/wiki/Quest_item): the tooltip says “Quest Item”; those items cannot be sold or traded.
6. Slot is Shirt or Tabard. They equip but do not enter the score.

`bind` of Soulbound, Binds when picked up, or Binds when equipped does **not** by itself make an item illegal. It changes what a bad choice costs:

- **Binds when picked up.** Choosing it on a reward window binds it. If it is inadmissible, the only recovery is the vendor sell price. Do not pick it when an admissible piece or coins exist.
- **Binds when equipped.** Safe in the bag. Binding happens at the equip click. Do not equip an inadmissible BoE.
- **Soulbound.** Already ours. It can still be the equipped baseline, or be sold if it is not a quest item and not the Hearthstone. It cannot be traded.

### 1.2 Scoring skeleton

Score only an admissible item whose required fields parsed.

```
value =
    W_dps  * weapon_dps          # 0 if the slot is not a weapon
  + W_ap   * attack_power
  + W_str  * strength
  + W_agi  * agility
  + W_sta  * stamina
  + W_int  * intellect
  + W_spi  * spirit
  + W_spd  * spell_damage        # after the healing rule in the class profile
  + W_heal * healing
  + W_mp5  * mp5
  + W_arm  * armor
  + W_hit  * hit_pct
  + W_crit * crit_pct
```

Compare **sets**, not naked tooltips.

- A one-hand weapon replaces Main Hand only. A shield or off-hand replaces Off Hand only.
- A two-hand or a staff replaces Main Hand **and** Off Hand. `value(staff)` must beat `value(main hand) + value(off hand)`. An empty hand scores 0.
- Rings and trinkets: the candidate replaces the weaker of the two occupied slots. If one slot is empty, it fills the empty slot.
- Upgrade if `value(candidate set) > value(current set) + 1`. The +1 stops a swap on OCR noise. **Inference** (the epsilon, not the comparison).

`weapon_dps` is the tooltip’s “damage per second”, not `(min+max)/2`. Do not treat the white-hit “12–18 Damage” line as spell damage.

### 1.3 Quest reward choice

Forever rewrote rewards so more roles have a choice. A remembered Classic reward is not evidence. **Source:** [Blizzard, Forever Deep Dive recap, 13 Sep 2026](https://worldofwarcraft.blizzard.com/en-us/news/24303313/world-of-warcraft-forever-deep-dive-panel-recap): “Quest rewards have also been updated or expanded to support more classes and roles.”

When the reward window is open:

1. Score every choice that passes §1.1. Drop the rest.
2. If any admissible choice has set-delta > 1, take the largest delta.
3. Else if the window offers coins as a choice, take the coins.
4. Else take the admissible item with the highest `sell_price` (it will be vendored on the next vendor stop).
5. If every item failed the gates, take coins if offered. If the only choices are inadmissible items, take the highest `sell_price`. A bind-on-pickup mistake is limited to that sell price; do not take a null `sell_price` over a known one.
6. If any chosen row has a null name, stop and leave the window open. Do not click.

**Stash for a later level (inference).** Only when `req_level` ≤ player+2, the item would beat the current set by more than 14 value points (about +1 weapon DPS), free bag slots ≥ 4, and no currently wearable upgrade is on the same window. Otherwise a too-high level is not a reason to skip a usable piece.

### 1.4 Vendor: what to sell

Do this before buying. Each successful sell of one item (or one stack) must show **money up by `sell_price × count`** and **that stack’s count down by the amount sold**. If money does not move, the sell did not happen; do not click again.

| Sell | Condition | Effect to verify |
| --- | --- | --- |
| Poor (grey) | `quality = poor` and `bind` is not Quest Item | money += sell price; bag count -= n |
| Replaced gear | in bags, not equipped, admissible or previously equipped, `value` ≤ equipped value in that slot, not a saved second weapon, not a class-profile keep (totems, §2.4) | same |
| Old food or drink | a lower rank of food or drink than the rank we can legally use now, and the higher rank is already in the bags | money += sell price; old stack → 0 |

Do not sell white items as a class. A white weapon is often the upgrade at levels 1–20 (§2.4).

### 1.5 Vendor: never sell

If a sell click on these leaves money unchanged, that is the correct effect. Stop.

| Never sell | How the reader tells | Why |
| --- | --- | --- |
| Quest Item | tooltip says Quest Item | Cannot be sold ([Warcraft Wiki](https://warcraft.wiki.gg/wiki/Quest_item)). Deleting one can drop the quest; do not delete to “test”. |
| Items named in the quest log | bag name matches a quest objective line, even with no Quest Item tag | The wiki notes many quest objects are not tagged Quest Item. **Source:** same page. |
| Hearthstone | name Hearthstone | No sell price. Classic baseline. An innkeeper replaces a destroyed one; do not destroy it. |
| Equipped gear | character panel slot holds it | Selling it is a separate unequip. Never do that inside a “sell junk” pass. |
| Current upgrades | in bags, set-delta > 1, not yet equipped | Equip them; do not vendor them. |
| Unreadable rows | `name` or `quality` is null | Fail closed. |
| Consumables in use | the food, drink, bandage, and potion stacks on the action bar, plus the reserve in §1.6 | Using them is the point of buying them. |
| Buff food | tooltip grants a timed stat or “well fed” effect | Forever crafted food can grant a small experience bonus and stats. **Source:** [Blizzard recap](https://worldofwarcraft.blizzard.com/en-us/news/24303313/world-of-warcraft-forever-deep-dive-panel-recap), Camping and Professions. Vendor rations do not. |

### 1.6 Food and water

**When.** At a vendor who lists food or drink, out of combat, before leaving town. Also when the reserve below is not met and this vendor sells the rank.

**Which rank.** The highest rank whose required level ≤ player level and whose tooltip is not red. Never buy the next rank early.

Classic vendor ladder. Prices are the per-item buy price from ClassicDB’s Jaeana (Darnassus meat vendor) and the Warcraft Wiki classic meat table. **Forever may change them; pay the vendor row’s `unit_price`.** Restore amounts are Classic and must be read off the tooltip (Refreshing Spring Water is 151 mana over 18 seconds on older Classic pages and has been printed as 180 on later ones).

| Player level | Drink | Req | Each | Food of the same tier | Each |
| --- | --- | --- | --- | --- | --- |
| 1–4 | Refreshing Spring Water | 1 | 25c | Tough Jerky, or bread/cheese at 25c | 25c |
| 5–14 | Ice Cold Milk | 5 | 1s 25c | Haunch of Meat | 1s 25c |
| 15–20 | Melon Juice | 15 | 5s | Mutton Chop | 5s |

**Sources:** [ClassicDB Jaeana](https://classicdb.ch/?npc=4169) (Refreshing Spring Water 25c, Ice Cold Milk req 5 at 1s 25c, Melon Juice req 15 at 5s, Tough Jerky 25c, Haunch of Meat req 5 at 1s 25c, Mutton Chop req 15 at 5s); [Warcraft Wiki vendor template, meat classic](https://warcraft.wiki.gg/wiki/Template:Vendors); [Wowpedia — Drink](https://wowpedia.fandom.com/wiki/Drink). Stack size 20: [Warcraft Wiki — Refreshing Spring Water](https://warcraft.wiki.gg/wiki/Refreshing_Spring_Water).

**How many (inference on the counts, prices sourced above).**

- Target when the budget allows: **20 drink** (one stack) and **10 food**.
- Hard floor: **10 drink** and **5 food**. Do not leave town under the floor if `unit_price` fits the budget.
- Do not buy a second stack. Stop early if free bag slots < 2.
- Mana users spend the drink budget before the food budget. Classes with no mana skip drink.

**Budget, in order.** Let `reserve` be the Repair All price if any equipped piece is damaged, else 0. Let `train` be the sum of trainer rows this stop will actually buy (§1.8). Buy only while:

`money − reserve − train − (units × unit_price) ≥ 0`

after the planned purchase. One stack of Melon Juice is 1 gold at the Classic price (20 × 5s). One stack of Ice Cold Milk is 25 silver. One stack of spring water is 5 silver.

**Effect to verify.** Money down by `units × unit_price`. That item’s bag count up by `units`. A mismatch means the buy mis-clicked; do not buy the same row again until the bag is re-read.

### 1.7 Repair

**When.**

- Any equipped durability is 0 (the piece contributes nothing). Repair before leaving, and before buying food if the Repair All price is known.
- Or any equipped piece is below its maximum and a repair button is on this vendor, and `repair_all_price` ≤ money.
- Forever campfires can expose a repair vendor. **Source:** [Blizzard recap](https://worldofwarcraft.blizzard.com/en-us/news/24303313/world-of-warcraft-forever-deep-dive-panel-recap): a Basic Campfire can grant vendors and repairs. The same button check applies. Do not assume a campfire exists.

Death removes 10% durability from **equipped** gear only. **Source:** local `leveling_fundamentals.md` §13, citing [Warcraft Wiki — Death](https://warcraft.wiki.gg/wiki/Death_(gameplay)). That is why a town stop repairs even when nothing is broken yet.

**Effect to verify.** Money down by exactly `repair_all_price`. Every equipped slot that was repaired reads `durability == durability_max`. If money moves and a slot stays at 0, stop; do not buy gear until that slot is understood.

If `repair_all_price` > money, repair the weapon first (a broken weapon has no damage), then chest and legs. **Inference** on that order. Verify each click: money down, that slot’s durability up.

### 1.8 Trainer

**When a visit is due.** Classic trainers offer new ranks on even levels, starting at level 4, plus whatever level-1 spells are not granted for free. **Source:** [Wowhead — Classic shaman trainers](https://www.wowhead.com/classic/guide/wow-classic-shaman-class-trainer-locations): “trainers present new abilities every other level on the even-numbered levels starting with level 4.” The same page says starter-zone trainers often stop at level 6. Icy Veins repeats the two-level cadence for Forever Enhancement. **Source:** [Icy Veins — Forever Enhancement](https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-guide), leveling section.

Rules:

- Set `visit_due` when the player level is even and greater than `last_trained_level`, or when a level-1 class spell is missing from the spellbook.
- Satisfy `visit_due` at the next trainer in a hub we are already visiting. Do not cross a zone only for a **rank number** increase.
- A spell **name that is absent from the spellbook** and whose level ≤ player level is not optional. Buy it before leaving the hub if the row is on this trainer.
- You do not have to buy every row. **Source:** the same Wowhead page: “You don’t have to buy all spells or abilities.”

**Cost versus money.** Read each row’s copper price. Ignore any copied price table if it disagrees with the row. Wowhead’s shaman table is real but this fetch could not read the money icons, so the units below are **inference** from the bare numbers plus the Earth Shock rank 1 page, which prints “Training cost: 1” at level 4 ([Wowhead Classic spell 8042](https://www.wowhead.com/classic/spell=8042/earth-shock)). Neutral/Friendly base, per spell of that level, inferred unit:

| Spell level | Inferred Classic price per row |
| --- | --- |
| 1 | 10 copper |
| 4 | 1 silver |
| 6 | 1 silver |
| 8 | 2 silver |
| 10 | 4 silver |
| 12 | 8 silver |
| 14 | 9 silver |
| 16 | 18 silver |
| 18 | 20 silver |
| 20 | 22 silver |

A level-20 visit is several rows, so it can pass 1 gold and rival a stack of Melon Juice. Honored reputation discounts the row; the row already shows the discount. Forever prices are unverified against this table.

**Buy order when the sum does not fit** after `reserve` and the drink floor (10 of the current water):

1. Any row whose spell **name** is missing from the spellbook.
2. The highest rank of the class’s main heal, then its main damage spell.
3. Everything else.

Skip the rest rather than spending the repair or the drink floor. Rank-ups can wait for the next hub.

**Starter trainer cap.** If player level ≥ 8 and this trainer shows no row at or below the player level, do not clear `visit_due`. Classic 1–5 zone trainers stop at level 6 (Wowhead, above). A higher trainer is a different NPC.

**How to confirm a spell was learnt.**

1. Read money and the spellbook rank **before** the click.
2. Click one row.
3. Success is all of: money down by that row’s price; spellbook shows that name at that rank; the trainer row is no longer buyable.
4. The action bar is not the proof. Classic does not place a new spell on the bar by itself. An unchanged bar does not mean the learn failed. A rank-up keeps the same icon; the bar tooltip’s rank changes only if that slot is updated later. **Inference** from Classic trainer behaviour, consistent with Wowhead describing a paid trainer rather than Retail’s automatic grant.
5. If money fell and the spellbook did not show the rank, stop. Re-read the book before buying another row. Do not buy the same row twice.
6. If money did not fall, the click did not train.

Talent points are not trainer rows. The first point is at level 10 and shows on the talent pane, with no money delta. **Source:** [Blizzard recap](https://worldofwarcraft.blizzard.com/en-us/news/24303313/world-of-warcraft-forever-deep-dive-panel-recap) keeps the Classic talent structure; local shaman notes put the first point at 10.

### 1.9 Town-stop order

One vendor session, then the trainer if it is a different window:

1. Sell §1.4. Check money and bag deltas.
2. Repair §1.7 if the button exists. Check money and durability.
3. Train §1.8. Check money and spellbook.
4. Class-profile weapon buy, if any (§2.4).
5. Drink to target, then food. Check money and counts.

If a delta does not match, stop the session and rescan. Do not repeat the last click.

---

## 2. Shaman profile (Skyborne hybrid, levels 1–20)

### 2.1 What this shaman may wear

**Armor.** Cloth and leather from level 1. Mail is a trainer skill at level 40 in Classic, so it is illegal for this whole band. Plate is illegal. Cloaks, necks, rings, and trinkets have no armor class and are legal. Shields are legal in the off-hand.

**Sources:** [Warcraft Tavern — Classic shaman](https://www.warcrafttavern.com/wow-classic/guides/shaman/) (“Cloth and Leather from level 1”, “Mail at level 40 from their class trainer”); [Warcraft Wiki — Shaman abilities (Classic)](https://warcraft.wiki.gg/wiki/Shaman_abilities_(Classic)) lists Mail at 40, trainer. Forever has not announced an earlier mail skill. A mail tooltip at levels 1–20 should also be red; if the armor word parsed as mail, reject it even when the red line was missed.

**Weapons, Classic defaults.** One-handed maces, staves, and unarmed are known at creation. Shields and off-hand frills are usable. One-handed axes and daggers are weapon-trainer skills at level 10, 10 silver each, in a capital. **Source:** [Wowhead — Classic shaman weapons](https://www.wowhead.com/classic/guide/wow-classic-best-shaman-weapons).

**Not usable.** Swords (one- and two-hand), polearms, bows, guns, crossbows, wands, thrown weapons. Dual wield is not available: the off-hand is a shield or an off-hand item, never a second weapon. **Sources:** the same Wowhead page; Forever demo write-ups that a level-38 BlizzCon build had no dual wield ([Zockify](https://www.zockify.com/forever/shaman/), [WoWSource](https://wowsrc.com/classes/shaman/)).

**Two-handed axes and maces.** In Classic they require the Enhancement talent Two-Handed Axes and Maces, which Forever’s talent lists remove. Several Forever write-ups treat them as baseline ([Zockify](https://www.zockify.com/forever/shaman/), [WoWSource](https://wowsrc.com/classes/shaman/)). [wowclassicforever.info](https://wowclassicforever.info/classes/shaman/) says it is still unclear. **Rule for the graph:** if the tooltip is not red, score the two-hander. If it is red or the weapon type line says the skill is unlearned, it is inadmissible. Do not spend a talent or 10 silver on a hunch. Staves need no extra skill and already occupy both hands, so a staff is the early two-hander either way.

**Weapon skill gate (Classic baseline).** Tooltip DPS assumes the weapon skill is near the cap, which is `5 × level`. A type you have not been hitting with can sit far below that cap, and misses erase the paper DPS. **Inference on the cutoff:** reject the swap when the Skills pane shows that weapon type more than 5 points under `5 × level`, unless the plan is to skill it on grey mobs. Maces and staves used all the way up do not hit this gate. A newly trained axe does.

Skyborne has no Orc axe bonus and no Dwarf mace bonus. Do not add one.

### 2.2 Stats that move this hybrid

Melee is most of the damage at 1–20. Bolts and shocks are the pull and the interrupt. Healing Wave is the heal. Weights follow that split.

**Sourced conversions**

| Tooltip stat | Effect on this shaman | Source |
| --- | --- | --- |
| 1 Strength | 2 attack power | [Vanilla WoW Archive — Attributes](https://vanilla-wow-archive.fandom.com/wiki/Attributes); restated for Forever by [Icy Veins](https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-guide) |
| 1 Agility | melee crit and dodge, **no** attack power | Icy Veins, same page. Vanilla archive gives AP-from-agility to rogues and hunters, not shamans. |
| 1 Stamina on gear | 10 health | [Vanilla WoW Archive — Attributes](https://vanilla-wow-archive.fandom.com/wiki/Attributes). The archive’s “first 20 stamina give 1 health” is starting stamina already inside base health. Do not apply it to “+N Stamina” on an item. |
| 1 Intellect | 15 mana, plus spell crit | Same archive; Icy Veins restates 15 mana. |
| Intellect → attack power | 0 until the talent pane shows Mental Dexterity. Rank 1/2/3 = 33% / 67% / 100% of intellect as attack power | [wowforevertalents.com — Mental Dexterity](https://wowforevertalents.com/shaman/talents/mental-dexterity), client build 1.60.1.70009; Icy Veins describes the rank-3 effect. Do not assume the talent from level alone. |
| 14 attack power | +1 melee DPS | Classic melee formula, used here so weapon DPS and strength share a scale. **Inference** only in the sense that Forever has not republished the constant; Icy Veins still treats weapon DPS as the melee stat. |
| Spirit | mana regen outside the five-second rule, and out-of-combat health regen | Icy Veins: “a luxury” at the level-20 cap. Local notes still disagree on whether Forever regen is the Classic five-second rule; spirit stays a small weight either way. |

**Forever globals (every class, applied here)**

- Hit chance is one stat for melee, ranged, and spells. Crit chance is one stat the same way. Enhancement is named as a beneficiary. **Source:** [Blizzard recap](https://worldofwarcraft.blizzard.com/en-us/news/24303313/world-of-warcraft-forever-deep-dive-panel-recap). Icy Veins (21 Sep 2026) says hit and expertise are **not on beta gear yet**. A missing hit line is normal at 1–20, not an OCR failure. If a percent is printed, the weights below count it.
- “Bonus healing now also includes one third as much bonus damage.” **Source:** the same Blizzard paragraph. The panel’s Hide of the Wild example is +42 healing and +14 damage (42/3 = 14). **Source for the example, not for the rule:** [Output Lag, 13 Sep 2026](https://outputlag.com/news/world-of-warcraft-forever-unifies-hit-and-crit-stats-and-gives-healing-gear-bonus-damage/), quoting the Deep Dive slide. Spell damage does **not** grant healing. The sentence is one direction.
- Caster weapons grant spell damage and healing, so a weapon is no longer only a melee tool. **Source:** Blizzard recap, same section. Output Lag quotes the designer that this reaches “all the way down to level 10.” That level floor is **not** in the official recap wording. Below level 10, a weapon with no spell-power line is complete, not unreadable.

**Do not double-count healing.**

| What the tooltip says | `spell_damage` | `healing` |
| --- | --- | --- |
| “damage and healing … by up to N” (one number) | N | N |
| a healing line H **and** a spell-damage line D | D | H |
| a healing line H only | `floor(H / 3)`, flag `inferred` | H |
| “12–18 Damage” / “damage per second” | not this field | not this field |
| “+N Weapon Damage” | not this field; ignore at 1–20 | |

If both H and D are printed, do not add `H/3` on top of D. The Hide of the Wild pair is already both numbers.

**Weights (inference).** They order rewards. They are not a damage simulation. `md` is 0, 1/3, 2/3, or 1 from the talent pane.

```
W_dps  = 14
W_ap   = 1
W_str  = 2
W_int  = md + 0.5      # 0.5 is the mana/spell-crit weight before any talent
W_agi  = 0.35
W_sta  = 0.35
W_spi  = 0.25
W_spd  = 0.40          # shocks and the occasional bolt; Icy Veins: minor at 20
W_heal = 0.25          # Healing Wave is in the kit from level 1
W_mp5  = 2
W_arm  = 0.01
W_hit  = 8             # rarely present
W_crit = 6
```

Icy Veins’ own order for this band, which the weights are built to follow: weapon DPS, then strength, intellect (mana, and attack power only with Mental Dexterity), agility, spell power, spirit, stamina. Hit and crit sit above strength **once they exist on gear**; they mostly do not in this band. Spell power on a weapon is real and still loses to a large DPS gap. **Source:** [Icy Veins stat list](https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-guide): “Be careful with weapons that have Spell Power on them — some have reduced weapon DPS to compensate.”

Slow versus fast: if two weapons are within 0.3 DPS, prefer the slower speed. Icy Veins says slower two-handers matter more later than they do now. Under 0.3 DPS the DPS term is a tie; the speed tie-break is **inference**.

**Worked comparisons (the weights above).**

- Staff 6.0 DPS, +2 intellect, no Mental Dexterity, against a 4.0 DPS mace and an empty off-hand. Staff value = 14×6 + 0.5×2 = 85. Mace value = 56. Equip the staff.
- Spell-power staff 3.0 DPS and +15 spell damage, against a 5.0 DPS mace. Staff = 14×3 + 0.4×15 = 48. Mace = 70. Keep the mace.
- Cloak “+12 healing and +4 damage”, +2 stamina, against an empty back. Use 4, not 4+floor(12/3). Value = 0.4×4 + 0.25×12 + 0.35×2 = 5.3. Equip it.
- Mail chest with better stats than the leather chest, at level 12. Inadmissible. Do not score it.

### 2.3 Quest rewards, shaman addenda

Use §1.3. Extra constraints:

- A mail or plate “upgrade”, a sword, a wand, or a bow is inadmissible even if its numbers are the largest on the window.
- A staff or two-hander that passes §2.1 competes with mace+shield as a **set**.
- If the only wearable option is worse than what is equipped, take coins, or else the highest sell price (§1.3 step 4).
- Do not prefer an axe because of a racial this Skyborne does not have.

### 2.4 Vendor addenda

**Never sell, in addition to §1.5.**

| Item | Why | Effect if a sell is attempted |
| --- | --- | --- |
| Earth Totem, Fire Totem, Water Totem, Air Totem | Those element’s totem spells do not cast without the item. Local `shaman.md`; Icy Veins says the quests unlock Earth at 4, Fire at 10, Water at 20. | Money unchanged. If money **does** change, stop and do not sell another totem. |
| The weapon just scored as an upgrade, still in the bag | It is the next equip. | — |
| Current drink and food down to the §1.6 floor | Icy Veins: “Always have food and especially water.” Healing Wave spends mana to replace food, so water is the one that runs out. | — |

**Buy a white weapon** when a weapon vendor is open, the row passes §2.1 and the skill gate, and `value` beats the equipped set by more than 14 (about +1 DPS) after paying `unit_price` without touching `reserve`, `train`, or the 10-drink floor. Wowhead’s early examples are Walking Stick (required level 3, 4.2 DPS) and Quarter Staff (required level 11, 9.4 DPS), sold by weapon vendors. **Source:** [Wowhead shaman weapons](https://www.wowhead.com/classic/guide/wow-classic-best-shaman-weapons). Read DPS and price off the vendor tooltip; do not pay a remembered price.

**Effect.** Money down by the vendor price. Bag gains the weapon, or the main-hand slot changes if it was equipped in the same action. Re-read the equipped DPS before the next pull.

**Water before food** for this class. Healing Wave is the health button and it costs mana (Forever rank 1 is 25 mana in the local client notes). Food is the floor of 5, then more only after 20 drink.

### 2.5 When this shaman trains

Visit on the class-agnostic schedule (§1.8), plus the first hub visit even at level 1–2: Rockbiter Weapon is a trainer spell, not a free default, in the Classic list. **Source:** [Warcraft Wiki — Shaman abilities (Classic)](https://warcraft.wiki.gg/wiki/Shaman_abilities_(Classic)). Local Forever notes agree it is the imbue used before every fight, and a beta video trains it in the starting hub rather than finding it pre-placed.

New **names** that justify buying before leaving the hub, from the local Forever client notes cross-checked with [Forever Codex](https://forever-codex.com/classes/shaman/) (that page’s Fire Nova note says “SoD”; the local client notes and Icy Veins treat Forever Fire Nova as a level-12 spell). Confirm on the trainer row. Do not treat this table as proof the spell is already known.

| Level | Buy if the row exists and the name is missing |
| --- | --- |
| 1–2 | Rockbiter Weapon |
| 4 | Earth Shock, Stoneskin Totem. Stoneskin still needs the Earth Totem item. |
| 6 | Earthbind Totem, Healing Wave rank 2 |
| 8 | Lightning Shield, Stoneclaw Totem, and the rank-2 bolts / shocks / Rockbiter if affordable |
| 10 | Flame Shock, Searing Totem, Flametongue Weapon, Strength of Earth. Searing needs the Fire Totem. Talent point is the talent pane, not this window. |
| 12 | Fire Nova, Purge, Ancestral Spirit, Healing Wave rank 3 |
| 14 | Rank-ups only (Lightning Bolt, Earth Shock, Stoneskin). These can wait if money is short. |
| 16 | Cure Poison, then rank-ups |
| 18 | Tremor Totem, then rank-ups |
| 20 | Ghost Wolf, Frost Shock, Lesser Healing Wave, Healing Stream Totem, then Call of the Elements and Totemic Recall if shown. Rank-ups after those names. |

Call of Earth / Fire / Water are **quests** the trainer may offer (Icy Veins: levels 4, 10, and 20). Accepting a quest is not learning a spell. Check the quest log, not the spellbook, for that click. A spell can be in the book and still fail the cast with a missing-totem error. That error means “learned, item missing.” Do not buy the row again, and do not sell the totem.

If the level-8 rows are absent on the Windshaper hub trainer, apply the starter-cap rule (§1.8). The hub trainer’s max level on Forever is **unverified**. Local video notes name Windshaper Boro / Borro as the shaman trainer; this file does not send the character there.

### 2.6 Confirming shaman spells

Use §1.8. Shaman-specific reading:

- Rockbiter, Lightning Shield, and weapon imbues are buffs. The learn is the spellbook line. The green weapon glow is a later cast, not proof of purchase.
- Rank-ups of Lightning Bolt and Healing Wave do not add a new bar icon. Read the spellbook rank.
- A new name (Earth Shock, Earthbind, Ghost Wolf) is a new spellbook entry. Put it on the bar in a separate step. The bar changing is sufficient evidence only after that step; it is not necessary for the learn itself.
- Totemic spells can be learned before the totem item exists. Spellbook rank is the learn check. A successful totem cast is a different check.

---

## 3. Failure cases

| Observation | Decision | Do not |
| --- | --- | --- |
| Stat lines garbled, name known | `value = null`. Leave it in the bag. | Equip, vendor, or pick it as a reward. |
| Weapon DPS parsed, other lines absent, no red text | Score DPS only. | Invent strength or spell power. |
| “Requires Level” unreadable | Inadmissible. | Assume it is wearable because the item looks low level. |
| Red line present, level number looks legal | Inadmissible. Red wins. | Average the two readings. |
| `classes` missing because the crop clipped the bottom | Inadmissible if the crop does not include the bottom of the tooltip. | Assume “no class line means legal” unless the full tooltip was visible and had no Classes line. |
| Armor word unreadable | Inadmissible for body slots. | Guess leather from the icon. |
| Mail or plate parsed at level ≤ 20 | Inadmissible for this shaman. | Score the stats “just in case”. |
| Sword, wand, bow, gun, polearm | Inadmissible. | Take it for the sell price when a wearable option exists. Take it only under §1.3 step 5. |
| Two-hand axe, red “skill not learned” | Inadmissible. | Buy the Classic talent; it is not on the Forever tree. |
| Two-hand axe, no red text, skill near cap | Score it against mace+shield. | Reject it from a Classic guide alone. |
| Spell-power weapon with low DPS | Score both terms. The DPS term will usually win. | Prefer it because Forever “added spell power to weapons”. |
| Healing line only | Set spell damage to `floor(healing/3)` and flag inferred. | Also do that when a damage line is already printed. |
| White-hit damage read as spell power | Reject the parse. Re-read. | Add “12–18 Damage” into `spell_damage`. |
| Soulbound equipped piece | It is the baseline of the set. | “Sell soulbound” during a junk pass. |
| BoP reward we cannot wear, next to a leather piece we can | Take the leather. | Take the BoP because its item level is higher. |
| BoE we cannot wear yet, bag has room, `req_level` ≤ player+2, no wearable upgrade on the window | Stash (§1.3). | Equip it. The equip fails or, worse, binds a useless piece. |
| Quest Item, grey or white | Never sell. | Retry the sell when money does not move. |
| Hearthstone | Never sell. | Treat “unique” as vendor trash. |
| Poor junk | Sell. Money and bag count must both move. | Sell a grey whose name is also in the quest log. |
| Vendor price unreadable | Do not buy that row. | Use the Classic 25c / 1s 25c / 5s table as the amount paid. The table is only the planning budget. |
| Trainer price unreadable | Do not buy that row. | Use the inferred silver table as the amount paid. |
| Money fell, spellbook rank unchanged | Stop. Re-read the book. | Buy the row again. |
| Spellbook rank updated, action bar unchanged | Learn succeeded. | Train it a second time. |
| Level ≥ 8 and the hub trainer has no rows | `visit_due` stays set. | Mark the character fully trained. |
| Mental Dexterity not on the talent pane | `md = 0`. Intellect is mana and spell crit only. | Apply 100% intellect-to-AP because the level is 17. |
| Durability fraction unreadable | Do not pay Repair All. | Assume gear is healthy. |
| Repair All price unreadable, a slot shows 0 | Repair that slot alone if its own price parses. | Buy water first. |

---

## 4. Sources

**Forever, primary**

- [Blizzard Entertainment, “World of Warcraft: Forever Deep Dive Panel Recap”, 13 Sep 2026](https://worldofwarcraft.blizzard.com/en-us/news/24303313/world-of-warcraft-forever-deep-dive-panel-recap). Combined hit and crit, healing grants one third as much damage, caster weapons grant spell damage and healing, quest rewards expanded, campfire repair vendors, 10–15 second solo kills.

**Forever, panel reporting and class guides**

- [Output Lag, 13 Sep 2026](https://outputlag.com/news/world-of-warcraft-forever-unifies-hit-and-crit-stats-and-gives-healing-gear-bonus-damage/). Slide examples (+42 healing / +14 damage) and the “down to level 10” weapon line, attributed to the Deep Dive.
- [Icy Veins — Forever Enhancement Shaman, updated 21 Sep 2026](https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-guide). Stat order, 2 AP per strength, 15 mana per intellect, Mental Dexterity, water-before-food, even-level training, totem quest levels, spell-power weapons with gutted DPS.
- [wowforevertalents.com — Mental Dexterity](https://wowforevertalents.com/shaman/talents/mental-dexterity). Ranks 33 / 67 / 100 percent, build 1.60.1.70009.
- [Zockify — Forever shaman](https://www.zockify.com/forever/shaman/) and [WoWSource — shaman](https://wowsrc.com/classes/shaman/). Two-handed axes and maces described as baseline; dual wield absent from the BlizzCon demo.
- [wowclassicforever.info — shaman](https://wowclassicforever.info/classes/shaman/). Disagrees that two-handers are settled.
- [Forever Codex — shaman abilities](https://forever-codex.com/classes/shaman/). Level-by-level trainer list used as a cross-check.

**Classic baseline**

- [Vanilla WoW Archive — Attributes](https://vanilla-wow-archive.fandom.com/wiki/Attributes). 2 AP per strength for shamans, 10 health per stamina, 15 mana per intellect.
- [Wowhead — Classic shaman weapons](https://www.wowhead.com/classic/guide/wow-classic-best-shaman-weapons). Default skills, weapon trainers, unusable types.
- [Wowhead — Classic shaman trainers](https://www.wowhead.com/classic/guide/wow-classic-shaman-class-trainer-locations). Even levels, level-6 starter cap, optional ranks.
- [Wowhead — Earth Shock](https://www.wowhead.com/classic/spell=8042/earth-shock). Level 4, training cost shown as 1.
- [Warcraft Wiki — Shaman abilities (Classic)](https://warcraft.wiki.gg/wiki/Shaman_abilities_(Classic)). Which spells are default versus trainer; Mail at 40.
- [Warcraft Tavern — Classic shaman](https://www.warcrafttavern.com/wow-classic/guides/shaman/). Cloth and leather from 1, mail at 40.
- [Warcraft Wiki — Quest item](https://warcraft.wiki.gg/wiki/Quest_item).
- [ClassicDB — Jaeana](https://classicdb.ch/?npc=4169) and [Warcraft Wiki vendor template](https://warcraft.wiki.gg/wiki/Template:Vendors). Food and drink prices.
- [Wowpedia — Drink](https://wowpedia.fandom.com/wiki/Drink).
- [Warcraft Wiki — Death](https://warcraft.wiki.gg/wiki/Death_(gameplay)). 10% durability on death.

**Inference, collected**

- The numeric weights, the +1 upgrade epsilon, the 0.3 DPS speed tie-break, the weapon-skill “within 5 of cap” cutoff, the 20/10 and 10/5 consumable counts, the stash-if-within-2-levels rule, the repair order when money is short, and the silver units on the trainer price table.
