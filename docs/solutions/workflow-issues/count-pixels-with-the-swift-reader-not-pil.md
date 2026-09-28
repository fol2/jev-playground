---
title: "Count and calibrate pixels with the runtime's Swift reader on live-path frames; other decoders only look"
date: 2026-09-28
category: workflow-issues
module: perception calibration (Swift pixel readers, saved frames)
problem_type: workflow_issue
component: development_workflow
severity: high
root_cause: missing_workflow_step
resolution_type: workflow_improvement
applies_when:
  - "A pixel threshold, colour rule or box is being set, tightened or loosened"
  - "A PR, README, review or code comment is about to state a pixel count or that a reader reads or misses something"
  - "The only frames at hand are saved JPEGs from live runs"
  - "PIL, a browser, Preview or another decoder is about to be used on a saved frame"
  - "A reader works offline and fails live, or the other way round"
  - "Training and test frames are being chosen for a learned reader"
symptoms:
  - "On 25 Sept PIL counted 2-3 red pixels on the bolt's range digit where the Swift reader counted 7-9 on the same saved JPEGs, and a false known limit (the reader missed a red digit) went into PR #33 until it was withdrawn (auto memory [claude] for the decoder and the 2-3)"
  - "The same saved frame decoded two ways differed by up to 69 per channel inside the facing arrow's box, and one of 16 labelled JPEG frames read 56 degrees off"
  - "A screenshot showed the minimap quest mark in a different colour from the live capture"
related_components:
  - perception
  - pixel-readers
  - perception-regression-set
  - learned-readers
tags: [pixel-calibration, swift-reader, pil, jpeg, png, live-decode-path, perception, evidence]
---

# Count and calibrate pixels with the runtime's Swift reader on live-path frames; other decoders only look

## Context

The pixel readers in this repo are Swift. `hudCount` counts the pixels in a box that pass a colour rule (`experiments/002_wow_visual/m3/Fight.swift:110`), and a threshold turns the count into a reading. The bolt's range digit reads red when more than `rangeMin` = 4 pixels pass `darkRedDigit` (`experiments/002_wow_visual/m3/Fight.swift:24-25`, `:41`, `:139`). A threshold like that is right only for the pixels its consumer actually sees.

**The runtime's decode.** A live frame goes through these steps:

- a ScreenCaptureKit sample, decoded by `VTCreateCGImageFromCVPixelBuffer` (`experiments/002_wow_visual/m0/Probe.swift:113`);
- a byte-for-byte copy, "so calibrated colours are unchanged" (`experiments/002_wow_visual/m0/Probe.swift:138-147`, `ownedCopy` at `:90`);
- `runtimeFrame`, which passes on only a fresh frame at the calibrated size (`experiments/002_wow_visual/m3/FightProbe.swift:97-104`);
- `rgba()`, which draws the image into an 8-bit RGB context (`experiments/002_wow_visual/m1/SeekProbe.swift:42-51`);
- the readers.

**What live runs save, and in what format.** The shared `write` passes a lossy quality of 0.7 (`experiments/002_wow_visual/m1/SeekProbe.swift:71-75`).

- *JPEG:*
  - a fight keeps every other observation as `f###-tag.jpg` (`experiments/002_wow_visual/m3/FightProbe.swift:194-196`);
  - a walk keeps every other frame, and every frame with a red name or hostile plate, as `f###.jpg` (`experiments/002_wow_visual/m4/NavProbe.swift:171-173`);
  - a hunt keeps `w###.jpg` and `h###.jpg` (`experiments/002_wow_visual/m4/HuntProbe.swift:120`, `:140`);
  - a quest run keeps the frame each NPC click was chosen on as `clickN.jpg` (`experiments/002_wow_visual/m4/QuestProbe.swift:826`).
