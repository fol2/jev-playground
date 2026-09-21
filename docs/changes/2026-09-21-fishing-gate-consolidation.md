# Fishing gate consolidation — 21 September 2026

## Accepted intent

Fold the separate `.github/workflows/fishing-offline.yml` into the single Focus
Gate so one exact-head run owns all offline proof, and register the fishing source
and evidence surface so the gate can no longer be green while the experiment is
unchecked. CI stays hosted, read-only and provider-free.

## Design and implementation

The Focus Gate job in `.github/workflows/ai-sdlc.yml` moves from `ubuntu-24.04` to
`macos-14`, because the fishing checks need `swiftc` and the native image
frameworks that the retained-image regressions load. It sets `TYPESAFE_API_KEY: ""`
so a provider key can never be picked up from the environment. `tools/sdlc.py`
asserts the expected runner per workflow, so the maintenance workflow stays on
`ubuntu-24.04` and neither can drift unnoticed.

`tools/fishing_offline.py` is the registered entry point:

```sh
python3 -m tools.fishing_offline
```

It runs, in order:

- `ast.parse` over every registered fishing Python file (syntax only, no import).
- `sh -n` over every registered shell script.
- The 39 shared recording checksums in `evidence/shared-recordings.json`, rejecting
  absolute paths, `..` segments and anything outside `data/001_wow_fishing/`.
- `json.loads` over every evidence `.json`, and every line of every `.jsonl`.
- `test_core.sh` (synthetic pixels, fake clock, fake HTTP).
- The experiment's Python unittests.
- `build.sh`, which compiles the real helper and runs the retained image and
  decision fixtures through `--self-test`.
- `setup_camera.sh --self-test`.
- `swiftc -typecheck` over `background.swift`, the four background-click probe
  files and `data/001_wow_fishing/pilot_20260921/recorder.swift`.

No capture, no input, no provider request and no live effect at any step.

## Routing

`tools/sdlc.py` gains `FISHING_CODE`, an explicit list of registered fishing
executables and sources, and `fishing_path`, which additionally admits evidence
and recording extensions under `experiments/001_wow_fishing/` and
`data/001_wow_fishing/`. Anything else under those trees still fails closed, so a
new script cannot arrive without registering its actual offline proof.

`inspect` routes the whole tree, not only the diff, so one unclassified tracked
file holds the gate on every future head. `experiments/README.md` had been in that
state since `45895de` and is now classified as allowlisted documentation.
`tests/test_sdlc.py` gains a check that routes every tracked path, so the next
unregistered file fails in the test suite rather than in CI.

## Evidence location

The adopting PR and its exact-head Focus Gate run are the execution record. A
local simulation of the gate over the full change set reported `result: PASS` with
checks `integrity, governance, python-tests, automation-tests, fishing-offline`.

## Non-goals

- No change to fishing runtime behaviour is claimed by this record; those changes
  and their offline proof are recorded in the experiment's `findings.md`.
- No live validation, acceptance or Mac-local effect. CI never runs on the owner's
  Mac and no provider account, key or spend is introduced.
