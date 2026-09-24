# Runtime: Jev chooses; native tools carry out the choice

This is the runtime entry point, not another agent framework. Languages do not
own architectural roles. `Runtime.swift` keeps task/evidence contracts, `Input.swift`
keeps input ownership, and `DecisionGraph.swift` lets Jev choose **information,
branching, or skills**. The existing Fight/Nav/Hunt implementations remain tools.

## Implemented slice

`skyborne-hunt.graph.json` is an opt-in candidate for the actual native `runHunt`.
One `GraphSession` lasts for a hunt. It retains the selected question path and the
IDs of requested references, not old position/health/inventory readings. Every new
skill decision starts from the caller's new observations. Within one lookup chain,
the input is one frozen pre-action snapshot; lookup does not turn it into fresh
vision. The existing executive re-reads the game before dispatching the chosen skill.

Every Jev reply chooses an exact key in the current tool menu:

| Output | Meaning | Next input |
| --- | --- | --- |
| `READ:recent` | Retrieve named task history | The next Jev call includes that history |
| `READ:class_conflicts` | Consult a source-qualified local reference | The next call includes the requested Markdown section |
| `ENTER:travel` | Delegate to a narrower question | Only that node's menu is presented |
| `BACK` | Reconsider the parent goal | Parent menu, with loaded references retained |
| `DO:LOOK_AROUND` | Invoke an existing bounded composite skill | New visual observations and the actual skill result |

The model does not generate file paths or key timings. Concrete tool arguments
are the supplied candidates; future candidate builders can offer parameterised
skills or named map/equipment records. A new menu is not a new physical capability.
References are snapshotted once from the trusted local repo configuration and
loaded into model context only when selected. Snapshot resources refresh their
values from each new input; absent values remain null. Loaded READ options are
removed to avoid spending another call fetching the same data. Jev can act directly
without a lookup, remain inside a subgoal for successive skills, or return upward.
This gives a sequence of adaptive skill choices, **not a blind queued combo**.

### Current executable graph (abbreviated)

```mermaid
flowchart TD
    H[Jev: hunt] --> R[READ task history / progress / class conflicts]
    R --> H
    H --> S[Jev: search]
    H --> F[DO FIGHT_TARGET]
    H --> E[DO REST / EAT_DRINK]
    S --> L[DO NEXT_TARGET / LOOK_AROUND / GO_TO_QUEST_CREATURE]
    S --> T[Jev: travel]
    T --> W[DO GO_TO_QUEST_AREA / GO_TO_QUEST_CREATURE]
    T --> D[Jev: detour]
    T --> C[Jev: compass]
    D --> DS[DO area-relative detour]
    C --> CS[DO compass walk]
    F --> FC[Existing M3 Jev tactical choices]
    FC --> N[New observation + skill result]
    L --> N
    W --> N
    DS --> N
    CS --> N
    E --> N
    N --> H
```

`BACK` edges and local READ edges are omitted above. The session actually retains
its selected node after a skill; new observations can prompt BACK. `ToolGraph.mermaid()`
renders the exact catalogue, including all skills, reads and child edges. The test
binary's `--graph` option prints it. There is no independent graph database or editor.

## Run and compare

Build the native M4 binary with the current [M4 instructions](../m4/README.md).
From the repo root:

```sh
# Pure simulation, canned choices, no key, game, capture or provider:
/tmp/m4-nav --hunt-dry-run --graph experiments/002_wow_visual/runtime/skyborne-hunt.graph.json
# Existing flat baseline remains unchanged:
/tmp/m4-nav --hunt-dry-run
```

The no-network demo traverses the real graph and real Hunt core with simulated
inputs. It may end at a call/decision limit; it is not a learned policy or a success
rate. SimHunt still has a canned fight outcome, NOT simulated M3 combat.

The same `--graph PATH` argument is wired to `--hunt-sim-jev` (real provider,
simulated world) and `--hunt --keys wqe` (real game). These are not run in this PR.
They retain their existing separate run authority and effects; file selection does
not start a game or grant an execution envelope. No new permission system was added.

There is one provider call for each selected READ/ENTER/BACK/DO edge. The sample
allows four calls per skill decision, 120 per hunt-policy session, within the
existing ten-second decision deadline. This is a starting cost envelope, not a
claim that four hops fit every real-time action. Graph-mode Hunt HTTP requests do
not retry. Warm-up and nested Fight requests remain separate from this graph budget.
Failed graph attempts are recorded. Exhaustion/error ends the candidate; there is
no silent rules replacement. Flat baseline defaults and existing input checks are
unchanged. No second confidence checker or safety framework is introduced.

`graph_call` events and `jev.jsonl` retain each exact request, actual response,
reference content used, node and latency. The final tool distribution is NOT padded
with zeroes or multiplied into a made-up probability of an action/success. Manifest
`graph_requests` counts these calls; `graph_usage_missing` counts missing usage
receipts. Token totals sum returned usage only and exclude unreported failed usage.
The inherited manifest does not account for warm-up usage or retries inside legacy
nested Fight; do not call it a complete invoice. Judge the new policy against flat
Jev on comparable episodes, not by the canned demo's path or CI test count.

## Extension direction, NOT completed capability

The intended wider hierarchy is owner goal -> Jev subgoal/tool choices -> selected
specialist decisions -> native skills -> new evidence. Add branches only when an
actual tool and meaningful task observation exist:

- Quest types: hunt, interact, collect, escort, puzzles and quest-specific references.
  Hunt is connected; Quest's existing turn-in/reward rules are not graph tools yet.
- Travel: route selection, local approach, obstacle recovery and location-specific
  references. Existing calibrated walks are connected; bridge/cliff geometry is NOT solved.
- Combat: tactical choices, learned abilities, movement, adds, buffs/debuffs and party
  context. M3 remains its existing Jev loop. It has no general party/debuff interpreter.
- Professions: fishing, skinning, mining, crafting. Fishing exists separately; none
  is made a selectable graph tool merely by listing it in this roadmap.
- Memory/tools: last observed inventory/equipment, visited map, skill/reference index,
  task history. Only history/progress/navigation snapshot and one qualified reference
  section are connected here. No hidden game-state source or generic LLM is involved.

The catalogue profile names Skyborne Shaman, but this is NOT qualification of all
level 1-20 spells, races, quest types or environments. Adding another profile means
new data plus supported skill adapters and evidence, not copying a name into JSON.

The inherited `huntAdmissible` still mixes technical preconditions and legacy
strategic restrictions (including health/nearby-hostile gates). This slice does not
relax them or claim complete tactical freedom. Policy/profile separation and shared
live/replay reference versions remain [#23](https://github.com/fol2/jev-playground/issues/23).
A model choice can be precise syntactically while wrong tactically; exact output
means a definite tool invocation, not guaranteed interpretation or gameplay success.

## References and licence decision

TypeSafe's [primitives](https://docs.typesafe.ai/primitives#when-one-question-depends-on-another)
require a later request when a lookup changes the evidence/options. Independent
questions on the same state can instead be batched; don't infer an answer-to-answer
dependency inside one request. Their [skill suggestion](https://docs.typesafe.ai/cookbooks/skill_suggestion)
uses progressive disclosure, and [jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13)
explains why huge state dumps and generating free-form plans are poor defaults.
These are design references, not WoW success evidence. Checked 24 September 2026.

No external implementation was copied and no dependency was added. A full behaviour-
tree/agent framework would duplicate the small native host interfaces without giving
us WoW perception or movement. Existing attributed MIT input code remains untouched.
