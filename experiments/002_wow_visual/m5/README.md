# M5 — learned perception: a labelling teacher, an honest score and a learned reader

## Why

The rules that find quest marks in `m4/Quest.swift` (`questMarks`: a colour test, blob shapes, a green name
below) are hand-tuned, and each new situation broke them. On 26 Sept alone these came one after another:

- a new zoom;
- a new character;
- a sub-zone map;
- a near "!" whose foot is drawn orange, not yellow;
- tan grass that read as a mark.

Each fix was one more rule. Its only check was the perception regression set (`m4/perception.jsonl`), which
records what the rules read before, not what is true. Some of its accepted readings are marks on grass.

The owner then asked whether patching frame by frame is the right way, and approved another way (26 Sept):

- A small learned detector for world objects, trained on the Mac with Create ML (Swift, no Python).
- A vision model as a labelling teacher, offline, never in the live loop.

The research behind the choice (26 Sept):

- [OmniParser](https://github.com/microsoft/OmniParser) splits locating (a YOLO detector) from
  understanding (a model reading the regions), and grounds far better than a vision model alone.
- [Auto-labelling](https://voxel51.com/blog/the-complete-guide-to-auto-labeling) with a foundation model,
  then training a small detector on those labels, is the usual way to a fast reader.
- [Create ML's `MLObjectDetector`](https://developer.apple.com/documentation/createml/mlobjectdetector) trains
  one from Swift.
- Apple's [Foundation Models](https://developer.apple.com/videos/play/wwdc2026/241/) take images on the
  device in macOS 27. They name what an image shows, not where it is.
- End-to-end agents ([Cradle](https://arxiv.org/abs/2403.03186), [Lumine](https://arxiv.org/abs/2511.08892))
  need training and compute out of reach here. Vision models alone are weak on dense detail
  ([LVLM-Playground](https://arxiv.org/abs/2503.02358)).
- The usual WoW pixel bots ([WowClassicGrindBot](https://github.com/julianperrott/WowClassicGrindBot)) read
  an addon that paints game state as colours. That is injected telemetry, which AGENTS rules out.
- Game shortcuts (`/target NAME`, an Interact Key setting) were set aside by the owner: they are not how the
  engine should see.

## Stage one (this directory)

```text
saved frames (runs/002_wow_visual, private) -> m5-perceive --propose -> candidates.jsonl
    -> m5-teach (Apple's on-device model) -> marks.jsonl -> m5-perceive --sheet (audit) / --baseline (score)
```

| File | Role | Proof |
|---|---|---|
| `Marks.swift` | Pure: candidate glyphs (`markWarm`, `markCandidates`), the teacher's crop, the run split, the score | `MarksTests.swift` |
| `PerceiveTool.swift` | `m5-perceive`: `--propose` (frames on stdin), `--prelabel`, `--sheet N`, `--sheet-held N`, `--sheet-frames N`, `--audit FILE`, `--train`, `--baseline` | argument refusal in `tools/MotorProof.swift` |
| `Teacher.swift` | `m5-teach`: one crop, one fresh on-device session, a guided answer (`exclamation`, `question`, `none`); `--eval SET` | built; the proof checks it refuses bad arguments before any model call |

- **Candidates cast wide.** Solid warm parts, yellow to orange, each joined with a dot under it.
  - Recall matters here, not precision: the teacher says what each one is.
  - Sparse flecks, flat strips and anything more than three times wider than tall are left out.
  - At most 40 a frame.
- **The teacher is local.** It is Apple's on-device model (macOS 27, image input new in 2026).
  - No provider call is made, and no pixel leaves the Mac.
  - It needs Swift 6.4 and the macOS 27 SDK. Build it with `DEVELOPER_DIR=<Xcode 27>`. With an older
    compiler it is a stub that holds, so CI (macOS 14) builds it without the model.
  - The FoundationModels module brings an `Observation` module that clashes with the runtime's type, so
    the teacher is its own binary.
  - Each verdict is cached by the crop's pixel hash and the prompt's version (`fm-marks-v2`).
- **The split is by run.** One run in five, chosen by an FNV-1a hash of its name, is held out.
  - Frames of one run are near-duplicates, so a split by frame would leak.
- **Private.** Frames, candidates, labels, sheets and the cache stay under `runs/002_wow_visual/perception`.
  - The repository holds the code and the numbers only.

Rebuild and run from the repository root:

```sh
V=experiments/002_wow_visual
swiftc -O -parse-as-library $V/m0/Motor.swift $V/m1/Plate.swift $V/m3/Fight.swift $V/m3/Tactics.swift \
  $V/m4/Nav.swift $V/m4/Hunt.swift $V/m4/Quest.swift $V/m4/Roads.swift $V/m5/Marks.swift $V/m5/Reader.swift $V/m5/Train.swift $V/m5/RedNames.swift $V/m5/Objects.swift \
  $V/m5/PerceiveTool.swift $V/runtime/Runtime.swift $V/runtime/Input.swift $V/runtime/DecisionGraph.swift \
  $V/runtime/Experience.swift -o /tmp/m5-perceive
DEVELOPER_DIR=/Applications/Xcode-27.0.0-beta.5.app/Contents/Developer xcrun swiftc -O -parse-as-library $V/m5/Teacher.swift -o /tmp/m5-teach
(cd runs/002_wow_visual && find . -name '*.png' -o -name '*.jpg') | /tmp/m5-perceive --propose  # 2560 wide, 1320 (game), 1080 or 1440 (video) high
/tmp/m5-teach && /tmp/m5-perceive --sheet 48  # then --audit FILE, sheet by sheet, until none is left
/tmp/m5-perceive --train && /tmp/m5-perceive --baseline
(cd runs/002_wow_visual && find . -name '*.png' -o -name '*.jpg') | /tmp/m5-perceive --red-propose  # game frames only (2560 x 1320)
/tmp/m5-perceive --red-sheet 480  # then --red-audit FILE; --red-train, --red-train final, --red-baseline
```

## Results

### The teacher, first try: failed (26 Sept)

The first prompt (`fm-marks-v1`) asked for the kind alone.
- Of the first 60 candidates it called marks, the author found none that was one, by eye on two contact
  sheets.
- They were Cirrusflies, damage numbers, nameplate bars, "slain" lines, settings checkboxes and buttons.
- The run was stopped. Its labels are kept apart, not used.

### A hand-checked set, and the prompt that replaced it

The set is 91 crops, all checked by eye by the author, and kept in `runs/`.
- 31 are real marks: 28 "?" of Rorian, Windshaper Boro, Ventaari and Dalia, and 3 "!" of Ailee Farheart.
- 60 are the hard negatives above.
- The four example images of the third prompt were other crops, not in the set.

| Prompt | Marks found | False marks (of 60 hard negatives) |
|---|---|---|
| v1: the kind alone | 29 / 31 | 13 (60 in the first run: the model samples) |
| description first, then the kind | 29 / 31 | 8 |
| the same with four labelled example images | 30 / 31 | 35 |

- Guided generation writes the fields in order, so a verdict written after a short description of the
  shape is right more often. Example images made it worse.
- `fm-marks-v2` is the description-first prompt. It uses greedy sampling (the same crop gets the same
  verdict) and a description of at most eight words.
  - Greedy sampling can loop, repeating the description until the context is full. That stalled a run for
    minutes on one crop, so an answer is cut at 60 tokens, and a cut answer is kept as `refused`.
  - On the set it found 29 of 31 marks, each of the right kind, with 8 false marks, in 97 s (about 1 s a
    crop).
  - `m5-teach --eval SET` reruns this measure for any prompt.
- The model's guardrails refuse some game crops (about 6 %). Those are kept as `refused`, for the auditor.
- So the teacher is a wide first filter, not the truth. The labels the detector learns from are audited:
  - `m5-perceive --sheet N` shows the teacher's marks and refusals first.
  - The author checks each sheet by eye, and `--audit FILE` records the corrections.
  - `--baseline` scores against audited labels only, and only on frames whose candidates are all audited.

### Every candidate audited, and the two readers scored (26 Sept)

The author checked all 2158 candidates of 866 frames (92 runs) by eye on contact sheets, zooming in where a
glyph was a few pixels high. Far marks were labelled by their shape: a round hook is a "?", a wedge is a "!".

The first audit covered 1813 candidates. The review of this change then found that the text filter could drop
three marks standing in a row, so a line of text became a chain of letters no further apart than their height.
That added 427 candidates, all audited: none was a mark. 82 left the set, none a mark: settings text and grass
past the cap of 40 a frame.

- 76 are quest marks: 55 "?" and 21 "!".
  - They are over Rorian, Windshaper Boro, Ventaari Brightwish, Dalia the Collector and Ailee Farheart.
  - Many are far, 4 to 10 px high.
- The rest are fireflies and Cirrusflies, damage numbers, settings text, quest log and map icons, lamps and grass.
- The run split puts 8 marks in the held-out runs.

`m5-perceive --baseline`, on the audited labels:

| Reader | Hits | False marks | Missed | Precision | Recall |
|---|---|---|---|---|---|
| Teacher (`fm-marks-v2`), per candidate | 35 | 237 | 41 | 0.13 | 0.46 |
| Rule reader (`questMarks`), training runs | 65 | 11 | 3 | 0.86 | 0.96 |
| Rule reader, held-out runs | 5 | 0 | 3 | 1.00 | 0.62 |

- **The teacher is not good enough to label alone.** On real candidates it found fewer than half the marks, and
  most of what it called a mark was not one. Every mark it found was of the right kind.
  - The hand-checked set above overstated it: that set held clear marks and hand-picked negatives.
  - Every label the detector learns from must be audited. The teacher saves no audit time here.
- **The rule reader looks strong, but the numbers flatter it.**
  - Its rules were tuned on these same frames, from both splits, before the split existed.
  - Its errors are the failures seen live. `--baseline` writes each wrong frame to `perception/baseline-errors.txt`:
    - a near "!" read twice, as a glyph and its orange foot (3 frames);
    - a near "!" missed: the failure of the live runs of 26 Sept (3 frames);
    - grass flecks, a green spell and name text read as marks (4 frames, 8 false marks);
    - far marks of 4 to 10 px missed (3 frames).
- The score counts only marks some candidate caught. A mark the candidates missed is invisible to it.

8 held-out marks are too few to show that a learned reader beats the rules. The next live runs add frames, and
the audit continues on them.

## Stage two: a learned reader (26 Sept)

```text
audited candidates (training runs) -> m5-perceive --train -> models/detect.mlmodel, models/kind.mlmodel (private)
frame -> markCandidates -> detect (context crop): mark or none -> kind (shape crop): "!" or "?"   (Reader.swift)
```

| File | Role | Proof |
|---|---|---|
| `Marks.swift` | adds the three-way run split (`runSplit`), what a model may learn from (`learnable`, never a test run) and the two crops (`glyphCrops`) | `MarksTests.swift` (25 checks) |
| `Train.swift` | `m5-perceive --train`: crops of the training and validation runs, never the test runs; two Create ML image classifiers | built; not run by the proof (it needs the private frames) |
| `Reader.swift` | `MarkReader`: the candidates classified by the two models, through Core ML and Vision | built; scored by `--baseline` |

- **Two small classifiers, not one.** One run in five more, by the same hash, is a validation split. The design
  was chosen on it, before the test runs were scored:
  - One classifier for "!", "?" and none, on a crop of four glyph heights with the name under it, found the marks
    but read the near "!" of 26 Sept as "?".
  - On a crop of the glyph alone it read the kind right but missed far marks.
  - So `detect` says whether a candidate is a mark from the wide crop, and `kind` says which from the tight one.
  - A class-balanced training set added false marks. A wider floor for the context crop (40 px, not 24) lost far
    marks. Neither was kept.
- **Pinned, not bit-stable.** Scene-print features (revision 1) and logistic regression, with no augmentation.
  - Retraining on the same labels and SDK gave the same numbers (26 Sept).
  - A new SDK, or another file order, may not.
  - Training takes about 20 s on the Mac.
- **No frame drops out of the score.** A frame the learned reader cannot read stops `--baseline` (HOLD), so both
  readers are scored on the same 866 frames.
- **Private.** The models are made from private captures and stay under `runs/002_wow_visual/perception/models`.

`m5-perceive --baseline` (sim, offline, on the saved frames; 866 frames, all 2158 candidates audited):

| Split (marks) | Rule reader: hits / false / missed | Learned reader: hits / false / missed | Learned: wrong kind |
|---|---|---|---|
| Training (57) | 55 / 9 / 2 | 57 / 0 / 0 (learned on these) | 0 |
| Validation (11) | 10 / 2 / 1 | 9 / 2 / 2 | 0 |
| Test, held out (8) | 5 / 0 / 3 | 5 / 0 / 3 | 0 |

- **On the held-out runs the two readers tie**, 5 of 8 marks each with no false mark, but they miss different
  marks:
  - The learned reader finds the near "!" that the rules missed in the live run of 26 Sept (2 frames).
  - It misses far "?" marks 4 to 6 px high, which the rules find (2 frames). Few such marks are in the training runs.
- **It names the kind.** Every mark it found was of the right kind. The rule reader has no kind for a mark in
  the world.
- It does not beat the rules on held-out frames, so it is not promoted. 8 held-out marks are too few to tell two
  readers apart.

## Stage three: the learned reader in shadow on live quest runs

`m4/QuestProbe.swift` (`QuestRun`) hands each frame that `questMarks` reads to the learned reader, on a queue of its
own:

- the minimap scan's frame (`at: "view"`);
- the frame an NPC click is chosen on (`at: "open"`);
- each frame looked at again after Click-to-Move (`at: "again"`).

Each read is logged as a `learned_marks` event, with the count, up to five marks (kind, box and confidence) and
the time taken. An error is logged too.

- **The models load on the first read.** A `learned_reader` event says whether they loaded, and how long it took.
  With no models on the Mac, that event is the only trace.
- **Nothing is acted on, and nothing waits.** The quest run clicks where `questMarks` says, when it says, as before.
  - The first review of this change found a synchronous read, which delayed clicks and retries.
  - Now the caller returns at once.
  - A frame that comes while a read is still running is skipped (`skipped: busy`), never queued.
  - The proof pins this: the load and the read are only inside the queue's closure.
- The frames are already kept: `minimap-scan.png`, `clickN.jpg` and `no-marks.png`. Audited, they add live frames
  to the test and training runs.
- The proof builds the live binary with the reader. The shadow is first seen in a live run's `events.jsonl`.

## Stage four: frames from published videos (26 Sept)

The game could not run on 26 Sept afternoon, so the owner asked for training data from WoW Forever videos online.

- **Sources.** Six published Zephras Isle videos, all private under `runs/` with frames, labels and models. None
  is in the repository.
  - Three are by one Skyborne Shaman player (21:9, 2560 x 1080): one frame in 2 s.
  - Three are by other players: a Druid, a Hunter and a story playthrough (16:9, 1920 x 1080, taken at
    2560 x 1440): one frame in 3 s.
  - That makes 9723 frames. Other classes, other UI layouts and other quest givers widen what the reader sees.
- **Folder contract.** A video's frames sit under `runs/002_wow_visual/yt_<video>_sNN/`, one folder for each
  10-minute segment.
  - `--baseline` scores a frame as video when its run starts `yt_`, and as game otherwise.
  - Each segment is a run for the split: 24 train, 9 validation, 7 test (40 segments).
  - The game's own held-out runs stay the test that matters.
- **The learned reader labels first** (`m5-perceive --prelabel`, `reader-v1`).
  - Where the rule reader sees a mark that the learned reader calls none, the label is `disputed`, and the
    auditor must settle it.
  - `--audit` refuses to record a pass that leaves a `disputed` or `refused` label as it is.
- **The audit.**
  - The author checked by eye every candidate that either reader called a mark: 2324. 1024 are quest marks
    (544 "!" and 480 "?").
    - Most `disputed` candidates were the target frame's name bar, action bar icons, a level-up digit, campfires,
      skill trees or yellow interface text.
  - `--sheet-frames N` then drew about 100 whole frames in a fixed random order. Every candidate of those frames
    is audited, so readers can be scored frame by frame.
    - It found one mark that neither reader saw: a "!" over a yellow-named NPC.
- **Height.** A 16:9 frame is taken as 2560 x 1440. The world box keeps its share of the height
  (`MarkLabels.world(height:)`).

`m5-perceive --baseline` (sim, offline). Only frames whose candidates are all audited are scored: most video frames
with a mark, and few without. After training with every audited label of the training and validation runs:

| Split (marks) | Rule reader: hits / false / missed | Learned reader: hits / false / missed |
|---|---|---|
| Game, test (8) | 5 / 0 / 3 | 5 / 2 / 3 |
| Game, validation (11) | 10 / 2 / 1 | 8 / 0 / 3 |
| Video, test (16) | 15 / 20 / 1 | 16 / 0 / 0 |
| Video, validation (6) | 5 / 9 / 1 | 6 / 0 / 0 |

The learned reader on the 8 held-out game marks, as the training data grew. Each model was chosen before its test
score was seen, and none is picked by it:

| Trained on | Hits / false / missed |
|---|---|
| Game only | 5 / 0 / 3 |
| + three Shaman videos | 7 / 0 / 1 |
| + the Druid video | 6 / 0 / 2 |
| + the Hunter and story videos | 5 / 2 / 3 |

- **On video the learned reader is near perfect; the rules are not.** On the video test runs it finds all 16 marks
  with no false one. The rules find 15, with 20 false marks.
- **On the live game it does not beat the rules yet.** The held-out game score moves by two marks with each change
  of training data. With 8 marks that is noise: the test cannot tell these models apart.
  - Video frames are compressed and scaled, and the game's own frames are few. More video can pull the reader
    towards what videos look like.
- It named every kind right, on every split.
- The learned reader does not replace the rules: `questMarks` still finds the marks. At this stage it stayed in shadow;
  since live runs 21 and 31 a second, lazy instance acts in two bounded ways (see "The kind the rules cannot name" below).
  What promotion needs is held-out marks from the live game, which the live runs bring (stage three logs them).

## The kind the rules cannot name (live run 31, 27 Sept)

The learned reader acts in two ways, and in neither does it replace the rules.
- **It adds targets.** It supplies click targets the rules miss, and a hover must confirm each of them (live run 21).
- **It filters by kind.** It names the kind of each rule mark (`MarkReader.glyphKind`, the `kind` model on that
  mark's shape crop).
  - A hand-in clicks only "?" marks, and a quest taken only "!" marks.
  - Run 31's hand-in had clicked a giver's "!".

`m5-perceive --kinds FRAME...` prints each rule mark's kind and confidence. On saved frames of 24-27 Sept (the author
checked each crop by eye):
- **Marks of 6 px and more:** 20 of 20 right, all at confidence 0.99-1.00.
- **Far marks of 3-5 px:** not reliable.
  - The same "!" read "!" on one frame and "?" on the next, both at 1.00.
  - Confidence does not separate them: run 31's "!" read right at 0.70.
- **So a mark under 6 px keeps its place** (`QuestLimits.kindMinHeight`), whatever its kind reads.

## Red names the walk may pass (27 Sept)

The walk's red-name rule (`redNames`, M4h) stopped the quest walks through the Juvenile Vuldren field (live runs
35, 44 and 45). A red-brown body, a glint or a far fleck reads as a red name, and far names are too small for
OCR. A learned reader now drops the rule's candidates that are no text at all. A real name, and any other red
text, still stops the walk.

```text
saved frames -> m5-perceive --red-propose (the rule's candidates) -> --red-sheet N (48 a sheet) -> --red-audit FILE
    -> --red-train (design) / --red-train final -> models/redname.mlmodel (private) -> --red-baseline (score)
walk: frame -> redNames -> RedNameReader: drop "none" at 0.8 or more -> dangerNames -> DANGER_AHEAD   (redDanger)
```

| File | Role | Proof |
|---|---|---|
| `Marks.swift` | `BoxRow`, the crop (`redCrop`), the drop rule (`redDrops`), the audit grammar (`redAuditLabels`), the scores (`RedScore`, `RedFrames`) | `MarksTests.swift` |
| `RedNames.swift` | `m5-perceive --red-*`: candidates, contact sheets, audit, Create ML training, the per-split score | argument refusal in `tools/MotorProof.swift` |
| `Reader.swift` | `RedNameReader`: one candidate read through Core ML and Vision | built into `m4-nav`; scored by `--red-baseline` |
| `../m4/NavProbe.swift` | `redDanger`: the walk's danger decision, shared by the live look and `--replay`; `red_read`, `red_dropped`, `red_ms` and `red_filter` in each look's log | built; replayed on saved walk frames |

- **Labels by eye, three kinds.** 953 candidates from 6,350 saved frames, all seen by the author on contact sheets:
  - `name` (191): a hostile creature's red name, near or far (Al'Aketh Convert, Cirrusfly Soldier and Queen, Roiling
    Winds and others).
  - `text` (423): other red text, mostly the UI's error line ("Out of range", "Interrupted").
  - `none` (339): creature bodies, target rings, wings, terrain, red buttons and icons.
- **The walk drops only `none`.** Red text other than a name stops the walk as before; the error line is rare while
  walking. Labelling it `none` at first taught the model that some red text is none.
- **Design, chosen on the validation runs** (model trained on the training runs only):
  - A crop three times the candidate's width dropped 5 of the 29 validation names: the model learnt the scene.
  - A square crop of the width plus two heights dropped 4. Scene-print revision 2 in place of 1 dropped 2, both
    pieces of the Cirrusfly Queen's name (a validation run of 24 Sept).
  - A rectangle hugging the text dropped 1 name but only 24 of 43 false ones (the square: 41); the square was kept.
  - Augmentation (crop, blur, exposure, noise) gained nothing on validation and was left out.
  - `--red-baseline` prints every split, so the test figures were in view while these were chosen. Only the
    augmentation choice also looked at them (worse on test).
- **The final model** is the chosen design fitted on the training and validation runs together
  (`--red-train final`). The test runs were never learnt from.

`m5-perceive --red-baseline` (sim, offline, on the saved frames), the final model:

| Split | Names kept / dropped | False (`none`) kept / dropped | Frames with a name: missed | Frames without: still stopping |
|---|---|---|---|---|
| Training | 155 / 0 | 0 / 258 (learnt on these) | 0 of 94 | 0 of 307 |
| Validation | 29 / 0 | 0 / 43 (learnt on these) | 0 of 17 | 0 of 216 |
| Test, held out | 7 / 0 | 0 / 38 | 0 of 7 | 0 of 148 |

- **Small held-out evidence.** The test runs hold 7 names; the rule alone would have stopped all 38 false ones.
- **The walk's own decision, replayed** (`m4-nav --replay`, sim, offline) on the walk and hunt frames of the quest
  runs of 26-27 Sept that have a candidate:
  - Test runs: 2 of 9 frames still stop, both at a real Cirrusfly Soldier's name.
  - Validation runs: 0 of 25.
  - Training runs: 10 of 131, at 7 names and 3 lines of red text.
- **Not bit-stable.** Scene-print revision 2 with logistic regression; a new SDK may shift the numbers.
- **Fast enough to read in the move's loop.** A read takes about 6 ms a candidate on the Mac (64 ms the first, on
  replay), and no saved frame of the 6,350 had more than 5 candidates: at most about 60 ms against the forward key's
  1.5 s grant. The model loads once, with the first walk body, before any key goes down.
- **Without the model the rule alone decides**, as before (`red_filter: rule` in the log). The model is private.

## Objects on the ground (27 Sept)

Harvesting Windstones asks for 15 Windstone Clusters: small pale cyan crystals on the ground, not creatures. The hunt
never picked one up (live runs 46 and 48: `HUNT_NO_TARGET_FOUND`). The owner's line holds here too (27 Sept, "visual
we agreed not using machine/pixel decode instead of ml"). So the engine sees objects through a learned detector. A
colour test only proposes boxes for the auditor, offline, and is never the engine's eye.

```text
saved frames -> m5-perceive --obj-propose (a colour hint, for the auditor only) -> --obj-sheet N [RUN] -> --obj-audit FILE
    -> --obj-train (design) / --obj-train final -> models/objects.mlmodel (private) -> --obj-baseline (score)
hunt: frame -> ObjectReader (256 px tiles over the ground in view, merged) -> objects in view -> PICK_UP_OBJECT, Jev's choice
```

| File | Role | Proof |
|---|---|---|
| `Marks.swift` | `ObjectTiles` (the tiles), `mergeDetections`, `ObjectScore`; `BoxRow` and the audit grammar shared with red names | `MarksTests.swift` |
| `Objects.swift` | `m5-perceive --obj-*`: the hint (`objectHints`), sheets of whole frames, audit, Create ML `MLObjectDetector` training, the per-split score | argument refusal in `tools/MotorProof.swift` |
| `Reader.swift` | `ObjectReader`: the detector over the tiles of a frame, through Core ML and Vision | built into `m4-nav`; scored by `--obj-baseline` |

- **Labels by eye.** 600 hints from one frame in four of the quest runs' saved frames (whole frames, so a scored
  frame has every hint audited): 145 objects, 455 not (the character's portrait, lanterns, roofs, waterfalls, glowing
  wisps, lightning, zone names).
- **A crystal is small.** The median box is 8 x 11 px. In 512 px tiles the detector learnt almost nothing; 256 px
  tiles show it 1.6 times larger. Create ML fails on an annotation file that opens with an empty tile, so tiles with
  objects come first.
- **Near objects are what a pick-up needs.** The character walks to what it picks up, and a near crystal is large.
  Design model (training runs only, transfer learning on object prints, 1000 iterations), `--obj-baseline` (sim, offline):

| Split | All objects: found / missed / false | 16 px high or more: found / missed / false |
|---|---|---|
| Training | 34 / 76 / 7 | 22 / 3 / 5 |
| Validation | 7 / 20 / 0 | 5 / 2 / 0 |
| Test, held out | 3 / 5 / 0 | 2 / 0 / 0 |

- **The final model** (`--obj-train final`, training and validation runs together, 456 tiles; the one the engine
  loads) against the same boxes. Its training and validation rows are fitted data, not held-out evidence:

| Split | All objects: found / missed / false | 16 px high or more: found / missed / false |
|---|---|---|
| Training (fitted) | 30 / 80 / 5 | 22 / 3 / 4 |
| Validation (fitted) | 7 / 20 / 1 | 5 / 2 / 1 |
| Test, held out | 1 / 7 / 0 | 0 / 2 / 0 |

- **Not qualified.** On the held-out runs the final model found 1 of 8 crystals and neither near one, where the design
  model found both near ones: two boxes cannot tell the models apart, and the test was not used to choose. The
  detector's recall is a candidate; the live run that offers PICK_UP_OBJECT is the evidence, and its frames are the
  next labels.
- **A frame takes 0.24 to 0.38 s** (50 tiles; 0.63 s at most), read at each hunt decision while a collect objective is open (m4/README.md, M4n).
- **The hint misses what it does not propose**, so a detection on an unproposed crystal would count as false, and the
  held-out evidence is small (8 objects, 2 of them near).
- **Which object it is, the detector does not say.** PICK_UP_OBJECT hovers it, and only a tooltip that names an open
  objective is right-clicked (m4/README.md, M4n).

## The facing (27 Sept)

The walk and the hunt read the character's facing from the minimap arrow with a pixel rule (`arrowFacing`). In the open
the rule is good: on 33 frames where the character's own motion over 1.5-4 s gave the bearing, it was within 25 degrees
on 32 (median 3). It fails beside the minimap's icons. In live run 52 (27 Sept) the character stood by the Elemental
Convergence. There the rule read 350 and 316 where the arrow faced about 150, then nothing where it faced about 50, and
the walk ended `WALK_HUD_UNREADABLE`. The owner's line is that the engine sees through learned models, so the arrow's
bearing is now learnt too.

```text
saved walk and hunt frames -> m5-perceive --facing-labels (the rule's steady readings) -> --facing-train [final]
    -> models/facing.mlmodel (private) -> --facing-baseline (score) / --facing-read FRAME... (any frame, rule beside it)
walk, hunt: frame -> FacingReader (the arrow's crop, classes every 10 degrees) + arrowFacing -> fusedFacing
```

| File | Role | Proof |
|---|---|---|
| `Marks.swift` | `FacingCrop`, and `turnedCrop`: the arrow's crop, turned and scaled up, with optional quest-icon dots | `MarksTests.swift` |
| `Facing.swift` | `m5-perceive --facing-*`: labels, Create ML `MLImageClassifier` training, the per-split score, reads of any frame | argument refusal in `tools/MotorProof.swift` |
| `Reader.swift` | `FacingReader`: the bearing, as the probability-weighted mean of the classes near the top one | built into `m4-nav`; scored by `--facing-baseline` |

- **Labels.** The labels are the rule's readings where the next look within 0.6 s repeats them within 8 degrees: 927 frames
  from 27 runs (training 704, validation 140, test 83).
  - A walk's or hunt's looks are matched to their folder by their frame chain (0, 1, 2 ...). A quest read's position
    looks fall between them.
  - A first matching by frame number alone put walk 1's bearings on walk 2's frames: a crop sheet showed arrows facing
    north labelled south. A run whose chains do not fit its folders is left out.
  - Walk looks now log their frame's file, and the rule's own reading (`facing_rule`) apart from the fused facing.
    The labels take the rule's reading, never a fused one.
- **Training crops.** Each training crop is also turned by 60 to 300 degrees, so every bearing is seen on many backgrounds.
  Half of them get one or two yellow dots beside the arrow, as quest icons sit there.
  - Turning by every 30 degrees (8448 crops) failed in Create ML ("Failed to create CVPixelBufferPool"), as did a
    32 px crop. The crop is the frame's 32 px round the arrow, scaled up to 96.
- **Designs.** Each was trained on the training runs and chosen on the validation runs:

| Design | Validation within 15 degrees | Test within 15 degrees |
|---|---|---|
| 48 px crop, turns of 60 | 118 / 140 | 55 / 83 |
| 32 px crop scaled to 96, turns of 60 | 123 / 140 | 62 / 83 |
| as above, with quest-icon dots (**shipped**) | **125 / 140** | **73 / 83** |
| as above, fitted on training and validation (`final`) | (fitted) | 70 / 83 |

- **Which model was shipped, and why.** The shipped model is the design with the dots, trained on the training runs
  only. It has the only estimate on unseen data (validation); the `final` fit's training accuracy was 1.000.
- **The test is spent for this choice.** Both were also scored on the test runs, and read on run 52's frames where the
  rule failed. Run 52 is a test run: the design read 152, 159 and then 30 (0.75) where the arrow faced about 150 and 50;
  the `final` fit read 329 (0.73) for about 50. That comparison informed the choice, so the test set is no longer
  held out for it. The next live runs, whose walk looks name their frames, are the fresh held-out evidence.
- **How the walk uses it (`fusedFacing`, m4/Nav.swift).**
  - Where the rule reads, the walk takes the rule's bearing.
  - Where the rule reads nothing, it takes the reader's bearing at 0.7 or more.
  - Where they disagree, it takes the rule's, unless a turn test showed the rule wrong (m4/README.md).
  - On the test frames the reader was more than 30 degrees wrong on 4 of 83 at 0.7 or more. Live it did worse: on
    runs 54 and 58-62 (27 Sept, a new character, dusk) it was wrong at up to 1.00 where the rule was right, and giving
    no bearing on a disagreement ended run 62's walk. Those runs' walk looks log their frame's file and the rule's
    reading: they are the next training rows.
  - Without the private model the rule reads alone, as before. Every walk look logs `facing_rule`, `facing_learned`
    and `facing_confidence`.
- **A frame takes about 12 ms.**

## Next

1. Audit the shadow's live frames. Let the learned reader replace the rules' marks only when it beats them on held-out
   frames; until then it only adds hover-confirmed targets and names kinds (6 px and more).
2. An object detector (`MLObjectDetector`, in tiles at native resolution) follows when the audit has more marks.
3. The same detector then takes the HUD anchors (minimap, portrait, action bar, target frame), so boxes
   follow the layout instead of fixed pixels.

## Depth (27 Sept)

The owner, 27 Sept: Apple's models that understand the 3D world from 2D pictures ("apple depth pro is the first priority").

- Offline, on 268 live walk frames of 26-27 Sept, labelled by what the next straight move did (moved 0.4 or more: open, 256;
  moved 0.05 or less, blocked, and not a walk's first two decisions: blocked, 12), the view ahead's disparity against the
  ground by the character (rows 0.30-0.45 over 0.55-0.68 of the frame's middle column) separated blocked from open at AUC
  0.79 with Apple's Depth Anything V2 small (Core ML, 25 ms a frame on this M4) and at 0.64 with Depth Pro (Core ML, 5 s a
  frame, all of it on the Neural Engine by its compute plan). Depth Pro's maps of a wall close ahead read flat.
- `DepthReader` (Reader.swift) runs Depth Anything V2 small from the private models folder
  (`runs/002_wow_visual/perception/models/DepthAnythingV2SmallF16.mlpackage`, from `apple/coreml-depth-anything-v2-small`,
  Apache-2.0), compiled once per process; `viewDepth` (Nav.swift, pure) turns its disparity into the ahead, left and right
  ratios. Without the model, walks go on without them.
- M4's old walker (JEV_WALKER=jev) gives Jev the ratios as `view_depth` in each move's state; the steering walk (M4ac) steers
  by 20 columns of the same ratio (`depthColumns`), read once a tick.
- Evidence: offline as above (a side tool in the scratchpad; the frames are private). Sim: `NavTests` on synthetic grids and
  the state packet. Live: the next run.
