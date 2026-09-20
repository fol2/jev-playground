# Experiment conventions

## Organisation

Each `NNN_short_name/README.md` should describe the question, scope, current
status, next step, reproduction instructions, evidence and unresolved issues.
Keep experiment-specific code, fixtures, prompts and configuration together.
Choose dependencies per experiment before introducing a repository-wide runtime.
Only extract shared client or logging utilities when another experiment needs them.

Separate synthetic API checks, recorded-data evaluation, live observation and
input execution in both commands and reported results. A successful earlier stage
does not establish a later stage. Commands should state whether they contact the
provider; offline checks must work without an API key.

## Data and run records

Use `data/<experiment_id>/` for local recordings and annotations. Identify each
recording by a stable ID and SHA-256 hash; do not rely on its filename alone.
Keep synthetic examples clearly labelled and separate from real observations.
Do not commit recordings or private observations by default.

Use `runs/<experiment_id>/<UTC_timestamp>_<unique_suffix>/` for each run. Never
overwrite an earlier run. The planned manifest should contain:

- Experiment ID, run ID, UTC start time and mode (synthetic, replay or observer).
- Git revision and dirty status, dependency versions and machine/runtime details.
- Dataset IDs and hashes, split membership, configuration and question snapshots.
- Requested model and actual response model, timeout/retry settings and call budget.
- Outcome, failures and the paths to per-decision records and summary metrics.

Per-decision JSONL records should retain the actual input state, question version,
raw answer, probabilities, confidence, token usage and request duration. Include
observation and decision timestamps, policy identity and any rejection reason.
Use monotonic clocks for elapsed time and UTC timestamps for run identification.
Never record API keys, authorisation headers or an environment dump.
These are preparation conventions; a run writer is not implemented yet.

## Reporting

State sample counts and exclusions alongside metrics. Report errors and abstentions,
not only successful decisions. Preserve model/configuration identity across comparisons.
Publish a small reviewed `findings.md` within the experiment when evidence exists,
including limitations and the next question; keep bulk output in ignored run folders.

All repository prose and model instructions use UK English. Communicate with the
user in Hong Kong Cantonese.
