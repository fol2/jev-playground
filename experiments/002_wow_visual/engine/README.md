# Engine — the decision architecture v2 skeleton

The types and checks that [docs/architecture.md](../../../docs/architecture.md) names, so that the
programme in [the epic](https://github.com/fol2/jev-playground/issues/85) builds on one set of
contracts rather than on prose. Pure Foundation, compiled on Linux and macOS. `World.swift` and
`Controller.swift` are on every live path since #88: the run loop, the session loop, the hunt, the fight and
the walks ask `ReflexTable.first` each tick (below); `Planner.swift`, `Judge.swift` and `Report.swift` have no
consumer yet, so no provider is called through them.

| File | What it fixes | Replaces, when wired |
| --- | --- | --- |
| `World.swift` | `Reading`, `Belief` (value, confidence, captured-at, source; one merge policy), `WorldState` (the blackboard), `EntityTracker` (identity by name and bearing, never a raw OCR string) | `Obs`, `NavObs`, `HuntObs`, `QuestRead` as separate truths; `merged` sightings, `PositionTrack`, `targetCue`, the quest-log memory, the #84 caches |
| `Controller.swift` | `FailureKind` and `TaskOutcome` (the taxonomy), `ReflexTable` (ordered, tested; **the one home of the reflexes since #88**), `PlayLoop` (modes; a failure never ends the session) | the dozen terminal codes of `runQuests` and `runHunt`; the reflexes that were scattered through M3/M4 (#72, #73, #76, #79) |
| `Planner.swift` | `GoalPlanner.rank`: a utility ranking with the owner's rules as named terms; `tieBreak` gives the judge at most three | `questOffers` + `townOffers` + `withHistory` and the seventeen-skill quest graph |
| `Judge.swift` | `JudgeQuestion` (choice, score, noul as TypeSafe defines them), `JudgeRequest` (one call, several independent questions, a small flat state), `parseJudgeAnswers`, `Judge` (cache, receipts), `QuestionLibrary` v1 | one `choice` per tick; READ/ENTER/BACK; `fuzzyNameMatch`, `sameTitle`, `townNameHit`, `questKind` |
| `Report.swift` | `RunReport` from `events.jsonl`: decisions by controller, calls, latency, tokens, unread frames, deaths, quests, failures by kind, `FailureRecord` for the analyst | the manifest's partial counts; reading a run by hand |
| `EngineTests.swift` | counted checks, floor 110 (the count; a dropped check lowers it on purpose) | |

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

## The reflex table (#88)

`ReflexTable.standard`, tried in this order every tick, the first that fires wins; each entry names its controller and is
logged `reflex` with its name wherever it fires. The loops build a `WorldState` from what they already observe (`fightWorld`,
`huntWorld`, `navWorld`, the session's vitals, the run loop's quest read) and keep their own effects and outcome codes, so the
decision lives here and the qualified behaviour is unchanged.

| Entry | Controller | Fires when | Action, and who takes it |
| --- | --- | --- | --- |
| `owner_takeover` | OWNER | the owner has the game | `pause`: every loop ends or waits with no input (`ReflexTable.ownerTakeover` before a read) |
| `stale_vision` | SAFETY | no frame newer than the context's age | `holdAndReobserve`: the session holds; the skills wait for a frame their own way (`maximumVisionAge: .infinity`) |
| `dead` | SAFETY | the bar reads empty out of combat | `releaseSpirit`: the session revives (M4s); the hunt ends `DEAD` |
| `combat_low_health` | SAFETY | in combat, health under 30 %, mana for a heal | `heal`: the fight's `admissible` offers HEAL alone (WAIT while it casts) |
| `buff_before_fight` | RULE | a fight is starting, the enchant is down, no cast; attacked, only at 60 % health or more (review of #79) | `buffWeapon`: the fight casts it first, once |
| `combat` | SAFETY | in combat | `fightBack`: the session and the run loop fight back; the walks end `COMBAT`; the hunt offers FIGHT alone |
| `hostile_ahead` | RULE | a red name or hostile plate within 30° of the walk's heading; not on the way to safety, not on an armed walk past | `stopWalk(.hostileAhead)`: the walk ends `DANGER_AHEAD` (M4h, M4t) |
| `walk_past` | RULE | a stop stands, its creature is unaggressive with no threat in view, this step not yet walked past | `walkPast`: the stopped step is offered again and its walk goes past (M4am) |
| `blocker_fight` | RULE | a stop stands, a lone creature no higher than the character | `fightAhead`: FIGHT_AHEAD with no Jev call (M4ak; `JEV_BLOCKER_FIGHT=off` turns it off) |
| `walk_low_health` | SAFETY | in a walk, out of combat, under 30 %; not on the way to safety | `stopWalk(.lowHealth)`: the walk ends `LOW_HEALTH` |
| `fight_stop_hurt` | SAFETY | in a fight, out of combat, under 30 % | `stopFight`: the fight ends `SAFETY_STOP_PLAYER_BELOW_30` |
| `hurt_out_of_combat` | RULE | out of combat, under 60 % | `recover`: the session heals or rests (M4w); the hunt offers no walk or pick-up; `recover()` casts; a walk between 30 and 60 % walks on |

`ReflexLimits` holds the three thresholds (`combatHealthFloor` 0.3, `healMana` 0.15, `walkHealth` 0.6) and the cone (30°);
`FightLimits`, `HuntLimits`, `NavLimits` and `RecoverLimits` alias them. Nothing in the table is offered to Jev: `BUFF_WEAPON`
left the fight graph and `admissible`; HEAL stays Jev's only above the floor (the grey zone, #91). The fight keeps its tactics
(`hitAfterKill`, the chains, target selection); the hunt keeps REST and EAT_DRINK as Jev's choices above 60 %.

## Migration, in the epic's order

1. Wrap `runQuests` in a `PlayLoop`: the host maps each outcome code onto `TaskOutcome` with
   `failureKind(forCode:)`, and the loop plans again instead of returning. The old codes stay.
   **Done as an opt-in candidate:** `m4/Session.swift` (`runSession`, `SessionHost`), tested in
   `m4/SessionTests.swift`, live behind `--quests --session` (#87). Builds that include `QuestProbe.swift`
   now include `Session.swift`, `World.swift` and `Controller.swift`.
2. Move the M3/M4 reflexes behind `ReflexTable.standard`; delete their copies. **Done (#88):** the table above; the run
   loop, the session, `runFight`, `admissible`, `runHunt`, `huntAdmissible`, `runSteer`, `runNav`, `walk()`, `recover()`,
   `leaveDanger` and `leaveDangerRounds` ask it; every build with `Fight.swift` or `Quest.swift` includes the engine.
3. Make each `Obs`/`NavObs`/`HuntObs`/`QuestRead` field a `Reading` written into one `WorldState`.
4. Replace `questOffers` + `townOffers` with `GoalPlanner.rank`; keep the quest graph file only as the
   catalogue of skills the planner may name.
5. Add a live `JudgeClient` beside `LiveJev` (same endpoint, the whole `questions` object) and ask the
   first library questions where the fuzzy matchers are today; score them on the saved frames first.
6. Emit `task_failed`, `judge_call`, `frame` and `death` events; produce a `RunReport` at every run's end
   and attach it to the pull request.

Each step is its own sub-issue with its own acceptance. None widens live authority.
