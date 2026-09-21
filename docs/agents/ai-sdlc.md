# AI-native SDLC: Jev Playground

## Intent and authority

The owner owns why, what, constraints, risk appetite and live-effect authority.
Agents own ordinary execution through merge. A complete instruction/issue is enough;
use its PR as the durable capsule rather than producing three duplicate documents.
This adoption has one decision record because it establishes a lasting policy.

The design adapts [Anthropic's playbook](https://claude.com/blog/the-ai-native-sdlc-playbook):
versioned intent, working instructions, continuous evidence, review, governed delivery
and feedback into the next intent. The article retains human approvals in several
stages. Here, the owner's explicit human-above policy delegates routine source delivery
to the agent, without delegating new credentials, spending or live-machine effects.

## Six-stage loop

| Stage | Agent action | Smallest sufficient durable output |
| --- | --- | --- |
| Plan | Resolve acceptance, scope, authority and uncertainty | Existing instruction/issue linked in PR |
| Design | Choose affected boundaries, proof and rollback | Capsule/PR; a decision document only when reusable |
| Build | One coherent source change with tests | Topic-branch commits |
| Test | Narrow diagnostics, then exact-head selected gate | GitHub run and manifest: base/head/tree, selected/omitted checks |
| Deploy | Review, observe gates, guarded merge, read back main | Exact-head GitHub review, merged PR and introduced-main run |
| Maintain | Turn escaped defects into regression and repair | One automatically deduplicated current-main repair issue |

No service deployment or local-machine execution is implied by source integration.
Do not upgrade historical experiment results to acceptance of new code.

## Right-sized evidence

`tools/sdlc.py` owns the executable route. A clean committed checkout, resolvable
ancestor base, exact head, regular files and the complete no-renames diff are required.
Renames therefore expose both the deletion and addition. Invalid refs, empty changes,
unknown paths, missing contracts and unclassified executable inputs block; they never
fall back to a documentation pass.

F0 always checks integrity and structural governance. Only modifications of README
or one-level `docs/changes/*.md` can omit behavioural tests. Additions/deletions,
policy, CI, review, selectors, helpers and their tests select the entire maintained
offline suite (F1/F2). This repository starts without product code on main; do not
pretend it has a product test lane. Promoting an existing experiment must register
its actual offline tests/consumers in the selector and CI in that same delivery.

F3 requires authorised bounded actual-runtime evidence when fixtures cannot prove
a claim. F4 is the external-effect boundary, not governing rule 4. Even read-only
screen/audio capture can expose private data and needs a bounded target. Any live
authority must identify the machine, account, action, limits, stop, recovery and
post-condition. Inference, code inspection and a successful source gate cannot prove
that a Mac action, game interaction or provider result actually occurred.

## Review and integration

`REVIEW.md` supplies a three-pass rubric, not another permanent queue. Prefer a
fresh reviewer; explicitly disclose an author review rather than inventing independence.
A deterministic review is sufficient for genuinely mechanical work. Existing task
requirements for independence cannot be waived. One material-risk review per coherent
head, batched findings, no nit-only cycles. Never approve the author's own native PR.

`tools/merge_pr.py` uses an existing `gh` authentication session; it does not install
software, request keys, approve reviews or modify protections. Read-only is the default.
Its pure decision function and its pagination/network boundaries have offline tests.
The integration predicates are:

- Same-repository open, non-draft PR, exact full head, clean mergeability and current
  main ancestry; the pinned native workflow ID/path and latest exact-head PR run must match.
  The observed GitHub workflow ID is 363313034; recreating it requires an explicit contract update.
- Its authentic `Focus Gate` job must succeed. Other check runs/statuses must not be
  pending or failed; a skipped/neutral unrelated check cannot replace the Focus Gate.
- A trusted exact-head review must explicitly pass with disclosed independence; native
  requested changes, newer negative verdicts and unresolved threads block.

The helper rechecks head/base immediately before an expected-head squash merge and
reads the result back. A main advance during the final request is not atomically
prevented by GitHub's head guard. A merge queue/strict server protection would close
that gap; these files do not claim to install it. Never bypass a server-side blocker.
Connector agents must apply these same predicates and read back the merge.
Native run provenance is bound by the observed workflow ID, path, PR and head; a
separate mutable workflow-definition lookup adds no proof of the tested candidate.
Future workflow activation is observed through the post-merge run, not assumed.

CI runs candidate source on an ephemeral hosted runner with read-only repository
permission, no project secrets and no persisted checkout credential. The source gate
is not a cryptographic defence against an owner rewriting its own policy. Review
CI/selector changes substantively; branch protection is a separate server control.

After merge observe the introduced-main gate. Recover a failure through a fix/revert
PR, not a force-push. Delete only the merged task branch where tooling permits;
never delete experiment branches as governance cleanup.

## Automation and maintenance

Workflows are JSON-formatted YAML: valid workflow documents, directly parseable by
Python's standard library, with no YAML-package bootstrap. Third-party actions are
pinned to reviewed full commit IDs. PR updates trigger one gate; feature-branch saves
do not. Superseded runs cancel. Main reclassifies its introduced diff; manual dispatch
runs all maintained offline tests. No scheduled provider/model polling is configured.

The maintenance workflow has issue-write permission but never checks out or executes
repository code, nor consumes logs/artifacts as instructions. It verifies the workflow,
repository, current main SHA and event before opening/updating one bot-owned repair
issue. Stale failures are ignored; a green current-main result closes the repair issue.
The actual inline workflow script is exercised with mocked GitHub responses in Node.
This proves decision behaviour, not a previously unobserved live failure event.

Repair intents are ready for the next executing agent. No unattended LLM worker,
new provider account, API credential or paid schedule is provisioned. This is an
explicit capability boundary, not a claim that an issue repairs itself. An existing
local agent follows AGENTS.md without routine human prompts; provisioning a persistent
machine worker needs its own exact-host and budget authority.

## Cost and stop rules

Measure gate elapsed time and scope automatically; record first-pass success/rework
from PR history. The manifest's zero model tokens describes the deterministic gate
only. Author-session tokens are unknown unless supplied by the host; never fabricate
savings or a percentage improvement without a baseline. Do not add telemetry calls.

Use one context capsule, search-first reads, one environment setup, independent-only
parallelism and no unchanged reruns. Default to at most two repair iterations per
unchanged failure hypothesis; new evidence may justify another bounded hypothesis,
not an unbounded retry loop. A missing gate stops its claim, not unrelated authorised
work. Under-engineering omits relevant proof; over-engineering adds maintained work
that cannot alter a decision, catch a reachable failure or save more recurring cost.
