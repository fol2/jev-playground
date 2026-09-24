# Exact-head review

Read the accepted task, current-main contract, base/head, changed files and relevant
evidence, not the author's transcript. Prefer one fresh-context reviewer when
available. The owner agent may perform an explicitly labelled author-review for
bounded source-only delivery; this is not independent assurance. A task requiring
independence or a live/security claim without decisive evidence stays blocked.

Review three passes: correctness/negative cases; security and effect authority;
acceptance and the four rules (missing proof AND unnecessary recurring cost).
Look for stale SHAs, false-green selectors, missing/deleted consumers, untrusted
workflow inputs, secret exposure, unsafe defaults and unproved runtime claims.
Do not repeat deterministic checks without a new hypothesis. Style nits do not
block. Batch material findings with file/line, failure scenario and required proof.

## Learning and gameplay changes

Apply these questions only to the affected boundary; do not commission a second
ceremonial review. The operating model lives in docs/agents/ai-sdlc.md.

- Can each promoted claim be traced to a compatible game profile and real source,
  frame/PTS or exploration observation? Are interpretation, unknowns and conflicts
  explicit? Captions and contact sheets do not prove every frame was inspected.
- Does decision input contain only pre-action evidence? Are held-out episodes kept
  separate from tuning, including adjacent frames from the same episode? Human
  agreement, schema validation and live success are different claims.
- Which actual runtime consumer receives the versioned knowledge/skill, and what
  test proves the consumed request or action? A knowledge file is not deployment.
- Are controller provenance, visual freshness, admissible actions, deterministic
  watchdogs, bounded exploration, owner takeover and rollback preserved? Missing
  vision is not safety or completion. New knowledge must not rewrite authority.
- Is the result qualified only for its tested profile/mode? Is the evidence sufficient
  for unattended use, rather than copied from a supervised trial? Is repeated frame
  analysis or model control replaceable by cached evidence or a proven script without
  losing timing, accuracy or acceptance?

Submit a GitHub **COMMENT** review on the exact commit, using:

```text
AI-SDLC review: PASS
Independence: author-review
Head: <full SHA>
Evidence: <commands/results and CI run>
Findings: <resolved findings or none, with scope>
Omissions: <unobserved effects and residual uncertainty>
```

Other verdicts are REQUEST_CHANGES and INCONCLUSIVE. Independence is fresh-context,
author-review or deterministic; never impersonate another reviewer. Do not submit
APPROVE as the author. Only the latest trusted explicit verdict on the exact head
counts; native changes-requested reviews and unresolved threads still block.
A changed head invalidates the verdict. Fix once, then review changed risk only.
