# Jev Playground

An autonomous game-playing engine that learns from websites, walkthroughs, owner
or online video demonstrations, and bounded in-game exploration. The current focus
is WoW Forever / Skyborne Shaman: acquire useful skills, execute them with **JEV +
a visual decoder + deterministic scripts**, and improve from observed outcomes.

The owner sets the goal and run boundaries; agents own learning and engineering.
The engine should play without a human directing every action. This is the mission,
not a claim that the current probes have passed unattended qualification.

```text
sources / videos / exploration → evidence → candidate knowledge and skills
                                     ↓ held-out evaluation and promotion
pixels → visual decoder → structured state + relevant knowledge
                                     ↓
                         JEV or validated script policy
                                     ↓
                  admissibility / bounded execution / watchdog
                                     ↓
                    fresh outcome → next learning question
```

Start with [AGENTS.md](AGENTS.md). The [AI-SDLC operating model](docs/agents/ai-sdlc.md)
connects the learning, playing and engineering loops under the four rules. Scripts
replace unnecessary AI work in the control loop; the model is reserved for choices
that benefit from context. Every run must identify which controller actually acted.

## Current implementation and evidence

| Surface | Existing home | Evidence boundary |
| --- | --- | --- |
| Fishing | [001](experiments/001_wow_fishing/README.md) | Independent experiment; its reports own acceptance and historical results. |
| Visual state | [002](experiments/002_wow_visual/README.md) | Screen-derived packets and calibration, not hidden game-state access. |
| Movement, seeking, combat | [M0](experiments/002_wow_visual/m0/README.md), [M1](experiments/002_wow_visual/m1/README.md), [M3](experiments/002_wow_visual/m3/README.md) | Bounded probes; supervised results do not establish unattended reliability. |
| Navigation and hunting | [M4](experiments/002_wow_visual/m4/README.md) | Deterministic skills with JEV choices; current fixes and live gaps are recorded there. |
| Learning and replay | [Learning](experiments/002_wow_visual/learning/README.md) | Research, video annotations, knowledge and replay tools; replay agreement is not live skill. |

These surfaces are now on main. Earlier branch reports remain historical records,
not the current execution contract. Preserve experiment IDs and existing evidence;
read the current milestone README before making capability claims. A new instruction
or knowledge file does not automatically reach the live decision consumer.

## Working with the engine

Give an outcome, acceptance criteria and boundaries, for example: learn to recognise
an unfinished quest and reach its objective while preserving unknowns and existing
safety stops. The agent chooses the smallest complete learning/implementation slice,
tests it and integrates through a PR. New live effects require a specific run envelope;
within an authorised, validated envelope, do not require per-action approval.

Use [experiment conventions](experiments/README.md) for source identities, video time
ranges, split discipline and complete prediction/outcome records. Learning here means
verified knowledge, prompts, calibration and executable skills, not changing JEV's
weights. In the current integration JEV receives text/structured state; see the
[TypeSafe model contract](https://docs.typesafe.ai/models). Media interpretation belongs
to the decoder/learning pipeline, not a supposed video input to JEV.

## Offline repository checks

macOS with Swift and Git cover every check; Node.js 22+ runs the maintenance workflow's
test. Offline checks never need a Jev key or contact its provider. Use a clean committed
topic branch:

```sh
tools/sdlc route --base origin/main --head HEAD
tools/sdlc check --base origin/main --head HEAD
```

`Focus Gate` selects registered evidence for the exact diff. Unknown executable paths
must bring genuine proof rather than receive a blanket documentation pass. The merge
helper is read-only unless `--execute` is supplied; it uses existing `gh` authentication.
For provider work, consult the [TypeSafe docs](https://docs.typesafe.ai/introduction)
and an available local TypeSafe skill; never assume another machine's installed skill
or credentials exist here. Keep `TYPESAFE_API_KEY` out of source, prompts and logs.

## Deployment is a separate claim

Merging deploys source, instructions and GitHub workflows, not a game session. This
alignment provisions no persistent learner/player or additional paid model service.
GitHub checks and repair-intent creation are automation, not proof that a repair or
learning worker is running. Main protection is a server setting, not guaranteed by
these files. Actual autonomous play needs tested stop/takeover/recovery, profile-bound
capabilities, available runtime and applicable service permission.

Keep new raw captures and bulk runs untracked by default; reviewed small derivatives
use an explicitly tracked evidence path. Existing tracked historical media is retained,
not deleted or silently reclassified. [Initial adoption record](docs/changes/2026-09-21-ai-sdlc.md).
