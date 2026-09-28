// Counted offline checks for the engine skeleton. Pure Foundation; no capture, provider, input or game.
//
//   swiftc -parse-as-library experiments/002_wow_visual/engine/*.swift -o /tmp/engine-tests && /tmp/engine-tests
import Foundation

struct FakeJudgeClient: JudgeClient {
    var answers: [String: Any]
    var model = "jev-1.13.0"
    var calls: (() -> Void)? = nil
    func ask(state: [String: Any], questions: [String: [String: Any]]) async throws -> [String: Any] {
        calls?()
        return ["model": model, "answers": answers, "usage": ["prompt_tokens": 120, "completion_tokens": 0]]
    }
}

@main
struct EngineChecks {
    static var checks = 0
    static var failures = 0

    static func check(_ condition: Bool, _ what: String, line: Int = #line) {
        checks += 1
        if !condition { failures += 1; print("FAIL line \(line): \(what)") }
    }

    static func main() async {
        print("SIMULATION-ONLY proof: not live capture, OS input or a TypeSafe call.")
        beliefs()
        entities()
        world()
        reflexes()
        loop()
        planner()
        await judge()
        report()
        let floor = 111  // the count, as the motor proof's floor (tools/MotorProof.swift): removing a check must lower both on purpose
        if failures > 0 { print("engine checks failed: \(failures) of \(checks)") }
        print("engine checks passed: \(checks - failures)")
        if failures > 0 || checks < floor { exit(1) }
    }

    // MARK: Beliefs

    static func beliefs() {
        let a = Belief.known(Reading(value: 0.8, confidence: 1.0, capturedAt: 10, source: "pixels:hud"))
        let older = Belief.known(Reading(value: 0.5, confidence: 1.0, capturedAt: 9, source: "pixels:hud"))
        check(a.merged(older) == a, "an older frame's reading never replaces a newer one")
        let weak = Belief.known(Reading(value: 0.1, confidence: 0.4, capturedAt: 10.5, source: "learned:hud"))
        check(a.merged(weak) == a, "a weak reading within the window does not overturn a confident belief")
        let weakLater = Belief.known(Reading(value: 0.1, confidence: 0.4, capturedAt: 12, source: "learned:hud"))
        check(a.merged(weakLater) == weakLater, "after the window the newer reading wins")
        let strong = Belief.known(Reading(value: 0.6, confidence: 1.0, capturedAt: 10.5, source: "pixels:hud"))
        check(a.merged(strong) == strong, "a confident newer reading replaces")
        let miss = Belief<Double>.unknown(since: 11, reason: "plate over coordinates")
        check(a.merged(miss) == a, "a miss one second later keeps the belief")
        let lateMiss = Belief<Double>.unknown(since: 14, reason: "plate over coordinates")
        check(a.merged(lateMiss) == lateMiss, "a miss after keep seconds erases it")
        check(Belief<Double>.never.merged(a) == a, "a first reading fills an unknown")
        check(a.isFresh(at: 10.5, maximumAge: 1) && !a.isFresh(at: 12, maximumAge: 1) && !miss.isFresh(at: 11, maximumAge: 1),
              "freshness follows the capture time; an unknown is never fresh")
        let twoMisses = Belief<Double>.unknown(since: 11, reason: "a").merged(.unknown(since: 12, reason: "b"))
        check(twoMisses == .unknown(since: 12, reason: "b"), "the later miss is kept")
    }

    // MARK: Entities

    static func sighting(_ name: String, _ bearing: Double?, at t: Double, hostile: Bool = true, near: Bool = false, alive: Bool? = true) -> EntitySighting {
        EntitySighting(nameKey: worldNameKey(name), kind: .creature, hostility: hostile ? .hostile : .neutral, bearing: bearing,
                       near: near, alive: alive, confidence: 0.9, capturedAt: t, source: "ocr:plate")
    }

