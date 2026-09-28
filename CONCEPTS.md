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

A live failure is fixed by naming the capability it exposes and improving that capability for all its consumers; a goal such as a target level measures the engine but does not drive its design. One live run is one sample of a failure class: when a second fix is about to land in the same class, or the owner questions the method, the class needs its capability rather than another patch.

## Perceiving and remembering

### Learned reader
A perception component trained on audited, labelled frames and scored on held-out runs, as opposed to a hand-tuned pixel rule.
*Avoid:* pixel decode (for anything but fixed interface bars)

A learned reader first runs in shadow: its readings are logged but never acted on. It replaces a rule only after beating it on held-out data, and it is demoted again when it proves confidently wrong in live play. New failure cases become labelled data, not new rules.

### Working memory
What the engine has recently read from the screen, such as the quest log or the skill bar, kept so that it is not read again while nothing has changed; distinct from long-term knowledge.

Each entry is keyed by what it was read from and is dropped by the events that change it: a hand-in or accepted quest changes the log, a slot whose icon looks different is read again, loot or a sale changes the bags. A change the key cannot see, such as a new rank of a spell whose icon stays the same, is caught only when the entry expires, which is why the quest log and skill bar memories also expire with age. It only saves reads; it is not learning, and a store of places or read results is working memory at most (see Engine capability).

## Playing live

### Live run
One supervised session of the engine playing the real game inside a Run envelope, as opposed to a simulation or a replay of saved frames.

Evidence from a live run is labelled live; simulated or replayed results never stand in for it. A live run ends inside its envelope's limits.

### Run envelope
The owner's standing grant for live runs: which machine and account, which actions are allowed, the time, call and loss budgets, the stop and takeover conditions, the privacy scope and an expiry.

Inside an active envelope the engine may play and recover without asking each time; anything outside it, or any new kind of risk, goes back to the owner.

## Flagged ambiguities

- "Owner rules" (the owner's written instructions that Jev can read) are distinct from a Rule controller (code that decides in Jev's place).
