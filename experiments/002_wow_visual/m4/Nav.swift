// M4a walk core for issue #5: the character walks to a point on the zone map; Jev chooses
// every move, local code perceives, offers only admissible moves, runs each as a bounded skill
// and stops on safety rules. Pure Foundation with injected time, observations and keys (M3's
// LiveKeys), so the same walk skill runs offline against SimNav and live against the native shell.
// NavProbe.swift supplies capture, coordinates OCR, the pid key sink and the TypeSafe call.
import Foundation

enum NavHUD {
    /// Minimap player arrow: a silver head with a navy dot at its tail.
    static let arrowX0 = 2406, arrowX1 = 2440, arrowY0 = 182, arrowY1 = 212
    /// Zone coordinates under the minimap ("44.8, 28.1"); OCR'd after a x3 upscale.
    static let coordsX = 2322, coordsY = 300, coordsWidth = 200, coordsHeight = 34

    static func silver(_ r: Int, _ g: Int, _ b: Int) -> Bool { min(r, g, b) > 120 && max(r, g, b) - min(r, g, b) < 50 }
    static func navy(_ r: Int, _ g: Int, _ b: Int) -> Bool { b >= r + 10 && b >= g + 8 }
}

enum NavLimits {
    static let maxDecisions = 40
    static let maxSeconds = 180.0
    static let noProgressDecisions = 10
    static let progressStep = 0.3  // a new best distance must beat the old one by this much
    static let arriveDefault = 0.8
    static let arriveRange = 0.3...3.0
    static let maxStartDistance = 40.0
    static let moveSeconds = 3.0  // leaves the 1.5 s block window after the longest 0.7 s turn
    static let tick = 0.25
    static let blockedWindow = 1.5
    static let blockedMoved = 0.1
    static let blockedAtEnd = 1.0  // a move that ends by time with W down this long and no movement was blocked too
    static let stopToTurn = 100.0  // larger errors stop running before the turn
    static let deadband = 20.0
    static let turnRate = 150.0  // degrees per second with Q or E down, measured live
    static let minPulseMs = 60.0
    static let maxPulseMs = 700.0
    static let forwardWatchdog = 1.5
    static let repeatCap = 3
    static let nearRadius = 0.5
    static let headingTolerance = 25.0
    static let unreadableLimit = 6
    static let recentMoves = 6
    static let runSpeed = 0.2  // y units per second: 0.63-0.78 per 3.0-3.3 s move on the second live walk
    static let releaseCodes: [UInt16] = [FightLimits.turnLeft, FightLimits.forward, FightLimits.turnRight, FightLimits.zoomOut, 36, 8]  // M4c: Enter for chat, C for the character pane
}

typealias MapPoint = (x: Double, y: Double)

