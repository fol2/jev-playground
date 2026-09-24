import Foundation

@main struct RuntimeTests {
    static func main() {
        var count = 0
        func check(_ ok: Bool, _ reason: String) { count += 1; precondition(ok, reason) }
        let stamp = ObservationStamp(stream: "capture", geometry: "layout", capturedAt: 10, target: "A")
        var engine = RuntimeExecutive(goal: "one quest")
        engine.begin("navigation")
        func request(_ engine: inout RuntimeExecutive) -> DecisionContext {
            engine.request(stamp: stamp, candidates: ["WALK", "WAIT"], policy: "test-v1",
                           now: 10.1, maximumAge: 1, deadline: 11)!
        }
        func reject(_ engine: inout RuntimeExecutive, _ context: DecisionContext,
                    current: ObservationStamp? = stamp, action: String = "WALK", now: Double = 10.5,
                    stopped: Bool = false, candidates: [String] = ["WALK", "WAIT"]) -> String? {
            engine.rejection(DecisionProposal(context: context, action: action), current: current,
                             candidates: candidates, now: now, maximumAge: 1, ownerStopped: stopped)
        }
        let first = request(&engine)
        check(reject(&engine, first) == nil, "current proposal")
        check(reject(&engine, first) == "superseded_request", "one-shot authorisation")
        let old = request(&engine), new = request(&engine)
        check(reject(&engine, old) == "superseded_request", "old callback")
        check(reject(&engine, new) == nil, "old callback cannot consume new request")
        let bads: [(ObservationStamp?, String)] = [
            (nil, "observation_unavailable"),
            (ObservationStamp(stream: "new", geometry: "layout", capturedAt: 10.2, target: "A"), "observation_identity_changed"),
            (ObservationStamp(stream: "capture", geometry: "new", capturedAt: 10.2, target: "A"), "observation_identity_changed"),
            (ObservationStamp(stream: "capture", geometry: "layout", capturedAt: 9.8, target: "A"), "reordered_observation"),
            (ObservationStamp(stream: "capture", geometry: "layout", capturedAt: 10.2, target: "B"), "target_cue_changed"),
            (ObservationStamp(stream: "capture", geometry: "layout", capturedAt: 10.2), "target_cue_changed"),
            (ObservationStamp(stream: "capture", geometry: "layout", capturedAt: 11), "observation_unavailable"),
        ]
        for (current, reason) in bads {
            let context = request(&engine)
            check(reject(&engine, context, current: current) == reason, reason)
        }
        var context = request(&engine)
        check(reject(&engine, context, stopped: true) == "owner_stop", "owner stop")
        context = request(&engine)
        check(reject(&engine, context, now: 11) == "decision_expired", "deadline boundary")
        context = request(&engine)
        check(reject(&engine, context, action: "FIRE") == "action_no_longer_admissible", "unoffered action")
        context = request(&engine)
        check(reject(&engine, context, candidates: ["WAIT"]) == "action_no_longer_admissible", "changed preconditions")
        context = request(&engine)
        engine.begin("combat")
        check(reject(&engine, context) == "superseded_request", "skill transition revokes proposal")
        check(engine.memory.goal == "one quest" && engine.memory.suspendedSkills == ["navigation"], "task survives interrupt")
        let result = SkillResult(skill: "combat", status: .completed, code: "KILLED_AND_LOOTED", evidence: stamp, holdingInput: false)
        check(engine.finish(result), "complete current skill")
        check(engine.memory.activeSkill == "navigation", "resume parent task")
        check(!engine.finish(result), "duplicate result cannot resume twice")
        for _ in 0..<10 { engine.begin("combat"); _ = engine.finish(result) }
        check(engine.memory.recent.count == 6, "bounded memory")
        let missing: Observation<Int> = .unavailable("no_frame")
        check(missing.value == nil && missing.stamp == nil, "unknown is not zero")
        let zero: Observation<Int> = .observed(0, stamp)
        check(zero.value == 0 && zero.stamp == stamp, "observed zero preserved")
        for now in [Double.nan, .infinity, -.infinity, 9, 11] {
            check(!stamp.isFresh(at: now, maximumAge: 1), "invalid/stale clock")
        }
        for actions in [[], [""], ["WALK", "WALK"]] as [[String]] {
            check(engine.request(stamp: stamp, candidates: actions, policy: "v1", now: 10.1,
                                 maximumAge: 1, deadline: 11) == nil, "invalid candidates")
        }
        check(engine.request(stamp: stamp, candidates: ["WALK"], policy: "v1", now: 10.1,
                             maximumAge: 1, deadline: .infinity) == nil, "unbounded deadline")
        print("runtime checks passed: \(count)")
    }
}
