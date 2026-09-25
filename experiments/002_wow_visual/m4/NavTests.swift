// Offline M4 checks with synthetic minimap arrows, a simulated zone map and scripted Jev
// replies. They prove the readers, geometry, admissibility, reply validation, the walk skill and
// the episode's stops: SIMULATION ONLY. Nothing here shows that WoW turns and runs as SimNav does,
// that the calibration matches a live frame, or that Jev would choose these moves.
import Foundation

@main
struct NavTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        checks += 1
    }
    static func fails(_ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch { return true }
    }

    static func main() async {
        print("M4a walk checks: synthetic minimap arrows, simulated zone map, scripted Jev.")
        print("SIMULATION-ONLY proof: not live capture, OS input or a TypeSafe call.")
        arrows()
        coordinates()
        geometry()
        admissibility()
        packets()
        choices()
        arguments()
        await skill()
        await episodes()
        await hunts()
        quests()
        print("nav checks passed: \(checks)")
    }

    static func blank() -> RGBA {
        RGBA(width: HUD.width, height: HUD.height, pixels: [UInt8](repeating: 0, count: HUD.width * HUD.height * 4))
    }

    static func set(_ pixels: inout [UInt8], _ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
        let i = (y * HUD.width + x) * 4
        pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b; pixels[i + 3] = 255
    }

    /// A minimap arrow as the client draws it: a navy tail dot and a silver head pointing `heading`.
    static func arrow(_ heading: Double, lavender: Bool = false, head: Bool = true, icon: (dx: Int, dy: Int)? = nil,
                      ring: Int? = nil) -> RGBA {
        var pixels = blank().pixels
        let cx = 2423.0, cy = 197.0, h = heading * .pi / 180
        for dy in -1...1 { for dx in -1...1 { set(&pixels, Int(cx) + dx, Int(cy) + dy, 30, 40, 110) } }
        if head {
            for t in stride(from: 2.5, through: 11, by: 0.5) {
                for w in stride(from: -1.0, through: 1, by: 0.5) {
                    let x = cx + t * sin(h) + w * cos(h), y = cy - t * cos(h) + w * sin(h)
                    set(&pixels, Int(x.rounded()), Int(y.rounded()), 210, 210, 210)
                }
            }
        }
        if lavender { for x in NavHUD.arrowX0..<NavHUD.arrowX1 { set(&pixels, x, 184, 150, 130, 220) } }
        if let ring {  // the selected quest's bright ring on row `ring`, with its dark blue halo over the arrow
            for x in NavHUD.arrowX0 - 2..<NavHUD.arrowX1 + 2 {
                for y in ring - 1...ring + 1 { set(&pixels, x, y, 170, 205, 240) }
                for y in [ring - 3, ring - 2, ring + 2, ring + 3] { set(&pixels, x, y, 24, 32, 44) }
            }
        }
        if let icon {  // a quest icon's near-white highlight, as the live frames show beside the arrow
            for dy in 0...2 { for dx in 0...2 { set(&pixels, Int(cx) + icon.dx + dx, Int(cy) + icon.dy + dy, 235, 225, 200) } }
        }
        return RGBA(width: HUD.width, height: HUD.height, pixels: pixels)
    }

    static func arrows() {
        for heading in stride(from: 0.0, to: 360, by: 45) {
            let got = arrowFacing(arrow(heading))
            check(got.map { abs(angleError(heading, $0)) <= 15 } ?? false, "arrow at \(Int(heading))° reads within 15°")
        }
        check(arrowFacing(arrow(90, lavender: true)).map { abs(angleError(90, $0)) <= 15 } ?? false,
              "a lavender quest outline crossing the box is not taken for the navy tail")
        check(arrowFacing(arrow(0, ring: 184)).map { abs(angleError(0, $0)) <= 15 } ?? false,
              "the selected quest's ring and halo across the arrow's tip do not turn the reading round")
        check(arrowFacing(arrow(0, icon: (8, 6))).map { abs(angleError(0, $0)) <= 15 } ?? false,
              "a quest icon's highlight beside the arrow is not taken for its tip")
        check(arrowFacing(arrow(0, icon: (1, 2))).map { abs(angleError(0, $0)) <= 15 } ?? false,
              "an icon highlight touching the arrow does not move its axis")
        check(arrowFacing(arrow(90, head: false)) == nil, "a navy dot without a silver head reads nothing")
        check(arrowFacing(blank()) == nil, "a black minimap reads nothing")
        check(arrowFacing(RGBA(width: 100, height: 100, pixels: [UInt8](repeating: 0, count: 40_000))) == nil,
              "a frame smaller than the layout reads nothing")
    }

    static func same(_ a: MapPoint?, _ x: Double, _ y: Double) -> Bool {
        guard let a else { return false }
        return abs(a.x - x) < 1e-9 && abs(a.y - y) < 1e-9
    }

    static func coordinates() {
        check(same(parseCoords("44.8,28.1"), 44.8, 28.1), "coordinates with a comma")
        check(same(parseCoords("44.8, 28.1"), 44.8, 28.1), "coordinates with a comma and a space")
        check(same(parseCoords("44.7.27.9"), 44.7, 27.9), "coordinates whose comma OCR read as a dot")
        check(same(parseCoords("Player: 43.2, 23.8"), 43.2, 23.8), "coordinates inside the world map's player line")
        check(parseCoords("ITEn") == nil && parseCoords("") == nil, "noise reads no coordinates")
        check(parseCoords("144.8,28.1") == nil && parseCoords("44.8,28.15") == nil, "a digit on either side rejects the match")
    }

    static func geometry() {
        check(abs(bearing(from: (50, 50), to: (50, 40))) < 1e-9, "north is 0°")
        check(abs(bearing(from: (50, 50), to: (60, 50)) - 90) < 1e-9, "east is 90°")
        check(abs(bearing(from: (50, 50), to: (50, 60)) - 180) < 1e-9 && abs(bearing(from: (50, 50), to: (40, 50)) - 270) < 1e-9,
              "south is 180° and west 270°")
        check(abs(bearing(from: (50, 50), to: (51, 49)) - atan2(1.5, 1) * 180 / .pi) < 1e-9,
              "one x unit counts 1.5 y units in the bearing")
        check(abs(distance((50, 50), (51, 50)) - 1.5) < 1e-9 && abs(distance((50, 50), (50, 52)) - 2) < 1e-9,
              "distance is in y units")
        check(angleError(10, 350) == 20 && angleError(350, 10) == -20 && angleError(180, 0) == 180,
              "heading error wraps to -180...180")
        check(turnPulse(20) == nil && turnPulse(-20) == nil, "no turn inside the 20° deadband")
        check(turnPulse(90)?.code == FightLimits.turnRight && turnPulse(-90)?.code == FightLimits.turnLeft,
              "a positive error turns right (E), a negative one left (Q)")
        check(turnPulse(90)?.ms == 600 && turnPulse(500)?.ms == 700, "pulse length follows 150°/s, capped at 700 ms")
    }

    static func attempt(_ action: NavAction, at x: Double, _ y: Double, heading: Double, blocked: Bool = false,
                        after: Double = 5) -> NavAttempt {
        let o = NavObs(x: x, y: y, facing: heading)
        return NavAttempt(action: action, from: o, to: o, heading: heading, before: after, after: after, blocked: blocked)
    }

    static func admissibility() {
        let d = NavDestination(label: "stone", x: 40, y: 25)
        let here = NavObs(x: 40, y: 27.8, facing: 0)
        check(navAdmissible(here, destination: d, episode: NavEpisode()) == NavAction.allCases,
              "every move is offered at the start")

        var e = NavEpisode()
        e.record(attempt(.goToward, at: 40, 27.8, heading: 0, blocked: true))
        let near = navAdmissible(here, destination: d, episode: e)
        check(!near.contains(.goToward), "a heading blocked near here is not offered again")
        check(near.contains(.detourLeft45) && near.contains(.detourRight45), "headings 45° off a block are still offered")
        check(navAdmissible(NavObs(x: 40, y: 29, facing: 0), destination: d, episode: e).contains(.goToward),
              "the same heading from more than 0.5 away is offered")

        var stuck = NavEpisode()
        stuck.best = 5
        for _ in 0..<3 { stuck.record(attempt(.detourLeft90, at: 40, 30, heading: 270)) }
        check(!navAdmissible(NavObs(x: 40, y: 30, facing: 0), destination: d, episode: stuck).contains(.detourLeft90),
              "a fourth consecutive repeat without a new best is not offered")
        var moving = NavEpisode()
        moving.best = 5
        for step in 0..<3 { moving.record(attempt(.goToward, at: 40, 30, heading: 0, after: 4.5 - Double(step) * 0.5)) }
        check(navAdmissible(NavObs(x: 40, y: 30, facing: 0), destination: d, episode: moving).contains(.goToward),
              "repeating a move that keeps making progress stays offered")

        var boxed = NavEpisode()
        for heading in [0.0, 45, 90, 180, 270, 315] { boxed.record(attempt(.goToward, at: 40, 27.8, heading: heading, blocked: true)) }
        check(navAdmissible(here, destination: d, episode: boxed).isEmpty, "nothing is offered when every heading is blocked")
    }

    static func keyLike(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["api_key", "authorization", "bearer", "typesafe", "secret", "token"].contains { lower.contains($0) }
    }

    static func packets() {
        let d = NavDestination(label: "stone", x: 40, y: 25)
        var e = NavEpisode()
        e.best = 5
        for i in 0..<8 { e.record(attempt(.detourRight45, at: 40, 30 - Double(i) * 0.1, heading: 45)) }
        let state = navStatePacket(NavObs(x: 40, y: 30, facing: 350), destination: d, episode: e, decisionsLeft: 32)
        let keys = ["goal", "position", "destination", "progress", "recent_moves", "blocked_headings_near_here", "units"]
        check(keys.allSatisfy { state[$0] != nil } && state.count == keys.count, "the state packet has exactly its seven fields")
        check((state["recent_moves"] as? [[String: Any]])?.count == NavLimits.recentMoves, "recent moves are capped at six")
        let destination = state["destination"] as? [String: Any] ?? [:]
        check(destination["turn_needed_deg"] as? Int == 10 && destination["bearing_deg"] as? Int == 0,
              "the destination carries its bearing and the signed turn needed")
        let data = (try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])) ?? Data()
        check(!data.isEmpty && !keyLike(String(decoding: data, as: UTF8.self)), "the state packet is JSON with no key-like field")
        let question = actionQuestion([NavAction.goToward, .backTrack], instructions: navInstructions)
        let criteria = question["criteria"] as? [String: String] ?? [:]
        check(question["type"] as? String == "choice" && Set(criteria.keys) == ["GO_TOWARD", "BACK_TRACK"],
              "the question offers exactly the admissible moves")
        check(NavAction.allCases.allSatisfy { !$0.facts.isEmpty && !$0.facts.lowercased().contains("should") },
              "every move has facts and none gives advice")
    }

    static func reply(model: String = FightLimits.model, choice: String = "GO_TOWARD", confidence: Any = 0.9,
                      probabilities: [String: Any] = ["GO_TOWARD": 0.7, "BACK_TRACK": 0.3]) -> [String: Any] {
        let action: [String: Any] = ["choice": choice, "confidence": confidence, "probabilities": probabilities]
        return ["model": model, "answers": ["action": action]]
    }

    static func choices() {
        let allowed: [NavAction] = [.goToward, .backTrack]
        check(parseChoice(reply(), admissible: allowed, model: FightLimits.model)?.action == .goToward,
              "a well-formed reply is accepted")
        check(parseChoice(reply(model: "other"), admissible: allowed, model: FightLimits.model) == nil, "wrong model rejected")
        check(parseChoice(reply(choice: "DETOUR_LEFT_45"), admissible: allowed, model: FightLimits.model) == nil,
              "a move that is not admissible is rejected")
        check(parseChoice(reply(choice: "FLY"), admissible: allowed, model: FightLimits.model) == nil, "an unknown move is rejected")
        check(parseChoice(reply(probabilities: ["GO_TOWARD": 1.0]), admissible: allowed, model: FightLimits.model) == nil,
              "probabilities must cover exactly the admissible moves")
        check(parseChoice(reply(probabilities: ["GO_TOWARD": 1.01, "BACK_TRACK": 0]), admissible: allowed, model: FightLimits.model) == nil,
              "a probability above 1 is rejected")
        check(parseChoice(reply(probabilities: ["GO_TOWARD": 0.5, "BACK_TRACK": 0.4]), admissible: allowed, model: FightLimits.model) == nil,
              "probabilities must sum to 1")
        check(parseChoice(reply(confidence: 1.5), admissible: allowed, model: FightLimits.model) == nil,
              "a confidence outside 0...1 is rejected")
    }

    static func arguments() {
        check((try? parseNav([]))?.mode == .preflight, "no arguments is the preflight")
        check((try? parseNav(["--dry-run"]))?.mode == .dryRun, "dry-run parses")
        check((try? parseNav(["--replay", "runs/frames"]))?.directory == "runs/frames", "replay takes one directory")
        check((try? parseNav(["--sim-jev", "--scenario", "wall"]))?.scenario == "wall", "sim-jev takes a named scenario")
        let live = try? parseNav(["--execute", "--keys", "wqe", "--to", "47.1,21.8", "--arrive", "1", "--label", "Yala Windwatcher"])
        check(live?.toX == 47.1 && live?.toY == 21.8 && live?.arrive == 1 && live?.label == "Yala Windwatcher" && live?.profile == .wqe,
              "execute parses its destination, radius and label")
        check((try? parseNav(["--execute", "--keys", "wqe", "--ghost", "--to", "47.2,20.5"]))?.ghost == true && live?.ghost == false
              && (try? parseNav(["--execute", "--keys", "wqe", "--ghost", "--ghost", "--to", "47.2,20.5"])) == nil
              && (try? parseNav(["--sim-jev", "--ghost"])) == nil,
              "--ghost is a flag of --execute only, once")
        let refused: [[String]] = [
            ["--bogus"], ["--dry-run", "x"], ["--preflight", "x"], ["--replay"], ["--replay", "a", "b"], ["--replay", "-x"],
            ["--sim-jev"], ["--sim-jev", "--scenario", "maze"], ["--execute", "--keys", "wqe"], ["--execute", "--to", "47.1,21.8"],
            ["--execute", "--keys", "arrows", "--to", "47.1,21.8"], ["--execute", "--keys", "wqe", "--to", "47.1"],
            ["--execute", "--keys", "wqe", "--to", "a,b"], ["--execute", "--keys", "wqe", "--to", "101,2"],
            ["--execute", "--keys", "wqe", "--to", "47.1,21.8", "--arrive", "5"],
            ["--execute", "--keys", "wqe", "--to", "47.1,21.8", "--label", "rm $HOME"],
            ["--execute", "--keys", "wqe", "--keys", "wqe", "--to", "47.1,21.8"],
            ["--execute", "--keys", "wqe", "--to", "47.1,21.8", "--scenario", "wall"],
        ]
        for args in refused { check(fails { _ = try parseNav(args) }, "refused before any effect: \(args.joined(separator: " "))") }
    }

    static func skill() async {
        let d = NavDestination(label: "far", x: 40, y: 10)
        let open = SimNav(clock: FightClock(), x: 40, y: 30, facing: 0)
        let run = await walk(open, .goToward, from: open.look()!, to: d)
        check(!run.blocked && !run.arrived && run.moved > 0.3 && open.keys.isDown(FightLimits.forward),
              "a GO_TOWARD that runs its full time leaves W held for the next move")
        await open.sleep(NavLimits.forwardWatchdog + 0.1)
        check(!open.keys.holding && open.pad.pressed.isEmpty, "W left held is released by its watchdog if no move follows")

        let wall = SimNav(clock: FightClock(), x: 40, y: 27.9, facing: 0, boxes: [SimNav.Box(x0: 39, y0: 27.5, x1: 41, y1: 27.8)])
        let hit = await walk(wall, .goToward, from: wall.look()!, to: d)
        check(hit.blocked && hit.moved < NavLimits.blockedMoved && !wall.keys.holding,
              "running into a wall ends the move as blocked with W lifted")
        check(hit.seconds >= NavLimits.blockedWindow && hit.seconds < NavLimits.moveSeconds, "a block is called after the 1.5 s window")

        let patchy = SimNav(clock: FightClock(), x: 40, y: 27.9, facing: 0, boxes: [SimNav.Box(x0: 39, y0: 27.5, x1: 41, y1: 27.8)])
        patchy.missEvery = 2
        let patchyHit = await walk(patchy, .goToward, from: patchy.look()!, to: d)
        check(patchyHit.blocked && !patchy.keys.holding, "every other frame unreadable: the wall is still reported as a block")

        let behind = SimNav(clock: FightClock(), x: 40, y: 27.9, facing: 180, boxes: [SimNav.Box(x0: 39, y0: 27.5, x1: 41, y1: 27.8)])
        let late = await walk(behind, .goToward, from: behind.look()!, to: d)
        check(late.blocked && !behind.keys.holding, "a move that spent most of its time turning still reports its block")

        let turn = SimNav(clock: FightClock(), x: 40, y: 30, facing: 180)
        let turned = await walk(turn, .goToward, from: turn.look()!, to: d)
        check(abs(angleError(0, turn.facing)) <= NavLimits.deadband && turned.moved > 0,
              "a 180° error stops, turns and then runs toward the destination")

        let sticky = SimNav(clock: FightClock(), x: 40, y: 30, facing: 180)
        sticky.pad.failUps = 2 * Limits.releaseAttempts  // the first turn key-up and the W stop fail every attempt
        _ = await walk(sticky, .goToward, from: sticky.look()!, to: d)
        await sticky.sleep(NavLimits.forwardWatchdog + 0.1)
        check(!sticky.keys.holding && sticky.pad.pressed.isEmpty, "a failed turn key-up is retried and lifted, not left held")

        let blind = SimNav(clock: FightClock(), x: 40, y: 30, facing: 180)
        let seen = blind.look()!
        blind.unreadable = true
        _ = await walk(blind, .goToward, from: seen, to: d)
        let turns = blind.keys.codesPosted.filter { $0 != FightLimits.forward }
        check(turns.count == 1 && !blind.keys.holding, "unreadable frames stop the steering after one pulse, not a spin")

        let nest = SimNav(clock: FightClock(), x: 40, y: 30, facing: 0)
        nest.hostiles = [(40, 27)]  // 3 units north, on the way
        let warned = await walk(nest, .goToward, from: nest.look()!, to: d)
        check(warned.warned && warned.moved < 0.2 && !nest.keys.holding, "a red name ahead ends the move at once, with W lifted")
        let passing = SimNav(clock: FightClock(), x: 40, y: 30, facing: 0)
        passing.hostiles = [(41.3, 27)]  // in view, 33° off the way (x counts 1.5 times)
        let passed = await walk(passing, .goToward, from: passing.look()!, to: d)
        check(!passing.look()!.warnings.isEmpty && !passed.warned && passed.moved > 0.3,
              "a red name in view but more than 30° off the way does not stop the walk")
        let wary = SimNav(clock: FightClock(), x: 40, y: 30, facing: 0)
        wary.hostiles = [(40, 27)]
        let stopped = await runNav(body: wary, jev: scripted(), destination: d)
        check(stopped.outcome == "DANGER_AHEAD" && stopped.decisions == 1 && stopped.runtime?.status == .blocked && !wary.keys.holding,
              "runNav ends DANGER_AHEAD after the move a red name stopped: a walk never goes on into it")

        let swept = SimNav(clock: FightClock(), x: 40, y: 30, facing: 0)
        swept.keys.releaseAll()
        let before = swept.keys.codesPosted.count
        _ = await walk(swept, .goToward, from: swept.look()!, to: d)
        check(swept.keys.codesPosted.count == before && !swept.keys.holding && swept.pad.pressed.isEmpty,
              "after releaseAll (the SIGINT sweep) a walk presses nothing")
    }

    static func chosen(_ result: NavResult) -> [NavAction] {
        result.records.compactMap { ($0["attempt"] as? [String: Any])?["action"] as? String }.compactMap(NavAction.init)
    }

    static func longestRun(_ actions: [NavAction]) -> Int {
        var best = 0, run = 0
        for (i, action) in actions.enumerated() {
            run = i > 0 && actions[i - 1] == action ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }

    static func scripted(_ preference: [NavAction] = NavAction.allCases) -> ScriptedJev<NavAction> {
        ScriptedJev(preference: preference)
    }

    static func episodes() async {
        let (open, openGoal) = SimNav.scenario("open", clock: FightClock())!
        let walked = await runNav(body: open, jev: scripted(), destination: openGoal)
        check(walked.outcome == "ARRIVED" && walked.decisions > 1 && !walked.holding, "open ground: ARRIVED with keys released")
        check(Set(chosen(walked)) == [.goToward], "open ground: the scripted preference only runs straight")

        let (fence, fenceGoal) = SimNav.scenario("wall", clock: FightClock())!
        let around = await runNav(body: fence, jev: scripted(), destination: fenceGoal)
        let moves = chosen(around)
        check(around.outcome == "ARRIVED" && !around.holding, "a fence across the line: ARRIVED with keys released")
        check(moves.contains { $0 != .goToward }, "a fence across the line needs at least one detour")
        var reoffered = false
        for (i, record) in around.records.enumerated().dropLast() {
            let a = record["attempt"] as? [String: Any] ?? [:]
            if a["action"] as? String == "GO_TOWARD" && a["blocked"] as? Bool == true {
                let next = around.records[i + 1]["admissible"] as? [String] ?? []
                if next.contains("GO_TOWARD") { reoffered = true }
            }
        }
        check(around.episode.attempts.contains { $0.blocked } && !reoffered,
              "GO_TOWARD is not offered again right after it was blocked from the same spot")

        let (pocket, pocketGoal) = SimNav.scenario("pocket", clock: FightClock())!
        let trapped = await runNav(body: pocket, jev: scripted(), destination: pocketGoal)
        check(["ARRIVED", "NO_PROGRESS", "NO_ADMISSIBLE_MOVE"].contains(trapped.outcome) && trapped.decisions <= NavLimits.maxDecisions
              && !trapped.holding, "a pocket ends within the limits with keys released (\(trapped.outcome))")

        let (west, westGoal) = SimNav.scenario("open", clock: FightClock())!
        let stubborn = await runNav(body: west, jev: scripted([.detourLeft90, .detourRight90]), destination: westGoal)
        check(longestRun(chosen(stubborn)) == NavLimits.repeatCap && stubborn.outcome == "NO_PROGRESS",
              "a Jev that insists on a move making no progress gets it 3 times in a row at most, then NO_PROGRESS")

        let (down, downGoal) = SimNav.scenario("open", clock: FightClock())!
        let failed = await runNav(body: down, jev: NavThrowingJev(), destination: downGoal)
        check(failed.outcome == "JEV_FAILED" && failed.jevCalls == 1 && !failed.holding, "a failed Jev call ends the walk, no fallback")

        let (odd, oddGoal) = SimNav.scenario("open", clock: FightClock())!
        let invalid = await runNav(body: odd, jev: NavReplyJev(choice: "FLY"), destination: oddGoal)
        check(invalid.outcome == "INVALID_REPLY" && invalid.decisions == 1, "an invalid reply ends the walk")

        let (quit, quitGoal) = SimNav.scenario("open", clock: FightClock())!
        let stopped = await runNav(body: quit, jev: NavReplyJev(choice: "STOP"), destination: quitGoal)
        check(stopped.outcome == "INVALID_REPLY" && stopped.episode.attempts.isEmpty, "STOP is not a move Jev can choose")

        let stops: [(String, (SimNav) -> Void)] = [
            ("COMBAT", { $0.combat = true }), ("LOW_HEALTH", { $0.player = 0.2 }),
            ("HUD_UNREADABLE", { $0.unreadable = true }), ("OWNER_TOOK_FOCUS", { $0.ownerFront = true }),
        ]
        for (outcome, setup) in stops {
            let (world, goal) = SimNav.scenario("open", clock: FightClock())!
            setup(world)
            let result = await runNav(body: world, jev: scripted(), destination: goal)
            check(result.outcome == outcome && result.jevCalls == 0 && !result.holding, "\(outcome) stops before any decision")
        }

        let there = SimNav(clock: FightClock(), x: 40, y: 25.2, facing: 0)
        let already = await runNav(body: there, jev: scripted(), destination: NavDestination(label: "here", x: 40, y: 25))
        check(already.outcome == "ARRIVED" && already.decisions == 0, "a walk that starts within the radius has arrived")
    }
}

struct NavThrowingJev: JevClient {
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        throw ProbeError("jev down")
    }
}

struct NavReplyJev: JevClient {
    let choice: String
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        let criteria = question["criteria"] as? [String: Any] ?? [:]
        var probabilities: [String: Any] = [:]
        for key in criteria.keys { probabilities[key] = 1 / Double(max(1, criteria.count)) }
        let action: [String: Any] = ["choice": choice, "confidence": 1.0, "probabilities": probabilities]
        return ["model": FightLimits.model, "answers": ["action": action]]
    }
}