    static func entities() {
        var tracker = EntityTracker()
        tracker.observe([sighting("Pesky Cirrusfly 4845", 100, at: 1), sighting("Pesky Cirrusfly", 250, at: 1)], at: 1)
        check(tracker.tracks.count == 2, "two creatures of one name at different bearings are two tracks")
        tracker.observe([sighting("Pesky Cirrusfly AOPAU", 108, at: 2)], at: 2)
        check(tracker.tracks.count == 2 && tracker.tracks[0].sightings == 2 && tracker.tracks[0].bearing == 108,
              "an OCR tail and eight degrees of drift are the same creature")
        tracker.observe([sighting("Pesky Cirrusfiy Л Л4О", 104, at: 3)], at: 3)
        check(tracker.tracks.count == 2 && tracker.tracks[0].sightings == 3 && tracker.tracks[0].nameKey == "peskycirrusfly",
              "a misread letter with a Cyrillic tail is the same creature, and the cleaner key is kept")
        check(worldNameKey("Pesky Cirrusfly 4845") == worldNameKey("Pesky Cirrusfly"), "the name key drops digits and spaces")
        check(nameSimilar("roilingwinds", "roilingwind") && !nameSimilar("roilingwinds", "yalawindwatcher") && !nameSimilar("yala", "yalb")
              && nameSimilar("juvenilevuldren", "xypenilvuldren") == false && nameSimilar("juvenilevuldren", "juvenilevuldrem"),
              "name similarity: a prefix or two edits on a long name, never a short name's near miss")
        check(editDistance("kitten", "sitting") == 3 && editDistance("", "ab") == 2 && editDistance("same", "same") == 0, "edit distance")
        tracker.observe([], at: 40)
        check(tracker.tracks.isEmpty, "tracks unseen for the forget time are dropped")
        tracker.observe([sighting("Roiling Winds", 20, at: 50, near: true), sighting("Vuldren", 200, at: 50, hostile: false)], at: 50)
        check(tracker.hostiles().count == 1 && tracker.hostiles(near: true).count == 1, "hostile tracks by nearness")
        check(tracker.hostilesAhead(of: 40).count == 1 && tracker.hostilesAhead(of: 90).isEmpty, "a hostile within 30 degrees of the heading is ahead")
        tracker.observe([sighting("Roiling Winds", 22, at: 51, alive: false)], at: 51)
        check(tracker.hostiles().isEmpty, "a dead track is no hostile")
        tracker.observe([sighting("Yala", nil, at: 52, hostile: false)], at: 52)
        tracker.observe([sighting("Yala", 300, at: 53, hostile: false)], at: 53)
        check(tracker.tracks.filter { $0.nameKey == "yala" }.count == 1, "a sighting without a bearing matches a track of its name")
        check(abs(bearingError(350, 10) - 20) < 1e-9 && abs(bearingError(10, 350) + 20) < 1e-9, "bearing error wraps")
    }

    // MARK: World

    static func world() {
        var w = WorldState()
        w.update(\.character.health, .known(Reading(value: 0.9, confidence: 1, capturedAt: 5, source: "pixels:hud")))
        w.update(\.character.health, .unknown(since: 5.5, reason: "no bar"))
        check(w.character.health.value == 0.9, "the key-path update goes through the merge policy")
        w.note(frame: FrameIdentity(stream: "s", geometry: "g", capturedAt: 5))
        w.note(frame: FrameIdentity(stream: "s", geometry: "g", capturedAt: 4))
        check(w.frame?.capturedAt == 5, "an older frame does not move the newest frame back")
        check(w.visionAge(at: 6.5) == 1.5 && w.visionStale(at: 7, maximumAge: 1) && !w.visionStale(at: 5.5, maximumAge: 1), "vision age and staleness")
        check(WorldState().visionAge(at: 0) == .infinity, "no frame ever: infinite age")
        let q = QuestBelief(title: "Infestation Investigation", level: 2, objectives: [
            ObjectiveBelief(text: "Pesky Cirrusfly slain", done: 3, need: 8, kind: .kill),
            ObjectiveBelief(text: "Speak with Elatrell", done: nil, need: nil, kind: .talk)], readyToHandIn: false, pin: nil, ender: nil, inThisZone: true)
        w.update(\.quests, .known(Reading(value: [q], confidence: 1, capturedAt: 6, source: "ocr:log")))
        check(w.unfinishedObjectives.count == 2, "a line with no count stays unfinished")
        check(!ObjectiveBelief(text: "x", done: 8, need: 0, kind: .kill).finished && ObjectiveBelief(text: "x", done: 8, need: 8, kind: .kill).finished,
              "finished only by its own count")
        check(WorldPoint(x: 43.2, y: 24).distance(to: WorldPoint(x: 43.2, y: 26)) == 2, "y units are ground units")
        check(abs(WorldPoint(x: 40, y: 20).distance(to: WorldPoint(x: 42, y: 20)) - 3) < 1e-9, "one x unit is 1.5 y units")
    }

    // MARK: Reflexes

    static func healthy(at t: Double, combat: Bool = false, health: Double = 1.0, mana: Double = 1.0) -> WorldState {
        var w = WorldState()
        w.note(frame: FrameIdentity(stream: "s", geometry: "g", capturedAt: t))
        w.update(\.character.health, .known(Reading(value: health, confidence: 1, capturedAt: t, source: "pixels:hud")))
        w.update(\.character.mana, .known(Reading(value: mana, confidence: 1, capturedAt: t, source: "pixels:hud")))
        w.update(\.character.inCombat, .known(Reading(value: combat, confidence: 1, capturedAt: t, source: "pixels:hud")))
        w.update(\.character.dead, .known(Reading(value: false, confidence: 1, capturedAt: t, source: "pixels:hud")))
        w.update(\.character.weaponBuffActive, .known(Reading(value: true, confidence: 1, capturedAt: t, source: "pixels:hud")))
        return w
    }

