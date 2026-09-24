# Experiment and learning conventions

## Organisation

Each `NNN_short_name/README.md` describes the question, scope, current status,
next step, reproduction, evidence and unresolved issues. Preserve permanent IDs.
Experiments are capability increments towards autonomous play, not mandatory isolated
products. Keep their code, fixtures, prompts and configuration together; extract shared
code when a second real consumer needs it. Do not rename a probe into a proven engine.

The learning/playing lifecycle and promotion requirements are in
[the operating model](../docs/agents/ai-sdlc.md). Existing research, knowledge and replay
live in [002/learning](002_wow_visual/learning/README.md); use that home rather than
creating a parallel knowledge system. A learning trial is not a PR per frame or fact.

Separate offline fixtures, recorded-data evaluation, provider-backed replay, live
observation, supervised execution and qualified unattended execution in commands and
reports. A synthetic state sent to real JEV is still a provider call. No earlier mode
establishes a later one. Offline checks must work without a key or network request.

## Sources, video and run records

Identify sources by stable ID, URL/path, retrieval date and content hash where retained;
record client/build, race/class, level/spells and UI/control context, with unknowns explicit.
Use local `data/<experiment_id>/` for raw recordings and working annotations. For video,
keep the original ID/hash, frame index/PTS, extraction settings, selected time ranges,
crops and gaps. Keep pre-action observations distinct from action labels and future
outcomes. Store corrections separately from original annotations with reviewer provenance.
Synthetic fixtures are not observations. Split evaluation by episode/session/source, not
adjacent frames; selected misses are a diagnostic set, not a held-out benchmark.

Do not commit raw recordings or private observations by default. Existing tracked
historical media stays intact. Small privacy-reviewed, reproducible evidence derivatives
need a deliberately tracked path: an ignored `runs/` directory is not a published result.

Use `runs/<experiment_id>/<UTC_timestamp>_<unique_suffix>/` per run; never overwrite it.
Record the following when applicable, reusing existing writers and schemas:

- Experiment/run IDs, UTC start, actual mode, machine/account safe IDs and run authority.
- Git revision/tree and dirty status; decoder, calibration, knowledge, prompt and policy
  versions; requested and returned model; applicable game/character profile.
- Dataset IDs/hashes, split membership, configuration/question snapshots and runtime
  knowledge IDs actually consumed (not merely files present on disk).
- Time/call/token/loss limits, timeout/retry policy, outcome, failures, interventions,
  exclusions and paths to complete per-decision evidence.

Per-decision records retain the actual input state, source frame/time/target/geometry,
question version, raw response/probabilities, chosen/executed action, controller identity
(JEV/RULE/SAFETY/OWNER), rejection reason, duration/usage and fresh observed outcome.
Use one monotonic clock for live freshness and elapsed time, UTC for run identification;
record explicit mappings from source-video PTS rather than mixing unrelated clocks.
Never record API keys, authorisation headers or an environment dump.

These are evidence requirements, not a claim every current writer implements every
field. Name missing fields and extend only the consumer/writer needed for the claim.

## Reporting

Publish a small reviewed finding with sample counts, exclusions, errors, abstentions,
interventions and limitations. Preserve model/configuration identity across comparisons.
Human imitation agreement is a diagnostic, not a safety or objective-completion score.
A promoted fact/skill needs its actual runtime loading and held-out behaviour proved;
otherwise label it research or candidate. Freeze the policy for a measured run; queue
new observations for a later evaluated version. This is not JEV weight training.

All repository prose and model instructions use UK English. Communicate with the
owner in Hong Kong Cantonese. Learning evidence never grants live-effect authority.
