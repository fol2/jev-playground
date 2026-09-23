// M4b for issue #5: Jev chooses how to hunt for the creatures that quest objectives name. Pure core:
// the objectives tracker, the minimap's quest ring and the view's nameplates; the hunt's actions and
// their admissibility; the state packet; the skills (M4a walks, a look around, Tab); runHunt and
// SimHunt. Each fight is one M3 episode (runFight) on a fresh host; the live shell is HuntProbe.swift.
import Foundation

enum HuntLimits {
    static let maxDecisions = 40
    static let maxSeconds = 900.0
    static let jevTimeout = 10.0  // a hunt decides out of combat; its fights keep M3's 4 s
    static let maxFights = 4
    static let searchLimit = 12  // hunt decisions in a row without a fight
    static let maxMoves = 24  // walks per hunt, about 3 s each
    static let repeatCap = 4  // the same compass walk at most this many times in a row
    static let restSeconds = 20.0
    static let lookSeconds = 90 / NavLimits.turnRate  // about 90°; live turns run up to 15 % further
    static let tap = 0.08
    static let settle = 0.5  // for the target frame to follow a key
    static let tick = 0.25
    static let unreadableLimit = 3
    static let recent = 6
    static let restHealth = 0.99
    static let restMana = 0.95
    static let fightMana = 0.6  // owner, 23 Sept: a fight starts only with 60% mana (a Convert took half of it)
    static let walkHealth = 0.6  // below this, rest before walking on
    // ponytail: an assumed horizontal field of view; calibrate from a plate's shift over a known turn.
    static let viewDegrees = 90.0
    static let nearRow = 0.35  // a plate lower in view than this fraction of its height is near (roughly 25 yards)
    static let panoramaFor = 0.6  // map units: a LOOK_AROUND is stale once the character is this far from it
    static let sameCreature = 20.0  // degrees: sightings of one name closer than this are one creature
    static let escape: UInt16 = 53
    static let releaseCodes: [UInt16] = [53, 48, 12, 13, 14]
    static let continueAfter: Set<String> = ["KILLED_AND_LOOTED", "KILLED_NO_CORPSE", "JEV_STOP"]
}

struct Objective: Equatable {
    var quest: String
    var done: Int
    var need: Int
    var text: String
    var unfinished: Bool { done < need }
}

