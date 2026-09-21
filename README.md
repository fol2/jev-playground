# Jev Playground

Source-controlled local-machine experiments and evidence, managed through an
AI-native SDLC. The owner sets outcomes and effect boundaries; agents own ordinary
research, implementation, validation, review and PR integration.

Start with [AGENTS.md](AGENTS.md). The [operating model](docs/agents/ai-sdlc.md)
explains the four rules, evidence routes, review, merge and repair loop.

## Offline repository checks

Python 3.11+, Git and Node.js 22+ are sufficient; no package installation, API key,
Jev request or Mac permission is needed. Use a clean committed topic branch:

```sh
python3 tools/sdlc.py route --base origin/main --head HEAD
python3 tools/sdlc.py check --base origin/main --head HEAD
```

`Focus Gate` runs once per PR update and on the introduced main diff. The merge
helper defaults to read-only; `--execute` uses an existing authenticated `gh`
session and an exact-head guard. Never paste a credential into the repository.

## Preserved experiments

At adoption, main contained only this README. Existing work remains on its branches:
[experiment/test-a-playbook](https://github.com/fol2/jev-playground/tree/experiment/test-a-playbook),
[experiment/test-b-parity](https://github.com/fol2/jev-playground/tree/experiment/test-b-parity),
and [refactor/fishing-observation-loop](https://github.com/fol2/jev-playground/tree/refactor/fishing-observation-loop).
This governance change does not merge, rerun or certify those experiments. Promotion
must bring its genuine offline checks into the selector; unknown paths cannot pass
as documentation. Preserve existing experiment identifiers and historical evidence.

## Deployment boundary

Merging deploys the repository policy and GitHub workflows, **not** anything onto a
Mac. No live capture/input, game launch, provider call or machine change is enabled.
Failed current-main CI creates or updates a repair issue; an executing agent consumes
it. There is no provisioned unattended model worker or paid scheduled model call.
Branch protection is a server setting, not something these files can guarantee.

[Adoption decision and source audit](docs/changes/2026-09-21-ai-sdlc.md).
