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
| `PerceiveTool.swift` | `m5-perceive`: `--propose` (frames on stdin), `--sheet N`, `--sheet-held N`, `--audit FILE`, `--baseline` | argument refusal in `tools/MotorProof.swift` |
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
  $V/m4/Nav.swift $V/m4/Hunt.swift $V/m4/Quest.swift $V/m5/Marks.swift $V/m5/PerceiveTool.swift \
  $V/runtime/Runtime.swift $V/runtime/Input.swift $V/runtime/DecisionGraph.swift $V/runtime/Experience.swift -o /tmp/m5-perceive
DEVELOPER_DIR=/Applications/Xcode-27.0.0-beta.5.app/Contents/Developer xcrun swiftc -O -parse-as-library $V/m5/Teacher.swift -o /tmp/m5-teach
(cd runs/002_wow_visual && find . -name '*.png') | /tmp/m5-perceive --propose
/tmp/m5-teach && /tmp/m5-perceive --sheet 180 && /tmp/m5-perceive --baseline
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
| `Marks.swift` | adds the three-way run split (`runSplit`) and the two crops (`glyphCrops`) | `MarksTests.swift` (24 checks) |
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
- **Deterministic.** Create ML's scene features with no augmentation: the same labels make the same models, and
  `--baseline` gives the same numbers. Training takes about 20 s on the Mac.
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

## Next

1. Run the learned reader in shadow beside `questMarks` on live runs. It logs what it reads and does not act.
   Its frames go to the audit, and more far marks go to training.
2. Promote it only when it beats the rules on held-out frames.
3. An object detector (`MLObjectDetector`, in tiles at native resolution) follows when the audit has more marks.
4. The same detector then takes the HUD anchors (minimap, portrait, action bar, target frame), so boxes
   follow the layout instead of fixed pixels.
