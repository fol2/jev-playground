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

/// Why a walk stops: a hostile ahead of its heading (M4h, M4t), or the character below the floor out of combat.
enum WalkStop: String, Equatable { case hostileAhead, lowHealth }

enum ReflexAction: Equatable {
    case pause(String)                 // the owner has the game: release every key and wait
    case holdAndReobserve(String)      // no fresh vision: release held movement, read again, do not act
    case releaseSpirit                 // dead: the death recovery skill (M4s)
    case fightBack                     // in combat: the fight skill owns the keys until the fight ends
    case heal                          // in combat below the floor: heal now (the fight's own reflex)
    case stopWalk(WalkStop, String)    // the walk stops: a hostile ahead of the heading, or low health (the way to safety for neither)
    case recover                       // out of combat and hurt: heal, rest or eat before walking on (M4w)
    case buffWeapon                    // about to fight with no weapon enchant (M3, review of #79)
    case walkPast(String)              // an unaggressive creature alone stopped the walk: walk past it, once a step (M4am)
    case fightAhead(String)            // a lone creature no higher than the character stopped the walk: fight it (M4ak)
    case stopFight(String)             // in a fight, below the floor out of combat: the fight ends and the loop recovers (M3)
}

struct ReflexContext: Equatable {
    var now: Double
    var ownerTookFocus: Bool
    var maximumVisionAge: Double = 1.0
    var walkingHeading: Double? = nil  // set while a walk holds W: its heading
    var aboutToFight: Bool = false     // the planner's next task is a fight
    var stoppedWalk: Bool = false      // a hostile stopped a walk and the stop stands; the world's `ahead` says what
    var walkedPast: Bool = false       // the stopped step already walked past once this session (M4am is once a step)
    var walkingToSafety: Bool = false  // the walk is the way to safety: a hostile ahead does not stop it (M4r)
    var passing: Bool = false          // a walk past is armed: a red name ahead does not stop this walk (M4am)
    var inFight: Bool = false          // inside the fight's loop: its stop floor out of combat applies (M3's SAFETY_STOP)
    var walking: Bool = false          // inside a walk: its floor out of combat applies (LOW_HEALTH; not on the way to safety)
}