    static func reflexes() {
        let ctx = ReflexContext(now: 10, ownerTookFocus: false)
        check(ReflexTable.first(healthy(at: 10), ctx) == nil, "nothing fires on a healthy, calm, fresh world")
        check(ReflexTable.first(healthy(at: 10), ReflexContext(now: 10, ownerTookFocus: true))?.action == .pause("owner has the game"),
              "the owner's takeover comes first")
        check(ReflexTable.first(healthy(at: 5), ctx)?.action == .holdAndReobserve("no frame newer than 1.0 s"), "stale vision holds")
        var dead = healthy(at: 10)
        dead.update(\.character.dead, .known(Reading(value: true, confidence: 1, capturedAt: 10.5, source: "ocr:release")))
        check(ReflexTable.first(dead, ctx)?.action == .releaseSpirit, "death recovery")
        check(ReflexTable.first(healthy(at: 10, combat: true, health: 0.2), ctx)?.action == .heal, "in combat below the floor: heal")
        check(ReflexTable.first(healthy(at: 10, combat: true, health: 0.2, mana: 0.05), ctx)?.action == .fightBack, "no mana: fight on")
        check(ReflexTable.first(healthy(at: 10, combat: true), ctx)?.action == .fightBack, "in combat: the fight owns the keys")
        var walk = healthy(at: 10)
        walk.entities.observe([sighting("Roiling Winds", 95, at: 10)], at: 10)
        check(ReflexTable.first(walk, ReflexContext(now: 10, ownerTookFocus: false, walkingHeading: 90))?.action == .stopWalk(.hostileAhead, "1 hostile ahead within 30 degrees"),
              "a hostile ahead stops the walk")
        let walking = ReflexContext(now: 10, ownerTookFocus: false, walking: true)
        check(ReflexTable.first(healthy(at: 10, health: 0.2), walking)?.action == .stopWalk(.lowHealth, "below the floor out of combat: the walk stops")
              && ReflexTable.first(healthy(at: 10, health: 0.2), walking)?.reflex.controller == .safety
              && ReflexTable.first(healthy(at: 10, health: 0.2), ReflexContext(now: 10, ownerTookFocus: false, walkingToSafety: true, walking: true))?.action == .recover
              && ReflexTable.first(healthy(at: 10, health: 0.5), walking)?.action == .recover
              && ReflexTable.first(healthy(at: 10, combat: true, health: 0.2), walking)?.action == .heal
              && ReflexTable.ownerTakeover(true, now: 10)?.reflex.name == "owner_takeover" && ReflexTable.ownerTakeover(false, now: 10) == nil,
              "a walk below 30 % out of combat stops (SAFETY); the way to safety walks on; 30-60 % is a recovery the walk ignores; combat is the fight's; the owner's takeover reads before any frame")
        check(ReflexTable.first(walk, ReflexContext(now: 10, ownerTookFocus: false, walkingHeading: 200)) == nil, "a hostile behind does not")
        check(ReflexTable.first(walk, ReflexContext(now: 10, ownerTookFocus: false, walkingHeading: 90, walkingToSafety: true)) == nil
              && ReflexTable.first(walk, ReflexContext(now: 10, ownerTookFocus: false, walkingHeading: 90, passing: true)) == nil,
              "the way to safety and an armed walk past do not stop for a hostile ahead")
        // After a stop (#88): M4am then M4ak, in the table, in that order.
        func stopped(_ a: AheadBelief?, level: Int? = 4, past: Bool = false, combat: Bool = false, health: Double = 1) -> (reflex: Reflex, action: ReflexAction)? {
            var w = healthy(at: 10, combat: combat, health: health)
            if let a { w.ahead = .known(Reading(value: a, confidence: 1, capturedAt: 10, source: "ocr:tab")) }
            if let level { w.update(\.character.level, .known(Reading(value: level, confidence: 1, capturedAt: 10, source: "ocr:log"))) }
            return ReflexTable.first(w, ReflexContext(now: 10, ownerTookFocus: false, stoppedWalk: true, walkedPast: past))
        }
        let meek = AheadBelief(nameKey: "juvenilevuldren", level: 1, company: 1, threats: 0, unaggressive: true)
        check(stopped(meek)?.action == .walkPast("an unaggressive creature stopped the walk: walk past it") && stopped(meek)?.reflex.name == "walk_past"
              && stopped(meek)?.reflex.controller == .rule && stopped(meek, past: true) == nil
              && stopped(AheadBelief(nameKey: "juvenilevuldren", level: 1, company: 1, threats: 1, unaggressive: true)) == nil
              && stopped(AheadBelief(nameKey: "juvenilevuldren", level: 1, company: 1, unaggressive: true)) == nil,
              "M4am: an unaggressive creature with no threat in view is walked past once, by RULE; a threat, unread company or a second stop is Jev's")
        let weak = AheadBelief(nameKey: "scrawnyursera", level: 3)
        check(stopped(weak)?.action == .fightAhead("a lone creature no higher than the character stopped the walk: fight it")
              && stopped(weak)?.reflex.name == "blocker_fight" && stopped(weak)?.reflex.controller == .rule
              && stopped(AheadBelief(nameKey: "scrawnyursera", level: 4)) != nil && stopped(AheadBelief(nameKey: "alakethbrute", level: 5)) == nil
              && stopped(AheadBelief(nameKey: "scrawnyursera", level: 3, company: 1)) == nil && stopped(AheadBelief(nameKey: "scrawnyursera")) == nil
              && stopped(weak, level: nil) == nil && stopped(nil) == nil,
              "M4ak: a lone creature no higher than the character is fought by RULE; company, a higher or unread level, or no reading, is Jev's")
        check(stopped(weak, combat: true)?.action == .fightBack && stopped(meek, combat: true)?.action == .fightBack,
              "combat outranks the stop rules: attacked at a stop, the fight back comes first")
        // Review of #117: the floors outrank a hostile ahead (one walk() call carries the heading), and a recovery outranks the
        // stop rules: hurt at a stop, the session recovers first and the stop stands for the next tick.
        var hurtWalk = healthy(at: 10, health: 0.2)
        hurtWalk.entities.observe([sighting("Roiling Winds", 95, at: 10)], at: 10)
        let order = ReflexTable.standard.map(\.name)
        func before(_ a: String, _ b: String) -> Bool { order.firstIndex(of: a)! < order.firstIndex(of: b)! }
        check(ReflexTable.first(hurtWalk, ReflexContext(now: 10, ownerTookFocus: false, walkingHeading: 90, walking: true))?.reflex.name == "walk_low_health"
              && stopped(weak, health: 0.45)?.action == .recover && stopped(meek, health: 0.45)?.action == .recover
              && stopped(weak, health: 0.2)?.action == .recover && stopped(weak, health: 0.6)?.action != .recover
              && before("combat", "walk_low_health") && before("walk_low_health", "hostile_ahead") && before("fight_stop_hurt", "hostile_ahead")
              && before("hostile_ahead", "hurt_out_of_combat") && before("hurt_out_of_combat", "walk_past") && before("walk_past", "blocker_fight"),
              "review of #117: the floors before a hostile ahead; a recovery before the stop rules; the fight before them all")
        check(ReflexTable.first(healthy(at: 10, health: 0.5), ctx)?.action == .recover, "hurt out of combat: recover before walking")
        var unbuffed = healthy(at: 10)
        unbuffed.update(\.character.weaponBuffActive, .known(Reading(value: false, confidence: 1, capturedAt: 10, source: "pixels:hud")))
        check(ReflexTable.first(unbuffed, ReflexContext(now: 10, ownerTookFocus: false, aboutToFight: true))?.action == .buffWeapon, "buff before a fight")
        check(ReflexTable.first(unbuffed, ctx) == nil, "no fight coming: no buff reflex")
        let combatFirst = ReflexTable.first(healthy(at: 10, combat: true, health: 0.5), ReflexContext(now: 10, ownerTookFocus: false, aboutToFight: true))
        check(combatFirst?.action == .fightBack && combatFirst?.reflex.controller == .safety, "combat outranks recovery and buffing")
        func fightBack(health: Double, mana: Double = 1, casting: Bool = false) -> ReflexAction? {
            var w = healthy(at: 10, combat: true, health: health, mana: mana)
            w.update(\.character.weaponBuffActive, .known(Reading(value: false, confidence: 1, capturedAt: 10, source: "pixels:hud")))
            w.update(\.character.casting, .known(Reading(value: casting, confidence: 1, capturedAt: 10, source: "pixels:hud")))
            return ReflexTable.first(w, ReflexContext(now: 10, ownerTookFocus: false, aboutToFight: true))?.action
        }
        check(fightBack(health: 0.8) == .buffWeapon && fightBack(health: 0.5) == .fightBack && fightBack(health: 0.2) == .heal
              && fightBack(health: 0.2, mana: 0.05) == .fightBack && fightBack(health: 0.8, casting: true) == .fightBack,
              "review of #79: a fight back with the enchant down casts it first only at 60 % health or more, never in a cast, never below the heal floor")
        let inFight = ReflexContext(now: 10, ownerTookFocus: false, inFight: true)
        check(ReflexTable.first(healthy(at: 10, health: 0.2), inFight)?.action == .stopFight("below the floor out of combat: the fight ends")
              && ReflexTable.first(healthy(at: 10, health: 0.2), inFight)?.reflex.controller == .safety
              && ReflexTable.first(healthy(at: 10, health: 0.2), ctx)?.action == .recover
              && ReflexTable.first(healthy(at: 10, health: 0.5), inFight)?.action == .recover
              && ReflexTable.first(healthy(at: 10, combat: true, health: 0.2), inFight)?.action == .heal,
              "M3's stop: in a fight, below 30 % out of combat ends the fight (SAFETY); outside a fight it is a recovery; in combat it is a heal")
        check(failureKind(forCode: "WALK_HUD_UNREADABLE") == .perception && failureKind(forCode: "NEXT_ZONE_NEEDS_ROADS") == .knowledge
              && failureKind(forCode: "WALK_DANGER_AHEAD") == .safety && failureKind(forCode: "WALK_NO_PROGRESS") == .budget
              && failureKind(forCode: "DIALOGUE_NOT_OPEN") == .execution && failureKind(forCode: "WALK_COMBAT") == .environment
              && failureKind(forCode: "OWNER_TOOK_FOCUS") == .safety, "the old outcome codes map onto the taxonomy")
    }

