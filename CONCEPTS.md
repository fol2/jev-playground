# Concepts

> Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Deciding and acting

### Jev
The small decision model that chooses among the skills the engine offers at each step, given a compact structured state; it judges between options and never executes them.
*Avoid:* the brain, the agent (for the model itself)

Jev receives structured state and the knowledge relevant to the choice, never raw frames, and it can only pick from options the engine has already judged admissible. When Jev keeps choosing badly, the first question is what its state was missing (see Engine capability).

### Controller
Who actually took an action, recorded with it: Jev (a model choice), Rule (a validated deterministic policy deciding in Jev's place), Safety (a protective reflex), or Owner (the human took over).

The real controller is always logged, and one is never silently substituted for another during a comparison. A Rule that overrides Jev usually means Jev lacked a fact; Rules belong with the jobs deterministic code already owns: admissibility, watchdogs, budgets and emergency stops.

### Engine capability
A general ability of the engine that every consumer relies on, such as locating interface elements wherever they are drawn, resolving read names to known entities, verifying an outcome from independent evidence, or learning world knowledge. It is distinct from a patch that makes one failure pass.
*Avoid:* fix, workaround (for the capability itself)

A live failure is fixed by naming the capability it exposes and improving that capability for all its consumers; a goal such as a target level measures the engine but does not drive its design.

## Playing live

### Live run
One supervised session of the engine playing the real game inside a Run envelope, as opposed to a simulation or a replay of saved frames.

Evidence from a live run is labelled live; simulated or replayed results never stand in for it. A live run ends inside its envelope's limits.

### Run envelope
The owner's standing grant for live runs: which machine and account, which actions are allowed, the time, call and loss budgets, the stop and takeover conditions, the privacy scope and an expiry.

Inside an active envelope the engine may play and recover without asking each time; anything outside it, or any new kind of risk, goes back to the owner.

## Flagged ambiguities

- "Owner rules" (the owner's written instructions that Jev can read) are distinct from a Rule controller (code that decides in Jev's place).
