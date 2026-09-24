# Jev Playground — Agent Contract

Build an autonomous game-playing engine that learns how to play using JEV, a visual
decoder and deterministic scripts. Current domain: WoW Forever / Skyborne Shaman;
verify the client profile, not Retail assumptions. This is the mission, not a claim
that unattended play is already qualified.

## Four inseparable rules

1. **AI-SDLC DNA:** agents own Plan → Design → Build → Test → Deploy → Maintain,
   applied to both learned capabilities and the software that executes them.
2. **Minimise Wall Time (Maximise Effectiveness):** minimise time to verified useful
   gameplay, not merely time to a green build. Remove repeated work and waiting.
3. **Minimise Token Consumption:** small retrieved context, reusable observations
   and deterministic control; no model call when a proven script suffices.
4. **No compromise:** never remove material acceptance, safety, provenance or
   relevant proof to meet 2 or 3. Use the cheapest decisive evidence that can falsify
   the claim. Unrelated green checks and unobserved success are not evidence.

## Two connected loops

Learning: question → websites/walkthroughs/demos/videos or authorised exploration
→ grounded observations → candidate knowledge/skill → held-out evaluation
→ versioned promotion → gameplay outcomes → next learning question.

Playing: pixels → visual decoder → validated structured state → JEV or an explicit
script policy → admissible bounded skill → fresh observation → verified outcome.
The engineering loop supports both; merged instructions and replay agreement do
not prove live-game capability.
JEV receives compact state and relevant verified knowledge, not raw frames. Learning
changes knowledge, prompts, decoder calibration or skills; it is not model weight
training. Name and test the actual runtime consumer before claiming transfer.

Scripts own capture timing, measurement, admissibility, key execution, watchdogs,
budgets and emergency stops. JEV owns contextual choices where it adds value. A
validated deterministic policy may replace a model decision; log the real controller
(JEV, RULE, SAFETY or OWNER), never silently substitute one during a comparison.
Preserve unknowns; bind proposals to frame/target/geometry and revalidate before acting.

## Authority and human-above autonomy

Owner intent sets scope and non-goals; then apply current safety/contracts, this file
and nearest code/tests. Historical reports/demos are evidence, not current authority.
One owner, one topic branch from current main, one outcome and one PR. Continue through
research, implementation, evidence, review, fixes, merge and cleanup without routine
plan approval, frame labelling or merge-button handoffs. Parallel work needs separate
mutable files/worktrees; never rewrite another agent's branch. Reconcile stale work
with current main without discarding experiments or rewriting historical evidence.

The owner sets goals, priorities, acceptance and a bounded run envelope, not each
keystroke. Within an active, implemented and validated envelope the engine may play,
explore and recover autonomously without repeated human confirmation. New learning
is a candidate, not self-authority to rewrite safety or expand that envelope.

Source merge does NOT authorise live capture/input, game launch, provider calls or
spend. Live authority must identify machine/account, permitted actions, privacy scope,
call/time/loss budgets, expiry, stop/takeover and recovery. Qualification must match
supervised versus unattended mode. Pause on stale vision, identity drift, exhaustion,
unsafe uncertainty or an owner stop; release held input. No hidden game state, memory
injection, packet telemetry or anti-detection work. Respect applicable service and
media permissions. Never commit or print secrets, private captures or credential dumps.
Escalate only unresolved binding ambiguity, unapproved breaking/irreversible effects,
missing credentials/permission or inconclusive material evidence. A live blocker does
not block independent source work. This instruction update starts no live run.

## Context and learning evidence

Read current-main instructions, task and nearest consumer/tests; search first. Keep
one capsule: goal/profile, constraints, acceptance, sources, versions/head, evidence
and next action. Research-only grants no delivery/live effects. One PR per useful
result, not per frame, fact or trial.
Keep timestamped pre-action frames separate from later outcomes. Frame-by-frame
requires a bounded interval and recorded coverage; captions or sparse samples alone
are not visual verification. Separate source claims, observations and inferences.
Do not leak answers/future frames into decision input or tune against the held-out test.

## Evidence, integration and maintenance

```sh
python3 tools/sdlc.py route --base origin/main --head HEAD
python3 tools/sdlc.py check --base origin/main --head HEAD
python3 tools/merge_pr.py PR_NUMBER FULL_HEAD_SHA          # read-only
python3 tools/merge_pr.py PR_NUMBER FULL_HEAD_SHA --execute
```

Use a clean committed tree. F0 integrity, F1 direct behaviour and F2 affected consumers
are source evidence; F3 real-runtime proof and F4 effect authority remain separate.
The selector owns governance/fishing/visual/motor-learning proof; unknown executable
paths block. Never weaken tests for green.
Run narrow diagnostics, then the relevant final route once; repeat only invalidated proof.
Use REVIEW.md for one substantive exact-head review; prefer fresh context and disclose
author-review when used. Never self-approve or waive explicitly required independence.
Merge only with the authentic exact-head Focus Gate, passing relevant checks/review,
current-main ancestry and no open vetoes/threads; guard the head and verify main after.
CI is hosted, source-only and provider-free; its repair issue is not a running worker.
Gameplay failures feed bounded learning; preserve the last accepted policy, add a
regression and revalidate changes. No silent live self-edit.

Load docs/agents/ai-sdlc.md for the learning lifecycle, rollout, gates and run envelope;
experiments/README.md for evidence conventions; experiments/002_wow_visual/learning/README.md
for existing research/replay; M0–M4 READMEs for actual runtime limits. CLAUDE.md imports
only this kernel. Do not restart methodology adoption without a demonstrated need.