    // MARK: The loop

    static func loop() {
        let budget = EnvelopeBudget(seconds: 1800, deaths: 2, judgeCalls: 500, consecutiveFailures: 6)
        var loop = PlayLoop(budget: budget, began: 0)
        let calm = ReflexContext(now: 10, ownerTookFocus: false)
        check(loop.next(world: healthy(at: 10), context: calm) == .plan, "idle and calm: plan")
        loop.begin(task: "HAND_IN Agitators", mode: .questing, at: 10)
        check(loop.mode == .questing && loop.next(world: healthy(at: 11), context: ReflexContext(now: 11, ownerTookFocus: false)) == .continueTask,
              "a running task is ticked")
        let stale = loop.next(world: healthy(at: 5), context: ReflexContext(now: 12, ownerTookFocus: false))
        check(stale == .reflex(.holdAndReobserve("no frame newer than 1.0 s"), .safety, "stale_vision") && loop.mode == .questing,
              "an unread frame holds; it does not end the session or the task")
        loop.end(task: "HAND_IN Agitators", controller: .rule, outcome: .failed(TaskFailure(kind: .execution, code: "DIALOGUE_NOT_OPEN", detail: "")), at: 20)
        check(loop.mode == .idleSafe && loop.usage.consecutiveFailures == 1 && loop.failures.count == 1
              && loop.next(world: healthy(at: 21), context: ReflexContext(now: 21, ownerTookFocus: false)) == .plan,
              "a failed task is recorded and the loop plans again")
        for i in 0..<5 {
            loop.begin(task: "HUNT x", mode: .questing, at: Double(30 + i))
            loop.end(task: "HUNT x", controller: .rule, outcome: .failed(TaskFailure(kind: .plan, code: "HUNT_NO_TARGET_FOUND", detail: "")), at: Double(31 + i))
        }
        check(loop.next(world: healthy(at: 40), context: ReflexContext(now: 40, ownerTookFocus: false)) == .stop("NO_PROGRESS_LIMIT"),
              "six failures in a row spend the envelope")
        var fresh = PlayLoop(budget: budget, began: 0)
        fresh.begin(task: "HUNT y", mode: .questing, at: 1)
        fresh.end(task: "HUNT y", controller: .rule, outcome: .failed(TaskFailure(kind: .plan, code: "x", detail: "")), at: 2)
        fresh.begin(task: "fight back", mode: .questing, at: 2.5)
        fresh.end(task: "fight back", controller: .safety, outcome: .succeeded("KILLED_AND_LOOTED"), at: 2.9)
        check(fresh.usage.consecutiveFailures == 1, "a safety reflex's success is not progress on the goal")
        fresh.begin(task: "HAND_IN z", mode: .questing, at: 3)
        fresh.end(task: "HAND_IN z", controller: .jev, outcome: .succeeded("COMPLETED"), at: 4)
        check(fresh.usage.consecutiveFailures == 0, "a planned step's success resets the run of failures")
        var dead = healthy(at: 50)
        dead.update(\.character.dead, .known(Reading(value: true, confidence: 1, capturedAt: 50, source: "ocr:release")))
        check(fresh.next(world: dead, context: ReflexContext(now: 50, ownerTookFocus: false)) == .reflex(.releaseSpirit, .safety, "dead") && fresh.mode == .dead,
              "death is a mode, not an end")
        fresh.countDeath()
        check(fresh.next(world: healthy(at: 60, health: 0.4), context: ReflexContext(now: 60, ownerTookFocus: false)) == .reflex(.recover, .rule, "hurt_out_of_combat")
              && fresh.mode == .recovering, "alive again and hurt: recovering")
        check(fresh.next(world: healthy(at: 70), context: ReflexContext(now: 70, ownerTookFocus: false)) == .plan && fresh.mode == .idleSafe,
              "recovered: idle-safe, then plan")
        check(fresh.next(world: healthy(at: 80), context: ReflexContext(now: 80, ownerTookFocus: true)) == .reflex(.pause("owner has the game"), .owner, "owner_takeover")
              && fresh.mode == .paused, "the owner pauses the loop")
        check(fresh.next(world: healthy(at: 90), context: ReflexContext(now: 90, ownerTookFocus: false)) == .plan && fresh.mode == .idleSafe,
              "and the loop resumes when the owner lets go")
        check(fresh.next(world: healthy(at: 1801), context: ReflexContext(now: 1801, ownerTookFocus: false)) == .stop("TIME_LIMIT"), "the envelope's time ends it")
        var deaths = PlayLoop(budget: budget, began: 0)
        deaths.countDeath(); deaths.countDeath()
        check(deaths.next(world: healthy(at: 1), context: ReflexContext(now: 1, ownerTookFocus: false)) == .stop("DEATH_LIMIT"), "the death limit ends it")
    }

