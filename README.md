# Jev Playground

A collection of independent experiments with TypeSafe's Jev model.

## Experiments

| ID | Experiment | Status | Next step |
| --- | --- | --- | --- |
| 001 | [WoW fishing](experiments/001_wow_fishing/README.md) | Visual-contract regression confirmed; expanded pipeline is not accepted | Validate corrected observations before further live A/B runs |

Each experiment owns its question, inputs, policy, evaluation and findings in
`experiments/NNN_short_name/`. Use a new, permanent number for each experiment;
do not renumber older experiments. Record unsuccessful results as well as successes.
For the first experiment, use the [Test A playbook](experiments/001_wow_fishing/playbook.md)
or [Test B playbook](experiments/001_wow_fishing/test-b-playbook.md).
See [experiment conventions](experiments/README.md) before adding another one.

Keep raw recordings in `data/<experiment_id>/` and generated results in
`runs/<experiment_id>/<run_id>/`. Both directories are ignored by Git.
Small synthetic fixtures and reviewed findings belong with the experiment.

## Agent setup

The official TypeSafe agent skill is installed globally on this machine in
`~/.codex/skills/typesafe-ai/`, rather than bundled with this repository.
Ask your coding agent to **use the TypeSafe skill** when working with Jev.

This installs agent guidance only. API experiments require a TypeSafe account
and a `TYPESAFE_API_KEY` environment variable. Keep the key out of source control.
The first experiment uses a native Swift helper and a Python standard-library
runner. Short diagnostic recording uses macOS's built-in `screencapture`; no
TypeSafe SDK or extra capture package is installed.
Shared code will be extracted when there is a demonstrated second use; fishing
capture, perception and control should not become assumptions of every experiment.

## Verified starting point

On 20 September 2026, one synthetic urgency request returned HTTP 200 using
`jev-latest`, resolving to `jev-1.13.0`. Its Noul answer was 0.98, measured request
time was 0.667 seconds, and usage was 286 input / 21 output tokens.
This is a session observation, not a retained benchmark dataset or fishing result.
Subsequently, screen observation and assisted casting were verified; see the
[fishing findings](experiments/001_wow_fishing/findings.md). The local script has
completed an earlier 15/15 fixed-scene Test A run. Live Test B subsequently achieved
16/17 catches in 314 seconds, including Jev readiness checks. Full Jev weapon/page
preparation was verified separately. A final same-source A trial stopped before
five minutes and WoW was later at login. Parity and generalisation remain open;
see the experiment README for the post-run correction awaiting live verification.

## Official documentation

- [Introduction](https://docs.typesafe.ai/introduction)
- [Quick start](https://docs.typesafe.ai/introduction/quickstart)
- [Agent skill](https://docs.typesafe.ai/agent-skill)

The latest [visual audit](experiments/001_wow_fishing/visual-audit.md) identifies a
tracker-dropout/submersion mix-up in the expanded pipeline. Historical results
above do not establish acceptance of that version.