- *PNG (lossless):*
  - `m1-seek --look` writes `look.png`: one window-only frame, with no input (`experiments/002_wow_visual/m1/SeekProbe.swift:215-231`);
  - a quest run writes `use-N.png`, `minimap-scan.png`, `quest-log.png`, `no-marks.png` (commented "for calibration") and `no-marks-after.png` (`experiments/002_wow_visual/m4/QuestProbe.swift:293`, `:423`, `:462`, `:818`, `:866`);
  - `m4-nav --zoom` writes `zoom.png` (`experiments/002_wow_visual/m4/QuestProbe.swift:1729`).
- *What that leaves:* fights, walks and hunts save no PNG. The fight HUD's states, such as a red range digit, a cast bar or error text, exist on disk only as JPEG.

**The offline decode.** `--replay` and `--pixels` open a saved file with ImageIO and then call the same `rgba()` (`experiments/002_wow_visual/m4/NavProbe.swift:297-327`, `:353-372`). M5's `loadImage` also opens files with ImageIO (`experiments/002_wow_visual/m5/PerceiveTool.swift:38-40`), then draws them into 8-bit RGB with its own `pixels()` (`:43-52`), not `rgba()`. On a saved JPEG, the Swift replay runs the runtime's reader code on pixels that compression has already changed. PIL, or any other decoder, adds a second difference: a different JPEG decoder on top of the compression.