/// A reflex's log line, the same in every loop: its controller, its name and the action.
func reflexEvent(_ hit: (reflex: Reflex, action: ReflexAction)) -> [String: Any] {
    ["controller": hit.reflex.controller.rawValue, "reflex": hit.reflex.name, "action": "\(hit.action)"]
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
    static let fightsWeakBlockers = ProcessInfo.processInfo.environment["JEV_BLOCKER_FIGHT"] != "off"  // M4ak's switch
    static let warnCone = 30.0           // NavLimits.warnCone: a red name or hostile plate within this of the heading stops a walk
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
        // The enchant at a fight's start (the owner: buff before every fight; live run 72: offered to Jev in every decision,
        // never chosen), before the fight itself takes over; attacked, only at 60 % health or more, so a hurt fight back spends
        // its global cooldown on healing, not the enchant (review of #79). Never in a cast, never below the heal floor.
        Reflex(name: "buff_before_fight", controller: .rule) { w, c in
            guard c.aboutToFight, w.character.weaponBuffActive.value == false, w.character.casting.value != true,
                  w.character.inCombat.value == false || (w.character.health.value ?? 0) >= ReflexLimits.walkHealth else { return nil }
            return .buffWeapon
        },
        Reflex(name: "combat", controller: .safety) { w, _ in w.character.inCombat.value == true ? .fightBack : nil },
        // The floors before a hostile ahead (review of #117: in walk() one call carries the heading, and the stop at 30 % out of
        // combat is the walk's answer whatever stands ahead, as on main). Inside a walk, out of combat below the floor, the walk
        // stops (LOW_HEALTH), except the way to safety, which walks on (reviews of #72: stopping among hostiles is what it leaves).
        Reflex(name: "walk_low_health", controller: .safety) { w, c in
            guard c.walking, !c.walkingToSafety, w.character.inCombat.value == false, let h = w.character.health.value,
                  h < ReflexLimits.combatHealthFloor else { return nil }
            return .stopWalk(.lowHealth, "below the floor out of combat: the walk stops")
        },
        // Inside a fight, out of combat below the floor, the fight ends and the loop recovers (M3: SAFETY_STOP_PLAYER_BELOW_30;
        // the owner, 23 Sept: never a stop in combat, where standing still is dying).
        Reflex(name: "fight_stop_hurt", controller: .safety) { w, c in
            guard c.inFight, w.character.inCombat.value == false, let h = w.character.health.value, h < ReflexLimits.combatHealthFloor else { return nil }
            return .stopFight("below the floor out of combat: the fight ends")
        },
        Reflex(name: "hostile_ahead", controller: .rule) { w, c in
            guard let heading = c.walkingHeading, !c.walkingToSafety, !c.passing else { return nil }
            let ahead = w.entities.hostilesAhead(of: heading, within: ReflexLimits.warnCone)
            return ahead.isEmpty ? nil : .stopWalk(.hostileAhead, "\(ahead.count) hostile ahead within \(Int(ReflexLimits.warnCone)) degrees")
        },
        // A recovery before the stop rules (review of #117: hurt at a stop, the session recovers first; the stop stands and the
        // walk past or the fight ahead is the next tick's). Between 30 and 60 % a walk walks on (the loop's recovery, after it).
        Reflex(name: "hurt_out_of_combat", controller: .rule) { w, _ in
            guard w.character.inCombat.value == false, let h = w.character.health.value, h < ReflexLimits.walkHealth else { return nil }
            return .recover
        },
        // After a stop, before any plan: M4am (the owner, 28 Sept: "Juvenile Vuldren is unagreesive") is tried before M4ak,
        // as the run loop did; both replace a Jev decision that the live record shows Jev got wrong (RETREAT at every stop,
        // runs 89-94). Company, a higher or unread level, a threat in view, or a second stop of the same step stay Jev's.
        Reflex(name: "walk_past", controller: .rule) { w, c in
            guard c.stoppedWalk, !c.walkedPast, let a = w.ahead.value, a.unaggressive, (a.threats ?? a.company) == 0 else { return nil }
            return .walkPast("an unaggressive creature stopped the walk: walk past it")
        },
        Reflex(name: "blocker_fight", controller: .rule) { w, c in
            guard c.stoppedWalk, ReflexLimits.fightsWeakBlockers, let a = w.ahead.value, !a.unaggressive, let level = a.level,
                  let mine = w.character.level.value, level <= mine, a.company == 0 else { return nil }
            return .fightAhead("a lone creature no higher than the character stopped the walk: fight it")
        },
    ]

    static func first(_ world: WorldState, _ context: ReflexContext, table: [Reflex] = standard) -> (reflex: Reflex, action: ReflexAction)? {
        for reflex in table {
            if let action = reflex.fires(world, context) { return (reflex, action) }
        }
        return nil
    }

    /// The owner's takeover before a loop reads anything this tick: the table's first entry over an empty world.
    static func ownerTakeover(_ ownerTookFocus: Bool, now: Double) -> (reflex: Reflex, action: ReflexAction)? {
        guard let hit = first(WorldState(), ReflexContext(now: now, ownerTookFocus: ownerTookFocus, maximumVisionAge: .infinity)),
              case .pause = hit.action else { return nil }
        return hit
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
    case reflex(ReflexAction, ControllerName, String)  // the action, its controller and the reflex's name, for the log
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
            case .stopWalk, .buffWeapon, .walkPast, .fightAhead, .stopFight: break
            }
            return .reflex(hit.action, hit.reflex.controller, hit.reflex.name)
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

    /// Record a task's end. A failure counts against the no-progress limit; a planned step's success (JEV's or RULE's,
    /// not a SAFETY reflex's: a fight back won or a walk to safety is not progress on the goal) resets it. Death is
    /// counted where it is seen, by the reflex, not here.
    mutating func end(task: String, controller: ControllerName, outcome: TaskOutcome, at now: Double) {
        if let i = history.lastIndex(where: { $0.task == task && $0.outcome == .running }) {
            history[i].controller = controller
            history[i].outcome = outcome
            history[i].ended = now
        } else {
            history.append(TaskRecord(task: task, controller: controller, outcome: outcome, began: now, ended: now))
        }
        if case .failed = outcome { usage.consecutiveFailures += 1 }
        else if case .succeeded = outcome, controller == .jev || controller == .rule { usage.consecutiveFailures = 0 }
        activeTask = nil
        if mode == .questing || mode == .inTown { mode = .idleSafe }
    }

    mutating func countJudgeCall() { usage.judgeCalls += 1 }
    mutating func countDeath() { usage.deaths += 1 }

    var failures: [TaskRecord] {
        history.filter { if case .failed = $0.outcome { return true }; return false }
    }
}
