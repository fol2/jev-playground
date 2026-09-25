// Shared in-process contracts. No capture, provider, clock, file or input effects.
import Foundation

struct ObservationStamp: Equatable {
    let stream: String
    let geometry: String
    let capturedAt: Double
    // A visual selection cue, NOT a unique game-entity ID. Nil means unavailable.
    var target: String? = nil
    // Absolute host-clock origin of the caller's relative clock (zero for host time).
    var clockOrigin: Double = 0

    func isFresh(at now: Double, maximumAge: Double) -> Bool {
        !stream.isEmpty && !geometry.isEmpty && capturedAt.isFinite && now.isFinite
            && clockOrigin.isFinite && maximumAge.isFinite && maximumAge > 0 && now >= capturedAt && now - capturedAt < maximumAge
    }
}

enum Observation<Value> {
    case observed(Value, ObservationStamp)
    case unavailable(String)

    var value: Value? { if case let .observed(value, _) = self { return value }; return nil }
    var stamp: ObservationStamp? { if case let .observed(_, stamp) = self { return stamp }; return nil }
}

enum SkillStatus: String {
    case completed, blocked, cancelled, observationLost, stopped, failed
}

struct SkillResult {
    let skill: String
    let status: SkillStatus
    let code: String
    let evidence: ObservationStamp?
    let holdingInput: Bool
    // An observed UI outcome is not engine truth, arrival or player safety.
    var json: [String: Any] {
        ["skill": skill, "status": status.rawValue, "code": code, "holding_input": holdingInput,
         "evidence": evidence.map { ["stream": $0.stream, "geometry": $0.geometry,
             "captured_at": $0.capturedAt, "clock_origin": $0.clockOrigin] as [String: Any] } as Any? ?? NSNull()]
    }
}

struct TaskMemory {
    let goal: String
    private(set) var revision = 0
    private(set) var activeSkill: String?
    private(set) var suspendedSkills: [String] = []
    private(set) var recent: [SkillResult] = []

    mutating func begin(_ skill: String) {
        if let activeSkill { suspendedSkills.append(activeSkill) }
        activeSkill = skill
        revision += 1
    }

    mutating func finish(_ result: SkillResult) -> Bool {
        guard activeSkill == result.skill else { return false }
        recent.append(result)
        if recent.count > 6 { recent.removeFirst() }
        activeSkill = suspendedSkills.popLast()
        revision += 1
        return true
    }
}

struct DecisionContext: Equatable {
    let request: Int
    let revision: Int
    let observation: ObservationStamp
    let candidates: [String]
    let policy: String
    let deadline: Double

    var json: [String: Any] {
        ["request": request, "task_revision": revision, "stream": observation.stream,
         "geometry": observation.geometry, "captured_at": observation.capturedAt, "clock_origin": observation.clockOrigin,
         "target_cue": observation.target as Any? ?? NSNull(), "policy": policy, "deadline": deadline]
    }
}

struct DecisionProposal {
    let context: DecisionContext
    let action: String
}

// The executive owns task transitions and one pending decision. Model output carries
// an action only; request identity/deadlines are attached by the caller, never the model.
struct RuntimeExecutive {
    private(set) var memory: TaskMemory
    private var serial = 0
    private var pending: DecisionContext?

    init(goal: String) { memory = TaskMemory(goal: goal) }

    mutating func begin(_ skill: String) { pending = nil; memory.begin(skill) }
    @discardableResult
    mutating func finish(_ result: SkillResult) -> Bool {
        guard memory.activeSkill == result.skill else { return false }
        pending = nil
        return memory.finish(result)
    }
    mutating func invalidate() { pending = nil }

    mutating func request(stamp: ObservationStamp, candidates: [String], policy: String,
                          now: Double, maximumAge: Double, deadline: Double) -> DecisionContext? {
        pending = nil
        guard stamp.isFresh(at: now, maximumAge: maximumAge), deadline.isFinite, deadline > now,
              !policy.isEmpty, !candidates.isEmpty, candidates.allSatisfy({ !$0.isEmpty }),
              Set(candidates).count == candidates.count else { return nil }
        serial += 1
        let context = DecisionContext(request: serial, revision: memory.revision, observation: stamp,
                                      candidates: candidates, policy: policy, deadline: deadline)
        pending = context
        return context
    }

    // Each reply can authorise at most one skill, including rejected replies. A new
    // decision supersedes an old one; an old callback cannot consume the new request.
    mutating func rejection(_ proposal: DecisionProposal, current: ObservationStamp?,
                            candidates: [String], now: Double, maximumAge: Double,
                            ownerStopped: Bool) -> String? {
        guard let pending, pending == proposal.context else { return "superseded_request" }
        self.pending = nil
        guard !ownerStopped else { return "owner_stop" }
        guard now.isFinite, now < pending.deadline else { return "decision_expired" }
        guard pending.revision == memory.revision else { return "task_changed" }
        guard pending.candidates.contains(proposal.action), candidates.contains(proposal.action) else {
            return "action_no_longer_admissible"
        }
        guard let current, current.isFresh(at: now, maximumAge: maximumAge) else { return "observation_unavailable" }
        guard current.stream == pending.observation.stream, current.geometry == pending.observation.geometry,
              current.clockOrigin == pending.observation.clockOrigin else {
            return "observation_identity_changed"
        }
        guard current.capturedAt >= pending.observation.capturedAt else { return "reordered_observation" }
        guard current.target == pending.observation.target else { return "target_cue_changed" }
        return nil
    }
}

// Compatibility mapping: preserve the original code and its qualification limits.
func skillStatus(_ code: String) -> SkillStatus {
    if ["ARRIVED", "OBJECTIVES_COMPLETE", "KILLED_AND_LOOTED", "KILLED_NO_CORPSE"].contains(code) { return .completed }
    if ["NO_FRESH_FRAME", "HUD_UNREADABLE"].contains(code) { return .observationLost }
    if ["OWNER_TOOK_FOCUS", "OWNER_STOP"].contains(code) { return .cancelled }
    if ["COMBAT", "DANGER_AHEAD", "NO_PROGRESS", "NO_ADMISSIBLE_MOVE", "NO_TARGET_FOUND"].contains(code) { return .blocked }
    if code.contains("FAILED") || code.contains("ERROR") || code == "INVALID_REPLY" { return .failed }
    return .stopped
}
