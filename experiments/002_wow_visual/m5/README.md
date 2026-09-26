# M5 — learned perception, stage one: a labelling teacher and an honest score

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
| `PerceiveTool.swift` | `m5-perceive`: `--propose` (frames on stdin), `--sheet N`, `--audit FILE`, `--baseline` | argument refusal in `tools/MotorProof.swift` |
| `Teacher.swift` | `m5-teach`: one crop, one fresh on-device session, a guided answer (`exclamation`, `question`, `none`); `--eval SET` | built, never run by the proof |

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
- The example images below were four other crops.

| Prompt | Marks found | False marks (of 60 hard negatives) |
|---|---|---|
| v1: the kind alone | 29 / 31 | 13 (60 in the first run: the model samples) |
| description first, then the kind | 29 / 31 | 8 |
| the same with four labelled example images | 30 / 31 | 35 |

- Guided generation writes the fields in order, so a verdict written after a short description of the
  shape is right more often. Example images made it worse.
- `fm-marks-v2` is the description-first prompt. It uses greedy sampling (the same crop gets the same
  verdict) and a description of at most eight words.
  - On the set it found 29 of 31 marks, each of the right kind, with 8 false marks, in 97 s (about 1 s a
    crop).
  - `m5-teach --eval SET` reruns this measure for any prompt.
- The model's guardrails refuse some game crops (about 6 %). Those are kept as `refused`, for the auditor.
- So the teacher is a wide first filter, not the truth. The labels the detector learns from are audited:
  - `m5-perceive --sheet N` shows the teacher's marks and refusals first.
  - The author checks each sheet by eye, and `--audit FILE` records the corrections.
  - `--baseline` uses an audited label wherever there is one.

Pending: the audited labels, and the rule reader's baseline against them.

## Next

1. Train a Create ML object detector (`MLObjectDetector`) on the teacher's training-split labels, in
   tiles at native resolution, because a far mark is 5-10 px high.
2. Score it on the held-out runs against the rule reader, then run it in shadow beside `questMarks` on live
   runs.
3. Promote it only when it beats the rules on held-out frames.
4. The same detector then takes the HUD anchors (minimap, portrait, action bar, target frame), so boxes
   follow the layout instead of fixed pixels.