func compass(dx: Double, dy: Double) -> Double {  // dy grows southwards, as on screen and on the map
    (atan2(dx, -dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}

/// Facing from the minimap arrow as a compass bearing (0 north, 90 east). The arrow is a silver cone
/// with a navy dot at its tail; quest icons often sit beside it and their highlights are silver too.
/// So only silver connected to the navy dot counts, and the facing is the ray from the dot along which
/// that silver runs longest (the cone's axis): an icon adds a short blob, never an 8-10 px run.
/// Within 18° of the author's labels on 16 frames, 11 of them with icons beside the arrow.
func arrowFacing(_ image: RGBA) -> Double? {
    guard image.pixels.count == image.width * image.height * 4,
          image.width >= NavHUD.arrowX1, image.height >= NavHUD.arrowY1 else { return nil }
    let w = image.width
    // The selected quest's bright ring can cross the box: its core and a 2 px margin count as neither
    // silver nor navy (live hunt, 23 Sept: a ring over the arrow's tip turned the reading around).
    var ring = Set<Int>()
    for y in NavHUD.arrowY0 - 2..<NavHUD.arrowY1 + 2 {
        for x in NavHUD.arrowX0 - 2..<NavHUD.arrowX1 + 2 {
            let i = (y * w + x) * 4
            guard MinimapHUD.bright(Int(image.pixels[i]), Int(image.pixels[i + 1]), Int(image.pixels[i + 2])) else { continue }
            for dy in -2...2 { for dx in -2...2 { ring.insert((y + dy) * w + x + dx) } }
        }
    }
    var silver = Set<Int>(), navy: [(Int, Int)] = []
    for y in NavHUD.arrowY0..<NavHUD.arrowY1 {
        for x in NavHUD.arrowX0..<NavHUD.arrowX1 where !ring.contains(y * w + x) {
            let i = (y * w + x) * 4
            let r = Int(image.pixels[i]), g = Int(image.pixels[i + 1]), b = Int(image.pixels[i + 2])
            if NavHUD.silver(r, g, b) {
                silver.insert(y * w + x)
            } else if NavHUD.navy(r, g, b) {
                navy.append((x, y))
            }
        }
    }
    func nearSilver(_ x: Int, _ y: Int) -> Bool {
        for dy in -3...3 {
            for dx in -3...3 where silver.contains((y + dy) * w + x + dx) { return true }
        }
        return false
    }
    navy = navy.filter { nearSilver($0.0, $0.1) }  // the lavender quest-area outline is not beside silver
    guard navy.count >= 3 else { return nil }
    let nx = Double(navy.map(\.0).reduce(0, +)) / Double(navy.count)
    let ny = Double(navy.map(\.1).reduce(0, +)) / Double(navy.count)
    var arrow = Set<Int>(), stack: [Int] = []  // silver 8-connected to the ring around the dot
    for (x, y) in navy {
        for dy in -2...2 {
            for dx in -2...2 where silver.contains((y + dy) * w + x + dx) && arrow.insert((y + dy) * w + x + dx).inserted {
                stack.append((y + dy) * w + x + dx)
            }
        }
    }
    while let k = stack.popLast() {
        for dy in -1...1 {
            for dx in -1...1 where silver.contains(k + dy * w + dx) && arrow.insert(k + dy * w + dx).inserted {
                stack.append(k + dy * w + dx)
            }
        }
    }
    guard arrow.count >= 6 else { return nil }
    var runs: [(heading: Double, length: Int)] = []
    for step in 0..<180 {
        let heading = Double(step) * 2, h = heading * .pi / 180
        var length = 0
        for t in 3...13 {
            let x = Int((nx + Double(t) * sin(h)).rounded()), y = Int((ny - Double(t) * cos(h)).rounded())
            if arrow.contains(y * w + x) { length += 1 } else if t > 4 { break }
        }
        runs.append((heading, length))
    }
    guard let longest = runs.map(\.length).max(), longest >= 3 else { return nil }
    let axis = runs.filter { $0.length == longest }.map { $0.heading * .pi / 180 }  // a flat top: its circular mean
    return compass(dx: axis.map(sin).reduce(0, +), dy: -axis.map(cos).reduce(0, +))
}

/// "44.8,28.1", "44.8, 28.1" or "44.7.27.9" (OCR reads the comma as a dot). A digit on either side
/// rejects the match, so "144.8,28.1" is not read as 44.8.
func parseCoords(_ text: String) -> MapPoint? {
    let pattern = #"(?<!\d)(\d{1,2})\.(\d)\s*[.,]\s*(\d{1,2})\.(\d)(?!\d)"#
    guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
    let n = text[match].split { !$0.isNumber }.compactMap { Int($0) }
    guard n.count == 4 else { return nil }
    return (Double(n[0]) + Double(n[1]) / 10, Double(n[2]) + Double(n[3]) / 10)
}

/// Zone-map coordinates are percent of a 3:2 map, so one x unit is 1.5 y units of ground.
let mapAspect = 1.5

func bearing(from a: MapPoint, to b: MapPoint) -> Double {
    compass(dx: (b.x - a.x) * mapAspect, dy: b.y - a.y)
}

func distance(_ a: MapPoint, _ b: MapPoint) -> Double {  // in y units
    let dx = (b.x - a.x) * mapAspect, dy = b.y - a.y
    return (dx * dx + dy * dy).squareRoot()
}

func angleError(_ want: Double, _ have: Double) -> Double {  // -180...180, positive = turn right
    var e = (want - have).truncatingRemainder(dividingBy: 360)
    if e > 180 { e -= 360 }
    if e < -180 { e += 360 }
    return e
}

/// A turn pulse at the measured turn rate: nil inside the deadband; a positive error turns right (E).
func turnPulse(_ error: Double) -> (code: UInt16, ms: Int)? {
    guard abs(error) > NavLimits.deadband else { return nil }
    let ms = min(NavLimits.maxPulseMs, max(NavLimits.minPulseMs, abs(error) / NavLimits.turnRate * 1000))
    return (error > 0 ? FightLimits.turnRight : FightLimits.turnLeft, Int(ms))
}

struct NavObs: Equatable {
    var x: Double
    var y: Double
    var facing: Double
    var combat = false
    var player = 1.0
    var point: MapPoint { (x, y) }
}

struct NavDestination: Equatable {
    let label: String
    let x: Double
    let y: Double
    var arrive = NavLimits.arriveDefault
    var point: MapPoint { (x, y) }
}

enum NavAction: String, JevAction {
    case goToward = "GO_TOWARD"
    case detourLeft45 = "DETOUR_LEFT_45"
    case detourRight45 = "DETOUR_RIGHT_45"
    case detourLeft90 = "DETOUR_LEFT_90"
    case detourRight90 = "DETOUR_RIGHT_90"
    case backTrack = "BACK_TRACK"
    // No STOP: in rehearsal Jev ended every walk at the first block (p 0.42-0.73 across phrasings),
    // and a walk has no danger that local stops miss. Ending a walk is local (README).

    /// Heading relative to the destination's bearing.
    var offset: Double {
        switch self {
        case .goToward: return 0
        case .detourLeft45: return -45
        case .detourRight45: return 45
        case .detourLeft90: return -90
        case .detourRight90: return 90
        case .backTrack: return 180
        }
    }

    /// What the move does, never advice on when to choose it.
    var facts: String {
        switch self {
        case .goToward:
            return "Run straight at the destination for up to 3 s, steering by the minimap arrow. Ends early on arrival or when the character stops moving (blocked)."
        case .detourLeft45, .detourRight45, .detourLeft90, .detourRight90:
            let side = offset < 0 ? "left" : "right"
            return "Run for up to 3 s on a heading \(Int(abs(offset)))° \(side) of the destination's bearing. Ends early when blocked."
        case .backTrack:
            return "Run for up to 3 s directly away from the destination. Ends early when blocked."
        }
    }
}

let navInstructions = "Which move is most likely to get the character to `destination`, given `position`, `recent_moves` and `blocked_headings_near_here`?"

func roundTo(_ value: Double, _ places: Double = 100) -> Double { (value * places).rounded() / places }

struct NavAttempt {
    let action: NavAction
    let from: NavObs
    var to: NavObs
    var heading: Double  // the heading steered at the end, where a block happened
    var seconds = 0.0
    let before: Double
    var after: Double
    var blocked = false
    var arrived = false
    var moved: Double { distance(from.point, to.point) }

    var json: [String: Any] {
        ["action": action.rawValue, "heading_deg": Int(heading.rounded()), "seconds": roundTo(seconds, 10),
         "moved": roundTo(moved), "distance_before": roundTo(before), "distance_after": roundTo(after),
         "blocked": blocked]
    }
}

struct NavEpisode {
    var attempts: [NavAttempt] = []
    var best = Double.infinity
    var sinceBest = 0

    mutating func record(_ attempt: NavAttempt) {
        attempts.append(attempt)
        if attempt.after <= best - NavLimits.progressStep {
            best = attempt.after
            sinceBest = 0
        } else {
            sinceBest += 1
        }
    }

    /// Headings of blocked moves that ended within nearRadius of here.
    func blockedHeadings(near o: NavObs) -> [Double] {
        attempts.filter { $0.blocked && distance($0.to.point, o.point) <= NavLimits.nearRadius }.map(\.heading)
    }
}

/// Every move, minus one whose heading was blocked near here, minus a move chosen for each of the
/// last repeatCap decisions without a new best distance.
func navAdmissible(_ o: NavObs, destination d: NavDestination, episode e: NavEpisode) -> [NavAction] {
    let aim = bearing(from: o.point, to: d.point)
    let blocked = e.blockedHeadings(near: o)
    let recent = e.attempts.suffix(NavLimits.repeatCap).map(\.action)
    let capped = recent.count == NavLimits.repeatCap && Set(recent).count == 1 && e.sinceBest >= NavLimits.repeatCap
        ? recent.first : nil
    return NavAction.allCases.filter { action in
        if action == capped { return false }
        let heading = aim + action.offset
        return !blocked.contains { abs(angleError(heading, $0)) <= NavLimits.headingTolerance }
    }
}

func navStatePacket(_ o: NavObs, destination d: NavDestination, episode e: NavEpisode, decisionsLeft: Int) -> [String: Any] {
    let aim = bearing(from: o.point, to: d.point)
    let position: [String: Any] = ["x": o.x, "y": o.y, "facing_deg": Int(o.facing.rounded())]
    let destination: [String: Any] = [
        "label": d.label, "x": d.x, "y": d.y, "distance": roundTo(distance(o.point, d.point)),
        "bearing_deg": Int(aim.rounded()), "turn_needed_deg": Int(angleError(aim, o.facing).rounded()),
    ]
    let progress: [String: Any] = [
        "best_distance": e.best.isFinite ? roundTo(e.best) : roundTo(distance(o.point, d.point)),
        "decisions_since_best": e.sinceBest, "decisions_left": decisionsLeft,
    ]
    let state: [String: Any] = [
        "goal": "Reach the destination on the zone map with this character. Moves cannot see obstacles: a move that ends blocked ran into something on that heading (a tree, rock, fence or building), and other headings may be clear.",
        "position": position, "destination": destination, "progress": progress,
        "recent_moves": e.attempts.suffix(NavLimits.recentMoves).map(\.json),
        "blocked_headings_near_here": e.blockedHeadings(near: o).map { Int($0.rounded()) },
        "units": "zone-map units: x and y are map percent, distances are in y units (one x unit is 1.5 y units); running covers about 0.2 per second; headings are compass degrees, 0 north, 90 east",
    ]
    return state
}

/// What a walk needs from the world: SimNav offline, the WoW window live.
protocol NavBody: AnyObject {
    var keys: LiveKeys { get }
    func now() -> Double
    func sleep(_ seconds: Double) async
    func look() -> NavObs?  // nil: coordinates or arrow unreadable
    func ownerTookFocus() -> Bool
    func emit(_ event: String, _ fields: [String: Any])
}

/// One bounded move: steer by Q/E pulses with W held, re-aiming at the destination each tick for
/// GO_TOWARD or holding the move's fixed heading otherwise, until its time is up, arrival, a block
/// (W held for blockedWindow with less than blockedMoved of movement), or an unsafe frame. A move that
/// ran its full time leaves W held under its watchdog grant, so the next move continues without a stop.
func walk(_ body: NavBody, _ action: NavAction, from start: NavObs, to d: NavDestination) async -> NavAttempt {
    let forward = FightLimits.forward
    let fixed = bearing(from: start.point, to: d.point) + action.offset
    var attempt = NavAttempt(action: action, from: start, to: start, heading: fixed, before: distance(start.point, d.point),
                             after: distance(start.point, d.point))
    let began = body.now()
    var here = start
    var trail: [(t: Double, point: MapPoint)] = []  // positions seen while W stayed down
    var misses = 0
    var ranOut = true
    while body.now() - began < NavLimits.moveSeconds {
        if misses == 0 {  // never steer by a stale facing: after a miss, W only lapses under its grant
            let want = action == .goToward ? bearing(from: here.point, to: d.point) : fixed
            attempt.heading = (want + 360).truncatingRemainder(dividingBy: 360)
            let error = angleError(want, here.facing)
            if abs(error) > NavLimits.stopToTurn {
                body.keys.lift(forward)
                trail.removeAll()
            }
            if let pulse = turnPulse(error) {
                if body.keys.isDown(forward) {
                    body.keys.grant(forward, seconds: Double(pulse.ms) / 1000 + NavLimits.forwardWatchdog)
                }
                body.keys.press(pulse.code)
                await body.sleep(Double(pulse.ms) / 1000)
                body.keys.lift(pulse.code)
            }
            if abs(error) <= NavLimits.stopToTurn {
                if !body.keys.isDown(forward) { body.keys.press(forward) }
                body.keys.grant(forward, seconds: NavLimits.forwardWatchdog)
            }
        }
        await body.sleep(NavLimits.tick)
        guard let o = body.look() else {  // the trail survives a miss: W's state is checked at the next reading
            misses += 1
            if misses >= NavLimits.unreadableLimit { ranOut = false; break }
            continue
        }
        misses = 0
        here = o
        if o.combat || o.player < FightLimits.playerSafety || body.ownerTookFocus() { ranOut = false; break }
        if distance(o.point, d.point) < d.arrive { attempt.arrived = true; ranOut = false; break }
        let now = body.now()
        if body.keys.isDown(forward) { trail.append((now, o.point)) } else { trail.removeAll() }
        if let old = trail.last(where: { now - $0.t >= NavLimits.blockedWindow }) {
            if distance(old.point, o.point) < NavLimits.blockedMoved { attempt.blocked = true; ranOut = false; break }
            trail.removeAll { now - $0.t > NavLimits.blockedWindow + 1 }
        }
    }
    if ranOut, let first = trail.first, body.now() - first.t >= NavLimits.blockedAtEnd,
       distance(first.point, here.point) < NavLimits.blockedMoved {
        attempt.blocked = true  // most of the move went on turning, so the window never filled
        ranOut = false
    }
    if !ranOut { body.keys.lift(forward) }
    attempt.to = here
    attempt.after = distance(here.point, d.point)
    attempt.seconds = body.now() - began
    return attempt
}

struct NavResult {
    var outcome = "DECISION_LIMIT"
    var decisions = 0
    var jevCalls = 0
    var latencies: [Double] = []
    var records: [[String: Any]] = []
    var episode = NavEpisode()
    var start: NavObs?
    var end: NavObs?
    var holding = false
    var codesPosted: [UInt16] = []
}

func runNav(body: NavBody, jev: JevClient, destination d: NavDestination) async -> NavResult {
    var result = NavResult()
    let began = body.now()
    var misses = 0

    func finish(_ outcome: String) -> NavResult {
        body.keys.releaseAll()
        result.outcome = outcome
        result.holding = body.keys.holding
        result.codesPosted = body.keys.codesPosted
        var fields: [String: Any] = ["outcome": outcome, "decisions": result.decisions]
        if let end = result.end { fields["x"] = end.x; fields["y"] = end.y }
        body.emit("outcome", fields)
        return result
    }

    while true {
        if body.ownerTookFocus() { return finish("OWNER_TOOK_FOCUS") }
        guard let o = body.look() else {
            misses += 1
            if misses >= NavLimits.unreadableLimit { return finish("HUD_UNREADABLE") }
            await body.sleep(NavLimits.tick)  // a W left held lapses under its watchdog meanwhile
            continue
        }
        misses = 0
        if result.start == nil {
            result.start = o
            result.episode.best = distance(o.point, d.point)
        }
        result.end = o
        if o.combat { return finish("COMBAT") }
        if o.player < FightLimits.playerSafety { return finish("LOW_HEALTH") }
        if distance(o.point, d.point) < d.arrive { return finish("ARRIVED") }
        if result.episode.sinceBest >= NavLimits.noProgressDecisions { return finish("NO_PROGRESS") }
        if result.decisions >= NavLimits.maxDecisions { return finish("DECISION_LIMIT") }
        if body.now() - began >= NavLimits.maxSeconds { return finish("TIME_LIMIT") }
        let allowed = navAdmissible(o, destination: d, episode: result.episode)
        if allowed.isEmpty { return finish("NO_ADMISSIBLE_MOVE") }

        let state = navStatePacket(o, destination: d, episode: result.episode,
                                   decisionsLeft: NavLimits.maxDecisions - result.decisions)
        let question = actionQuestion(allowed, instructions: navInstructions)
        let asked = body.now()
        let reply: [String: Any]
        do {
            reply = try await jev.ask(state: state, question: question)
            result.jevCalls += 1
        } catch {
            result.jevCalls += 1
            body.emit("jev_error", ["error": "\(error)"])
            return finish("JEV_FAILED")
        }
        let latency = body.now() - asked
        result.latencies.append(latency)
        result.decisions += 1
        var record: [String: Any] = [
            "decision": result.decisions, "t": asked, "state": state, "question": question,
            "admissible": allowed.map(\.rawValue), "response": reply, "latency_s": latency,
        ]
        guard let choice = parseChoice(reply, admissible: allowed, model: FightLimits.model) else {
            result.records.append(record)
            body.emit("decision", record)
            return finish("INVALID_REPLY")
        }
        let attempt = await walk(body, choice.action, from: o, to: d)
        result.episode.record(attempt)
        record["attempt"] = attempt.json
        result.records.append(record)
        body.emit("decision", record)
    }
}

/// SimNav's key sink: which keys are down. Locked, because SIGINT releases from another queue.
final class SimPad: KeySink {
    private let lock = NSLock()
    private var down: Set<UInt16> = []
    var failUps = 0  // the next key-ups that throw
    var onDown: ((UInt16) -> Void)?  // SimHunt's Tab and Esc
    func post(_ code: UInt16, down isDown: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        if !isDown && failUps > 0 {
            failUps -= 1
            throw ProbeError("fake key-up failure")
        }
        if isDown && !down.contains(code) { onDown?(code) }
        if isDown { down.insert(code) } else { down.remove(code) }
    }
    var pressed: Set<UInt16> {
        lock.lock()
        defer { lock.unlock() }
        return down
    }
}

/// Deterministic zone-map world for tests and the dry-run: rectangles block movement, W runs at
/// NavLimits.runSpeed, Q/E turn at NavLimits.turnRate. The keys go through LiveKeys on a SimPad,
/// so the live key rules (grant, watchdog, nothing after releaseAll) drive the simulated body.
final class SimNav: NavBody {
    struct Box {
        let x0: Double, y0: Double, x1: Double, y1: Double
        func contains(_ p: MapPoint) -> Bool { (x0...x1).contains(p.x) && (y0...y1).contains(p.y) }
    }

    let clock: FightClock
    let pad = SimPad()
    let keys: LiveKeys
    var x: Double
    var y: Double
    var facing: Double
    var boxes: [Box]
    var combat = false
    var player = 1.0
    var unreadable = false
    var missEvery = 0  // every n-th look is unreadable
    private var looks = 0
    var ownerFront = false
    var emitHandler: Emit = { _, _ in }

    init(clock: FightClock, x: Double, y: Double, facing: Double, boxes: [Box] = []) {
        self.clock = clock
        self.x = x
        self.y = y
        self.facing = facing
        self.boxes = boxes
        keys = LiveKeys(sink: pad, releaseCodes: NavLimits.releaseCodes, clock: { clock.now() })
        keys.emit = { [unowned self] event, fields in self.emit(event, fields) }
    }

    func now() -> Double { clock.now() }
    func emit(_ event: String, _ fields: [String: Any]) { emitHandler(event, fields) }
    func ownerTookFocus() -> Bool { ownerFront }

    func look() -> NavObs? {
        looks += 1
        guard !unreadable, missEvery == 0 || looks % missEvery != 0 else { return nil }
        return NavObs(x: roundTo(x, 10), y: roundTo(y, 10), facing: facing.rounded(), combat: combat, player: player)
    }

    /// Integrates in 0.05 s steps; the watchdog is swept after each, as the live 0.2 s timer would.
    func sleep(_ seconds: Double) async {
        var left = seconds
        while left > 1e-9 {
            let step = min(0.05, left)
            advance(step)
            clock.t += step
            keys.sweepExpired()
            left -= step
        }
        await clock.sleep(0)  // the dry-run's pace
    }

    private func advance(_ dt: Double) {
        let down = pad.pressed
        if down.contains(FightLimits.turnLeft) { facing -= NavLimits.turnRate * dt }
        if down.contains(FightLimits.turnRight) { facing += NavLimits.turnRate * dt }
        facing = (facing + 360).truncatingRemainder(dividingBy: 360)
        guard down.contains(FightLimits.forward) else { return }
        let step = NavLimits.runSpeed * dt, h = facing * .pi / 180
        let next: MapPoint = (x + step * sin(h) / mapAspect, y - step * cos(h))
        if !boxes.contains(where: { $0.contains(next) }) {
            x = next.x
            y = next.y
        }
    }

    /// Named worlds for the dry-run and the --sim-jev rehearsal.
    static func scenario(_ name: String, clock: FightClock) -> (SimNav, NavDestination)? {
        switch name {
        case "open":
            return (SimNav(clock: clock, x: 40, y: 30, facing: 0), NavDestination(label: "open ground", x: 42, y: 26))
        case "wall":  // a fence across the direct line, longer to the east
            let wall = Box(x0: 39.8, y0: 27.5, x1: 41.5, y1: 27.8)
            return (SimNav(clock: clock, x: 40, y: 30, facing: 0, boxes: [wall]),
                    NavDestination(label: "beyond a fence", x: 40, y: 25))
        case "pocket":  // a U open to the south, the destination north of its closed end
            let boxes = [Box(x0: 39.5, y0: 27.0, x1: 39.6, y1: 29.0), Box(x0: 40.4, y0: 27.0, x1: 40.5, y1: 29.0),
                         Box(x0: 39.5, y0: 27.0, x1: 40.5, y1: 27.1)]
            return (SimNav(clock: clock, x: 40, y: 28.5, facing: 0, boxes: boxes),
                    NavDestination(label: "beyond a pocket", x: 40, y: 24))
        default:
            return nil
        }
    }
}

struct NavCommand: Equatable {
    enum Mode: String {
        case preflight = "--preflight", dryRun = "--dry-run", replay = "--replay", simJev = "--sim-jev", execute = "--execute"
        case huntDryRun = "--hunt-dry-run", huntSimJev = "--hunt-sim-jev", hunt = "--hunt", turnIn = "--turn-in"
    }
    let mode: Mode
    var profile: KeyProfile?
    var toX: Double?
    var toY: Double?
    var arrive = NavLimits.arriveDefault
    var label = "destination"
    var ghost = false  // the character is dead and walks as a ghost: its empty health bar is not read
    var directory: String?
    var scenario: String?
    var quest: String?
}

let navScenarios: Set<String> = ["open", "wall", "pocket"]

/// Parses everything before any effect. Missing or unknown arguments never default to input.
func parseNav(_ arguments: [String]) throws -> NavCommand {
    guard let first = arguments.first else { return NavCommand(mode: .preflight) }
    guard let mode = NavCommand.Mode(rawValue: first) else { throw ProbeError("unknown mode '\(first.prefix(40))'") }
    var command = NavCommand(mode: mode)
    var rest = arguments.dropFirst()
    if mode == .replay {
        guard rest.count == 1, let directory = rest.first, !directory.hasPrefix("-") else {
            throw ProbeError("--replay takes one frame directory")
        }
        command.directory = directory
        return command
    }
    var seen: Set<String> = []
    while let option = rest.popFirst() {
        guard [.execute, .simJev, .hunt, .turnIn].contains(mode) else { throw ProbeError("\(mode.rawValue) takes no arguments") }
        if mode == .execute && option == "--ghost" {
            guard !command.ghost else { throw ProbeError("'--ghost' is repeated") }
            command.ghost = true
            continue
        }
        guard seen.insert(option).inserted, let value = rest.popFirst(), !value.hasPrefix("-") else {
            throw ProbeError("'\(option.prefix(40))' is repeated or has no value")
        }
        switch (mode, option) {
        case (.simJev, "--scenario"):
            guard navScenarios.contains(value) else { throw ProbeError("--scenario needs open, wall or pocket") }
            command.scenario = value
        case (.execute, "--keys"), (.hunt, "--keys"), (.turnIn, "--keys"):
            guard value == "wqe", let profile = KeyProfile(rawValue: value) else {
                throw ProbeError("--keys needs wqe, confirmed in-game")
            }
            command.profile = profile
        case (.execute, "--to"):
            let parts = value.split(separator: ",", omittingEmptySubsequences: false).map { Double($0) }
            guard parts.count == 2, let x = parts[0], let y = parts[1], (0...100).contains(x), (0...100).contains(y) else {
                throw ProbeError("--to needs X,Y zone coordinates in 0...100")
            }
            command.toX = x
            command.toY = y
        case (.execute, "--arrive"):
            guard let arrive = Double(value), NavLimits.arriveRange.contains(arrive) else {
                throw ProbeError("--arrive needs a radius in \(NavLimits.arriveRange)")
            }
            command.arrive = arrive
        case (.turnIn, "--quest"):
            guard value.count <= 60, value.allSatisfy({ $0.isLetter || $0.isNumber || " '-,.!".contains($0) }) else {
                throw ProbeError("--quest needs a quest title: up to 60 letters, digits and simple punctuation")
            }
            command.quest = value
        case (.execute, "--label"):
            guard value.count <= 60, value.allSatisfy({ $0.isLetter || $0.isNumber || " '()-,.".contains($0) }) else {
                throw ProbeError("--label needs up to 60 letters, digits and simple punctuation")
            }
            command.label = value
        default:
            throw ProbeError("unexpected option '\(option.prefix(40))'")
        }
    }
    if mode == .simJev && command.scenario == nil { throw ProbeError("--sim-jev requires --scenario open|wall|pocket") }
    if mode == .hunt && command.profile == nil { throw ProbeError("--hunt requires --keys wqe, confirmed in-game") }
    if mode == .turnIn && (command.profile == nil || command.quest == nil) {
        throw ProbeError("--turn-in requires --keys wqe and --quest NAME")
    }
    if mode == .execute {
        guard command.profile != nil else { throw ProbeError("--execute requires --keys wqe, confirmed in-game") }
        guard command.toX != nil else { throw ProbeError("--execute requires --to X,Y") }
    }
    return command
}
