// Real core loops, simulated observations/input and canned provider replies. No game/API.
import Foundation

struct ChangedDuringRequest<A: JevAction>: JevClient {
    let preference: [A]
    let change: () -> Void
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        let reply = try await ScriptedJev<A>(preference: preference).ask(state: state, question: question)
        change()
        return reply
    }
}

@main struct IntegrationTests {
    static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ reason: String) { checks += 1; precondition(value, reason) }
        let clock = FightClock(), pad = SimPad()
        let root = LiveKeys(sink: pad, releaseCodes: [13], clock: clock.now)
        check(root.press(13), "parent starts walking")
        root.grant(13, seconds: 1)
        let child = root.takeChild(releaseCodes: [19])!
        check(pad.pressed.isEmpty, "handoff releases parent before child exists")
        check(!root.press(13), "suspended parent cannot press")
        check(root.withControl { true } == nil, "suspended parent cannot click")
        check(child.press(19), "child owns the shared sink")
        root.lift(19, listed: true)
        check(pad.pressed == [19], "stale parent cannot lift child's input")
        check(root.codesPosted == [13] && child.codesPosted == [19], "per-skill provenance")
        check(!root.resume(after: child), "cannot resume a live child")
        child.releaseAll()
        check(pad.pressed.isEmpty && !root.holding, "child confirms release")
        check(root.resume(after: child), "parent explicitly resumes")
        check(!child.press(19) && child.withControl { true } == nil, "retired child cannot act")
        root.press(13)
        root.grant(13, seconds: 1)
        child.releaseAll()
        check(pad.pressed == [13], "late child cleanup cannot release resumed parent")
        clock.t += 2
        child.sweepExpired()
        check(pad.pressed.isEmpty, "one store watchdog even from a child handle")
        let next = root.takeChild(releaseCodes: [19])!
        next.press(19)
        root.releaseAll()
        check(pad.pressed.isEmpty && !root.holding, "root cancellation releases active child")
        next.releaseAll()
        check(!root.resume(after: next) && !next.press(19), "owner stop is irreversible")

        // A quest run's fight back (M4i): a finished walk's set is retired by its exit sweep, so the fight's
        // keys come from the run's own set, which only taps and lives until the run ends.
        let questPad = SimPad(), walk = LiveKeys(sink: questPad, releaseCodes: [13], clock: clock.now)
        let run = LiveKeys(sink: questPad, releaseCodes: [53], clock: clock.now)
        walk.press(13)
        walk.releaseAll()
        let fightKeys = run.takeChild(releaseCodes: [19])
        check(walk.takeChild(releaseCodes: [19]) == nil && fightKeys != nil && questPad.pressed.isEmpty,
              "a fight back takes its keys from the run's set; a finished walk's hands over nothing")
        fightKeys!.press(19)
        fightKeys!.releaseAll()
        check(run.resume(after: fightKeys!) && run.press(53), "the run's set taps again after the fight")
        run.releaseAll()

        let failedPad = SimPad(), failed = LiveKeys(sink: failedPad, releaseCodes: [13], clock: clock.now)
        failed.press(13)
        failedPad.failUps = Limits.releaseAttempts
        check(failed.takeChild(releaseCodes: [19]) == nil, "unconfirmed release blocks handoff")
        check(failed.holding, "failed release remains tracked")
        failed.sweepExpired()
        let recovered = failed.takeChild(releaseCodes: [19])!
        check(!failed.holding, "watchdog release retry enables handoff")
        recovered.press(19)
        failedPad.failUps = Limits.releaseAttempts
        recovered.releaseAll()
        check(!failed.resume(after: recovered), "unconfirmed child release blocks resume")
        recovered.sweepExpired()
        check(failed.resume(after: recovered), "confirmed retry enables parent")
        failed.releaseAll()

        let stamp = ObservationStamp(stream: "s", geometry: "g", capturedAt: 1)
        var executive = RuntimeExecutive(goal: "quest")
        let context = executive.request(stamp: stamp, candidates: ["WAIT"], policy: "p", now: 1, maximumAge: 1, deadline: 2)!
        check(JSONSerialization.isValidJSONObject(context.json), "unknown cue serialises as null")
        check(JSONSerialization.isValidJSONObject(SkillResult(skill: "fight", status: .observationLost,
                code: "NO_FRESH_FRAME", evidence: nil, holdingInput: false).json), "missing evidence serialises")
        check(skillStatus("NO_FRESH_FRAME") == .observationLost, "unknown is not a death claim")
        check(skillStatus("JEV_STOP") == .stopped, "stopping is not completing")
        check(skillStatus("INPUT_HANDOFF_FAILED") == .failed, "handoff failure is explicit")

        // These execute runFight/runNav/runHunt, not just contract-shaped test doubles.
        var fight = SimFight(clock: FightClock())
        var result = await runFight(host: fight, jev: ChangedDuringRequest<FightAction>(preference: [], change: { fight.wowIsFront = true }))
        check(result.outcome == "OWNER_TOOK_FOCUS" && fight.performed.isEmpty, "Fight rejects owner takeover during inference")
        fight = SimFight(clock: FightClock())
        result = await runFight(host: fight, jev: ChangedDuringRequest<FightAction>(preference: [], change: { fight.clock.t += 5 }))
        check(result.outcome == "DECISION_EXPIRED" && fight.performed.isEmpty, "Fight rejects late reply")
        fight = SimFight(clock: FightClock())
        result = await runFight(host: fight, jev: ChangedDuringRequest<FightAction>(preference: [], change: { fight.stalls = 1000 }))
        check(result.outcome == "NO_FRESH_FRAME" && fight.performed.isEmpty, "Fight rejects lost observation after inference")
        check(result.runtime?.status == .observationLost && !result.holdingKeys, "Fight publishes typed missing evidence outcome")
        fight = SimFight(clock: FightClock())
        result = await runFight(host: fight, jev: ChangedDuringRequest<FightAction>(preference: [], change: { fight.player = 0.1 }))
        check(result.outcome == "SAFETY_STOP_PLAYER_BELOW_30" && fight.performed.isEmpty, "Fight rechecks inherited risk boundary")

        var nav = SimNav(clock: FightClock(), x: 40, y: 30, facing: 0)
        let destination = NavDestination(label: "quest landmark", x: 40, y: 25)
        var moved = await runNav(body: nav, jev: ChangedDuringRequest<NavAction>(preference: [.goToward], change: { nav.combat = true }), destination: destination)
        check(moved.outcome == "COMBAT" && nav.keys.codesPosted.isEmpty, "Nav yields to combat before sending input")
        nav = SimNav(clock: FightClock(), x: 40, y: 30, facing: 0)
        moved = await runNav(body: nav, jev: ChangedDuringRequest<NavAction>(preference: [.goToward], change: { nav.clock.t += 5 }), destination: destination)
        check(moved.outcome == "DECISION_EXPIRED" && nav.keys.codesPosted.isEmpty, "Nav rejects late reply")
        nav = SimNav(clock: FightClock(), x: 40, y: 30, facing: 0)
        moved = await runNav(body: nav, jev: ChangedDuringRequest<NavAction>(preference: [.goToward], change: { nav.ownerFront = true }), destination: destination)
        check(moved.outcome == "OWNER_TOOK_FOCUS" && nav.keys.codesPosted.isEmpty, "Nav rejects owner takeover")
        nav = SimNav(clock: FightClock(), x: 40, y: 30, facing: 0)
        moved = await runNav(body: nav, jev: ChangedDuringRequest<NavAction>(preference: [.goToward], change: { nav.y = 25 }), destination: destination)
        check(moved.outcome == "ARRIVED" && nav.keys.codesPosted.isEmpty, "Nav does not walk past a newly reached destination")

        let hunt = SimHunt(world: SimNav(clock: FightClock(), x: 40, y: 30, facing: 0), mobs: [
            SimHunt.Mob(name: "Roiling Winds", x: 40, y: 29.8, hostile: false),
            SimHunt.Mob(name: "Al'Aketh Convert", x: 40, y: 29.7, hostile: false)
        ], objectives: [Objective(quest: "Agitators", done: 0, need: 1, text: "Roiling Winds destroyed"),
                        Objective(quest: "Agitators", done: 0, need: 1, text: "Al'Aketh Convert slain")])
        hunt.selected = 0
        var changes = 0, rejections: [String] = []
        hunt.world.emitHandler = { event, fields in if event == "proposal_rejected", let reason = fields["reason"] as? String { rejections.append(reason) } }
        let hunted = await runHunt(host: hunt, jev: ChangedDuringRequest<HuntAction>(preference: [.fight], change: {
            changes += 1
            if changes == 1 { hunt.selected = 1 } else { hunt.world.ownerFront = true }
        }))
        check(rejections.contains("target_cue_changed") && hunt.fightsRun == 0, "Hunt rejects a different selected creature after inference")
        check(hunted.outcome == "OWNER_TOOK_FOCUS", "Hunt owner stop remains terminal")

        let normal = SimHunt(world: SimNav(clock: FightClock(), x: 40, y: 30, facing: 0), mobs: [
            SimHunt.Mob(name: "Roiling Winds", x: 40, y: 29.8, hostile: false)
        ], objectives: [Objective(quest: "Agitators", done: 0, need: 1, text: "Roiling Winds destroyed")])
        normal.selected = 0
        let completed = await runHunt(host: normal, jev: ScriptedJev<HuntAction>(preference: [.fight]))
        check(completed.outcome == "OBJECTIVES_COMPLETE", "existing simulated hunt remains successful")
        check(completed.memory?.recent.map(\.skill) == ["combat", "hunt"], "parent task keeps the nested result")
        check(completed.memory?.goal == "complete the initial unfinished objectives", "task goal survives skill handoff")
        check(completed.memory?.activeSkill == nil && completed.memory?.suspendedSkills.isEmpty == true, "task stack closes")
        check(completed.runtime?.status == .completed && !completed.holding, "typed parent result and input release")
        // SimHunt.fight is a documented canned outcome, not a combat simulation or input proof.
        print("runtime integration checks passed: \(checks)")
    }
}
