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
    /// When the raw text does not parse, the box is read again under these masks (whiteText). 25 Sept, the
    /// first live --quests run: a quest giver's orange name drawn across the box read as "43.0, 23к7 Eнн"
    /// on arrival, and the walk stopped HUD_UNREADABLE 0.48 from the pin. One mask alone misread 23.7 as
    /// 23.1, and a floor of 140 misread 42.5 as 12.5; so a masked reading counts only when both agree.
    static let coordsMasks: [(spread: Int, floor: Int)] = [(60, 0), (60, 60)]

    static func silver(_ r: Int, _ g: Int, _ b: Int) -> Bool { min(r, g, b) > 120 && max(r, g, b) - min(r, g, b) < 50 }
    static func navy(_ r: Int, _ g: Int, _ b: Int) -> Bool { b >= r + 10 && b >= g + 8 }
}

/// The raw reading when it parses (unchanged since M4a); otherwise a masked reading only when every mask
/// reads the same point, so a misread glyph under one mask cannot move the character on the map.
func agreedCoords(raw: String, masked: [String]) -> MapPoint? {
    if let point = parseCoords(raw) { return point }
    let points = masked.map(parseCoords)
    guard points.count >= 2, let first = points[0],
          points.allSatisfy({ $0.map { $0.x == first.x && $0.y == first.y } ?? false }) else { return nil }
    return first
}

/// The image with its coloured pixels (channels spread wider than `spread`) and its dark ones (below
/// `floor`) blanked, so only neutral light text reaches OCR: a coloured name drawn across it goes.
func whiteText(_ image: RGBA, spread: Int, floor: Int) -> RGBA {
    var pixels = image.pixels
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        if max(r, g, b) - min(r, g, b) > spread || min(r, g, b) < floor { (pixels[i], pixels[i + 1], pixels[i + 2]) = (0, 0, 0) }
    }
    return RGBA(width: image.width, height: image.height, pixels: pixels)
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
    static let unstickTurn = 0.15  // s of E: about 25 degrees (a 300 ms press stepped 46-59 degrees)
    static let unstickDegrees = 25.0
    static let trustSeconds = 10.0  // a turn test's trust, then the two readings must agree or be tested again
    static let recentMoves = 6
    static let warnCone = 30.0  // a red name within this of the heading is on the way (M4h)
    static let runSpeed = 0.2  // y units per second: 0.63-0.78 per 3.0-3.3 s move on the second live walk
    static let releaseCodes: [UInt16] = [FightLimits.turnLeft, FightLimits.forward, FightLimits.turnRight, FightLimits.zoomOut, FightLimits.zoomIn, 36, 8, 37, 53, 11]  // M4c/d: Enter, C (character pane), L (map), Esc; M4m: B (bags)
}

typealias MapPoint = (x: Double, y: Double)

