// Offline checks for the session loop (#87): SIMULATION ONLY, on scripted reads, vitals and outcomes.
// They prove what the loop does round a decision and after a failure, not what the game or Jev does.
import Foundation

extension NavTests {
    /// A session host over FakeQuests' scripted steps, with scripted vitals, reads, the owner's focus and the recovery skills.
    final class FakeSession: SessionHost {
        let quests: FakeQuests
        var reads: [QuestRead?]
        var vitalsScript: [SessionVitals?] = []
        var vitalsDefault: SessionVitals? = SessionVitals(health: 1, mana: 1, inCombat: false, dead: false, capturedAt: 0)
        var focusUntil = -Double.infinity  // the owner has the game while the clock is under this
        var recoverOutcomes: [String] = [], safetyOutcomes: [String] = [], reviveOutcomes: [String?] = []
        var recovered = 0, safetyRuns = 0, reviveCalls = 0
        var waited: [Double] = []
        var events: [(name: String, fields: [String: Any])] = []
        init(_ quests: FakeQuests, reads: [QuestRead?]) { self.quests = quests; self.reads = reads }

        static func healthy(_ health: Double = 1, mana: Double = 1) -> SessionVitals {
            SessionVitals(health: health, mana: mana, inCombat: false, dead: false, capturedAt: 0)
        }
        static let combat = SessionVitals(health: 0.7, mana: 0.6, inCombat: true, dead: false, capturedAt: 0)
        static let dead = SessionVitals(health: 0, mana: 0, inCombat: false, dead: true, capturedAt: 0)

        func vitals() -> SessionVitals? {
            var v = vitalsScript.isEmpty ? vitalsDefault : vitalsScript.removeFirst()
            v?.capturedAt = quests.clock
            return v
        }
        func recover() async -> String { recovered += 1; return recoverOutcomes.isEmpty ? "RECOVERED" : recoverOutcomes.removeFirst() }
        func toSafety() async -> String { safetyRuns += 1; return safetyOutcomes.isEmpty ? "SAFE" : safetyOutcomes.removeFirst() }
        func revive() async -> String? { reviveCalls += 1; return reviveOutcomes.isEmpty ? "REVIVED" : reviveOutcomes.removeFirst() }
        func wait(_ seconds: Double) async { waited.append(seconds); quests.clock += seconds }
        /// The scripted reads in turn; the last one repeats (the world stands still), so a script never runs out into unread.
        func readQuests() async -> QuestRead? {
            quests.clock += 0.2
            guard let first = reads.first else { return nil }
            return reads.count > 1 ? reads.removeFirst() : first
        }
        func handIn(_ quest: PlannedQuest) async -> String { await quests.handIn(quest) }
        func accept(_ giver: Giver) async -> String { await quests.accept(giver) }
        func retreat() async -> String { await quests.retreat() }
        func fightAhead() async -> String { await quests.fightAhead() }
        func fightBack() async -> String { await quests.fightBack() }
        func hunt(_ quest: PlannedQuest, until deadline: Double) async -> String { await quests.hunt(quest, until: deadline) }
        func walkRoad(to quest: PlannedQuest, by legs: [MapPoint], until deadline: Double) async -> String {
            await quests.walkRoad(to: quest, by: legs, until: deadline)
        }
        func useItem(_ quest: PlannedQuest, item: String) async -> String { await quests.useItem(quest, item: item) }
        func visit(_ npc: TownNPC) async -> String { await quests.visit(npc) }
        func remember(_ key: String, outcome: String, level: Int?) { quests.remember(key, outcome: outcome, level: level) }
        func now() -> Double { quests.now() }
        func ownerTookFocus() -> Bool { quests.clock < focusUntil }
        func emit(_ event: String, _ fields: [String: Any]) { events.append((event, fields)) }

