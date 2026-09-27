// The session loop (#87): the quest loop inside the engine's PlayLoop. A failure is an outcome the loop
// records and plans round; an unread frame holds; the owner's takeover pauses; death, combat and low
// health are reflexes; only the envelope (or the owner holding the game) ends it. Opt-in beside
// `runQuests`, which stays the qualified baseline until a live session has run (`--quests --session`).
//
// Jev's part is unchanged in this slice: the same offers, the same quest graph, the same criteria. What
// changes is what happens around a decision, and what a failure does. Pure Foundation.
import Foundation

/// The HUD's vitals on a fresh frame, as the session's reflexes read them.
struct SessionVitals: Equatable {
    var health: Double   // 0...1
    var mana: Double     // 0...1
    var inCombat: Bool
    var dead: Bool       // an empty health bar out of combat, or the death screen
    var capturedAt: Double
}

/// What a session needs beyond a quest run: the vitals, and the recovery skills the live shell runs at a
/// run's end (M4r, M4s, M4w), here as steps the loop may take at any time.
protocol SessionHost: QuestHost {
    func vitals() -> SessionVitals?           // the HUD on a frame no older than the vision age; nil without one
    func recover() async -> String            // out of combat and hurt: heal (M4w); RECOVERED, STILL_HURT or why not
    func toSafety() async -> String           // walk to the nearest safe place, fighting back on the way (M4r); SAFE, or a walk's outcome
    func revive() async -> String?            // death recovery (M4s); nil when the screen shows no death
    func wait(_ seconds: Double) async        // stand, with no input
}

enum SessionLimits {
    static let visionAge = 1.0          // FightLimits.maxFrameAge: an older newest frame is a stall, not calm
    static let settle = 0.5             // between two reads of a world that did not read
    static let unreadLimit = 5          // unread reads in a row before a perception failure is recorded and the loop backs off
    static let backoff = 10.0           // seconds to wait after that
    static let idleSeconds = 120.0      // with nothing to do: stand in safety, then read again
    static let restSeconds = 20.0       // hurt with no heal to cast: stand and regenerate before reading again
    static let ownerPause = 120.0       // the owner has the game this long: the session ends OWNER_TOOK_FOCUS
    static let endReserve = 300.0       // kept from the envelope for the way to safety and a revive at the end
    static let deadRetry = 60.0         // the HUD reads dead but no death screen shows this long: a perception failure, then backoff
    static let deaths = 3               // the envelope's default death limit
    static let judgeCalls = 400         // and its default call limit: a decision spends up to four (M4f)
    static let consecutiveFailures = 8  // planned steps failed in a row with no success between: the session is not making progress
}

struct SessionResult {
    var outcome = ""
    var steps: [(quest: String, outcome: String)] = []
    var records: [TaskRecord] = []
    var graphRecords: [[String: Any]] = []
    var usage = EnvelopeUsage()
    var modes: [String] = []  // each mode the loop entered, in order
}

/// A step's code as a task outcome: the codes that worked, the codes that found nothing to do, and the rest as
/// failures of the taxonomy's kind. The codes themselves are unchanged, so the run log reads as before.
func taskOutcome(_ code: String) -> TaskOutcome {
    // Prefixes carry their detail ("COMPLETED_TO_WEAR", "HUNTED_SOME", "SOLD 38", "KILLED_NO_CORPSE"); the rest match whole,
    // so that "SAFE" never takes "SAFETY_STOP_PLAYER_BELOW_30" for a success.
    let worked = ["COMPLETED", "ACCEPTED", "HUNTED", "BY_ROAD", "USED", "SOLD", "TRAINED", "RETREATED", "KILLED", "REVIVED", "RECOVERED"]
    if worked.contains(where: code.hasPrefix) { return .succeeded(code) }
    if ["SAFE", "ARRIVED", "NOTHING_TO_TRAIN", "NO_JUNK", "NOT_HURT"].contains(code) { return .succeeded(code) }
    return .failed(TaskFailure(kind: failureKind(forCode: code), code: code, detail: ""))
}

