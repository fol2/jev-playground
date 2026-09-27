// The deterministic controller: the failure taxonomy, the reflex table and the session loop.
// Pure Foundation. No capture, provider, clock, file or input effects. Linux and macOS.
//
// A reflex fires before any task on every tick. A task failure is an outcome the loop records and
// plans round; it never ends the session. Only the owner or an exhausted envelope ends a session.
import Foundation

/// Who decided: the provenance every action and every log line carries (AGENTS.md).
enum ControllerName: String, Equatable {
    case jev = "JEV", rule = "RULE", safety = "SAFETY", owner = "OWNER"
}

/// Why a task did not succeed. The offline learning loop sorts failures by this first.
enum FailureKind: String, CaseIterable, Equatable {
    case perception   // a reader gave no value or a wrong one (unread HUD, misread OCR, a false mark)
    case knowledge    // the engine did not know something the world required (no ender, no road, no item)
    case plan         // the chosen goal was wrong or impossible (a hunt for objects on the ground)
    case execution    // the skill ran and the world did not follow (a click on the ground, a stuck walk)
    case environment  // the world intervened (attacked, another player's tag, a world refresh)
    case safety       // a safety floor stopped it (low health, a hostile ahead)
    case budget       // the envelope's limits (time, calls, tokens, repeats)
}

struct TaskFailure: Equatable {
    var kind: FailureKind
    var code: String    // the existing outcome codes fit here unchanged: WALK_NO_PROGRESS, DIALOGUE_NOT_OPEN ...
    var detail: String
}

enum TaskOutcome: Equatable {
    case running
    case succeeded(String)
    case failed(TaskFailure)
}

/// Map an existing outcome code onto the taxonomy, so the old skills report into the new loop unchanged.
func failureKind(forCode code: String) -> FailureKind {
    let c = code.uppercased()
    if c.contains("UNREADABLE") || c.contains("NO_FRESH_FRAME") || c.contains("LOG_INCOMPLETE") || c.contains("INVALID_REPLY")
        || c.contains("TARGET_CUE_CHANGED") { return .perception }
    if c.contains("NEEDS_ROADS") || c.contains("NO_QUEST_MARK") || c.contains("NO_TARGET_FOUND") || c.contains("NO_ENDER") { return .knowledge }
    if c.contains("OWNER") { return .safety }
    if c.contains("DANGER") || c.contains("SAFETY") || c.contains("LOW_HEALTH") || c.contains("HOLD_PLAYER_HEALTH") { return .safety }
    if c.contains("LIMIT") || c.contains("EXPIRED") || c.contains("NO_PROGRESS") || c.contains("JEV_FAILED") || c.contains("GRAPH_") { return .budget }
    if c.contains("COMBAT") || c.contains("DEAD") || c.contains("REFRESH") { return .environment }
    return .execution
}

// MARK: Reflexes

enum ReflexAction: Equatable {
    case pause(String)                 // the owner has the game: release every key and wait
    case holdAndReobserve(String)      // no fresh vision: release held movement, read again, do not act
    case releaseSpirit                 // dead: the death recovery skill (M4s)
    case fightBack                     // in combat: the fight skill owns the keys until the fight ends
    case heal                          // in combat below the floor: heal now (the fight's own reflex)
    case stopWalk(String)              // a hostile ahead of the heading (M4h, M4t)
    case recover                       // out of combat and hurt: heal, rest or eat before walking on (M4w)
    case buffWeapon                    // about to fight with no weapon enchant (M3, review of #79)
}

struct ReflexContext: Equatable {
    var now: Double
    var ownerTookFocus: Bool
    var maximumVisionAge: Double = 1.0
    var walkingHeading: Double? = nil  // set while a walk holds W: its heading
    var aboutToFight: Bool = false     // the planner's next task is a fight
}

struct Reflex {
    let name: String
    let controller: ControllerName
    let fires: (WorldState, ReflexContext) -> ReflexAction?
}

enum ReflexLimits {
    static let combatHealthFloor = 0.3   // FightLimits.playerSafety
    static let healMana = 0.15           // FightLimits.healMana
    static let walkHealth = 0.6          // HuntLimits.walkHealth
}

/// The standard table, in the order the rules are tried. The first that fires wins the tick.
/// Every entry here is something the live record shows was first offered to Jev and then taken back.
enum ReflexTable {
    static let standard: [Reflex] = [
        Reflex(name: "owner_takeover", controller: .owner) { _, c in c.ownerTookFocus ? .pause("owner has the game") : nil },
        Reflex(name: "stale_vision", controller: .safety) { w, c in
            w.visionStale(at: c.now, maximumAge: c.maximumVisionAge) ? .holdAndReobserve("no frame newer than \(c.maximumVisionAge) s") : nil
        },
        Reflex(name: "dead", controller: .safety) { w, _ in w.character.dead.value == true ? .releaseSpirit : nil },
        Reflex(name: "combat_low_health", controller: .safety) { w, _ in
            guard w.character.inCombat.value == true, let h = w.character.health.value, h < ReflexLimits.combatHealthFloor,
                  (w.character.mana.value ?? 0) >= ReflexLimits.healMana else { return nil }
            return .heal
        },
        Reflex(name: "combat", controller: .safety) { w, _ in w.character.inCombat.value == true ? .fightBack : nil },
        Reflex(name: "hostile_ahead", controller: .rule) { w, c in
            guard let heading = c.walkingHeading else { return nil }
            let ahead = w.entities.hostilesAhead(of: heading)
            return ahead.isEmpty ? nil : .stopWalk("\(ahead.count) hostile ahead within 30 degrees")
        },
        Reflex(name: "hurt_out_of_combat", controller: .rule) { w, _ in
            guard w.character.inCombat.value == false, let h = w.character.health.value, h < ReflexLimits.walkHealth else { return nil }
            return .recover
        },
        Reflex(name: "buff_before_fight", controller: .rule) { w, c in
            c.aboutToFight && w.character.inCombat.value == false && w.character.weaponBuffActive.value == false ? .buffWeapon : nil
        },
    ]