    // MARK: Planner

    static func planner() {
        let here = WorldPoint(x: 43.2, y: 24.0)
        let ready = QuestBelief(title: "Agitators", level: 3, objectives: [ObjectiveBelief(text: "Ready for turn-in", done: nil, need: nil, kind: .handIn)],
                                readyToHandIn: true, pin: WorldPoint(x: 47.3, y: 21.9), ender: "Yala Windwatcher", inThisZone: true)
        let hunt = QuestBelief(title: "Foul Matriarch", level: 4, objectives: [ObjectiveBelief(text: "Foul Matriarch slain", done: 0, need: 1, kind: .kill)],
                               readyToHandIn: false, pin: WorldPoint(x: 39.6, y: 23.9), ender: nil, inThisZone: true)
        let windstones = QuestBelief(title: "Harvesting Windstones", level: 3, objectives: [ObjectiveBelief(text: "Windstone Cluster", done: 0, need: 15, kind: .collect)],
                                     readyToHandIn: false, pin: WorldPoint(x: 45.8, y: 27.1), ender: nil, inThisZone: true)
        let far = QuestBelief(title: "The Next Step", level: 5, objectives: [ObjectiveBelief(text: "Speak with Shen'dar", done: nil, need: nil, kind: .talk)],
                              readyToHandIn: false, pin: WorldPoint(x: 43.4, y: 44.8), ender: nil, inThisZone: false)
        let tooHigh = QuestBelief(title: "Queen", level: 9, objectives: [ObjectiveBelief(text: "Queen slain", done: 0, need: 1, kind: .kill)],
                                  readyToHandIn: false, pin: WorldPoint(x: 44, y: 25), ender: nil, inThisZone: true)
        var inputs = PlannerInputs(quests: [hunt, windstones, ready, far, tooHigh],
                                   givers: [GiverBelief(name: "Ailee Farheart", pin: WorldPoint(x: 43.5, y: 24.2), questInLog: false),
                                            GiverBelief(name: "Rorian", pin: WorldPoint(x: 43.0, y: 24.0), questInLog: true)],
                                   services: [TownServiceBelief(name: "Uualia Suncrest", role: "vendor", at: WorldPoint(x: 43.1, y: 24.2)),
                                              TownServiceBelief(name: "Windshaper Boro", role: "trainer", at: WorldPoint(x: 43.2, y: 22.4))],
                                   player: here, level: 4, bagItems: 3, lastTrainedLevel: 3, pastFailures: [:], dangerStops: [], roadsReach: ["The Next Step"],
                                   usableItems: [:])
        var ranked = GoalPlanner.rank(inputs)
        check(ranked.first?.kind == .handIn && ranked.first?.subject == "Agitators", "a ready hand-in within one walk comes first")
        check(ranked.contains { $0.kind == .accept && $0.subject == "Ailee Farheart" } && !ranked.contains { $0.subject == "Rorian" },
              "a giver is offered; an icon whose tooltip names a logged quest is not")
        check(ranked.contains { $0.kind == .train }, "a level above the last trained level offers the trainer")
        check(!ranked.contains { $0.kind == .sell }, "three bag items do not send the character to a vendor")
        let farCandidate = ranked.first { $0.subject == "The Next Step" }!
        check(farCandidate.utility < ranked.first { $0.subject == "Foul Matriarch" }!.utility && farCandidate.reasons.contains { $0.hasPrefix("other zone") }
              && farCandidate.reasons.contains { $0.hasPrefix("by road") }, "another zone waits, and a road is the way there")
        let queen = ranked.first { $0.subject == "Queen" }!
        check(queen.reasons.contains { $0.hasPrefix("quest level 9") } && queen.utility < ranked.first { $0.subject == "Foul Matriarch" }!.utility,
              "a quest far above the character's level waits")
        inputs.pastFailures["HUNT Harvesting Windstones"] = 2
        inputs.bagItems = 9
        ranked = GoalPlanner.rank(inputs)
        let windstonesCandidate = ranked.first { $0.subject == "Harvesting Windstones" }!
        check(windstonesCandidate.reasons.contains { $0.hasPrefix("failed 2 time") } && windstonesCandidate.utility < ranked.first { $0.subject == "Foul Matriarch" }!.utility,
              "two earlier failures push a step down (M4y as a term, not a sentence to Jev)")
        check(ranked.contains { $0.kind == .sell && $0.reasons.contains("9 bag items") }, "nine bag items offer the vendor")
        inputs.dangerStops = [WorldPoint(x: 40.4, y: 23.5)]
        ranked = GoalPlanner.rank(inputs)
        check(ranked.first { $0.subject == "Foul Matriarch" }!.reasons.contains { $0.hasPrefix("a walk there stopped") }, "a recorded danger stop near the pin counts")
        inputs.roadsReach = []
        ranked = GoalPlanner.rank(inputs)
        check(ranked.first { $0.subject == "The Next Step" }!.utility < -500, "beyond one walk with no road is not a goal")
        let tie = GoalPlanner.tieBreak([GoalCandidate(kind: .hunt, subject: "a", distance: nil, utility: 50, reasons: []),
                                        GoalCandidate(kind: .hunt, subject: "b", distance: nil, utility: 45, reasons: []),
                                        GoalCandidate(kind: .hunt, subject: "c", distance: nil, utility: 20, reasons: [])])
        check(tie.map(\.subject) == ["a", "b"], "only candidates within the margin go to the judge")
        check(GoalPlanner.tieBreak([GoalCandidate(kind: .hunt, subject: "a", distance: nil, utility: 50, reasons: [])]).count == 1
              && QuestionLibrary.tieBreak(GoalPlanner.tieBreak([GoalCandidate(kind: .hunt, subject: "a", distance: nil, utility: 50, reasons: [])])) == nil,
              "one candidate is no question")
        check(GoalPlanner.tieBreak([]).isEmpty, "no candidates, no tie")
    }

