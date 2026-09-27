# Shaman trainer UI — ThVlyymiLfI, 01:52:10–01:53:10

All of this is read from a public video's frames of another player's client: **unverified** for this character's client
(layout, colours and prices may differ with UI scale and build) until the engine reads its own trainer window.

Source: `clip.mp4` (1920×1080, video id `ThVlyymiLfI`, section 01:52:10–01:53:10). Frames `f001.png`–`f060.png` are one frame per second. `f001` is 01:52:10, so frame `fNNN` is 01:52:10 + (N−1) seconds. The frames are not kept: re-extract them from the public video with `yt-dlp --download-sections "*01:52:10-01:53:10"` and `ffmpeg -vf fps=1`.

The class trainer is in this minute. No wider scan was needed. No vendor window appears in any frame.

NPC: **Aarnor Galestrike**, subtitle **Shaman Trainer**, in Shen'dar Village. The video player's frame shows level 6, which is why every visible level requirement (8, 10, 12) is unmet.

Boxes are fractions of the frame `(x0, y0, x1, y1)`, origin top-left. Colours are approximate sRGB samples from the pixels. The same window chrome (portrait, title, close button) is shared by the gossip frame and the trainer frame.

## When it is on screen

| Time | Frames | What is open |
|---|---|---|
| 01:52:10–01:52:28 | f001–f019 | No window. Nameplate only, clearest on f019. |
| 01:52:29 | f020 | Still walking up; nameplate only. |
| 01:52:30 | f021 | Gossip window. Only frame that shows it. |
| 01:52:31–01:53:06 | f022–f057 | Trainer window. List scrolls later in the range. |
| 01:53:07–01:53:09 | f058–f060 | Window closed. |

Best frames: **f021** (gossip), **f022** (trainer top of list, Filter, costs, Train, Lightning Bolt tooltip), **f033** or **f045** (Lightning Shield tooltip), **f050** (Stoneclaw Totem tooltip), **f055** (scrolled list: Strength of Earth Totem tooltip, Ancestral Spirit).

## Nameplate

Not a window. White name text, green health bar underneath.

- f019, large and low-left while standing on the NPC. Name is the line above the subtitle; OCR smears the name, subtitle is clean. Subtitle box `(0.036, 0.681, 0.080, 0.703)`. Text: `Shaman Trainer`. Colour near-white `(248, 250, 255)`.
- f022–f057, smaller, over the NPC at screen centre. Name `(0.487, 0.351, 0.545, 0.364)`. Text: `Aarnor Galestrike`. Colour near-white `(238, 247, 252)`. Green health bar just below, about y 0.365–0.372.

## Gossip window

Only **f021** (01:52:30). Parchment gossip frame, same outer chrome as the trainer.

Outer frame, including the portrait that hangs off the top-left and the Goodbye button: `(0.008, 0.088, 0.172, 0.520)`. Border is bronze-gold, about `(140, 100, 50)` to `(180, 140, 60)`.

- Portrait. `(0.005, 0.075, 0.055, 0.158)`. Circular night-elf portrait (pale blue skin, white hair) overlapping the top-left corner.
- Title. `(0.070, 0.101, 0.121, 0.114)`. Text: `Aarnor Galestrike`. Yellow-gold `(226, 213, 125)`.
- Close. `(0.150, 0.090, 0.166, 0.116)`. Red square, gold X. Red fill about `(83, 11, 0)`, X about `(253, 216, 79)`.
- Parchment. `(0.018, 0.154, 0.147, 0.485)`. Tan `(231, 172, 95)`. Body copy is dark brown. A thin scrollbar sits on the right of the parchment, about x 0.151–0.165, with small arrow caps.
- Body text. Block about `(0.020, 0.155, 0.140, 0.250)`. Exact text:

```
The spirits of the wind may have left us,
but the power of the elements is not
entirely out of reach for those with the
patience to seek them out.

If you are initiated in the ways of the
shaman, I can help you grasp them.
```

- Gossip option. Yellow hover bar about `(0.020, 0.248, 0.145, 0.270)`, bright yellow `(255, 252, 97)`. A small grey icon sits at the left of the line, about `(0.015, 0.250, 0.035, 0.272)`. Option text is dark on that bar: `I'd like training!` The cursor is on this row in f021.
- Goodbye. `(0.125, 0.478, 0.165, 0.510)`. Text: `Goodbye`. Yellow letters on a dark red button `(140, 20, 10)` with a gold rim. Bottom-right of the frame.

## Trainer window

Open on **f022–f057**. Same width and chrome as gossip; shorter, because the parchment is replaced by a spell list. Outer frame `(0.008, 0.088, 0.172, 0.460)`. Interior is near-black brown `(40, 25, 5)`. Title, portrait, and close match the gossip window (same boxes, same colours). Title text again `Aarnor Galestrike`.

### Filter

Closed for the whole clip. The menu never opens, so its entries are not visible.

Button `(0.118, 0.122, 0.162, 0.148)`. Dark grey pill. Label `Filter` in yellow `(235, 206, 95)`, about `(0.131, 0.129, 0.147, 0.140)`. A yellow right-pointing triangle sits at the right end of the button. Clearest on f022, f033, f050, f054.

### List columns

List area `(0.015, 0.148, 0.155, 0.420)`. A thin scrollbar with a bottom chevron is at about x 0.155–0.168. Rows are about 0.039 tall (two text lines). Dark red hairline separators between rows, about `(100, 30, 20)`.

Each row, left to right:

1. Square spell icon, about x 0.015–0.033.
2. Two text lines, x about 0.033–0.125.
   - Line 1, spell name and rank, yellow `(217, 198, 84)`. Example: `Earth Shock (Rank 2)`.
   - Line 2, requirement, white `(250, 245, 235)`, except the unmet level number, which is red `(152, 37, 43)`. Example: `Requires: Level 8, Earth Shock (Rank 1)` with only the `8` in red.
3. Price, right-aligned, about x 0.125–0.158, on the name line. White numerals if the player can afford it; red numerals `(166, 44, 56)` if not. Coins follow the number: silver is a pale disc `(230, 230, 235)`, copper is orange `(167, 81, 19)`.

Nothing in the visible list is drawn as already known. No grey names, no green text, no checkmark, no "Already known" label. Every row is an unlearned spell with a yellow name. Unmet requirements show up only as the red level number. Unaffordable prices show up as red digits. The player has 2 silver 39 copper (footer), so 95 copper stays white and anything of 3 silver or more is red.

Hover (the cursor is on the row) draws a light blue bar around that row, edge about `(70, 116, 138)`, centre darker teal `(44, 77, 84)`. The name stays yellow. On f022 the hovered row is Lightning Bolt. On f055 it is Strength of Earth Totem.

### Rows on f022 (top of the list)

Boxes are the full row. Price sits on the right of the name line.

| Row | Box | Name (yellow) | Requires (white, level number red) | Price |
|---|---|---|---|---|
| 1 | `(0.015, 0.150, 0.165, 0.188)` | `Earth Shock (Rank 2)` | `Requires: Level 8, Earth Shock (Rank 1)` | 95 copper, white |
| 2 | `(0.015, 0.188, 0.165, 0.228)` | `Lightning Bolt (Rank 2)` | `Requires: Level 8, Lightning Bolt (Rank 1)` | 95 copper, white. Blue hover. |
| 3 | `(0.015, 0.230, 0.165, 0.270)` | `Lightning Shield (Rank 1)` | `Requires: Level 8` | 95 copper, white |
| 4 | `(0.015, 0.270, 0.165, 0.310)` | `Rockbiter Weapon (Rank 2)` | `Requires: Level 8, Rockbiter Weapon (Rank 1)` | 95 copper, white |
| 5 | `(0.015, 0.310, 0.165, 0.350)` | `Stoneclaw Totem (Rank 1)` | `Requires: Level 8` | 95 copper, white |
| 6 | `(0.015, 0.348, 0.165, 0.388)` | `Flame Shock (Rank 1)` | `Requires: Level 10` | 3 silver 80 copper, red |
| 7 | `(0.015, 0.388, 0.165, 0.425)` | `Flametongue Weapon (Rank 1)` | `Requires: Level 10` | 3 silver 80 copper, red |

### Rows that appear once the list scrolls (f055)

Same columns and colours. Lightning Shield through Flametongue Weapon are still on screen; Earth Shock and Lightning Bolt have scrolled off. New rows:

- `Strength of Earth Totem (Rank 1)`, `Requires: Level 10`. Blue hover, cursor covering the left part of the price. The visible remainder is `80` and a copper coin. The silver digit, if any, is under the cursor, so it is not readable on this frame.
- `Ancestral Spirit (Rank 1)`, `Requires: Level 12`. Price `7` silver `60` copper, red digits.

### Footer

- Player money, not the hovered spell's price. It stays `2` silver `39` copper on every trainer frame while the hovered price changes. Box about `(0.045, 0.428, 0.090, 0.448)`. Numerals white `(210, 211, 218)`. Silver coin, then copper coin.
- Train. Button about `(0.118, 0.420, 0.165, 0.452)`. Label `Train` about `(0.132, 0.431, 0.153, 0.444)`. Grey `(121, 124, 121)` on a dark grey button `(40, 40, 40)`. Disabled the entire time the window is open. No frame shows it lit.

## Spell tooltip

Floats to the right of the trainer, top aligned near the hovered row. Dark blue panel `(17, 24, 45)` with a gold rim. Not part of the trainer frame itself. The cursor determines which spell it describes.

Chrome, using the Lightning Bolt tooltip on f022 as the box: `(0.165, 0.085, 0.305, 0.210)`.

- Title, white `(238, 242, 250)`.
- Cost, cast time, range, cooldown, reagent line: white.
- Description: yellow `(240, 223, 133)`.
- Last line, every tooltip in this clip, blue `(126, 167, 212)`: `Press F6 to submit an issue for this Spell`. That line is an addon, not the trainer.

Exact tooltip text:

f022, Lightning Bolt:

```
Lightning Bolt
30 Mana                          30 yd range
2 sec cast
Casts a bolt of lightning at the target for
27 to 31 Nature damage.
```

f033 and f045, Lightning Shield (panel extends lower, about y 0.075–0.235):

```
Lightning Shield
45 Mana
Instant
The caster is surrounded by 3 balls of
lightning. When a spell, melee or
ranged attack hits the caster, the
attacker will be struck for 13 Nature
damage. This expends one lightning
ball. Only one ball will fire every few
seconds. Lasts 10 min.
```

f050, Stoneclaw Totem:

```
Stoneclaw Totem
15 Mana
Instant
30 sec cooldown
Tools: Earth Totem
Summons a Stoneclaw Totem with 50
health at the feet of the caster for 15
sec that taunts creatures within 8 yards
to attack it.
```

f055, Strength of Earth Totem (panel about y 0.200–0.360):

```
Strength of Earth Totem
25 Mana
Instant
Tools: Earth Totem
Summons a Strength of Earth Totem
with 5 health at the feet of the caster.
The totem increases the strength of
party members within 30 yards by 7.
Lasts 5 min.
```

## Vendor

No vendor, merchant, repair, or buy/sell window is visible in 01:52:10–01:53:10.