/// Reads the objectives tracker's OCR lines, top to bottom: "Agitators", "- 0/6 Roiling Winds destroyed".
/// A line with no count is a quest title. Upscale the crop first: at 1x, "0/6" reads as "Oyo".
func parseTracker(_ lines: [String]) -> [Objective] {
    let count = try! NSRegularExpression(pattern: #"^\W*(\d{1,3})\s*/\s*(\d{1,3})\s+(\S.*)$"#)
    var quest = "", out: [Objective] = []
    for raw in lines {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if let m = count.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let done = Int(line[Range(m.range(at: 1), in: line)!]), let need = Int(line[Range(m.range(at: 2), in: line)!]) {
            if !quest.isEmpty && need > 0 {
                out.append(Objective(quest: quest, done: done, need: need, text: String(line[Range(m.range(at: 3), in: line)!])))
            }
        } else if line.first?.isLetter == true && line.filter(\.isLetter).count >= 4 {
            quest = line
        }
    }
    return out
}

/// Letters only, lower case, with "i" read as "l": OCR reads "Al'Aketh" as "AI' Aketh".
func nameKey(_ text: String) -> String {
    String(text.lowercased().filter(\.isLetter).map { $0 == "i" ? "l" : $0 })
}

/// The unfinished objective a creature counts for: its name starts the objective's text, as
/// "Roiling Wind" starts "Roiling Winds destroyed". A partial-word match would let
/// "Yala Windwatcher" count for Roiling Winds.
// ponytail: prefix match; irregular plurals ("Wolf" for "Wolves slain") never count.
func objective(for name: String?, in objectives: [Objective]) -> Objective? {
    guard let name, nameKey(name).count >= 4 else { return nil }
    return objectives.first { $0.unfinished && nameKey($0.text).hasPrefix(nameKey(name)) }
}

/// The objectives in `wanted` still unfinished in `now`. A line that has gone counts as finished.
func remaining(_ wanted: [Objective], in now: [Objective]) -> [Objective] {
    wanted.filter { w in
        now.contains { nameKey($0.quest) == nameKey(w.quest) && nameKey($0.text) == nameKey(w.text) && $0.unfinished }
    }
}

/// The selected quest's area on the north-up minimap. The owner: its ring is drawn bright, and the
/// other quests' rings dim. On a PNG capture beside both, only the selected ring passed `bright`.
struct QuestArea: Equatable {
    var bearing: Double  // compass degrees from the character to the ring's centre
    var distance: Double  // y units
    var inside: Bool  // the ring crosses all four compass rays from the character
}

enum MinimapHUD {
    static let cx = 2423, cy = 197, radius = 94  // the player arrow's centre; inside the bronze rim
    static let unitPx = 19.0  // one y unit, measured in M4a
    static let minPixels = 40
    static func bright(_ r: Int, _ g: Int, _ b: Int) -> Bool { b >= 225 && g >= 175 && b > r + 30 }
}

// ponytail: the centroid of the visible ring; a ring cut by the minimap's edge pulls it towards the character.
func questArea(_ image: RGBA) -> QuestArea? {
    let c = MinimapHUD.self
    guard image.pixels.count == image.width * image.height * 4, c.cx + c.radius < image.width,
          c.cy + c.radius < image.height else { return nil }
    var sx = 0, sy = 0, n = 0
    var rays: Set<Int> = []  // 0 north, 1 east, 2 south, 3 west
    image.pixels.withUnsafeBufferPointer { p in
        for dy in -c.radius...c.radius {
            for dx in -c.radius...c.radius where dx * dx + dy * dy <= c.radius * c.radius {
                let i = ((c.cy + dy) * image.width + c.cx + dx) * 4
                guard c.bright(Int(p[i]), Int(p[i + 1]), Int(p[i + 2])) else { continue }
                sx += dx
                sy += dy
                n += 1
                if abs(dx) <= 2 { rays.insert(dy < 0 ? 0 : 2) }
                if abs(dy) <= 2 { rays.insert(dx > 0 ? 1 : 3) }
            }
        }
    }
    guard n >= c.minPixels else { return nil }
    let mx = Double(sx) / Double(n), my = Double(sy) / Double(n)
    return QuestArea(bearing: compass(dx: mx, dy: my), distance: (mx * mx + my * my).squareRoot() / c.unitPx,
                     inside: rays.count == 4)
}

/// One untargeted nameplate's bar in the game view: dim, semi-transparent red (hostile) or yellow
/// (neutral), about 95x7 px, with a dark outline above and below. The selected creature's plate has a
/// white outline instead and is M1's findTargetPlate. Capture pixels.
struct PlateBar: Equatable {
    var hostile: Bool
    var x0: Int, x1: Int, y0: Int, y1: Int
    var centre: Double { Double(x0 + x1) / 2 }
}

enum PlateScan {
    static let rows = 0.03..<0.72, columns = 0.86  // the game view, as M1's PlateLimits
    static let minRun = 45, width = 50...200, height = 4...12, bridge = 3
    static let solid = 0.85, solidRows = 3, border = 0.6
    static func kind(_ r: Int, _ g: Int, _ b: Int) -> Bool? {  // true hostile red, false neutral yellow
        if r - b >= 25 && abs(r - g) <= 14 && r >= 40 { return false }
        if r - g >= 35 && r - b >= 35 && r >= 60 { return true }
        return nil
    }
}

/// Every untargeted nameplate bar in view: runs of one colour stacked into a bar, solid across most
/// rows, with dark rows just above and below (a creature's body is patchy and has no outline). On 15
/// hunt frames (23 Sept) it found every Vuldren and Roiling Winds plate and nothing else.
func nameplates(_ image: RGBA) -> [PlateBar] {
    let w = image.width, h = image.height, s = PlateScan.self
    guard image.pixels.count == w * h * 4 else { return [] }
    return image.pixels.withUnsafeBufferPointer { p -> [PlateBar] in
        func kind(_ x: Int, _ y: Int) -> Bool? {
            let i = (y * w + x) * 4
            return s.kind(Int(p[i]), Int(p[i + 1]), Int(p[i + 2]))
        }
        func dark(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return Int(p[i]) + Int(p[i + 1]) + Int(p[i + 2]) < 120
        }
        let columns = Int(s.columns * Double(w))
        var bars: [PlateBar] = []
        for y in Int(s.rows.lowerBound * Double(h))..<Int(s.rows.upperBound * Double(h)) {
            var x = 0
            while x < columns {
                guard let k = kind(x, y) else { x += 1; continue }
                let start = x
                var miss = 0, n = 0
                while x < columns && miss <= s.bridge {
                    if kind(x, y) == k { n += 1; miss = 0 } else { miss += 1 }
                    x += 1
                }
                guard n >= s.minRun else { continue }
                let x1 = x - miss
                if let i = bars.lastIndex(where: { $0.hostile == k && y - $0.y1 <= 1 && start < $0.x1 && $0.x0 < x1 }) {
                    bars[i].y1 = y
                    bars[i].x0 = min(bars[i].x0, start)
                    bars[i].x1 = max(bars[i].x1, x1)
                } else {
                    bars.append(PlateBar(hostile: k, x0: start, x1: x1, y0: y, y1: y))
                }
            }
        }
        return bars.filter { b in
            guard s.width.contains(b.x1 - b.x0), s.height.contains(b.y1 - b.y0 + 1),
                  b.y0 >= 3, b.y1 + 3 < h else { return false }
            let span = (b.x0 + 3)..<(b.x1 - 3)
            let solid = (b.y0...b.y1).filter { y in
                Double(span.filter { kind($0, y) == b.hostile }.count) >= s.solid * Double(span.count)
            }.count
            let edge = { (rows: [Int]) in rows.map { y in Double(span.filter { dark($0, y) }.count) / Double(span.count) }.max() ?? 0 }
            return solid >= s.solidRows && edge([b.y0 - 1, b.y0 - 2, b.y0 - 3]) >= s.border
                && edge([b.y1 + 1, b.y1 + 2, b.y1 + 3]) >= s.border
        }
    }
}

/// A creature whose nameplate was in view: its name, colour, compass bearing (facing plus the plate's
/// angle off the view's centre) and whether it stood low in view, which means near.
struct Seen: Equatable {
    var name: String
    var hostile: Bool
    var bearing: Double
    var near: Bool
}

func sighting(_ bar: PlateBar, name: String, facing: Double, width: Int, height: Int) -> Seen {
    let off = (bar.centre / Double(width) - 0.5) * HuntLimits.viewDegrees
    return Seen(name: name, hostile: bar.hostile, bearing: (facing + off + 360).truncatingRemainder(dividingBy: 360),
                near: Double(bar.y0) / Double(height) > HuntLimits.nearRow)
}

/// Sightings with one name and nearly one bearing are one creature; the newer one wins.
func merged(_ older: [Seen], _ newer: [Seen]) -> [Seen] {
    older.filter { o in !newer.contains { $0.name == o.name && abs(angleError($0.bearing, o.bearing)) < HuntLimits.sameCreature } } + newer
}

/// The unfinished objective a sighted creature counts for. Plate names are read small, so two shared
/// 4-letter runs suffice ("Rolling WWinds" is a Roiling Wind).
func counts(_ creature: Seen, _ objectives: [Objective]) -> Objective? {
    objectives.first { $0.unfinished && fuzzyNameMatch($0.text, [creature.name]) }
}

struct HuntObs: Equatable {
    var objectives: [Objective] = []
    var player = 1.0
    var mana = 1.0
    var combat = false
    var target: String? = nil  // the target frame's name; nil when nothing is selected
    var targetAlive = false
    var gameMenu = false
    var facing: Double? = nil  // the minimap arrow
    var area: QuestArea? = nil
    var here: NavObs? = nil  // coordinates and facing, as a walk reads them
    var seen: [Seen] = []  // this view's plates, plus a fresh LOOK_AROUND's
}

enum HuntAction: String, JevAction {
    case fight = "FIGHT_TARGET"
    case nextTarget = "NEXT_TARGET"
    case lookAround = "LOOK_AROUND"
    case toCreature = "GO_TO_QUEST_CREATURE"
    case toArea = "GO_TO_QUEST_AREA"
    case detourLeft45 = "DETOUR_LEFT_45", detourRight45 = "DETOUR_RIGHT_45"
    case detourLeft90 = "DETOUR_LEFT_90", detourRight90 = "DETOUR_RIGHT_90", backTrack = "BACK_TRACK"
    case north = "GO_N", northEast = "GO_NE", east = "GO_E", southEast = "GO_SE"
    case south = "GO_S", southWest = "GO_SW", west = "GO_W", northWest = "GO_NW"
    case rest = "REST"

    static let compass: [HuntAction] = [.north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest]
    static let detours: [HuntAction] = [.detourLeft45, .detourRight45, .detourLeft90, .detourRight90, .backTrack]
    var compassHeading: Double? { HuntAction.compass.firstIndex(of: self).map { Double($0) * 45 } }
    /// Degrees from the area's bearing, as M4a's detours are from the destination's.
    var areaOffset: Double? {
        switch self {
        case .toArea: return 0
        case .detourLeft45: return -45
        case .detourRight45: return 45
        case .detourLeft90: return -90
        case .detourRight90: return 90
        case .backTrack: return 180
        default: return nil
        }
    }
    var isWalk: Bool { compassHeading != nil || areaOffset != nil || self == .toCreature }

    var facts: String {
        let walk = "then selects the nearest enemy in front. Stops early if blocked or attacked."
        if let heading = compassHeading { return "Walks about 3 s on compass heading \(Int(heading))° (0 north, 90 east), \(walk)" }
        switch self {
        case .fight:
            return "Fights the selected creature to the end: pull, spells, melee, healing and looting, each chosen in its own decisions. Costs mana and usually health."
        case .nextTarget:
            return "Clears the selection, then selects the nearest enemy in front of the character, if one is within about 40 yards."
        case .lookAround:
            return "Turns a full circle in four 90° steps without moving, listing the creatures whose nameplates come into view with their compass bearings, then selects the nearest enemy in front."
        case .toCreature:
            return "Walks about 3 s towards the nearest creature in view that counts for an unfinished objective, \(walk)"
        case .toArea:
            return "Walks about 3 s towards the selected quest's area on the minimap, \(walk)"
        case .detourLeft45, .detourRight45, .detourLeft90, .detourRight90:
            let side = rawValue.contains("LEFT") ? "left" : "right", by = rawValue.hasSuffix("45") ? 45 : 90
            return "Walks about 3 s on a heading \(by)° \(side) of the selected quest's area, \(walk)"
        case .backTrack:
            return "Walks about 3 s directly away from the selected quest's area, \(walk)"
        case .rest:
            return "Stands still for 20 s to regain health and mana, about 40% of each. A fight can start only at 90% health or more. Ends early if something attacks."
        default:
            return ""
        }
    }
}

/// The creature GO_TO_QUEST_CREATURE heads for: one that counts, nearest first, then nearest the facing.
func questCreature(_ o: HuntObs) -> Seen? {
    o.seen.filter { counts($0, o.objectives) != nil }
        .min { ($0.near ? 0 : 1, abs(angleError($0.bearing, o.facing ?? 0))) < ($1.near ? 0 : 1, abs(angleError($1.bearing, o.facing ?? 0))) }
}

/// Local rules only: what is possible, safe to start, or pointless to repeat. In combat the only choice
/// is to fight back. A fight starts on a creature that counts, at M3's start health and 60% mana, and
/// not while another hostile creature is near (live hunt 5 died to a Roiling Wind that joined a
/// Convert fight). Below 60% health the character rests before walking on. Walks need a
/// readable position, stay within maxMoves, and never head within 25° of a heading blocked near here.
/// Outside the selected area the walks are M4a's, relative to the area's bearing: offered compass
/// headings, the real Jev backed away from a ridge instead of following it. Inside, the walks are
/// compass headings and the way to a creature that counts. NEXT_TARGET right after a walk or a look
/// would select the same creature: both end with a Tab.
func huntAdmissible(_ o: HuntObs, steps: [HuntStep] = [], blocked: [Double] = []) -> [HuntAction] {
    // Attacked with nothing alive selected: the attacker may be behind, where Tab never reaches (live hunt
    // 9 died to a Roiling Wind at the edge of the view), so LOOK_AROUND turns and Tabs; FIGHT can heal.
    if o.combat { return o.targetAlive ? [.fight] : [.lookAround, .fight] }
    let last = steps.last?.action
    let open = { (heading: Double) in !blocked.contains { abs(angleError($0, heading)) < NavLimits.headingTolerance } }
    let repeated = { (action: HuntAction) in
        steps.count >= HuntLimits.repeatCap && steps.suffix(HuntLimits.repeatCap).allSatisfy { $0.action == action }
    }
    var out: [HuntAction] = []
    var others = o.seen.filter { $0.hostile && $0.near }
    if let target = o.target, let i = others.firstIndex(where: { nameKey($0.name) == nameKey(target) }) { others.remove(at: i) }
    if o.targetAlive && o.player >= FightLimits.startHealth && o.mana >= HuntLimits.fightMana && others.isEmpty
        && objective(for: o.target, in: o.objectives) != nil {
        out.append(.fight)
    }
    if !(last.map { $0.isWalk || $0 == .lookAround || $0 == .nextTarget } ?? false) { out.append(.nextTarget) }
    if last != .lookAround { out.append(.lookAround) }
    if o.here != nil && o.player >= HuntLimits.walkHealth && steps.filter({ $0.action.isWalk }).count < HuntLimits.maxMoves {
        if let c = questCreature(o), open(c.bearing) { out.append(.toCreature) }
        if let a = o.area, !a.inside {
            out += ([.toArea] + HuntAction.detours).filter { open(a.bearing + $0.areaOffset!) && ($0 == .toArea || !repeated($0)) }
        } else {
            out += HuntAction.compass.filter { open($0.compassHeading!) && !repeated($0) }
        }
    }
    if o.player < HuntLimits.restHealth || o.mana < HuntLimits.restMana { out.append(.rest) }
    return out
}

struct HuntStep {
    var action: HuntAction
    var result: String
    var json: [String: Any] { ["action": action.rawValue, "result": result] }
}

let huntInstructions = "Which action most safely advances the unfinished `objectives`, given `selected_quest_area`, `creatures_in_view`, `blocked_headings_near_here`, `character`, `target` and `recent_actions`?"

func huntStatePacket(_ o: HuntObs, recent: [HuntStep], fights: [String], blocked: [Double]) -> [String: Any] {
    var target: [String: Any] = ["selected": o.target != nil]
    if let name = o.target {
        target["name"] = name
        target["alive"] = o.targetAlive
        target["counts_for_objective"] = objective(for: name, in: o.objectives)?.text ?? "none"
    }
    var area: [String: Any] = ["on_minimap": o.area != nil]
    if let a = o.area {
        area["character_inside"] = a.inside
        area["distance"] = roundTo(a.distance)
        area["bearing_deg"] = Int(a.bearing.rounded())
    }
    var character: [String: Any] = ["health_percent": Int(o.player * 100), "mana_percent": Int(o.mana * 100), "in_combat": o.combat,
                                    "can_start_a_fight": o.player >= FightLimits.startHealth && o.mana >= HuntLimits.fightMana]
    if let facing = o.facing { character["facing_deg"] = Int(facing.rounded()) }
    if let here = o.here { character["position"] = ["x": here.x, "y": here.y] }
    return [
        "goal": "Complete the unfinished quest objectives by defeating the creatures they name: quests are how this character levels up. Only a creature named in an unfinished objective counts, and those creatures are found inside the selected quest's area on the minimap. Choose where to go from what is known: whether the character is inside that area, which creatures are in view (a hostile creature attacks when approached, and several near each other are dangerous to fight at once), and which headings were blocked here. A fight starts only at 90% health and 60% mana or more, with no other hostile creature near; below 60% health the character rests before walking on. The character must stay alive. The owner is supervising.",
        "objectives": o.objectives.filter(\.unfinished).map {
            ["quest": $0.quest, "objective": $0.text, "progress": "\($0.done)/\($0.need)"]
        },
        "character": character,
        "target": target,
        "selected_quest_area": area,
        "creatures_in_view": o.seen.map {
            ["name": $0.name, "hostile": $0.hostile, "near": $0.near, "bearing_deg": Int($0.bearing.rounded()),
             "counts_for_objective": counts($0, o.objectives)?.text ?? "none"] as [String: Any]
        },
        "hostile_creatures_near": o.seen.filter { $0.hostile && $0.near }.count,
        "blocked_headings_near_here": blocked.map { Int($0.rounded()) },
        "recent_actions": recent.suffix(HuntLimits.recent).map(\.json),
        "fights_so_far": fights,
        "units": "positions are zone-map percent (one x unit is 1.5 y units); walks cover about 0.6 y units; headings are compass degrees, 0 north, 90 east",
    ]
}

/// What a hunt needs from the world: SimHunt offline, the WoW window live. A hunt walks as M4a does, so
/// its host is a NavBody: `look` reads position and facing for the walk skill.
protocol HuntHost: NavBody {
    func survey() -> HuntObs?  // everything, OCR included; nil when the tracker is unreadable
    func vitals() -> HuntObs  // pixels only (no OCR), for polling and aiming
    func fight(jev: JevClient, inCombat: Bool) async -> FightResult
}

func tap(_ host: HuntHost, _ code: UInt16) async {
    guard host.keys.press(code) else { return }
    await host.sleep(HuntLimits.tap)
    host.keys.lift(code)
    await host.sleep(HuntLimits.settle)
}

/// Tab does not move off a selected creature, and Esc with nothing selected opens the Game Menu. So Esc
/// only while something is selected, close a Game Menu that opened anyway, then Tab.
func selectNearest(_ host: HuntHost) async -> String {
    if host.survey()?.target != nil { await tap(host, HuntLimits.escape) }
    if host.survey()?.gameMenu == true { await tap(host, HuntLimits.escape) }
    await tap(host, FightLimits.tab)
    guard let o = host.survey() else { return "the tracker was unreadable after Tab" }
    guard let name = o.target else { return "no enemy in range in front" }
    if let counted = objective(for: name, in: o.objectives) { return "selected \(name), which counts for \"\(counted.text)\"" }
    return "selected \(name), which counts for no unfinished objective"
}

/// Stands still, polling vitals, until `seconds` pass, an attack or the owner. Low health is what a
/// rest is for: live hunt 7 began at 23% and a rest that stopped for it never started.
func rest(_ host: HuntHost, seconds: Double) async -> String {
    let began = host.now()
    while host.now() - began < seconds {
        await host.sleep(HuntLimits.tick)
        if host.vitals().combat { return "attacked after \(Int(host.now() - began)) s" }
        if host.ownerTookFocus() { return "stopped after \(Int(host.now() - began)) s" }
    }
    return "rested \(Int(seconds)) s"
}

/// One M4a walk (steering, block detection, safety stops) on a fixed heading, then a Tab. W is lifted:
/// Jev's next decision is not made on the run.
func walkOn(_ host: HuntHost, heading: Double, episode: inout NavEpisode) async -> String {
    guard let start = host.look() else { return "position unreadable; did not walk" }
    let heading = (heading + 360).truncatingRemainder(dividingBy: 360)
    let h = heading * .pi / 180
    let far = NavDestination(label: "heading \(Int(heading))", x: start.x + 10 * sin(h) / mapAspect, y: start.y - 10 * cos(h))
    let attempt = await walk(host, .goToward, from: start, to: far)
    host.keys.lift(FightLimits.forward)
    episode.record(attempt)
    let how = attempt.blocked ? "blocked on heading \(Int(heading.rounded()))° after moving \(roundTo(attempt.moved))"
        : "moved \(roundTo(attempt.moved)) on heading \(Int(heading.rounded()))°"
    return how + "; " + (await selectNearest(host))
}

/// Four 90° turns to the right, surveying the plates at each; the facing ends where it began. In combat
/// each step also Tabs, and the look ends on the first living creature selected: the attacker.
func lookAround(_ host: HuntHost) async -> (result: String, seen: [Seen]) {
    var seen: [Seen] = []
    for step in 0..<4 {
        if let o = host.survey() { seen = merged(seen, o.seen) }
        if host.vitals().combat {
            let tabbed = await selectNearest(host)
            if host.survey()?.targetAlive == true { return ("attacked; turned \(step * 90)° and " + tabbed, seen) }
        }
        guard host.keys.press(FightLimits.turnRight) else { return ("keys released", seen) }
        await host.sleep(HuntLimits.lookSeconds)
        host.keys.lift(FightLimits.turnRight)
        await host.sleep(HuntLimits.tick)
        if step == 3 { break }
    }
    let hostile = seen.filter(\.hostile).count
    return ("saw \(seen.count) creatures, \(hostile) hostile; " + (await selectNearest(host)), seen)
}

struct HuntResult {
    var outcome = "DECISION_LIMIT"
    var decisions = 0
    var latencies: [Double] = []
    var records: [[String: Any]] = []
    var steps: [HuntStep] = []
    var fights: [FightResult] = []
    var walks = NavEpisode()
    var start: [Objective] = []
    var end: [Objective] = []
    var holding = false
    var codesPosted: [UInt16] = []
}

func runHunt(host: HuntHost, jev: JevClient) async -> HuntResult {
    var r = HuntResult()
    let began = host.now()
    var misses = 0, sinceFight = 0
    var panorama: (at: NavObs, seen: [Seen])?

    func finish(_ outcome: String) -> HuntResult {
        host.keys.releaseAll()
        r.outcome = outcome
        r.holding = host.keys.holding
        r.codesPosted = host.keys.codesPosted
        return r
    }

    guard let first = host.survey() else { return finish("HUD_UNREADABLE") }
    r.start = first.objectives
    let wanted = first.objectives.filter(\.unfinished)
    if wanted.isEmpty { return finish("NO_UNFINISHED_OBJECTIVE") }

    while r.decisions < HuntLimits.maxDecisions {
        if host.now() - began >= HuntLimits.maxSeconds { return finish("TIME_LIMIT") }
        if host.ownerTookFocus() { return finish("OWNER_TOOK_FOCUS") }
        guard var o = host.survey() else {
            misses += 1
            if misses >= HuntLimits.unreadableLimit { return finish("HUD_UNREADABLE") }
            await host.sleep(HuntLimits.settle)
            continue
        }
        misses = 0
        r.end = o.objectives
        if o.player < 0.01 && !o.combat { return finish("DEAD") }  // an empty health bar out of combat
        if remaining(wanted, in: o.objectives).isEmpty { return finish("OBJECTIVES_COMPLETE") }
        if !o.combat && r.fights.count >= HuntLimits.maxFights { return finish("FIGHT_LIMIT") }
        if !o.combat && sinceFight >= HuntLimits.searchLimit { return finish("NO_TARGET_FOUND") }
        if let p = panorama, let here = o.here, distance(p.at.point, here.point) <= HuntLimits.panoramaFor {
            o.seen = merged(p.seen, o.seen)
        }
        let blocked = o.here.map { r.walks.blockedHeadings(near: $0) } ?? []

        let allowed = huntAdmissible(o, steps: r.steps, blocked: blocked)
        let state = huntStatePacket(o, recent: r.steps, fights: r.fights.map(\.outcome), blocked: blocked)
        let question = actionQuestion(allowed, instructions: huntInstructions)
        let asked = host.now()
        let reply: [String: Any]
        do {
            reply = try await jev.ask(state: state, question: question)
        } catch {
            host.emit("jev_error", ["error": "\(error)"])
            return finish("JEV_FAILED")
        }
        r.latencies.append(host.now() - asked)
        r.decisions += 1
        let record: [String: Any] = ["decision": r.decisions, "t": asked, "state": state, "question": question,
                                     "admissible": allowed.map(\.rawValue), "response": reply]
        r.records.append(record)
        host.emit("decision", record)
        guard let choice = parseChoice(reply, admissible: allowed, model: FightLimits.model) else {
            return finish("INVALID_REPLY")
        }

        var result: String
        sinceFight += 1
        switch choice.action {
        case .fight:
            let fight = await host.fight(jev: jev, inCombat: o.combat)
            r.fights.append(fight)
            sinceFight = 0
            result = "the fight ended \(fight.outcome) after \(fight.decisions) decisions"
            if !HuntLimits.continueAfter.contains(fight.outcome) {
                r.steps.append(HuntStep(action: .fight, result: result))
                return finish("FIGHT_" + fight.outcome)
            }
        case .nextTarget:
            result = await selectNearest(host)
        case .lookAround:
            let look = await lookAround(host)
            result = look.result
            if let here = host.look() { panorama = (here, look.seen) }
        case .rest:
            result = await rest(host, seconds: HuntLimits.restSeconds)
        case .toCreature:
            let heading = questCreature(o)?.bearing
            result = heading == nil ? "nothing to walk to" : await walkOn(host, heading: heading!, episode: &r.walks)
        case _ where choice.action.areaOffset != nil:
            let heading = o.area.map { $0.bearing + choice.action.areaOffset! }
            result = heading == nil ? "no area to walk by" : await walkOn(host, heading: heading!, episode: &r.walks)
        default:
            result = await walkOn(host, heading: choice.action.compassHeading ?? 0, episode: &r.walks)
        }
        r.steps.append(HuntStep(action: choice.action, result: result))
        host.emit("acted", ["action": choice.action.rawValue, "result": result])
    }
    return finish("DECISION_LIMIT")
}

/// Deterministic field for tests and the dry-run, on SimNav's zone map: its walls block, W runs and Q/E
/// turn as there, and Tab/Esc arrive through its pad. Tab selects the nearest living creature within
/// 1.2 units (about 40 yards) and 45° of the facing; Esc clears a selection or else toggles the Game
/// Menu; plates show within 1.2 units and 45° (near within 0.7); a hostile creature within 0.25 attacks.
/// The selected quest's area is a circle, on the minimap within 5 units. A fight is not simulated: it
/// kills the selected creature and costs health and mana, or ends as `fightOutcome` says.
final class SimHunt: HuntHost {
    struct Mob {
        var name: String
        var x: Double
        var y: Double
        var hostile = true
        var alive = true
        var point: MapPoint { (x, y) }
    }

    let world: SimNav
    var mobs: [Mob]
    var area: (x: Double, y: Double, radius: Double)?
    var objectives: [Objective]
    var mana = 1.0
    var selected: Int?
    var gameMenu = false
    var fightOutcome = "KILLED_AND_LOOTED"
    var fightsRun = 0
    var surveyBlind = false

    init(world: SimNav, mobs: [Mob], objectives: [Objective]) {
        self.world = world
        self.mobs = mobs
        self.objectives = objectives
        world.pad.onDown = { [unowned self] code in
            if code == FightLimits.tab { self.selected = self.nearest() }
            if code == HuntLimits.escape {
                if self.gameMenu { self.gameMenu = false } else if self.selected != nil { self.selected = nil } else { self.gameMenu = true }
            }
        }
    }

    var keys: LiveKeys { world.keys }
    var clock: FightClock { world.clock }
    func now() -> Double { world.now() }
    func emit(_ event: String, _ fields: [String: Any]) { world.emit(event, fields) }
    func ownerTookFocus() -> Bool { world.ownerTookFocus() }
    func look() -> NavObs? { world.look() }

    private func inView(_ m: Mob, within reach: Double) -> Bool {
        let here: MapPoint = (world.x, world.y)
        return m.alive && distance(here, m.point) <= reach && abs(angleError(bearing(from: here, to: m.point), world.facing)) <= 45
    }

    private func nearest() -> Int? {
        let here: MapPoint = (world.x, world.y)
        return mobs.indices.filter { inView(mobs[$0], within: 1.2) }.min { distance(here, mobs[$0].point) < distance(here, mobs[$1].point) }
    }

    /// Integrates the walk, then lets a hostile creature within 0.25 units attack; rest regains 2 % a second.
    func sleep(_ seconds: Double) async {
        await world.sleep(seconds)
        let here: MapPoint = (world.x, world.y)
        if !world.combat, mobs.contains(where: { $0.alive && $0.hostile && distance(here, $0.point) <= 0.25 }) {
            world.combat = true  // as in WoW, an attacker is not selected for you
        }
        if !world.combat {
            world.player = min(1, world.player + 0.02 * seconds)
            mana = min(1, mana + 0.02 * seconds)
        }
    }

    func vitals() -> HuntObs {
        var o = HuntObs(player: world.player, mana: mana, combat: world.combat, facing: world.facing, here: world.look())
        if let a = area {
            let here: MapPoint = (world.x, world.y), centre: MapPoint = (a.x, a.y)
            let d = distance(here, centre)
            if d - a.radius <= 5 { o.area = QuestArea(bearing: bearing(from: here, to: centre), distance: d, inside: d < a.radius) }
        }
        return o
    }

    func survey() -> HuntObs? {
        guard !world.unreadable, !surveyBlind else { return nil }
        var o = vitals()
        o.objectives = objectives
        o.target = selected.map { mobs[$0].name }
        o.targetAlive = selected.map { mobs[$0].alive } ?? false
        o.gameMenu = gameMenu
        let here: MapPoint = (world.x, world.y)
        o.seen = mobs.filter { inView($0, within: 1.2) }.map {
            Seen(name: $0.name, hostile: $0.hostile, bearing: bearing(from: here, to: $0.point), near: distance(here, $0.point) <= 0.7)
        }
        return o
    }

    func fight(jev: JevClient, inCombat: Bool) async -> FightResult {
        fightsRun += 1
        clock.t += 30
        if selected == nil || !mobs[selected!].alive {  // nothing to fight: time passes, the attacker keeps hitting
            if world.combat { world.player = max(0, world.player - 0.3) }
            return FightResult(outcome: "JEV_STOP", decisions: 3, jevCalls: 3, latencies: [], episode: Episode(), walkedMs: 0,
                               turnedMs: 0, holdingKeys: false, codesPosted: [], jevRecords: [])
        }
        var outcome = fightOutcome
        if outcome == "KILLED_AND_LOOTED" {
            if let i = selected, mobs[i].alive {
                mobs[i].alive = false
                if let counted = objective(for: mobs[i].name, in: objectives),
                   let k = objectives.firstIndex(of: counted) { objectives[k].done += 1 }
                world.player = max(0, world.player - (mobs[i].hostile ? 0.3 : 0.2))
                mana = max(0, mana - 0.5)
                world.combat = false
            } else {
                outcome = "JEV_STOP"
            }
        }
        return FightResult(outcome: outcome, decisions: 8, jevCalls: 8, latencies: [], episode: Episode(), walkedMs: 0,
                           turnedMs: 0, holdingKeys: false, codesPosted: [], jevRecords: [])
    }

    static let agitators = [
        Objective(quest: "Agitators", done: 0, need: 7, text: "Al'Aketh Convert slain"),
        Objective(quest: "Agitators", done: 0, need: 6, text: "Roiling Winds destroyed"),
        Objective(quest: "Infestation Investigation", done: 5, need: 8, text: "Pesky Cirrusfly slain"),
    ]

    /// Near Yala, as live: the Agitators area lies north beyond a rocky ridge that is open at its east
    /// end; Roiling Winds and a Convert inside it, a neutral Vuldren to the south-west.
    static func field(clock: FightClock) -> SimHunt {
        let ridge = SimNav.Box(x0: 46.3, y0: 21.25, x1: 47.55, y1: 21.4)
        let world = SimNav(clock: clock, x: 47.3, y: 21.9, facing: 200, boxes: [ridge])
        let field = SimHunt(world: world, mobs: [
            Mob(name: "Juvenile Vuldren", x: 46.8, y: 22.3, hostile: false),
            Mob(name: "Roiling Winds", x: 47.2, y: 20.6),
            Mob(name: "Roiling Winds", x: 47.5, y: 20.2),
            Mob(name: "Al'Aketh Convert", x: 46.9, y: 20.3),
        ], objectives: agitators)
        field.area = (x: 47.2, y: 20.3, radius: 0.8)
        return field
    }
}