        func count(_ event: String) -> Int { events.filter { $0.name == event }.count }
        func failures(_ kind: String? = nil) -> [String] {
            events.filter { $0.name == "task_failed" && (kind == nil || $0.fields["kind"] as? String == kind) }.compactMap { $0.fields["code"] as? String }
        }
    }

    static func session() async {
        let path = "experiments/002_wow_visual/runtime/skyborne-quest.graph.json"
        func graph() -> GraphSession { try! GraphSession.load(URL(fileURLWithPath: path)) }
        let thendal: MapPoint = (43.2, 24.0)
        let ready = PlannedQuest(title: "Agitators", level: 3, ready: true, objective: "- Ready for turn-in", pin: (47.3, 21.9))
        let matriarch = PlannedQuest(title: "Foul Matriarch", level: 4, ready: false, objective: "- 0/1 Foul Matriarch slain", pin: (39.6, 23.9))
        func read(_ quests: [PlannedQuest], missing: [String] = []) -> QuestRead { QuestRead(quests: quests, player: thendal, missing: missing) }
        func budget(_ seconds: Double, deaths: Int = 3, calls: Int = 400, failures: Int = 8) -> EnvelopeBudget {
            EnvelopeBudget(seconds: seconds, deaths: deaths, judgeCalls: calls, consecutiveFailures: failures)
        }

        // Outcomes and codes.
        check(taskOutcome("COMPLETED_TO_WEAR") == .succeeded("COMPLETED_TO_WEAR") && taskOutcome("NOTHING_TO_TRAIN") == .succeeded("NOTHING_TO_TRAIN")
              && taskOutcome("DIALOGUE_NOT_OPEN") == .failed(TaskFailure(kind: .execution, code: "DIALOGUE_NOT_OPEN", detail: ""))
              && taskOutcome("WALK_HUD_UNREADABLE") == .failed(TaskFailure(kind: .perception, code: "WALK_HUD_UNREADABLE", detail: ""))
              && taskOutcome("HUNT_NO_TARGET_FOUND") == .failed(TaskFailure(kind: .knowledge, code: "HUNT_NO_TARGET_FOUND", detail: ""))
              && taskOutcome("SAFETY_STOP_PLAYER_BELOW_30") == .failed(TaskFailure(kind: .safety, code: "SAFETY_STOP_PLAYER_BELOW_30", detail: ""))
              && taskOutcome("SAFE") == .succeeded("SAFE") && taskOutcome("KILLED_NO_CORPSE") == .succeeded("KILLED_NO_CORPSE"),
              "a step's code is a success, a nothing-to-do, or a failure of the taxonomy's kind; a lost fight is never a safe arrival")
        check(endsSession("WALK_KEYS_HELD") && endsSession("INPUT_HANDOFF_FAILED") && !endsSession("WALK_NO_PROGRESS"), "only the engine's own faults end a session")

        // The envelope's last endReserve seconds are the end's (the way to safety, a revive): a budget of 400 s starts no step
        // after 100 s, and one idle (120 s) reaches that.
        // 1. Two unread positions hold; the hand-in follows; nothing left ends in idle-safe, and the envelope's time ends the session
        // with the way to safety and a revive check.
        let held = FakeSession(FakeQuests([]), reads: [nil, nil, read([ready]), read([])])
        let one = await runSession(host: held, jev: CannedGraph(["DO:HAND_IN_1"]), graph: graph(), budget: budget(400))
        check(held.quests.handed == ["Agitators"] && held.failures().isEmpty, "two unread positions hold the loop; the hand-in follows; no failure is recorded")
        check(one.outcome == "TIME_LIMIT" && one.steps.map(\.quest) == ["Agitators", "to safety", "revive"] && held.safetyRuns == 2 && held.reviveCalls == 1
              && one.modes == ["questing", "idleSafe"],
              "nothing left: idle-safe walks to safety; the envelope's time ends the session, which walks to safety and checks for death")
        check(one.records.count == 2 && one.records[0].outcome == .succeeded("COMPLETED") && one.records[0].controller == .jev
              && one.records[1].task == "idle" && one.records[1].controller == .safety, "every task is recorded with its controller and outcome")

        // 2. Five unread positions in a row record one perception failure and back off; the loop goes on and the hand-in still follows.
        let blind = FakeSession(FakeQuests([]), reads: [nil, nil, nil, nil, nil, read([ready]), read([])])
        _ = await runSession(host: blind, jev: CannedGraph(["DO:HAND_IN_1"]), graph: graph(), budget: budget(400))
        check(blind.failures("perception") == ["POSITION_UNREADABLE"] && blind.quests.handed == ["Agitators"] && blind.waited.contains(SessionLimits.backoff),
              "five unread positions: one recorded perception failure, a backoff, then the session goes on")

        // 3. No fresh frame holds the same way, and an incomplete log read is read again.
        let dark = FakeSession(FakeQuests([]), reads: [read([ready], missing: ["The Gift of Skysight"]), read([ready]), read([])])
        dark.vitalsScript = [nil, nil, nil]
        _ = await runSession(host: dark, jev: CannedGraph(["DO:HAND_IN_1"]), graph: graph(), budget: budget(400))
        check(dark.events.prefix(3).allSatisfy { $0.name == "reflex" && ($0.fields["action"] as? String)?.hasPrefix("holdAndReobserve") == true }
              && dark.quests.handed == ["Agitators"] && dark.failures().isEmpty,
              "no fresh frame: the stale-vision reflex holds three ticks; an incomplete log is read again; the hand-in follows")

        // 4. A failed step is a recorded outcome: the loop plans again without it, and a later success resets the run of failures.
        let flawed = FakeQuests([])
        flawed.outcomes["Agitators"] = "DIALOGUE_NOT_OPEN"
        let again = FakeSession(flawed, reads: [read([ready, matriarch]), read([ready, matriarch]), read([])])
        let planner = CannedGraph(["DO:HAND_IN_1", "DO:HUNT_1"])
        let two = await runSession(host: again, jev: planner, graph: graph(), budget: budget(400))
        check(flawed.handed == ["Agitators", "HUNT Foul Matriarch"] && again.failures("execution") == ["DIALOGUE_NOT_OPEN"]
              && planner.offered[1].contains("DO:HUNT_1") && !planner.offered[1].contains("DO:HAND_IN_1"),
              "a hand-in that did not open is a recorded execution failure; the next offers leave it out; the session goes on")
        check(two.usage.consecutiveFailures == 0 && two.records.filter { if case .failed = $0.outcome { return true }; return false }.count == 1,
              "the hunt's success resets the run of failures")
        check(flawed.budgets.first.map { $0 <= 400 - SessionLimits.endReserve + 1 } == true, "a hunt gets what the envelope leaves before its reserve")

        // 5. A step that fails every time, retried after each idle, spends the envelope's no-progress limit.
        let stuck = FakeQuests([])
        stuck.outcomes["Agitators"] = "NO_QUEST_MARK_IN_VIEW"
        let looping = FakeSession(stuck, reads: Array(repeating: read([ready]), count: 8))
        let three = await runSession(host: looping, jev: CannedGraph(Array(repeating: "DO:HAND_IN_1", count: 5)), graph: graph(), budget: budget(2000, failures: 3))
        check(three.outcome == "NO_PROGRESS_LIMIT" && stuck.handed.count == 3 && looping.failures("knowledge").count == 3
              && looping.count("plan") >= 5 && three.steps.last?.quest == "revive",
              "three failures in a row, with idle-safe between, end the session NO_PROGRESS_LIMIT; the end still walks to safety")

        // 6. Attacked on the way: the combat reflex fights back (SAFETY), and the interrupted step is offered again.
        let ambushed = FakeQuests([])
        ambushed.outcomes["Agitators"] = "WALK_COMBAT"
        let fought = FakeSession(ambushed, reads: [read([ready]), read([ready]), read([])])
        fought.vitalsScript = [FakeSession.healthy(), FakeSession.combat, FakeSession.healthy()]
        let backJev = CannedGraph(["DO:HAND_IN_1", "DO:HAND_IN_1"])
        _ = await runSession(host: fought, jev: backJev, graph: graph(), budget: budget(400))
        check(ambushed.handed == ["Agitators", "FIGHT_BACK", "Agitators"]
              && fought.events.contains { $0.name == "reflex" && $0.fields["controller"] as? String == "SAFETY" && ($0.fields["action"] as? String) == "fightBack" }
              && backJev.offered.count == 2, "attacked on a walk: the next tick's combat reflex fights back as SAFETY, then the hand-in is offered again")

        // 7. Death is a mode: the death reflex revives and counts it, recovery heals, then the loop plans again.
        let slain = FakeQuests([])
        slain.outcomes["HUNT Foul Matriarch"] = "HUNT_DEAD"
        let revived = FakeSession(slain, reads: [read([matriarch]), read([ready]), read([])])
        revived.vitalsScript = [FakeSession.healthy(), FakeSession.dead, FakeSession.healthy(0.4), FakeSession.healthy()]
        let four = await runSession(host: revived, jev: CannedGraph(["DO:HUNT_1", "DO:HAND_IN_1"]), graph: graph(), budget: budget(400))
        check(revived.reviveCalls == 2 && four.usage.deaths == 1 && revived.recovered == 1 && revived.count("death") == 1
              && four.modes == ["questing", "dead", "recovering", "idleSafe", "questing", "idleSafe"] && slain.handed == ["HUNT Foul Matriarch", "Agitators"],
              "a death is revived and counted, low health is recovered, and the session plans on: the hand-in follows the hunt that died")

        // 8. A lost fight back does not end the session; the death that follows is revived; the death limit ends it, with a revive.
        let beaten = FakeQuests([])
        beaten.outcomes["Agitators"] = "WALK_COMBAT"
        beaten.outcomes["FIGHT_BACK"] = "SAFETY_STOP_PLAYER_BELOW_30"
        let limit = FakeSession(beaten, reads: [read([ready]), read([ready])])
        limit.vitalsScript = [FakeSession.healthy(), FakeSession.combat, FakeSession.dead]
        let five = await runSession(host: limit, jev: CannedGraph(["DO:HAND_IN_1"]), graph: graph(), budget: budget(400, deaths: 1))
        check(five.outcome == "DEATH_LIMIT" && limit.failures("safety") == ["SAFETY_STOP_PLAYER_BELOW_30"] && limit.reviveCalls == 2
              && limit.safetyRuns == 0 && five.steps.map(\.quest) == ["Agitators", "fight back", "revive"],
              "a lost fight back is a recorded safety failure, not an end; the death limit ends the session with a revive and no walk")

        // 9. The owner takes the game: the session pauses without input and resumes when the owner lets go; held longer, it ends.
        let paused = FakeSession(FakeQuests([]), reads: [read([ready]), read([])])
        paused.focusUntil = 20
        let six = await runSession(host: paused, jev: CannedGraph(["DO:HAND_IN_1"]), graph: graph(), budget: budget(400))
        check(six.modes.first == "paused" && paused.quests.handed == ["Agitators"] && paused.waited.prefix(10).allSatisfy { $0 == SessionLimits.settle }
              && six.outcome == "TIME_LIMIT", "the owner's takeover pauses the loop; it resumes when the owner lets go")
        let taken = FakeSession(FakeQuests([]), reads: [read([ready])])
        taken.focusUntil = 10_000
        let seven = await runSession(host: taken, jev: CannedGraph(["DO:HAND_IN_1"]), graph: graph(), budget: budget(1000))
        check(seven.outcome == "OWNER_TOOK_FOCUS" && taken.quests.handed.isEmpty && taken.safetyRuns == 0 && taken.reviveCalls == 0
              && taken.quests.clock >= SessionLimits.ownerPause && taken.quests.clock < SessionLimits.ownerPause + 2,
              "held for the pause limit, the session ends OWNER_TOOK_FOCUS with no input, no walk and no click")

        // 10. A failed Jev call is a recorded budget failure, not an end; the loop asks again on the next read.
        let mute = FakeSession(FakeQuests([]), reads: [read([ready]), read([ready]), read([ready])])
        let eight = await runSession(host: mute, jev: CannedGraph([]), graph: graph(), budget: budget(400, failures: 2))
        check(eight.outcome == "NO_PROGRESS_LIMIT" && mute.failures("budget") == ["GRAPH_noSkills", "GRAPH_noSkills"] && mute.quests.handed.isEmpty,
              "two failed calls in a row are two recorded budget failures; the envelope's no-progress limit ends the session, not the first failure")

        // 11. The envelope's call limit and the engine's own faults end the session as before.
        let chatty = FakeSession(FakeQuests([]), reads: [read([ready]), read([ready]), read([ready])])
        let nine = await runSession(host: chatty, jev: CannedGraph(["READ:recent", "DO:HAND_IN_1", "DO:HAND_IN_1"]), graph: graph(), budget: budget(400, calls: 2))
        check(nine.outcome == "CALL_LIMIT" && nine.usage.judgeCalls == 2 && nine.steps.first?.quest == "Agitators", "the call limit counts every graph call and ends the session")
        let jammed = FakeQuests([])
        jammed.outcomes["Agitators"] = "WALK_KEYS_HELD"
        let keys = FakeSession(jammed, reads: [read([ready])])
        let ten = await runSession(host: keys, jev: CannedGraph(["DO:HAND_IN_1"]), graph: graph(), budget: budget(400))
        check(ten.outcome == "WALK_KEYS_HELD" && keys.safetyRuns == 0 && keys.reviveCalls == 0, "keys held end the session at once, with no walk or click after")

        // 12. A danger stop offers RETREAT and FIGHT_AHEAD next, as a run does; a retreat that fails leaves the stop standing.
        let wary = FakeQuests([])
        wary.outcomes["Agitators"] = "WALK_DANGER_AHEAD"
        wary.outcomes["RETREAT"] = "NO_WAY_BACK"
        let stopped = FakeSession(wary, reads: [read([ready]), read([ready]), read([ready]), read([])])
        let danger = CannedGraph(["DO:HAND_IN_1", "DO:RETREAT", "DO:FIGHT_AHEAD"])
        _ = await runSession(host: stopped, jev: danger, graph: graph(), budget: budget(400))
        check(danger.offered[1].contains("DO:RETREAT") && danger.offered[1].contains("DO:FIGHT_AHEAD") && danger.offered[2].contains("DO:FIGHT_AHEAD")
              && !danger.offered[2].contains("DO:RETREAT") && wary.handed == ["Agitators", "RETREAT", "FIGHT_AHEAD"] && stopped.failures("safety") == ["WALK_DANGER_AHEAD"],
              "a danger stop offers the retreat and the fight ahead; a failed retreat is not offered again while the fight ahead is; the stop is a safety failure")

        // 13. The command line: --session is a flag of --quests only.
        check((try? parseNav(["--quests", "--graph", "g.json", "--keys", "wqe", "--session"]))?.session == true
              && (try? parseNav(["--quests", "--graph", "g.json", "--keys", "wqe"]))?.session == false
              && fails { _ = try parseNav(["--quests", "--graph", "g.json", "--keys", "wqe", "--session", "--session"]) }
              && fails { _ = try parseNav(["--hunt", "--keys", "wqe", "--session"]) },
              "--session opts a quest run into the session loop; repeated or on another mode it is refused")
    }
}