    // MARK: Judge

    static func judge() async {
        let request = JudgeRequest(state: ["tooltip_line": "Windshaper Boro", "health_percent": "45"], questions: [
            QuestionLibrary.namesThing("tooltip_line", kind: "NPC", name: "Windshaper Boro"),
            QuestionLibrary.healNow(),
            QuestionLibrary.pullDanger(),
            QuestionLibrary.objectiveKind("objective_text"),
        ])
        check((try? request.check()) != nil, "a well-formed request checks")
        let payload = request.payloadQuestions
        check(payload["tooltip_line"]?["type"] as? String == "noul" && payload["tooltip_line"]?["criteria"] == nil, "a noul has no criteria")
        check((payload["pull_danger"]?["criteria"] as? [String])?.count == 4, "a score's criteria are its ordered levels")
        check((payload["objective_text"]?["criteria"] as? [String: String])?["useAt"] != nil, "a choice's criteria are its described options")
        check(payload.count == 4, "four independent questions in one request")
        check((try? JudgeRequest(state: [:], questions: []).check()) == nil, "an empty request is refused")
        check((try? JudgeQuestion.choice(id: "x", instructions: "y", options: ["only": "one"]).check()) == nil, "a choice needs two options")
        check((try? JudgeQuestion.score(id: "x", instructions: "y", levels: ["a", "a"]).check()) == nil, "a score needs distinct levels")
        check((try? JudgeRequest(state: [:], questions: [QuestionLibrary.healNow(), QuestionLibrary.healNow()]).check()) == nil, "duplicate ids are refused")
        let same = JudgeRequest(state: ["health_percent": "45", "tooltip_line": "Windshaper Boro"], questions: Array(request.questions.reversed()))
        check(same.cacheKey == request.cacheKey, "the cache key ignores field and question order")
        check(JudgeRequest(state: ["tooltip_line": "Windshaper Bor"], questions: request.questions).cacheKey != request.cacheKey, "a changed state is a new key")

        let good: [String: Any] = [
            "tooltip_line": ["noul": 0.93],
            "heal_now": ["noul": 0.2],
            "pull_danger": ["score": 1.4, "legend": ["0": "Safe", "1": "Fair", "2": "Risky", "3": "Reckless"], "probabilities": [0.1, 0.5, 0.3, 0.1], "confidence": 0.6],
            "objective_text": ["choice": "kill", "probabilities": ["kill": 0.9, "collect": 0.04, "useAt": 0.02, "talk": 0.02, "travel": 0.01, "handIn": 0.01], "confidence": 0.88],
        ]
        var calls = 0
        let client = FakeJudgeClient(answers: good, calls: { calls += 1 })
        let judge = Judge(client: client, cacheSeconds: 2)
        var now = 100.0
        let answers = try? await judge.ask(request, now: { now })
        check(answers?["tooltip_line"]?.noul == 0.93 && answers?["heal_now"]?.noul == 0.2, "nouls parse")
        check(answers?["pull_danger"]?.score == 1.4, "a score between levels parses")
        check(answers?["objective_text"]?.choice == "kill", "a choice parses")
        check(judge.calls == 1 && judge.receipts.first?.promptTokens == 120, "one call, with its usage receipt")
        now = 101
        _ = try? await judge.ask(request, now: { now })
        check(calls == 1 && judge.receipts.count == 2 && judge.receipts.last?.cached == true, "the same request within the cache time makes no call")
        now = 105
        _ = try? await judge.ask(request, now: { now })
        check(calls == 2, "after the cache time it asks again")

        func fails(_ answers: [String: Any], _ what: String) async {
            let j = Judge(client: FakeJudgeClient(answers: answers), cacheSeconds: 0)
            let result = try? await j.ask(request, now: { 0 })
            check(result == nil, what)
        }
        var bad = good
        bad["objective_text"] = ["choice": "fly", "probabilities": ["kill": 1.0], "confidence": 0.9]
        await fails(bad, "a choice not offered is refused")
        bad = good
        bad["objective_text"] = ["choice": "kill", "probabilities": ["kill": 0.9, "collect": 0.04, "useAt": 0.02, "talk": 0.02, "travel": 0.01, "handIn": 0.5], "confidence": 0.88]
        await fails(bad, "probabilities that do not sum to one are refused")
        bad = good
        bad["tooltip_line"] = ["noul": 1.5]
        await fails(bad, "a noul outside 0...1 is refused")
        bad = good
        bad.removeValue(forKey: "heal_now")
        await fails(bad, "a missing answer is refused")
        bad = good
        bad["pull_danger"] = ["score": 7, "probabilities": [], "confidence": 0.5]
        await fails(bad, "a score beyond the levels is refused")
        let wrongModel = Judge(client: FakeJudgeClient(answers: good, model: "other"), cacheSeconds: 0)
        let wrong = try? await wrongModel.ask(request, now: { 0 })
        check(wrong == nil, "another model's answer is refused")
        check(QuestionLibrary.tieBreak([GoalCandidate(kind: .hunt, subject: "a", distance: 2.5, utility: 50, reasons: ["hunt base 60", "distance -3"]),
                                        GoalCandidate(kind: .handIn, subject: "b", distance: nil, utility: 48, reasons: [])])
              .map { if case let .choice(_, _, options) = $0 { return options.count == 2 && options["hunt:a"]?.contains("2.5 units") == true }; return false } == true,
              "the tie-break offers each candidate with its distance and reasons")
    }