**What happened on 25 September (#33, #34).**

- #33 (M3b) first claimed that "the new shock digit reads red on 11 saved frames (the 23 Sept evening bar)". The review found a different fault there, not a decode one. The digit box sat on key 5, and the dark-red rule missed Earth Shock's muted red. The review records "the '11 frames' claim withdrawn".
- The first review-fix commit added `mutedRedDigit`. Its comment gave counts of "0 pixels on all 407 without a target, and 0 or 8-20 on the 518 with one". The M3 README gained a known limit: the bolt's digit rule "missed a red '2' on the approach".
- A third commit, "M3b: the shock digit's counts are the Swift reader's; the bolt digit's known limit restated", replaced both.
  - The counts became "at most 1 pixel on the 407 without a target, and 0-2 or 13-14 on the 518 with one", as they read today (`experiments/002_wow_visual/m3/Fight.swift:42-44`).
  - The "missed a red '2'" claim was removed. Only the held-key finding stayed.
  - The exact-head review records "Swift counts on 24 Sept 0-1 px on 407 no-target frames and 0-2 or 13-14 on 518 with target, 30 red, checked by eye".
- GitHub does not say which tool made the first numbers. The agent's note of that day does (auto memory [claude]). The first counts came from PIL on the same saved JPEGs. PIL counted 2-3 red pixels on the bolt digit, where the Swift reader counted 7-9. The threshold is more than 4 pixels, so PIL's 2-3 made a working reader look as if it missed red digits.
- #34, merged the same day, headed its evidence "offline, saved frames; the Swift reader". The bolt "now reads out of range on exactly the 9 frames whose '2' is red by eye (7–9 px each, where the negatives max out at 3)". It used a physical cross-check: "when the shock reads in range, the bolt (30 yd) must read in range too". Its 77 changed frames were all checked by eye on contact sheets.

**Earlier, the same lesson in other readers.**

- *The facing (M4a, #17, 23 Sept).* "Saved JPEGs do not replay the live frames faithfully. The same frame decoded two ways differed by up to 69 per channel inside the arrow box. Through the live decode path, one of 16 labelled JPEG frames read 56° off. Calibrate on PNG captures" (`experiments/002_wow_visual/m4/README.md:131-133`). On eight lossless PNG captures, the facing was within 12° of the author's labels (`:129-130`). The README does not name the two decoders.
- *A UI change (M4b, #18).* The owner's UI changed on 23 Sept, and "the readers were re-calibrated on live PNGs" (`experiments/002_wow_visual/m4/README.md:292`).
- *A screenshot (M4d-f, #26).* "The live capture drew a minimap '?' as (239, 236, 116), not the screenshot's (248, 246, 58)". The yellow test became a hue test, "calibrated on the probe's own saved frame" (`experiments/002_wow_visual/m4/Quest.swift:86-87`, `experiments/002_wow_visual/m4/README.md:466-467`).
- *Quest marks (M4g, #28).* "The 23 Sept frames are JPEG, not the live decode path" (`experiments/002_wow_visual/m4/README.md:536`). #28's review kept this as a documented limit: "the 23 Sept '!' calibration frames are JPEG".
- *Red names (M4h).* The replay ran on "975 saved M4 frames (23-24 Sept, JPEG …)" and "is calibration, not a held-out result". "Not seen live: raw (not JPEG) frames" (`experiments/002_wow_visual/m4/README.md:559-563`, `:572`).
- *The perception regression set (#32).* It runs every pixel reader on every saved frame (`m4-nav --pixels`, `experiments/002_wow_visual/m4/NavProbe.swift:7`). The gate calls it at `tools/MotorProof.swift:194-195`. "Saved JPEGs are not live frames (see facing above). The set catches code changes, not calibration" (`experiments/002_wow_visual/m4/README.md:211-213`).
  - The file holds 5,714 frames today, and 123 of them are PNG (`experiments/002_wow_visual/m4/perception.jsonl`; the floor is at `tools/MotorProof.swift:16`).
  - The README still says 2,397 frames (`:189`).

**What prints counts today.** No tool prints the raw count behind a reading.

- `pixelReadings` turns counts into booleans (`range_red`, `shock_range_red`, `error_red`, `buff`, `combat`) and bar fractions (`experiments/002_wow_visual/m4/NavProbe.swift:331-348`).
- `--replay` prints the bars as percentages.
- The agent's note of 25 Sept gives the only way to get counts: a temporary edit of `pixelReadings` in a scratch worktree, reverted afterwards (auto memory [claude]). Neither #33 nor #34 says how its counts were printed.

**PIL is outside the repo.** #37 moved the gate to Swift ("no Python remains"), and no `.py` file is tracked. The owner allows Python in side tools that are not part of the engine (auto memory [claude]). So an agent can still reach for PIL to look at a frame, and that is where the risk now lies.

## Guidance

**The decode that counts is the runtime's: the live capture path into `rgba()` and the Swift reader. Calibrate thresholds on lossless PNG captures from that path. Count pixels for any claim about a reader with the Swift reader. Use other tools only to look.**

| Frames and decoder | Use it for | Not for |
|---|---|---|
| Live frames in a run (the reader's own readings in the log) | Qualifying a reader | — |
| PNG captures from the live path, read by the Swift reader | Setting a threshold; counts in a PR | A held-out claim, once the threshold was tuned on them |
| Saved JPEGs read by the Swift reader (`--pixels`, `--replay`, `tools/sdlc motor`) | Regression: did a code change move a reading? Rough counts, labelled as JPEG | A threshold near its margin; a claim that the reader sees or misses something live |
| Saved JPEGs in PIL, a browser, Preview or any other decoder | Looking: crops, contact sheets, labels by eye | Any count, any threshold, any claim about a reader |

1. **Get PNG frames from the live path.**
   - `m1-seek --look` writes one lossless frame with no input (`experiments/002_wow_visual/m1/README.md:135`). It is still a live capture, so it needs the current run envelope, with WoW running and not in front.
   - Quest runs already keep the PNGs listed above. Use them for the readers they show: the minimap, the arrow, the coordinates, quest marks and the bars at rest.
   - For a fight-HUD threshold, capture the state it needs with `--look`, for example a target selected beyond bolt range. A PNG option for fight or walk frames would close the gap. That is a proposal, not code on main.
2. **Count with the Swift reader.**
   - `m4-nav --pixels DIR` prints each reader's reading for every frame under DIR. `m4-nav --replay DIR` adds the OCR readers and `redDanger`. Both run the runtime's reader code. Name the format of the frames you ran them on.
   - No mode prints the raw count behind a boolean. The stopgap (auto memory [claude]), labelled as a stopgap:
     - in a scratch worktree, add the box's `hudCount(...)` to the row that `pixelReadings` returns;
     - build `m4-nav` with the M4 README's `swiftc` line (`experiments/002_wow_visual/m4/README.md:1644-1651`);
     - run `--pixels` on the main checkout's `runs/002_wow_visual`, since a worktree has no `runs/`;
     - read the counts, then delete the worktree.
   - Never commit that edit. Never build while a live run is on. If the stopgap is needed again, a counts mode in `m4-nav` is the fix. That is a proposal.
3. **Label by eye, and check the labels against physics.**
   - Crops and contact sheets from any viewer are fine for looking. That is what other tools are for.
   - Check the labels against what the game guarantees. With no target, a range digit is not red. When the shock (20 yd) is in range, the bolt (30 yd) is in range too (#34).
   - Name the known confounds. Below 30% health the screen's red tint reads as red (`experiments/002_wow_visual/m3/README.md:290-292`). A held key lights the slot's edge (#34).
   - Count over the whole set, positives and negatives, and give the margin, for example "red 7-9 px, negatives at most 3, threshold > 4".
4. **Keep the saved-JPEG set for regression, not calibration.** `tools/sdlc motor` compares the Swift readings of the saved frames with `perception.jsonl` and holds on any change (`experiments/002_wow_visual/m4/README.md:197-201`). A diff there says that a code change moved a reading. It does not say that a threshold is right live.
5. **In a PR, name the decoder and the format beside every number.**
   - Follow #34: "Evidence (offline, saved frames; the Swift reader)". Or, for example: "Swift reader (`hudCount`, `mutedRedDigit`), saved JPEG, 24 Sept, 925 frames".
   - A number from PIL or any other decoder is not evidence, so it does not go in a PR. If one got in, withdraw it in the PR and restate it with the Swift reader's count, as #33's third commit did, and let the review name the withdrawal.
   - Say whether the frames are JPEG or PNG, and whether the set is calibration or held out. A threshold set on JPEG stays unqualified on the live decode until a PNG check or a live run.
6. **The same rule applies to learned readers, in a different place.**
   - M5 trains and scores on saved frames decoded by ImageIO (`experiments/002_wow_visual/m5/PerceiveTool.swift:38-40`). The facing reader's rows are walk and hunt `.jpg` frames (`experiments/002_wow_visual/m5/Facing.swift:44`, `:56`). Video frames "are compressed and scaled" (`experiments/002_wow_visual/m5/README.md:286-287`). Live, the readers see raw frames.
   - So the decode is a difference between training and serving. The held-out test that counts is the live game's frames.
   - When explaining a live miss, keep "JPEG against live" as an unmeasured candidate. The README puts the facing reader's live misses down to "a new character, dusk" (`experiments/002_wow_visual/m5/README.md:473-474`). The effect of the decode was not measured.

## Why This Matters

- **The margin is a few pixels.** On the bolt digit, red frames count 7-9 and the negatives at most 3, with the threshold at more than 4 (#34). A decoder that counts 2-3 on red frames reverses the conclusion (auto memory [claude]). The facing's decodes differed by up to 69 per channel, and one of 16 labelled JPEGs read 56° off (`experiments/002_wow_visual/m4/README.md:131-133`).
- **A false "misses" claim invites a wrong fix.** "Missed a red '2' on the approach" went into #33 as a known limit. Taken at face value, it points to a looser colour rule or a lower threshold, on a reader that was reading correctly. It was removed before merge. (Inference: no such fix was made.)
- **Other capture paths differ too.** A macOS screenshot showed a minimap "?" as (248, 246, 58), and the live capture as (239, 236, 116). The blue channel differs by 58 (`experiments/002_wow_visual/m4/Quest.swift:86-87`). A rule set on the screenshot would miss the live mark.
- **The contract names the consumer.** "Name and test the actual runtime consumer before claiming transfer" (AGENTS.md). PIL is not the consumer. `docs/agents/ai-sdlc.md:96` asks to cache extraction "by source hash and extraction/decoder version, not filename", so the decoder is part of what a result is.
- **Experiment 001 already wrote this down.** Its pilot recording "was H.264, not a lossless screen master … Use this batch for appearance, not precise latency or frame-rate threshold claims" (`experiments/001_wow_fishing/evidence/2026-09-21-animation-pilot/README.md:43-47`).
- **The right way is cheap.** The Swift reader replays the whole saved set in about 8 s (`experiments/002_wow_visual/m4/README.md:196`, measured at 2,397 frames). A `--look` PNG is one frame with no input.

## When to Apply

- Setting or moving a colour rule, a box or a count threshold: `HUD`, `hudCount`, `redNames`, `questMarks`, `arrowFacing`, `markYellow`.
- Writing a pixel count, a "reads" or "misses" claim, or a known limit into a PR, a README, a review or a code comment.
- Opening a saved frame in PIL, numpy, a browser or Preview. Look; do not count.
- Choosing the training and test frames for a learned reader.
- When a reader works offline and fails live, or the other way round.
- After the owner's UI changes, as on 23 Sept.

Exception: looking needs no rule. Crops and contact sheets from any tool are fine, as long as none of their numbers are reported.

## Examples

**The bolt's range digit (#33 → #34).**
- *Before:* PIL counts of 2-3 red pixels on the saved JPEGs led to "missed a red '2' on the approach", written into #33 as a known limit (auto memory [claude]; the claim is in #33's history).
- *After:* the Swift reader on the same frames counted 7-9. The claim was withdrawn, and #34 reported exactly 9 red frames, all red by eye, with negatives at most 3. No frame read the bolt out of range while the shock read in range, or with no target.

**The shock's digit counts (#33).**
- *Before:* the first fix's comment gave "0 pixels on all 407 without a target, and 0 or 8-20 on the 518 with one".
- *After:* a commit titled "the shock digit's counts are the Swift reader's" changed them to "at most 1 pixel … 0-2 or 13-14" (`experiments/002_wow_visual/m3/Fight.swift:42-44`). The review gives the Swift counts and "checked by eye".

**The facing (#17).**
- *Before:* labelled JPEG frames, read through the live decode path, put one of 16 at 56° off.
- *After:* the README says "Calibrate on PNG captures". Eight lossless captures read within 12° (`experiments/002_wow_visual/m4/README.md:129-133`).

**The minimap "?" (#26).**
- *Before:* a screenshot showed the mark as (248, 246, 58).
- *After:* the live capture showed (239, 236, 116). The rule became a hue test, calibrated on the probe's own saved frame (`experiments/002_wow_visual/m4/Quest.swift:86-87`).

**Labelled correctly: red names (M4h).** The replay on 975 JPEG frames is called "calibration, not a held-out result", and raw frames are listed under "Not seen live" (`experiments/002_wow_visual/m4/README.md:559-563`, `:572`). That is the wording to copy when only JPEG was available.

## Related

- [Replay new logic on saved frames and states before a live run](../workflow-issues/replay-offline-before-live-and-cap-repeated-actions.md) (#118). That note says which replay to run. This one says which decode and which frames can produce a number, and it limits that note's perception replay to regression.
- [Keep the live-run harness and envelope in the repo](../workflow-issues/live-run-harness-and-envelope-belong-in-the-repo.md): no build beside a live run, which covers the stopgap build too.
- `AGENTS.md`: "Name and test the actual runtime consumer before claiming transfer".
- `docs/agents/ai-sdlc.md:96` (the decoder version as part of an extraction's identity) and `:101-103` ("A visual-capable analyst checks actual frames for claims about pixels").
- `CONCEPTS.md`: *Pixel rule*, kept for fixed interface bars such as the range digits, and *Learned reader*, the trained alternative.
- `experiments/002_wow_visual/m4/README.md:129-133`, `:178-213`, `:292`, `:536`, `:559-572`; `experiments/002_wow_visual/m3/README.md:282-292`, `:310-317`; `experiments/002_wow_visual/m5/README.md:286-287`, `:441-476`.
- PRs: #17 (facing, PNG), #26 (screenshot against capture), #28 (JPEG calibration frames), #32 (the perception set), #33 and #34 (the digits), #37 (the gate in Swift).