/// The engine's own faults, after which no key may go down: they end the session as they ended a run.
func endsSession(_ code: String) -> Bool {
    code.hasSuffix("KEYS_HELD") || code.contains("HANDOFF")
}

func runSession(host: SessionHost, jev: JevClient, graph: GraphSession, roads: RoadGraph? = nil, town: [TownNPC] = [],
                budget: EnvelopeBudget = EnvelopeBudget(seconds: QuestLimits.envelopeSeconds, deaths: SessionLimits.deaths,
                                                        judgeCalls: SessionLimits.judgeCalls,
                                                        consecutiveFailures: SessionLimits.consecutiveFailures)) async -> SessionResult {
    var r = SessionResult()
    let began = host.now()
    var loop = PlayLoop(budget: budget, began: began)
    var world = WorldState()
    var failed: Set<String> = [], used: Set<String> = []
    var danger: QuestStep?  // the step a hostile stopped, while that stop stands (M4h, M4o, M4p)
    var unread = 0, wasDead = false
    var deadSince: Double?, pausedSince: Double?
    var lastMode = loop.mode
    let stepsEnd = began + budget.seconds - SessionLimits.endReserve  // no step starts after this: the end has its reserve

    /// The vitals into the world model. No fresh frame: the frame ages, and the stale-vision reflex holds.
    func observe() {
        guard let v = host.vitals() else { return }
        world.note(frame: FrameIdentity(stream: "hud", geometry: "hud", capturedAt: v.capturedAt))
        func read<T: Equatable>(_ value: T) -> Belief<T> {
            .known(Reading(value: value, confidence: 1, capturedAt: v.capturedAt, source: "pixels:hud"))
        }
        world.update(\.character.health, read(v.health))
        world.update(\.character.mana, read(v.mana))
        world.update(\.character.inCombat, read(v.inCombat))
        world.update(\.character.dead, read(v.dead))
    }
    /// Record a task's end; a failure is logged with its kind for the run report.
    @discardableResult
    func note(_ task: String, _ controller: ControllerName, _ code: String) -> TaskOutcome {
        let outcome = taskOutcome(code)
        loop.end(task: task, controller: controller, outcome: outcome, at: host.now())
        if case let .failed(f) = outcome {
            host.emit("task_failed", ["task": task, "controller": controller.rawValue, "kind": f.kind.rawValue, "code": code])
        }
        return outcome
    }
    func modeChanged() {
        guard loop.mode != lastMode else { return }
        lastMode = loop.mode
        r.modes.append(loop.mode.rawValue)
        host.emit("session_mode", ["mode": loop.mode.rawValue])
    }
    func finish(_ outcome: String) async -> SessionResult {
        host.emit("session_end", ["outcome": outcome, "steps": r.steps.count, "deaths": loop.usage.deaths,
                                  "judge_calls": loop.usage.judgeCalls, "failures": loop.failures.count])
        // The way to safety and a revive, as a run's end (M4r, M4s): not after the owner's takeover or an engine fault.
        if outcome == "DEATH_LIMIT" {
            if let end = await host.revive() { r.steps.append(("revive", end)) }
        } else if leavesDanger(outcome) {
            r.steps.append(("to safety", await host.toSafety()))
            if let end = await host.revive() { r.steps.append(("revive", end)) }
        }
        r.outcome = outcome; r.records = loop.history; r.usage = loop.usage
        return r
    }
    func recordCalls() {
        for call in graph.lastTrace { r.graphRecords.append(call); host.emit("graph_call", call); loop.countJudgeCall() }
    }

    while true {
        observe()
        let now = host.now()
        let step = loop.next(world: world, context: ReflexContext(now: now, ownerTookFocus: host.ownerTookFocus(),
                                                                   maximumVisionAge: SessionLimits.visionAge))
        modeChanged()
        switch step {
        case .stop(let why):
            return await finish(why)
        case .reflex(let action, let controller):
            host.emit("reflex", ["controller": controller.rawValue, "action": "\(action)"])
            switch action {
            case .pause:
                // The owner has the game: no input, and the session waits. Held this long, the owner has taken over.
                if pausedSince == nil { pausedSince = now }
                if now - pausedSince! >= SessionLimits.ownerPause { return await finish("OWNER_TOOK_FOCUS") }
                await host.wait(SessionLimits.settle)
            case .holdAndReobserve:
                // No fresh frame: nothing acts. Many in a row are a perception failure, recorded, and the loop backs off.
                unread += 1
                if unread >= SessionLimits.unreadLimit {
                    note("observe", .safety, "HUD_UNREADABLE")
                    unread = 0
                    await host.wait(SessionLimits.backoff)
                } else {
                    await host.wait(SessionLimits.settle)
                }
            case .releaseSpirit:
                if !wasDead {
                    wasDead = true; deadSince = now
                    loop.countDeath()
                    host.emit("death", ["controller": "SAFETY"])
                }
                if let end = await host.revive() {
                    note("revive", .safety, end)
                    if end == "REVIVED" { deadSince = nil } else { await host.wait(SessionLimits.settle) }
                } else if now - (deadSince ?? now) >= SessionLimits.deadRetry {
                    // The bar reads empty out of combat but no death screen shows: a misread, not a resurrection to wait for.
                    note("revive", .safety, "DEATH_NOT_SHOWN")
                    deadSince = now
                    await host.wait(SessionLimits.backoff)
                } else {
                    await host.wait(SessionLimits.settle)
                }
            case .fightBack, .heal:
                // In combat the only choice is to fight back (M4i); the fight heals under its own rules. Whatever it ended,
                // the next tick reads the HUD again: still in combat fights again, dead revives, hurt recovers.
                loop.begin(task: "fight back", mode: loop.mode, at: now)
                let outcome = await host.fightBack()
                r.steps.append(("fight back", outcome))
                note("fight back", .safety, outcome)
                if endsSession(outcome) { return await finish(outcome) }
            case .recover:
                loop.begin(task: "recover", mode: .recovering, at: now)
                let outcome = await host.recover()
                note("recover", .rule, outcome)
                if outcome != "RECOVERED" { await host.wait(SessionLimits.restSeconds) }  // no heal to cast: stand and regenerate
            case .stopWalk, .buffWeapon:
                break  // the skills own their walks and fights; this loop never holds a walking heading
            }
            continue
        case .plan, .continueTask:
            break
        }
        pausedSince = nil
        wasDead = false  // no death reflex fired this tick: alive
        if now >= stepsEnd { return await finish("TIME_LIMIT") }  // no step starts inside the end's reserve

        guard let read = await host.readQuests() else {  // the position was unreadable: hold, as an unread frame
            unread += 1
            if unread >= SessionLimits.unreadLimit {
                note("read", .rule, "POSITION_UNREADABLE")
                unread = 0
                await host.wait(SessionLimits.backoff)
            } else {
                await host.wait(SessionLimits.settle)
            }
            continue
        }
        guard read.missing.isEmpty else {  // a quest the minimap names is not in the log read: read again, never end
            unread += 1
            if unread >= SessionLimits.unreadLimit {
                note("read", .rule, "LOG_INCOMPLETE")
                unread = 0
                await host.wait(SessionLimits.backoff)
            } else {
                await host.wait(SessionLimits.settle)
            }
            continue
        }
        unread = 0
        let stopped = danger, stoppedKey = danger?.key
        let offers = (questOffers(read, failed: failed, stopped: stopped, roads: roads, used: used) + townOffers(read, npcs: town, failed: failed))
            .map { (skill: $0.skill, step: $0.step, criterion: withHistory($0.criterion, read.history[$0.step.key])) }
        host.emit("plan", ["offers": offers.map(\.skill), "failed": failed.sorted()])
        if offers.isEmpty {
            // Idle-safe: nothing within reach. Stand in safety, forget this session's failures (a later read may show change;
            // the envelope's no-progress limit bounds a step that fails every time), and read again later.
            loop.begin(task: "idle", mode: .idleSafe, at: host.now())
            note("idle", .safety, await host.toSafety())
            failed = []; danger = nil
            await host.wait(SessionLimits.idleSeconds)
            continue
        }

        // Decide: Jev, through the quest graph, as runQuests does. A failed call is a recorded failure, not an end.
        let decision: GraphDecision
        do {
            decision = try await graph.next(state: questState(read, steps: r.steps),
                skills: Dictionary(uniqueKeysWithValues: offers.map { ($0.skill, $0.criterion) }), jev: jev,
                now: host.now, deadline: host.now() + QuestLimits.decisionSeconds, stopped: host.ownerTookFocus)
        } catch {
            recordCalls()
            note("decide", .jev, error is GraphError ? "GRAPH_\(error)" : "JEV_FAILED")
            await host.wait(SessionLimits.settle)
            continue
        }
        recordCalls()
        guard let offer = offers.first(where: { $0.skill == decision.action }) else {
            note("decide", .jev, "INVALID_REPLY")
            continue
        }
        host.emit("quest_step", ["controller": "JEV", "skill": offer.skill, "step": offer.step.name])
        var mode = PlayMode.questing
        if case .town = offer.step { mode = .inTown }
        loop.begin(task: offer.step.name, mode: mode, at: host.now())
        modeChanged()
        let until = min(host.now() + HuntLimits.maxSeconds, stepsEnd)  // a hunt or a road: what the envelope leaves, at most a hunt's own
        let outcome: String
        switch offer.step {
        case .handIn(let q): outcome = await host.handIn(q)
        case .accept(let g): outcome = await host.accept(g)
        case .hunt(let q): outcome = await host.hunt(q, until: until)
        case .road(let q, let legs): outcome = await host.walkRoad(to: q, by: legs, until: until)
        case .use(let q, let item): outcome = await host.useItem(q, item: item)
        case .retreat: outcome = await host.retreat()
        case .fightAhead: outcome = await host.fightAhead()
        case .town(let n): outcome = await host.visit(n)
        }
        r.steps.append((offer.step.name, outcome))
        switch offer.step {  // a retreat, a fight ahead or an accept is not a step to remember across runs (review of #81)
        case .retreat, .fightAhead, .accept: break
        default: host.remember(offer.step.key, outcome: outcome, level: read.level)
        }
        note(offer.step.name, .jev, outcome)
        if endsSession(outcome) { return await finish(outcome) }

        // The bookkeeping of runQuests, without its ends: the next tick's reflexes answer combat, death and low health.
        if outcome == "WALK_DANGER_AHEAD" {
            danger = offer.step
            failed.remove(QuestStep.fightAhead.key)
        } else if case .fightAhead = offer.step, QuestLimits.fightAheadHeld.contains(outcome) {
            failed.insert(QuestStep.fightAhead.key)
        } else if case .retreat = offer.step, outcome != "RETREATED" {
            // No way back: the stop stands (a run ended here for the owner; the session offers the fight ahead and the rest).
        } else {
            danger = nil
        }
        if offer.skill == "FROM_HERE" && outcome.hasPrefix("HUNTED") { failed.remove(offer.step.key) }
        if case .fightAhead = offer.step {
            let fought = outcome.hasPrefix("BACK_") ? String(outcome.dropFirst(5)) : outcome
            if QuestLimits.fightWon.contains(fought), let stoppedKey { failed.remove(stoppedKey) }
            continue
        }
        if case .town = offer.step, !outcome.hasPrefix("WALK_") {  // one visit a session, whatever it found (M4u)
            failed.insert(offer.step.key)
            continue
        }
        if outcome == "WALK_COMBAT" { continue }  // attacked on the way: the combat reflex fights back (SAFETY, M4i); the step stays offered
        if outcome.hasPrefix("COMPLETED") || outcome.hasPrefix("ACCEPTED") || outcome.hasPrefix("HUNTED") || outcome == "RETREATED"
            || outcome == "BY_ROAD" { continue }
        if outcome == "USED" || outcome == "USED_ABILITY" {  // used once: what the log still names is not used again
            failed.insert(offer.step.key)
            if outcome == "USED", case .use(let q, _) = offer.step { used.insert(q.title) }
            continue
        }
        if case .retreat = offer.step {  // no way back: the retreat is not offered again; the fight ahead and the rest are
            failed.insert(offer.step.key)
            continue
        }
        failed.insert(offer.step.key)  // a walk that stopped, a hunt that found nothing, a hand-in that did not open: not offered again
    }
}