    // MARK: Report

    static func report() {
        let lines = """
        {"t": 0.0, "event": "start", "run_id": "r1"}
        {"t": 1.0, "event": "quest_step", "controller": "JEV", "skill": "HAND_IN_1", "step": "HAND_IN Agitators"}
        {"t": 1.2, "event": "graph_call", "node": "quest", "latency_s": 0.5, "response": {"usage": {"prompt_tokens": 900, "completion_tokens": 3}}}
        {"t": 1.9, "event": "graph_call", "node": "quest", "latency_s": 0.7}
        {"t": 5.0, "event": "proposal_rejected", "reason": "target_cue_changed", "request": 3}
        {"t": 6.0, "event": "recover", "controller": "RULE", "casts": 2}
        {"t": 7.0, "event": "frame_wait", "seconds": 1.4}
        {"t": 8.0, "event": "death"}
        {"t": 9.0, "event": "task_failed", "task": "WALK", "kind": "execution", "code": "WALK_NO_PROGRESS", "detail": "boulder", "frame": "walk2/f122.jpg"}
        not json at all
        {"t": 60.0, "event": "quests_done", "outcome": "TIME_LIMIT", "steps": [{"quest": "HAND_IN Agitators", "outcome": "COMPLETED"}, {"quest": "ACCEPT Ailee", "outcome": "ACCEPTED"}, {"quest": "HUNT Windstones", "outcome": "HUNT_NO_TARGET_FOUND"}]}
        """
        let parsed = RunReportBuilder.parseEvents(lines)
        check(parsed.events.count == 10 && parsed.skipped == 1, "events parse and a bad line is counted, not guessed")
        let r = RunReportBuilder.build(runID: "r1", events: parsed.events)
        check(r.seconds == 60 && r.decisionsByController["JEV"] == 1 && r.decisionsByController["RULE"] == 1, "decisions by controller")
        check(r.judgeCalls == 2 && r.promptTokens == 900 && r.usageMissing == 1 && r.percentile(0.5) == 0.5 && r.percentile(0.95) == 0.7, "judge calls, tokens, latency")
        check(r.unreadFrames == 1 && r.deaths == 1 && r.outcome == "TIME_LIMIT", "unread frames, deaths, outcome")
        check(r.questsCompleted == 1 && r.questsAccepted == 1, "quest outcomes from the run's steps")
        check(r.failures.count == 3 && r.failuresByKind["perception"] == 1 && r.failuresByKind["execution"] == 1 && r.failuresByKind["knowledge"] == 1,
              "failures by kind: the rejected proposal, the stuck walk, the hunt for objects")
        check(r.failures.first { $0.code == "WALK_NO_PROGRESS" }?.frame == "walk2/f122.jpg" && r.failures.allSatisfy { $0.hypothesis == nil },
              "a failure keeps its frame and leaves the hypothesis to the analyst")
        let json = r.json
        check((json["quests_per_hour"] as? Double) == 60 && (json["unread_frame_rate"] is NSNull), "rates only where the denominator exists")
        check(RunReportBuilder.build(runID: "empty", events: []).json["judge_latency_p50"] is NSNull, "no latency without calls")
    }
}
