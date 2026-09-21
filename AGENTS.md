# Jev Playground — Agent Contract

This repository owns repeatable local-machine experiments, their source and evidence.
Start here; load [the operating model](docs/agents/ai-sdlc.md) only as needed.

## Four inseparable rules

1. **AI-SDLC DNA:** agents own Plan → Design → Build → Test → Deploy → Maintain.
2. **Minimise Wall Time (Maximise Effectiveness):** remove waiting and repeated work.
3. **Minimise Token Consumption:** use bounded context and deterministic automation.
4. **No compromise:** never drop acceptance, safety, compatibility or relevant proof
   to achieve rules 2 or 3. Use the cheapest decisive evidence that can falsify each
   material claim. Unrelated green checks are not additional assurance.

## Authority and human-above autonomy

The complete owner instruction or active issue is accepted intent. Apply its scope,
non-goals and limits, current safety/contracts, this file, then the nearest code/tests.
Historical reports are evidence, not present permission. Never rewrite them as new proof.

One owner, one topic branch from current main, one independently mergeable outcome,
one PR. Agents research when needed, plan once, implement, test, review, fix, merge
and clean up. Do not request routine plan approval, test selection or merge-button
handoffs. Parallel work must have independent files/worktrees and explicit ownership.

Escalate only unresolved binding ambiguity, unapproved breaking or irreversible
changes, credentials/provider terms, new spend, or unavailable decisive evidence.
A blocked live action does not block independent authorised source work.

## Smallest sufficient context

Read current-main instructions, the task, touched paths and nearest tests. Search
before opening long files. Keep one capsule: outcome, non-goals, constraints,
acceptance, base/head, decisions, evidence, blocker and next action. Do not duplicate
an adequate issue into a second intent/spec/plan or replay whole transcripts.
Bound research by a question, immutable inputs, cheapest discriminating experiment,
budget and stop rule; promote only the chosen result, not every trial.

## Source delivery is not live-machine permission

Default to offline fixtures and dry-run. Repository merge does NOT authorise Mac
execution, screen/audio capture, accessibility/input control, game launch, real Jev
requests, account changes, installs, sudo, launchd, deletion, reboot or provider spend.
Live work needs the exact machine/account/action, limits, stop condition, recovery
and post-condition in current owner authority. Stop on identity drift or ambiguity.
No game-memory injection. Keep raw capture, local settings and credentials untracked;
never print secrets or copy them into prompts, reviews, logs or evidence.

## Evidence and delivery

```sh
python3 tools/sdlc.py route --base origin/main --head HEAD
python3 tools/sdlc.py check --base origin/main --head HEAD
python3 tools/merge_pr.py PR_NUMBER FULL_HEAD_SHA          # read-only preflight
python3 tools/merge_pr.py PR_NUMBER FULL_HEAD_SHA --execute
```

The gate requires a clean committed tree. F0 proves identity/integrity; F1/F2 prove
changed behaviour and affected contracts. F3 is separately authorised real-runtime
proof; F4 is separately bounded live effect, never granted by CI. Unknown executable
paths fail closed: add their actual offline proof before promotion, not a blanket skip.

Run narrow diagnostics during editing, then the selected coherent-candidate gate
once. Re-run only invalidated proof; widen only for a failure or uncovered boundary.
Do not weaken tests, conceal errors or claim unobserved runtime/CI results.

Use [REVIEW.md](REVIEW.md) for one substantive exact-head review. Prefer a fresh
reviewer; disclose author-review honestly when no independent reviewer is available.
Never self-approve a native PR or claim an author review is independent. Mechanical
changes may use a recorded deterministic review. Batch findings; repeat only after
material changes or unresolved risk. An explicitly required independent review must
not be replaced. Security/live-effect claims need their own decisive proof.

Merge only after the exact-head Focus Gate, other relevant checks and review pass,
current main is included, and no requested changes or unresolved threads remain.
Use the expected-head SHA; never bypass protection. Connector agents apply the same
predicates as the merge helper. Verify GitHub readback and the introduced main gate.

CI is hosted, read-only and provider-free. It never runs on the owner's Mac. Failed
current-main CI automatically records one repair intent. The next executing agent
claims it, adds the regression and closes the loop. No paid or unattended model
worker is provisioned by this repository. Keep fixes bounded; stop repeated attempts
when new evidence no longer changes the decision.
