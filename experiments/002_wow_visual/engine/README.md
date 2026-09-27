# Engine — the decision architecture v2 skeleton

The types and checks that [docs/architecture.md](../../../docs/architecture.md) names, so that the
programme in [the epic](https://github.com/fol2/jev-playground/issues/85) builds on one set of
contracts rather than on prose. Pure Foundation, compiled on Linux and macOS. **Nothing here is on
a live path yet**: no probe imports it, no key is pressed, no provider is called.

| File | What it fixes | Replaces, when wired |
| --- | --- | --- |
| `World.swift` | `Reading`, `Belief` (value, confidence, captured-at, source; one merge policy), `WorldState` (the blackboard), `EntityTracker` (identity by name and bearing, never a raw OCR string) | `Obs`, `NavObs`, `HuntObs`, `QuestRead` as separate truths; `merged` sightings, `PositionTrack`, `targetCue`, the quest-log memory, the #84 caches |
| `Controller.swift` | `FailureKind` and `TaskOutcome` (the taxonomy), `ReflexTable` (ordered, tested), `PlayLoop` (modes; a failure never ends the session) | the dozen terminal codes of `runQuests` and `runHunt`; the reflexes scattered through M3/M4 (#72, #73, #76, #79) |
| `Planner.swift` | `GoalPlanner.rank`: a utility ranking with the owner's rules as named terms; `tieBreak` gives the judge at most three | `questOffers` + `townOffers` + `withHistory` and the seventeen-skill quest graph |
| `Judge.swift` | `JudgeQuestion` (choice, score, noul as TypeSafe defines them), `JudgeRequest` (one call, several independent questions, a small flat state), `parseJudgeAnswers`, `Judge` (cache, receipts), `QuestionLibrary` v1 | one `choice` per tick; READ/ENTER/BACK; `fuzzyNameMatch`, `sameTitle`, `townNameHit`, `questKind` |
| `Report.swift` | `RunReport` from `events.jsonl`: decisions by controller, calls, latency, tokens, unread frames, deaths, quests, failures by kind, `FailureRecord` for the analyst | the manifest's partial counts; reading a run by hand |
| `EngineTests.swift` | counted checks, floor 60 | |

## Build and check

```sh
swiftc -parse-as-library experiments/002_wow_visual/engine/*.swift -o /tmp/engine-tests && /tmp/engine-tests
```

The engine compiles alone. Its names do not clash with the existing sources (`Sighting` is M1's, so
this one is `EntitySighting`; `MapPoint` is M4's tuple, so this one is `WorldPoint`), so a later build
may compile both together.

## How the pieces fit

```text
frame -> readers (pixels, OCR, learned models) -> Reading -> WorldState (Belief, EntityTracker)
                                                                  |
                       ReflexTable.first  (SAFETY / RULE / OWNER, every tick, before any task)
                                                                  |
                       PlayLoop.next  ->  .reflex | .plan | .continueTask | .stop(envelope)
                                                                  |
                 GoalPlanner.rank (owner's rules as terms)  ->  tieBreak  ->  Judge (one batched call)
                                                                  |
                    the existing bounded skills (walk, fight, hand-in, hunt, town, revive)
                                                                  |
                              TaskOutcome  ->  PlayLoop.end  ->  RunReport / FailureRecord
```

## Migration, in the epic's order

1. Wrap `runQuests` in a `PlayLoop`: the host maps each outcome code onto `TaskOutcome` with
   `failureKind(forCode:)`, and the loop plans again instead of returning. The old codes stay.
   **Done as an opt-in candidate:** `m4/Session.swift` (`runSession`, `SessionHost`), tested in
   `m4/SessionTests.swift`, live behind `--quests --session` (#87). Builds that include `QuestProbe.swift`
   now include `Session.swift`, `World.swift` and `Controller.swift`.
2. Move the M3/M4 reflexes behind `ReflexTable.standard`; delete their copies.
3. Make each `Obs`/`NavObs`/`HuntObs`/`QuestRead` field a `Reading` written into one `WorldState`.
4. Replace `questOffers` + `townOffers` with `GoalPlanner.rank`; keep the quest graph file only as the
   catalogue of skills the planner may name.
5. Add a live `JudgeClient` beside `LiveJev` (same endpoint, the whole `questions` object) and ask the
   first library questions where the fuzzy matchers are today; score them on the saved frames first.
6. Emit `task_failed`, `judge_call`, `frame` and `death` events; produce a `RunReport` at every run's end
   and attach it to the pull request.

Each step is its own sub-issue with its own acceptance. None widens live authority.
