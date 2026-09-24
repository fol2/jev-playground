# Runtime boundaries: first integrated slice

Base: `bfff663be71efc1bc1b84e6f3b3b808e112ae2fa`. The owner's architecture review
asks for roles, not a Python-versus-Swift split. Keep the native runtime and existing
algorithms. Deliver one in-process boundary used by Fight, Nav and Hunt, not a new
framework or a claim of general autonomous gameplay.

## Responsibilities and actual consumers

| Role | Current consumer and this change |
| --- | --- |
| Perception | Native probes stamp the actual complete frame, capture stream and fixed session geometry. `Observation<Value>` explicitly distinguishes unavailable evidence; Obs/NavObs/HuntObs retain their domain measurements. |
| State and memory | `TaskMemory` preserves the goal, active/suspended skills and six recent typed outcomes. Hunt keeps its existing objective and navigation episode data; combat completion returns to hunt for a fresh decision, not an automatic replay of old movement. |
| Policy | Existing `admissible`, `navAdmissible`, `huntAdmissible`, prompts and rules remain unchanged. Contexts label these inherited policies `fight/nav/hunt-legacy-v1`. Their strategic filters are not proof of physical impossibility. |
| Executive | `RuntimeExecutive` issues locally identified, expiring, one-shot decision contexts. All three core loops re-observe and recheck before executing a reply. Skill transitions revoke pending decisions. |
| Skills and input | `runtime/Input.swift` holds the existing watchdog/retrying key-up mechanics in one store. Nested live Hunt/Fight use revocable scopes on that store; mouse loot dispatch uses the same ownership gate. |
| Learning | Existing video/replay knowledge remains separate. No general LLM is added to the play path, and no runtime self-edit or model training is introduced. |

`ObservationStamp` is evidence identity, not a semantic detector. Target names are
visual *cues*, not unique entity IDs: same-name substitutions can remain unresolved.
No missing cue is upgraded to a verified target. The fixed-layout assumptions remain.
Capture time and `clockOrigin` identify the caller's monotonic domain; a nested
fight's relative time must not be confused with the parent's host-clock time.
Python `screen-evidence/v1` remains a separate offline packet format: no implicit
cross-language serialisation or automatic migration of its consumers is claimed.

## Changed behaviour, deliberately small

A reply is rejected if it is superseded/consumed, past its locally set deadline,
no longer admissible, or based on a changed stream/geometry/target cue. The latest
frame must be fresh and non-reordered. Nav also rechecks combat, health and arrival
before moving. A fresh frame does not make old assumptions true: current admissibility
and visual cue agreement are required as well.

Request expiry uses the existing per-stage timeout and remaining run duration.
The provider may still retry internally; a response arriving past this deadline
cannot execute merely because its HTTP request eventually succeeded. This tightens
the previous behaviour and is NOT a catch-rate, combat-success or latency claim.
A rejection releases a held bolt/forward key and re-observes; owner-stop and expired
requests terminate under their explicit outcome. Stopping input is not player safety.

Input handoff first confirms release of the parent. Only then is the child scope
active. Suspended parents and retired children cannot press/lift/grant or dispatch
mouse clicks. Child completion must confirm release before the parent can resume;
an unconfirmed release becomes `INPUT_HANDOFF_FAILED`. Root cancellation revokes all
scopes. Key-up retries remain observable and watchdogs share one locked state store.
This is one process's ownership boundary, not protection against a second executable,
OS failure, physical user input or every failure of private Apple event APIs.

## Preserved policy, not implicitly loosened

Owner stop/time budgets and fresh evidence are execution constraints. Availability
of a target, a learned skill and a calibrated layout are preconditions. The inherited
90% start-health, 60% walking-health, nearby-hostile exclusions and repetition costs
mix conservative run limits with strategy. This slice preserves them all and labels
the policy version; it does not retrospectively reclassify or weaken their authority.
The detector thresholds, ability discovery, movement algorithms, prompts, action menus,
model version and bounded provider retry behaviour are retained.

## Evidence and limits

Run `python3 -m tools.motor_offline` on macOS. It compiles the actual native binaries,
the existing M0/M1/M3/M4 suites and counted runtime tests. Contract tests cover stale,
reordered and mismatched replies, one-shot consumption and retained task state. New
integration tests call the actual core Fight/Nav/Hunt loops with simulated observations
and responses, including state changes *during* inference. Input tests exercise the
same store/scopes used by the native Hunt/Fight adapter, including failed releases.
SimHunt's fight is still a documented canned outcome, not a combat simulation.
Native compilation and these checks do not prove OS input or live-game success.

No game, screen/audio capture, provider request, local agent, installation or account
change is run for this delivery. Historical evidence is untouched. The one-off tracked
source-export workflow used for review is absent from the final tree. Revert this PR
to recover the previous code; no user data migration is required.

## Next bounded slice, not implemented here

Extract a versioned profile/policy/knowledge catalogue with real replay AND live
request-consumer tests; reconcile conflicting historical mechanics before promotion.
Do not wire unverified Markdown into live decisions merely to claim a shared loader.
Persistent task checkpoints, per-field freshness/unknown migration, distinct entity
identity and full navigation-to-combat-to-waypoint resumption remain separate work.
No service, database, vector store or general planner is needed for the next slice.