    static func first(_ world: WorldState, _ context: ReflexContext, table: [Reflex] = standard) -> (reflex: Reflex, action: ReflexAction)? {
        for reflex in table {
            if let action = reflex.fires(world, context) { return (reflex, action) }
        }
        return nil
    }
}

// MARK: The session loop

enum PlayMode: String, Equatable {
    case dead, recovering, idleSafe, inTown, questing, paused
}

/// The owner's run envelope as limits the loop can count against. Values come from the owner, not from here.
struct EnvelopeBudget: Equatable {
    var seconds: Double
    var deaths: Int
    var judgeCalls: Int
    var consecutiveFailures: Int  // tasks failed in a row with no success between: the loop is not making progress
}

struct EnvelopeUsage: Equatable {
    var elapsed = 0.0
    var deaths = 0
    var judgeCalls = 0
    var consecutiveFailures = 0

    func exhausted(_ budget: EnvelopeBudget) -> String? {
        if elapsed >= budget.seconds { return "TIME_LIMIT" }
        if deaths >= budget.deaths { return "DEATH_LIMIT" }
        if judgeCalls >= budget.judgeCalls { return "CALL_LIMIT" }
        if consecutiveFailures >= budget.consecutiveFailures { return "NO_PROGRESS_LIMIT" }
        return nil
    }
}

struct TaskRecord: Equatable {
    var task: String
    var controller: ControllerName
    var outcome: TaskOutcome
    var began: Double
    var ended: Double
}

/// What the loop asks its host to do next.
enum PlayStep: Equatable {
    case reflex(ReflexAction, ControllerName)
    case plan                 // out of danger and idle: rank goals and start the best task
    case continueTask         // a task is running: tick it
    case stop(String)         // the envelope is spent or the owner stopped: release everything and report
}

struct PlayLoop: Equatable {
    private(set) var mode: PlayMode = .idleSafe
    private(set) var usage = EnvelopeUsage()
    private(set) var history: [TaskRecord] = []
    private(set) var activeTask: String?
    let budget: EnvelopeBudget
    let began: Double

    init(budget: EnvelopeBudget, began: Double) {
        self.budget = budget
        self.began = began
    }

    /// One tick. The loop never ends on a task failure or an unread frame; it ends only when the owner takes
    /// over or the envelope is spent.
    mutating func next(world: WorldState, context: ReflexContext) -> PlayStep {
        usage.elapsed = max(usage.elapsed, context.now - began)
        if let spent = usage.exhausted(budget) { return .stop(spent) }
        if let hit = ReflexTable.first(world, context) {
            switch hit.action {
            case .pause: mode = .paused
            case .releaseSpirit: mode = .dead
            case .holdAndReobserve: break  // the mode stands; nothing acts on stale vision
            case .fightBack, .heal: if mode != .dead { mode = mode == .paused ? .questing : mode }
            case .recover: mode = .recovering
            case .stopWalk, .buffWeapon: break
            }
            return .reflex(hit.action, hit.reflex.controller)
        }
        if mode == .paused { mode = .idleSafe }
        if mode == .dead, world.character.dead.value == false { mode = .recovering }
        if mode == .recovering, (world.character.health.value ?? 0) >= ReflexLimits.walkHealth, world.entities.hostiles(near: true).isEmpty {
            mode = .idleSafe
        }
        if activeTask != nil { return .continueTask }
        return .plan
    }

    mutating func begin(task: String, mode: PlayMode, at now: Double) {
        activeTask = task
        self.mode = mode
        history.append(TaskRecord(task: task, controller: .rule, outcome: .running, began: now, ended: now))
    }

    /// Record a task's end. A failure counts against the no-progress limit; a success resets it. Death is counted
    /// where it is seen, by the reflex, not here.
    mutating func end(task: String, controller: ControllerName, outcome: TaskOutcome, at now: Double) {
        if let i = history.lastIndex(where: { $0.task == task && $0.outcome == .running }) {
            history[i].controller = controller
            history[i].outcome = outcome
            history[i].ended = now
        } else {
            history.append(TaskRecord(task: task, controller: controller, outcome: outcome, began: now, ended: now))
        }
        if case .failed = outcome { usage.consecutiveFailures += 1 } else if case .succeeded = outcome { usage.consecutiveFailures = 0 }
        activeTask = nil
        if mode == .questing || mode == .inTown { mode = .idleSafe }
    }

    mutating func countJudgeCall() { usage.judgeCalls += 1 }
    mutating func countDeath() { usage.deaths += 1 }

    var failures: [TaskRecord] {
        history.filter { if case .failed = $0.outcome { return true }; return false }
    }
}
