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
        roads()
        geometry()
        admissibility()
        packets()
        choices()
        arguments()
        await skill()
        await episodes()
        await roadLegs()
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
        // Live run 36: a quest area's blue band, 4 px wide, passing 2 px beyond the tip of an arrow at 131°. The live tail
        // is ringed by the cone's silver outline ("SNNNNS" across it on the run's frames), drawn here round the dot.
        var band = arrow(131).pixels
        for dy in -2...2 { for dx in -2...2 where max(abs(dx), abs(dy)) == 2 { set(&band, 2423 + dx, 197 + dy, 210, 210, 210) } }
        for y in NavHUD.arrowY0 - 2..<NavHUD.arrowY1 + 2 {
            for x in NavHUD.arrowX0 - 2..<NavHUD.arrowX1 + 2 where (2637...2640).contains(x + y) {
                let i = (y * HUD.width + x) * 4
                band[i] = 60; band[i + 1] = 80; band[i + 2] = 160
            }
        }
        check(arrowFacing(RGBA(width: HUD.width, height: HUD.height, pixels: band)).map { abs(angleError(131, $0)) <= 15 } ?? false,
              "a blue quest band beyond the arrow's tip is not its tail: the tail is the compact dot (it read 304° live)")
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
        check(parseCoords("44.9,23") == nil && parseCoords("4.9, 23") == nil && parseCoords("44, 23.5") == nil && parseCoords("44.9.2314") == nil,
              "live runs 28-29: a reading that lost a decimal is no position (\"4.9, 23\" for 44.9, 23.4 put the player 40 units off)")
        check(same(parseCoords("42,2,23.7"), 42.2, 23.7) && same(parseCoords("42,2, 23,7"), 42.2, 23.7) && parseCoords("42,23.7") == nil,
              "live run 31: a decimal point read as a comma keeps its glyph and is a position")
        check(same(parseCoords("42.G,24.3"), 42.6, 24.3) && same(parseCoords("42.G,24.З"), 42.6, 24.3) && parseCoords("42.G,24") == nil,
              "live run 32: a \"6\" read as \"G\" and a \"3\" as a Cyrillic \"З\" are those digits; a lost decimal is still no position")
        var track = PositionTrack()
        let standing = [track.accept((43.3, 24), t: 0), track.accept((48.3, 24), t: 0.4), track.accept((3.3, 24), t: 0.8),
                        track.accept((43.3, 24), t: 1.2), track.accept((43.4, 24.1), t: 3)]
        check(standing == [true, false, false, true, true],
              "live run 33: a reading 5 or 40 units from the last, a fraction of a second later, is no place; a step is")
        var stalled = PositionTrack()
        check(stalled.accept((43.3, 24), t: 0) && !stalled.accept((48.3, 24), t: 20),
              "a 5-unit misread after a 20 s stall (Jev calls) is still no place: the allowance stops growing at 2 s")
        _ = [track.accept((50, 30), t: 4), track.accept((50, 30), t: 4.4)]
        check(track.accept((50.1, 30), t: 4.8) && track.last?.at.x == 50.1,
              "three readings that agree are the place, far as it is from the last (a teleport, or a wrong last reading)")
        // 25 Sept, live: a quest giver's orange name across the box. Raw first; masks only when they agree.
        check(same(agreedCoords(raw: "42.5, 23.7", masked: ["12.5, 23.7", "12.5, 23.7"]), 42.5, 23.7), "a raw reading that parses is kept")
        check(same(agreedCoords(raw: "43.0.23к7 Eнн", masked: ["43.0,23.7", "43.0, 23.7"]), 43.0, 23.7), "masks that agree read through a name")
        check(agreedCoords(raw: "43.0.23v7", masked: ["43.0,23.1", "43.0,23.7"]) == nil, "masks that disagree read nothing")
        check(agreedCoords(raw: "43.0.23v7", masked: ["43.0,23.7", "43.0.2311-"]) == nil, "one mask alone reads nothing")
        check(agreedCoords(raw: "", masked: ["43.0,23.7"]) == nil && agreedCoords(raw: "", masked: []) == nil, "fewer than two masks read nothing")
        let orange: [UInt8] = [236, 140, 30, 255], white: [UInt8] = [240, 238, 236, 255], dark: [UInt8] = [40, 40, 40, 255]
        let masked = whiteText(RGBA(width: 3, height: 1, pixels: orange + white + dark), spread: 60, floor: 60).pixels
        check(masked == [0, 0, 0, 255] + white + [0, 0, 0, 255], "the mask blanks a coloured and a dark pixel, and keeps white")
    }


    /// Roads.swift on made-up trails: breaks, shared places, ways as walked, routes and their bends.
    static func roads() {
        let jumpy: [MapPoint] = [(40, 20), (40, 20.6), (40, 21.2), (47, 30), (40, 21.8), (40, 22.4)]
        check(trailPieces(jumpy, at: { $0 }).map(\.count) == [3, 2],
              "a jump breaks a trail (a flight, a misread: no way is learned across it), and a lone reading is dropped")
        // Maps: Thendal and Shen'dar share a trail, Shen'dar and Windfield another; Dalaran's trail (a video's last hour) is
        // on another map, and a trail named only by an OCR slip ("Hair", read twice) is on no known map.
        func trail(_ names: [(String, Int)]) -> [(MapPoint, String?)] { names.flatMap { n, k in Array(repeating: ((40, 20), n), count: k) } }
        let maps = [trail([("Thendal Village", 25), ("Shen'dar Village", 25)]), trail([("Shen'dar Village", 5), ("Windfield Orchard", 20)]),
                    trail([("Dalaran", 30)]), trail([("Hair", 2)])]
        check(oneMap(maps, subzone: { $0.1 }).map { $0[0].1 } == ["Thendal Village", "Shen'dar Village"],
              "trails joined by the subzones they walk through are one map, the one with most readings; another map's trail and a slip's are left out")
        let north: [MapPoint] = [(40, 20.5), (40, 21.5), (40, 22.5)]
        let shared = buildRoads([("a", north), ("b", north.map { ($0.x + 0.1, $0.y) })])
        check(shared.places.count == 3 && shared.ways == [[0, 1, 2], [1, 2, 2]] && shared.sources == ["a", "b"] && same(shared.point(0), 40.05, 20.5),
              "two players on one road share its places, each the mean of its readings; a way counts both players, and only as walked")
        // An L: south along x = 40, then east along y = 24.2 (0.7 x units is 1.05 y units of ground).
        let south: [MapPoint] = (0...4).map { i -> MapPoint in (40, 20.2 + Double(i)) }
        let east: [MapPoint] = (1...5).map { i -> MapPoint in (40 + 0.7 * Double(i), 24.2) }
        let bend = south + east
        let l = buildRoads([("a", bend)])
        let legs = route(l, from: (40, 19.5), to: (44, 24.2))
        check(legs?.count == 3 && same(legs?[1], 40, 24.2) && same(legs?.last, 44, 24.2),
              "a route keeps the road's corner and ends at the goal: no straight line across the corner")
        check(route(l, from: (44, 24.2), to: (40, 19.5)) == nil, "a road walked one way only gives no route back: a drop may not climb back")
        check(route(l, from: (30, 10), to: (44, 24.2)) == nil && route(l, from: (40, 19.5), to: (60, 60)) == nil,
              "no route when no place is within reach of the player or of the goal")
        check(simplified([(0, 0), (0, 1), (0, 2), (0, 3)]).count == 2 && simplified([(0, 0), (1, 0), (1, 3)]).count == 3,
              "a straight walk is one leg; a bend beyond the tolerance is kept")
        let held = heldOutRoads([bend, [(80, 80), (80, 81)]], roads: l, longer: 3)
        check(held.readings == 12 && held.covered == 10 && held.walks == 1 && held.routed == 1,
              "held out: readings near a learned place, and the long walks the roads route")
        // The committed roads, learned from the videos (sim: no live walk). Thendal Village to The Adventurer's pin near
        // Shen'dar Village goes west round the ridge that a straight walk ran into (M4d), not straight south.
        let learned = try? RoadGraph.load(), way = learned.flatMap { route($0, from: (42.8, 23.5), to: (42.0, 44.4)) }
        check(way.map { $0.contains { $0.x < 40 } && same($0.last, 42.0, 44.4) } == true,
              "the committed roads route Thendal Village to Shen'dar Village round the ridge")
        // Stands: two players come from the east to stand beside an NPC, one from the west; a lone trail makes none.
        let fromEast: [MapPoint] = [(43, 24), (42.8, 23.9), (42.6, 23.8), (42.2, 23.5), (42.1, 23.5), (42.1, 23.5), (42.1, 23.5)]
        let fromWest: [MapPoint] = [(41.2, 23.5), (41.6, 23.5), (42.2, 23.5), (42.2, 23.5), (42.2, 23.5)]
        let learnt = learnStands([fromEast, fromEast, fromWest])
        check(learnt.count == 1 && learnt[0][4] == 3 && abs(learnt[0][2] - 42.8) < 1e-9 && abs(learnt[0][3] - 23.9) < 1e-9 && learnStands([fromEast]).isEmpty,
              "a stand is where trails stood still; its approach is from the side most came from, never an average of two sides")
        let stood = RoadGraph(sources: [], subzones: [], places: [], ways: [], stands: learnt)
        check(same(approach(to: (42.2, 23.2), in: stood), 42.8, 23.9) && approach(to: (45, 23.2), in: stood) == nil && approach(to: (42.2, 23.2), in: nil) == nil,
              "before an NPC is clicked, the walk goes to where players came from to stand beside it; no stand near: the pin")
        // Live run 30: Elatrell Featherlight stands beside Rorian on his platform, approached from Rorian's stand.
        let platform = RoadGraph(sources: [], subzones: [], places: [], ways: [], stands: [[42.1, 23.5, 42.58, 23.55, 8], [41.7, 23.35, 42.1, 23.5, 3]])
        let loop = RoadGraph(sources: [], subzones: [], places: [], ways: [], stands: [[1, 1, 2, 2, 2], [2, 2, 1, 1, 2]])
        check(same(approach(to: (41.6, 23.2), in: platform), 42.58, 23.55) && approach(to: (1, 1), in: loop) != nil,
              "an approach that is another NPC's stand is followed down to the ground players came from; a loop ends")
        // Live run 18: Rorian's bridge. The committed stand beside his pin is approached from the east, as players did.
        check(learned.flatMap { approach(to: (42.2, 23.2), in: $0) }.map { $0.x > 42.4 } == true,
              "the committed roads approach Rorian the Dayseeker from the east, up his ramp, not from under his bridge")
        check(learned.flatMap { approach(to: (41.5, 23.1), in: $0) }.map { $0.x > 42.4 } == true,
              "live run 30: Elatrell Featherlight, beside Rorian on his platform, is approached up the same ramp")
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("roads-\(getpid()).json").path
        try? #"{"sources":[],"subzones":[],"places":[[1,2]],"ways":[[0,5,1]]}"#.write(toFile: broken, atomically: true, encoding: .utf8)
        func loads(_ path: String) -> String { do { return try RoadGraph.load(path) == nil ? "none" : "roads" } catch { return "error" } }
        check(loads("/nonexistent/roads.json") == "none" && loads(broken) == "error",
              "no roads file: no roads; a way to a place the file does not have stops the run before any walk")
        try? FileManager.default.removeItem(atPath: broken)
        // The island comes first, so its places take the low numbers and every kept way must be renumbered.
        let island = pruned(buildRoads([("b", [(6.2, 50.5), (6.2, 51.5)]), ("a", (0..<6).map { i -> MapPoint in (40, 20.5 + Double(i)) })]), minPlaces: 5)
        check(island.places.count == 6 && island.ways == (0..<5).map { [$0, $0 + 1, 1] } && same(island.point(0), 40, 20.5) && same(island.point(5), 40, 25.5),
              "a small part of the roads (a reading that lost a digit: 6.2 for 66.2) is pruned, the rest renumbered")
        check(walkStart(at: nil, to: (40, 20), road: true) == .refused("WALK_HUD_UNREADABLE") && walkStart(at: (40, 20.3), to: (40, 20), road: false) == .there
              && walkStart(at: (40, 20), to: (40, 35), road: false) == .refused("TOO_FAR_NEEDS_ROADS") && walkStart(at: (40, 20), to: (40, 35), road: true) == .walk,
              "a walk beyond one walk is refused unless it is a road's leg; no position is never there")
        check(huntStartsNear("WALK_DANGER_AHEAD", at: (44.6, 26.5), pin: (45.8, 27.1)) && !huntStartsNear("WALK_DANGER_AHEAD", at: (42, 24), pin: (45.8, 27.1))
              && !huntStartsNear("WALK_COMBAT", at: (45.7, 27.1), pin: (45.8, 27.1)) && !huntStartsNear("WALK_DANGER_AHEAD", at: nil, pin: (45.8, 27.1)),
              "live run 35: a hunt walk stopped by a red name near its pin starts the hunt; far away, unseen, or another stop ends the step")
        // Runs 35 and 44: a Juvenile Vuldren's body under its own yellow plate read as a red name; the 24 Sept nest's red name,
        // level with a neutral plate beside it, is a real one.
        let body35 = RedName(x0: 1128, x1: 1152, y0: 631, y1: 639), nest = RedName(x0: 888, x1: 920, y0: 399, y1: 415)
        let plates35 = [PlateBar(hostile: false, x0: 1162, x1: 1352, y0: 547, y1: 563), PlateBar(hostile: false, x0: 516, x1: 709, y0: 609, y1: 625)]
        let plates24 = [PlateBar(hostile: false, x0: 958, x1: 1155, y0: 396, y1: 411)]
        check(dangerNames([body35], plates: plates35).isEmpty && dangerNames([nest], plates: plates24) == [nest]
              && dangerNames([body35], plates: [PlateBar(hostile: true, x0: 1162, x1: 1352, y0: 547, y1: 563)]) == [body35],
              "a red name under a neutral plate is its creature's body; one level with it, or under a hostile plate, stays a danger")
        check(walkStart(at: (42.5, 23.1), to: (42.58, 23.55), road: false) == .there
              && walkStart(at: (42.5, 23.1), to: (42.58, 23.55), road: false, arrive: RoadLimits.approachArrive) == .walk,
              "live run 19: 0.45 from Rorian's approach counts as there at a walk's 0.5, not at the approach's 0.15")
    }

    /// walkLegs with a scripted clock and walk: legs in turn, the first stop ends the road, no leg after the deadline.
    static func roadLegs() async {
        let legs: [MapPoint] = [(40, 25), (40, 30), (42, 44)]
        var clock = 0.0, walked: [Int] = []
        func run(_ stops: [Int: String], deadline: Double, legTakes: Double = 60) async -> String {
            clock = 0; walked = []
            return await walkLegs(legs, until: deadline, now: { clock }) { i, _ in walked.append(i); clock += legTakes; return stops[i] }
        }
        let arrived = await run([:], deadline: 1500)
        check(arrived == "BY_ROAD" && walked == [0, 1, 2], "every leg arrives: the road is walked")
        let stopped = await run([1: "WALK_DANGER_AHEAD"], deadline: 1500)
        check(stopped == "WALK_DANGER_AHEAD" && walked == [0, 1],
              "a red name ahead on a leg ends the road there, with the walk's own outcome")
        let late = await run([:], deadline: 100)
        check(late == "ROAD_TIME_LIMIT" && walked == [0, 1],
              "no leg starts at or after the run's deadline")
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
        check((try? parseNav(["--pixels", "runs/002"]))?.mode == .pixels && (try? parseNav(["--pixels", "runs/002"]))?.directory == "runs/002",
              "pixels takes one directory")
        check((try? parseNav(["--sim-jev", "--scenario", "wall"]))?.scenario == "wall", "sim-jev takes a named scenario")
        let live = try? parseNav(["--execute", "--keys", "wqe", "--to", "47.1,21.8", "--arrive", "1", "--label", "Yala Windwatcher"])
        check(live?.toX == 47.1 && live?.toY == 21.8 && live?.arrive == 1 && live?.label == "Yala Windwatcher" && live?.profile == .wqe,
              "execute parses its destination, radius and label")
        check((try? parseNav(["--execute", "--keys", "wqe", "--ghost", "--to", "47.2,20.5"]))?.ghost == true && live?.ghost == false
              && (try? parseNav(["--execute", "--keys", "wqe", "--ghost", "--ghost", "--to", "47.2,20.5"])) == nil
              && (try? parseNav(["--sim-jev", "--ghost"])) == nil,
              "--ghost is a flag of --execute only, once")
        let fighting = try? parseNav(["--quests", "--graph", "q.json", "--keys", "wqe", "--fight-graph", "f.json"])
        check(fighting?.fightGraph == "f.json" && fighting?.graph == "q.json"
              && (try? parseNav(["--hunt", "--keys", "wqe", "--fight-graph", "f.json"]))?.fightGraph == "f.json",
              "a live quest run or hunt takes M3b's fight graph beside its own")
        check((try? parseNav(["--quests", "--graph", "q.json", "--keys", "wqe", "--hunt-graph", "h.json"]))?.huntGraph == "h.json"
              && (try? parseNav(["--hunt", "--keys", "wqe", "--hunt-graph", "h.json"])) == nil
              && (try? parseNav(["--zoom", "--keys", "wqe"]))?.zoomIn == FightLimits.zoomInSeconds
              && (try? parseNav(["--zoom", "--keys", "wqe", "--seconds", "0.8"]))?.zoomIn == 0.8
              && (try? parseNav(["--zoom", "--keys", "wqe", "--seconds", "3"])) == nil && (try? parseNav(["--zoom"])) == nil,
              "a quest run takes M4b's hunt graph for its hunts (a hunt names its own with --graph); --zoom needs the keys, and 0-2 s of F11")
        let refused: [[String]] = [
            ["--hunt-dry-run", "--fight-graph", "f.json"], ["--execute", "--keys", "wqe", "--to", "47.1,21.8", "--fight-graph", "f.json"],
            ["--quests", "--graph", "q.json", "--keys", "wqe", "--fight-graph"],
            ["--bogus"], ["--dry-run", "x"], ["--preflight", "x"], ["--replay"], ["--replay", "a", "b"], ["--replay", "-x"], ["--pixels"], ["--pixels", "a", "b"], ["--pixels", "-x"],
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

        // 25 Sept, live: arrival seen mid-move, then a quest giver's name covered the coordinates.
        let (covered, coveredGoal) = SimNav.scenario("open", clock: FightClock())!
        covered.readsNear = ((coveredGoal.x, coveredGoal.y), coveredGoal.arrive, 1)
        let reached = await runNav(body: covered, jev: scripted(), destination: coveredGoal)
        check(reached.outcome == "ARRIVED" && !reached.holding && reached.end.map { distance($0.point, (coveredGoal.x, coveredGoal.y)) < coveredGoal.arrive } == true,
              "arrival seen during a move ends the walk, though the next looks cannot read")
        let (blind, blindGoal) = SimNav.scenario("open", clock: FightClock())!
        blind.readsNear = ((blindGoal.x, blindGoal.y), blindGoal.arrive, 0)
        let unseen = await runNav(body: blind, jev: scripted(), destination: blindGoal)
        check(unseen.outcome != "ARRIVED" && !unseen.holding
              && unseen.end.map { distance($0.point, (blindGoal.x, blindGoal.y)) >= blindGoal.arrive } ?? true,
              "an arrival never seen is not claimed (\(unseen.outcome))")

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