func compass(dx: Double, dy: Double) -> Double {  // dy grows southwards, as on screen and on the map
    (atan2(dx, -dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}

/// The facing a walk or a hunt acts on, from the rule (arrowFacing) and the learned reader (M5, FacingReader): the rule's
/// where it reads, the learned one at 0.7 or more where the rule has none, and the learned one over the rule only where a
/// turn test (turnTest) showed the rule wrong. Live evidence, 27 Sept: beside the Elemental Convergence the rule was wrong
/// and the reader right (run 52: 350 and 316 for about 150), but on runs 54 and 58-62 the rule was right and the reader
/// wrong at up to 1.00 (run 62: 320, 270 and 150 for 42 and 68). A disagreement that gave no bearing ended run 62's walk
/// HUD_UNREADABLE in 10 s, so a disagreement no longer does: until the reader is retrained, it only fills the rule's gaps.
func fusedFacing(rule: Double?, learned: (bearing: Double, confidence: Double)?, trust: FacingSource? = nil) -> Double? {
    switch (rule, learned) {
    case let (r?, l?):
        if abs(angleError(r, l.bearing)) <= 30 { return r }
        return trust == .learned && l.confidence >= 0.7 ? l.bearing : r
    case let (nil, l?): return l.confidence >= 0.7 ? l.bearing : nil
    case let (r, nil): return r
    }
}

enum FacingSource: String { case rule, learned }

/// The two facing readings of the last live frame, and the reader a turn test showed right until the two agree again.
final class FacingState {
    var rule: Double?, learned: Double?
    var trust: FacingSource?
    var trustUntil = 0.0  // a trust lapses (review of #67): a reader right once may be wrong later
}

/// The trust a disagreement may follow now: none once the two readings agree again or the trust has lapsed, and both
/// clear it.
func currentTrust(_ s: FacingState, rule: Double?, learned: Double?, now: Double) -> FacingSource? {
    if let rule, let learned, abs(angleError(rule, learned)) <= 30 { s.trust = nil }
    if now >= s.trustUntil { s.trust = nil }
    return s.trust
}

/// Which reader followed a turn of `turned` degrees clockwise (within 20 degrees) while the other did not; nil when both,
/// neither, or a reading is missing. Live run 58 (27 Sept): standing still the rule read 222 and the learned reader 150
/// (0.93); a turn right of about 25 degrees moved the rule to 254 and the reader to 118, so the rule was right.
func turnTest(before: (rule: Double?, learned: Double?), after: (rule: Double?, learned: Double?), turned: Double) -> FacingSource? {
    func followed(_ a: Double?, _ b: Double?) -> Bool? {
        guard let a, let b else { return nil }
        return abs(angleError(angleError(b, a), turned)) <= 20
    }
    switch (followed(before.rule, after.rule), followed(before.learned, after.learned)) {
    case (true?, false?): return .rule
    case (false?, true?): return .learned
    default: return nil
    }
}

/// One turn on the spot (NavLimits.unstickTurn of E, about 25 degrees), W lifted first, when the place cannot be read: a
/// quest icon beside the minimap arrow stays where it is while the arrow turns off it (live run 54, 27 Sept: standing
/// still, the rule read 130 and the learned reader 250 on every frame, and the walk ended HUD_UNREADABLE). With the
/// live facing state and a fresh look after the turn, it is also a turn test (turnTest): the reader whose bearing
/// followed the turn is trusted where the two disagree (live run 58).
func unstickTurn(_ keys: LiveKeys, misses: Int, sleep: (Double) async -> Void, emit: (String, [String: Any]) -> Void,
                 facing: FacingState? = nil, reread: (() async -> Void)? = nil, now: (() -> Double)? = nil) async {
    let before = facing.map { (rule: $0.rule, learned: $0.learned) }
    keys.lift(FightLimits.forward)
    emit("unreadable_turn", ["misses": misses, "ms": Int(NavLimits.unstickTurn * 1000)])
    keys.grant(FightLimits.turnRight, seconds: NavLimits.unstickTurn + NavLimits.forwardWatchdog)
    keys.press(FightLimits.turnRight)
    await sleep(NavLimits.unstickTurn)
    keys.lift(FightLimits.turnRight)
    guard let facing, let before, let reread else { return }
    await sleep(0.3)  // the turn's last frames settle
    await reread()
    let after = (rule: facing.rule, learned: facing.learned)
    guard let source = turnTest(before: before, after: after, turned: NavLimits.unstickDegrees) else {
        facing.trust = nil  // no verdict: an older trust is not carried past a new test
        return
    }
    facing.trust = source
    facing.trustUntil = (now?() ?? 0) + NavLimits.trustSeconds
    emit("facing_turn_test", ["trust": source.rawValue, "before": [orNull(before.rule), orNull(before.learned)],
                              "after": [orNull(after.rule), orNull(after.learned)]])
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
    // Where that navy falls in several parts and two or more are dot-sized (within 7 x 7, 9 px at least), the tail is the
    // one silver rings on most sides: a quest area's blue band beyond the tip is beside silver on one side (live run 36,
    // 27 Sept: its pixels pulled the "dot" towards the tip, the facing read 258-344° for 131°, and the walk turned on the
    // spot until NO_PROGRESS). Otherwise every part counts, as before: over water the dot joins the water's navy.
    var parts: [[(Int, Int)]] = [], left = navy
    while let seed = left.popLast() {
        var part = [seed], i = 0
        while i < part.count {
            let (px, py) = part[i]
            i += 1
            let near = left.indices.filter { abs(left[$0].0 - px) <= 1 && abs(left[$0].1 - py) <= 1 }
            part += near.map { left[$0] }
            for k in near.reversed() { left.remove(at: k) }
        }
        parts.append(part)
    }
    let dots = parts.filter { p in p.count >= 9 && p.map(\.0).max()! - p.map(\.0).min()! < 7 && p.map(\.1).max()! - p.map(\.1).min()! < 7 }
    func ringed(_ p: [(Int, Int)]) -> Int {  // quadrants round the part's centre holding silver within 3 px of it
        let cx = Double(p.map(\.0).reduce(0, +)) / Double(p.count), cy = Double(p.map(\.1).reduce(0, +)) / Double(p.count)
        var sides = Set<Int>()
        for (x, y) in p {
            for dy in -3...3 {
                for dx in -3...3 where silver.contains((y + dy) * w + x + dx) {
                    sides.insert((Double(x + dx) >= cx ? 1 : 0) + (Double(y + dy) >= cy ? 2 : 0))
                }
            }
        }
        return sides.count
    }
    if parts.count > 1 && dots.count > 1 { navy = dots.max { (ringed($0), $0.count) < (ringed($1), $1.count) }! }
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
    let pattern = #"(?<!\d)(\d{1,2})[.,](\d)\s*[.,]\s*(\d{1,2})[.,](\d)(?!\d)"#
    // Both numbers keep their decimal: a reading that lost one lost a glyph, and a glyph lost elsewhere reads a wrong
    // place (live runs 28-29, 26 Sept: "44.9, 23.4" read as "44.9, 23", and then as "4.9, 23", 40 units off).
    // A decimal point may read as a comma, a glyph kept (live run 31, 27 Sept: "42,2,23.7" twice, and the hunt stopped).
    // Letters OCR has put for a digit of the same shape, live (run 32, 27 Sept: "42.G,24.3" on every frame for 3 s, with
    // "24.З", a Cyrillic Ze, and the walk stopped); the pattern still asks for every digit.
    let text = String(text.map { ["G": "6", "З": "3"][$0] ?? $0 })
    guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
    let n = text[match].split { !$0.isNumber }.compactMap { Int($0) }
    guard n.count == 4 else { return nil }
    return (Double(n[0]) + Double(n[1]) / 10, Double(n[2]) + Double(n[3]) / 10)
}

/// Readings of the zone coordinates in time. One that moved further than a character can since the last is a misread
/// glyph, not a place (live run 33, 27 Sept: 43.3 read as 48.3 and as 3.3 on single frames while standing, and a hunt walk
/// "moved 59.55"). Three in a row that agree with each other are the place, whatever the last one was.
struct PositionTrack {
    static let speed = 0.5, slack = 0.5, agree = 3  // y units a second; walking is about 0.16 (live run 3)
    /// The time the allowance grows for: Jev calls can stall reading for seconds, and 9 s would pass run 33's 5-unit misread
    /// (review of #53). A longer real move is taken once three readings agree.
    static let maxGap = 2.0
    private(set) var last: (at: MapPoint, t: Double)?
    private var doubted: [MapPoint] = []

    mutating func accept(_ at: MapPoint, t: Double) -> Bool {
        if let last, distance(at, last.at) > PositionTrack.slack + PositionTrack.speed * min(PositionTrack.maxGap, max(0, t - last.t)) {
            doubted.append(at)
            let recent = doubted.suffix(PositionTrack.agree)
            guard recent.count == PositionTrack.agree, recent.allSatisfy({ distance($0, at) <= 0.3 }) else { return false }
        }
        doubted = []
        last = (at, t)
        return true
    }
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
    var stamp: ObservationStamp? = nil
    var x: Double
    var y: Double
    var facing: Double
    var combat = false
    var player = 1.0
    var warnings: [Double] = []  // compass bearings of red names in view (M4h); the hunt's body reads none
    var point: MapPoint { (x, y) }
}

struct NavDestination: Equatable {
    let label: String
    let x: Double
    let y: Double
    var arrive = NavLimits.arriveDefault
    // A walk to safety (M4r) walks on past a red name ahead and at low health: stopping among hostiles is what it leaves
    // (reviews of #72). Combat still stops it, and is fought back.
    var toSafety = false
    var seconds = NavLimits.maxSeconds  // a walk to safety gets what is left of the run envelope
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
    var warned = false  // a red name came into view ahead
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
    var facingState: FacingState? { get }  // the live facing's readings, for a turn test; nil in a simulation
}

extension NavBody {
    var facingState: FacingState? { nil }
}

extension NavBody {
    func readObservation() -> Observation<NavObs> {
        guard let o = look(), let stamp = o.stamp,
              stamp.isFresh(at: now(), maximumAge: FightLimits.maxFrameAge) else { return .unavailable("navigation_unreadable") }
        return .observed(o, stamp)
    }
}

/// One bounded move: steer by Q/E pulses with W held, re-aiming at the destination each tick for
/// GO_TOWARD or holding the move's fixed heading otherwise, until its time is up, arrival, a block
/// (W held for blockedWindow with less than blockedMoved of movement), a red name ahead, or an unsafe frame. A move that
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
                // A turn key held too: the watchdog lifts it if this task stalls (review of #53).
                body.keys.grant(pulse.code, seconds: Double(pulse.ms) / 1000 + NavLimits.forwardWatchdog)
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
        if o.combat || (!d.toSafety && o.player < FightLimits.playerSafety) || body.ownerTookFocus() { ranOut = false; break }
        if distance(o.point, d.point) < d.arrive { attempt.arrived = true; ranOut = false; break }
        if !d.toSafety, o.warnings.contains(where: { abs(angleError($0, attempt.heading)) <= NavLimits.warnCone }) {
            attempt.warned = true; ranOut = false; break
        }
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
    var runtime: SkillResult? = nil
}

func runNav(body: NavBody, jev: JevClient, destination d: NavDestination) async -> NavResult {
    var result = NavResult()
    var executive = RuntimeExecutive(goal: d.label)
    executive.begin("navigation")
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
        let skill = SkillResult(skill: "navigation", status: skillStatus(outcome), code: outcome,
                                evidence: result.end?.stamp, holdingInput: result.holding)
        executive.finish(skill)
        result.runtime = skill
        body.emit("skill_result", skill.json)
        return result
    }

    while true {
        if body.ownerTookFocus() { return finish("OWNER_TOOK_FOCUS") }
        guard let o = body.readObservation().value else {
            misses += 1
            if misses >= NavLimits.unreadableLimit { return finish("HUD_UNREADABLE") }
            if misses == NavLimits.unreadableLimit / 2 {
                await unstickTurn(body.keys, misses: misses, sleep: { await body.sleep($0) }, emit: body.emit,
                                  facing: body.facingState, reread: { _ = body.look() }, now: body.now)
            }
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
        if !d.toSafety && o.player < FightLimits.playerSafety { return finish("LOW_HEALTH") }
        if distance(o.point, d.point) < d.arrive { return finish("ARRIVED") }
        if result.episode.sinceBest >= NavLimits.noProgressDecisions { return finish("NO_PROGRESS") }
        if result.decisions >= NavLimits.maxDecisions { return finish("DECISION_LIMIT") }
        if body.now() - began >= d.seconds { return finish("TIME_LIMIT") }
        let allowed = navAdmissible(o, destination: d, episode: result.episode)
        if allowed.isEmpty { return finish("NO_ADMISSIBLE_MOVE") }

        let state = navStatePacket(o, destination: d, episode: result.episode,
                                   decisionsLeft: NavLimits.maxDecisions - result.decisions)
        let question = actionQuestion(allowed, instructions: navInstructions)
        let asked = body.now()
        guard let stamp = o.stamp, let context = executive.request(stamp: stamp, candidates: allowed.map(\.rawValue),
                policy: "nav-legacy-v1", now: asked, maximumAge: FightLimits.maxFrameAge,
                deadline: min(asked + FightLimits.jevTimeout, began + d.seconds)) else { return finish("HUD_UNREADABLE") }
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
            "admissible": allowed.map(\.rawValue), "response": reply, "latency_s": latency, "context": context.json,
        ]
        guard let choice = parseChoice(reply, admissible: allowed, model: FightLimits.model) else {
            result.records.append(record)
            body.emit("decision", record)
            return finish("INVALID_REPLY")
        }
        let current = body.readObservation().value
        let transition: String?
        if current?.combat == true { transition = "COMBAT" }
        else if let current, !d.toSafety, current.player < FightLimits.playerSafety { transition = "LOW_HEALTH" }
        else if let current, distance(current.point, d.point) < d.arrive { result.end = current; transition = "ARRIVED" }
        else { transition = nil }
        if let transition {
            record["rejection"] = "state_transition:" + transition
            result.records.append(record); body.emit("decision", record)
            return finish(transition)
        }
        let candidates = current.map { navAdmissible($0, destination: d, episode: result.episode).map(\.rawValue) } ?? []
        if let rejection = executive.rejection(DecisionProposal(context: context, action: choice.action.rawValue),
                current: current?.stamp, candidates: candidates, now: body.now(), maximumAge: FightLimits.maxFrameAge,
                ownerStopped: body.ownerTookFocus()) {
            body.keys.lift(FightLimits.forward)
            record["rejection"] = rejection
            result.records.append(record)
            body.emit("decision", record)
            if rejection == "owner_stop" { return finish("OWNER_TOOK_FOCUS") }
            if rejection == "decision_expired" { return finish("DECISION_EXPIRED") }
            continue
        }
        let attempt = await walk(body, choice.action, from: current!, to: d)
        result.episode.record(attempt)
        record["attempt"] = attempt.json
        if attempt.warned { record["danger_ahead"] = attempt.to.warnings.map { Int($0.rounded()) } }
        result.records.append(record)
        body.emit("decision", record)
        if attempt.warned { result.end = attempt.to; return finish("DANGER_AHEAD") }  // never walk on into it
        // Seen within the radius during the move, W released: arrived, without one more reading. 25 Sept,
        // live: 0.46 from a quest giver, its name then covered the coordinates for six looks (HUD_UNREADABLE).
        if attempt.arrived { result.end = attempt.to; return finish("ARRIVED") }
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
    var hostiles: [MapPoint] = []  // red names, seen within nameRange and the view
    static let nameRange = 4.0
    var unreadable = false
    var missEvery = 0  // every n-th look is unreadable
    var readsNear: (point: MapPoint, radius: Double, reads: Int)?  // within it, only so many looks read (a name over the text)
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
        if let near = readsNear, distance((roundTo(x, 10), roundTo(y, 10)), near.point) < near.radius {  // as it would read
            guard near.reads > 0 else { return nil }
            readsNear?.reads -= 1
        }
        let warnings = hostiles.filter { distance((x, y), $0) <= SimNav.nameRange }.map { bearing(from: (x, y), to: $0) }
            .filter { abs(angleError($0, facing)) <= HuntLimits.viewDegrees / 2 }
        return NavObs(stamp: ObservationStamp(stream: "sim-nav", geometry: "sim-layout", capturedAt: now()),
                      x: roundTo(x, 10), y: roundTo(y, 10), facing: facing.rounded(), combat: combat, player: player, warnings: warnings)
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
        case preflight = "--preflight", dryRun = "--dry-run", replay = "--replay", pixels = "--pixels", simJev = "--sim-jev"
        case execute = "--execute"
        case huntDryRun = "--hunt-dry-run", huntSimJev = "--hunt-sim-jev", hunt = "--hunt", turnIn = "--turn-in", plan = "--plan"
        case quests = "--quests", zoom = "--zoom", bags = "--bags"
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
    var graph: String?
    var experience: String?
    var fightGraph: String?  // M3b's fight graph for a live hunt's or quest run's fights
    var huntGraph: String?  // M4b's hunt graph for a quest run's hunts
    var zoomIn = FightLimits.zoomInSeconds  // --zoom: F11 back from the widest view, to calibrate
}

let navScenarios: Set<String> = ["open", "wall", "pocket"]

/// Parses everything before any effect. Missing or unknown arguments never default to input.
func parseNav(_ arguments: [String]) throws -> NavCommand {
    guard let first = arguments.first else { return NavCommand(mode: .preflight) }
    guard let mode = NavCommand.Mode(rawValue: first) else { throw ProbeError("unknown mode '\(first.prefix(40))'") }
    var command = NavCommand(mode: mode)
    var rest = arguments.dropFirst()
    if mode == .replay || mode == .pixels {
        guard rest.count == 1, let directory = rest.first, !directory.hasPrefix("-") else {
            throw ProbeError("\(mode.rawValue) takes one frame directory")
        }
        command.directory = directory
        return command
    }
    var seen: Set<String> = []
    while let option = rest.popFirst() {
        guard [.execute, .simJev, .hunt, .turnIn, .plan, .quests, .zoom, .bags, .huntDryRun, .huntSimJev].contains(mode) else { throw ProbeError("\(mode.rawValue) takes no arguments") }
        if mode == .execute && option == "--ghost" {
            guard !command.ghost else { throw ProbeError("'--ghost' is repeated") }
            command.ghost = true
            continue
        }
        guard seen.insert(option).inserted, let value = rest.popFirst(), !value.hasPrefix("-") else {
            throw ProbeError("'\(option.prefix(40))' is repeated or has no value")
        }
        switch (mode, option) {
        case (.hunt, "--graph"), (.huntDryRun, "--graph"), (.huntSimJev, "--graph"), (.quests, "--graph"):
            command.graph = value
        case (.hunt, "--experience"), (.huntDryRun, "--experience"), (.huntSimJev, "--experience"):
            command.experience = value
        case (.hunt, "--fight-graph"), (.quests, "--fight-graph"):
            command.fightGraph = value
        case (.quests, "--hunt-graph"):
            command.huntGraph = value
        case (.zoom, "--seconds"):
            guard let seconds = Double(value), (0...2).contains(seconds) else { throw ProbeError("--seconds needs 0...2 s of F11") }
            command.zoomIn = seconds
        case (.simJev, "--scenario"):
            guard navScenarios.contains(value) else { throw ProbeError("--scenario needs open, wall or pocket") }
            command.scenario = value
        case (.execute, "--keys"), (.hunt, "--keys"), (.turnIn, "--keys"), (.plan, "--keys"), (.quests, "--keys"), (.zoom, "--keys"), (.bags, "--keys"):
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
    if command.experience != nil && command.graph == nil {
        throw ProbeError("--experience requires --graph PATH so Jev explicitly chooses READ:experience")
    }
    if mode == .simJev && command.scenario == nil { throw ProbeError("--sim-jev requires --scenario open|wall|pocket") }
    if mode == .hunt && command.profile == nil { throw ProbeError("--hunt requires --keys wqe, confirmed in-game") }
    if [.plan, .quests, .zoom, .bags].contains(mode) && command.profile == nil { throw ProbeError("\(mode.rawValue) requires --keys wqe, confirmed in-game") }
    if mode == .quests && command.graph == nil { throw ProbeError("--quests requires --graph PATH: Jev chooses each quest step") }
    if mode == .turnIn && (command.profile == nil || command.quest == nil) {
        throw ProbeError("--turn-in requires --keys wqe and --quest NAME")
    }
    if mode == .execute {
        guard command.profile != nil else { throw ProbeError("--execute requires --keys wqe, confirmed in-game") }
        guard command.toX != nil else { throw ProbeError("--execute requires --to X,Y") }
    }
    return command
}
