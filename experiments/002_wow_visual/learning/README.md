# Learning from human play

Offline annotations, research and replay tooling for a Skyborne Shaman. A replay
measures decisions on a supplied description, not live gameplay or model training.
Start with the [peer review](review_20260924.md) and the
[scoped Skyborne curriculum](skyborne_training.md) before promoting claims to runtime.

## Evidence map

| Layer | Files | What it establishes |
| --- | --- | --- |
| Research | [research/common.md](research/common.md); `shaman_class`, `leveling_fundamentals`, `zephras_walkthrough`, `videos_low`, `videos_mid`, `multiclass_framework` in `research/` | Six Cursor/Composer 2.5 reports. Source claims need build, rank and context checks. |
| Synthesised knowledge | [general](knowledge/general.md), [Shaman](knowledge/shaman.md), [conflicts](knowledge/conflicts.md) | Historical synthesis by Grok 4.7: 119 general facts, class schema, 22 recorded disagreements. A trust label is not independent verification. |
| Video annotations | [brief](zerocks1/brief.md), `zerocks1/part{1,2,3}_decisions.jsonl`, companion techniques | 93 + 75 + 68 annotated decisions. State and human choices were model-read, not independently certified labels. |
| Selected probe inputs | [regen_probe.jsonl](zerocks1/regen_probe.jsonl) | Five selected questions. This file has no before/after Jev predictions. |
| Other video notes | [episode 4](zerocks4_frames.md), [caption notes](stream_captions_techniques.md) | Secondary observations. Caption notes include invalid timestamps such as `0:88:00`. |
| Evaluator | [video_jev.py](video_jev.py) | Offline structural validation, or an explicitly invoked provider-backed replay. |

The original work was recorded on 23-24 September 2026. Zerocks episode #1 is
*Skyborne Shaman: Zephras Isle, WoW Forever Beta Launch Day, No Commentary #1*,
YouTube ID `hCXWhb2_CyQ`, approximately 30 minutes. The original pipeline sampled
1 fps and made 300 six-frame sheets for Grok 4.7. Episode #4 was sampled every
5 seconds. Those are historical pipeline descriptions, not a new visual review.

## Historical replay results: reported, not independently recomputed

| Part | Hand-written facts | Original knowledge loader (`KB=1`) |
| --- | --- | --- |
| 1: 93 decisions | 67/93 | 65/93 |
| 2: 75 decisions | 48/75 | 48/75 |
| 3: 68 decisions | 36/68 | 40/68 |
| Total | 151/236 (64.0%) | 153/236 (64.8%) |

These totals were reported from offline video replay against live Jev
`jev-1.13.0`, not from Jev playing the game. At reviewed commit
`e2874faf280e0fb6d4b052870d01f7a8e210f1d0` the mismatch files were missing: the
repository-wide `runs/` ignore rule had silently excluded `zerocks1/runs/`. They are
now committed unchanged as [zerocks1/replay_mismatches/](zerocks1/replay_mismatches/),
and `--check` confirms that each table cell equals decisions minus that run's mismatch
rows, and that every row is a real decision where Jev differed. The agreeing rows'
probabilities were never kept, so the totals remain historical reports: reconciled,
not re-run. The `part1_facts` run already included the regeneration fact.

The reported regeneration-hint improvement was 4/5 on selected misses. The
committed probe preserves the questions only. Selection on prior errors, missing
paired outputs, and unverified regeneration mechanics prevent a generalisation or
causal-mechanics claim. The reported KB change is just +2 agreements; its direction
alone does not establish a useful or reliable improvement.

The original estimate that 30-40% of mismatches concern UI or streamer habits has
not been recomputed here. Separate discretionary UI from essential quest, vendor,
training and inventory actions; do not discard all UI from an end-to-end curriculum.
Unknown level, activity and objective membership remain important annotation gaps.
**64.8% is neither a live-performance score nor a demonstrated lower bound.**
Human agreement can penalise sensible alternatives and reward an unsafe imitation.

## What changed in the evaluator

`--check` now fails on missing or unregistered decision files, changed per-file
counts, any invalid row, duplicate JSON keys or action IDs, empty states/evidence,
invalid timestamps, and non-finite values. It constructs requests offline, checks
at least 100 flat knowledge facts, and runs 67 counted synthetic regression checks.
It never contacts Jev. This proves structure and request construction, **not**
visual accuracy, truth of facts, provider acceptance, or gameplay skill.

The KB loader now preserves complete trust/source suffixes and adds source line
locations. Fenced YAML is documentation, not an executable class policy. This is a
new prompt variant: historical KB totals must not be assigned to it. The legacy
hand-written `FACTS` string is retained for compatibility, not endorsed; its numeric
regeneration, fight-cost and chase assumptions still need scoped verification.

Importing the module is side-effect free. A live replay validates every input before
its first request, emits evaluator/fact/input hashes to stderr, and emits every
prediction with source, decision index and unrounded probabilities to stdout.
The final stdout line remains `agreement N/M`, so the complete stream is a log,
not pure JSONL. The legacy mismatch file is still written beside the first input.

## Reproduce

```sh
python3 experiments/002_wow_visual/learning/video_jev.py --self-test
python3 -O experiments/002_wow_visual/learning/video_jev.py --self-test
python3 experiments/002_wow_visual/learning/video_jev.py --check
python3 tools/sdlc.py check --base origin/main --head HEAD
```

For this review, the first two commands passed locally with 67 checks each. The
complete committed corpus and macOS Focus Gate were **not** run in the review
environment. Run them on the published exact head before source acceptance.
No live replay was performed and no higher Jev score is claimed.

Only under separately bounded provider-call authority, an operator can use the
existing replay interface and retain complete streams:

```sh
# TYPESAFE_API_KEY must already be supplied securely; do not paste it into source.
# Use a fresh output directory. This invocation makes real provider requests.
mkdir -p runs/002_wow_visual/learning-review
KB=1 python3 experiments/002_wow_visual/learning/video_jev.py \
  experiments/002_wow_visual/learning/zerocks1/part1_decisions.jsonl \
  > runs/002_wow_visual/learning-review/predictions.log \
  2> runs/002_wow_visual/learning-review/manifest-errors.log
```

Local `runs/` is not a publication surface. After privacy review, retain small
complete prediction/manifest derivatives in a deliberately tracked evidence path
and register their proof; do not invent or reconstruct missing historical outputs.

## Runtime relationship and next step

The owner's earlier demo informed M4b: no mana gate before pulling, recovery
choices, melee/casting costs, tapped targets and hotkey range cues. See
`../m4/Hunt.swift` and `../m4/tabletop.py`. The reported tabletop 13/13 is historical;
this review does not recertify it. Important observation-to-completion and missing
frame issues are documented in the [review](review_20260924.md).

Prioritise those runtime regressions and an independently relabelled, held-out
observation set before adding more general facts. Keep original annotations intact;
store corrections separately with pre-action crops, timestamps and review provenance.
Videos, frames, full transcripts, credentials and raw owner captures remain outside
this source change. No new footage was visually inspected in this review.
