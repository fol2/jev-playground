// M4b for issue #5: Jev chooses how to hunt for the creatures that quest objectives name. Pure core:
// the objectives tracker, the minimap's quest ring and the view's nameplates; the hunt's actions and
// their admissibility; the state packet; the skills (M4a walks, a look around, Tab); runHunt and
// SimHunt. Each fight is one M3 episode (runFight) on a fresh host; the live shell is HuntProbe.swift.
import Foundation

enum HuntLimits {
    static let maxDecisions = 40
    static let maxSeconds = 900.0
    static let stepLength = 1.5  // M4ad: y units a walking move steers on for, at most stepSeconds
    static let stepSeconds = 10.0
    static let pickUpSeconds = 15.0  // a right-click's walk, the gathering cast and the count (live run 86: 8.5 s of walk alone)
    static let placeRadius = 3.0  // y units: within this of a remembered pick-up place is inside its area (M4aj; run 86's and 89's were 3.3 apart)
    static let placesKept = 32  // remembered pick-up places per objective, the newest
    static let jevTimeout = 10.0  // a hunt decides out of combat; its fights keep M3's 4 s
    static let maxFights = 4
    static let searchLimit = 12  // hunt decisions in a row without a fight
    static let maxMoves = 24  // walks per hunt, each a steering walk of stepLength, stepSeconds at most (M4ad)
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
    // No mana gate for starting a fight: in the owner's recorded demo (23 Sept) 29 fights often began at
    // 10-30% mana, melee doing most of the damage. Jev weighs the costs, which the state carries.
    static let eatBelowHealth = 0.8, eatBelowMana = 0.5
    static var drink: UInt16 = 29, eat: UInt16 = 27  // 23 Sept defaults; live runs take them from the bar's tooltips
    static let eatSeconds = 20.0
    static let walkHealth = 0.6  // below this, rest before walking on
    // ponytail: an assumed horizontal field of view; calibrate from a plate's shift over a known turn.
    static let viewDegrees = 90.0
    static let nearRow = 0.35  // a plate lower in view than this fraction of its height is near (roughly 25 yards)
    static let panoramaFor = 0.6  // map units: a LOOK_AROUND is stale once the character is this far from it
    /// A walk that stopped at a red name this near its quest's pin (map units) offers its step FROM_HERE: see stepStartsNear.
    static let startNear = 3.0
    static let sameCreature = 20.0  // degrees: sightings of one name closer than this are one creature
    static let escape: UInt16 = 53
    static var releaseCodes: [UInt16] { [53, 48, 12, 13, 14, drink, eat, FightLimits.zoomOut, FightLimits.zoomIn] }
    static let continueAfter: Set<String> = ["KILLED_AND_LOOTED", "KILLED_NO_CORPSE", "JEV_STOP"]
}

struct Objective: Equatable {
    var quest: String
    var done: Int
    var need: Int
    var text: String
    var unfinished: Bool { done < need }
    /// A finished quest's tracker entry: its title, then "Ready for turn-in" where its objectives were
    /// (the owner's recorded demo, 23 Sept). Parsed as one finished pseudo-objective with this text.
    static let ready = "Ready for turn-in"
}

/// Reads the objectives tracker's OCR lines, top to bottom: "Agitators", "- 0/6 Roiling Winds destroyed".
/// A line with no count is a quest title. Upscale the crop first: at 1x, "0/6" reads as "Oyo".
/// "Ready for turn-in" counts only straight under a title: under an objective line it may belong to a
/// quest whose title OCR missed, and must not finish the quest above.
func parseTracker(_ lines: [String]) -> [Objective] {
    let count = try! NSRegularExpression(pattern: #"^\W*(\d{1,3})\s*/\s*(\d{1,3})\s+(\S.*)$"#)
    var quest = "", underTitle = false, out: [Objective] = []
    for raw in lines {
        // A title may carry its quest's level, "[1] Harmony in Balance" (live run 22, 26 Sept: the hunt read no objective),
        // and OCR reads its brackets as "1" and leads it with a marker (live run 38, 27 Sept: "12] Infestation Investigation",
        // "[41 Harvesting Windstones", "** [2] ...", "› [4] ..."; the hunt's quest changed its name, and its 3 kills to 7
        // counted for nothing). A finished quest's "?" icon reads as "3" or "?" (run 39: "3 12] Infestation Investigation").
        // Icons of one or two characters and the tag go; a count line is left as read.
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let counted = count.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
        let line = counted ? trimmed : trimmed
            .replacingOccurrences(of: #"^(?:[^\p{L}\s]{1,2}\s+)+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[\[(1lI|]?\d{1,2}[\])1lI|]\s+"#, with: "", options: .regularExpression)
        if let m = count.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let done = Int(line[Range(m.range(at: 1), in: line)!]), let need = Int(line[Range(m.range(at: 2), in: line)!]) {
            if !quest.isEmpty && need > 0 {
                out.append(Objective(quest: quest, done: done, need: need, text: String(line[Range(m.range(at: 3), in: line)!])))
            }
            underTitle = false
        } else if readyLine(line) {
            if underTitle { out.append(Objective(quest: quest, done: 1, need: 1, text: Objective.ready)) }
            underTitle = false
        } else if line.first?.isLetter == true && line.filter(\.isLetter).count >= 4 {
            quest = line
            underTitle = true
        }
    }
    return out
}

/// "Ready for turn-in" as the demo's OCR read it ("Ready for turn-", "adyfor turnien"), but not a
/// title that merely contains "for turn" ("Waiting for Turnips").
func readyLine(_ line: String) -> Bool {
    let key = nameKey(line)
    guard let r = key.range(of: "forturn") else { return false }
    return key.distance(from: key.startIndex, to: r.lowerBound) <= 5 && key.distance(from: r.upperBound, to: key.endIndex) <= 4
}

/// Letters only, lower case, with "i" read as "l": OCR reads "Al'Aketh" as "AI' Aketh".
func nameKey(_ text: String) -> String {
    String(text.lowercased().filter(\.isLetter).map { $0 == "i" ? "l" : $0 })
}

/// The unfinished objective a creature counts for: its name starts the objective's text, as
/// "Roiling Wind" starts "Roiling Winds destroyed". A partial-word match would let
/// "Yala Windwatcher" count for Roiling Winds; a target frame's misread name counts when most of it is there (mostlyIn).
// ponytail: irregular plurals ("Wolf" for "Wolves slain") never count.
func objective(for name: String?, in objectives: [Objective]) -> Objective? {
    guard let name, nameKey(name).count >= 4 else { return nil }
    return objectives.first { $0.unfinished && (nameKey($0.text).hasPrefix(nameKey(name)) || mostlyIn(name, $0.text)) }
}

/// Whether an objective is to collect things, not to defeat creatures: its text names no defeat ("Windstone Cluster", not
/// "Roiling Winds destroyed"). Only these count for an object picked up (review of #59).
func collects(_ o: Objective) -> Bool {
    let t = o.text.lowercased()
    return o.unfinished && !["slain", "destroyed", "killed", "defeated"].contains { t.hasSuffix($0) }
}

/// The collect objective an object's tooltip names. A unit's tooltip (a "Level" line) names none: the detector's box on a
/// creature that counts must not be right-clicked, which would start a fight outside the fight's admissibility (review of #59).
func objectTipObjective(_ lines: [String], in objectives: [Objective]) -> Objective? {
    guard !lines.contains(where: { nameKey($0).hasPrefix("level") }) else { return nil }  // "LeveI 3" too
    let collect = objectives.filter(collects)
    return lines.lazy.compactMap { objective(for: $0, in: collect) }.first
}

/// The object a hover confirms: two fresh tooltip reads at the hovered point, after the tooltip from before had gone, name one
/// collect objective and neither is a unit's. One read could still be a tooltip that had not yet given way (review of #59).
func confirmedObject(_ reads: [[String]], in objectives: [Objective]) -> Objective? {
    guard reads.count >= 2 else { return nil }
    let named = reads.suffix(2).map { objectTipObjective($0, in: objectives) }
    guard let first = named.first ?? nil, named.last ?? nil == first else { return nil }
    return first
}

/// The count a pick-up raised, found by the objective's own text. The quest's title can go unread while the tracker changes:
/// live run 86 read "5/15 Windstone Cluster" under the quest above it, and a pick-up that worked was recorded as failed.
func pickedUp(_ counted: Objective, in tracker: [Objective]) -> Objective? {
    tracker.first { nameKey($0.text) == nameKey(counted.text) && $0.done > counted.done }
}

/// The selected creature as a cue for revalidation: the objective it counts for, else its name's letters. The frame's
/// OCR reads one Juvenile Vuldren three ways ("Juvenile Vuldren 30s40", "luvenile Vuldren ЛОРAУ"), and each change
/// rejected the decision taken on it (live run 26, 26 Sept: target_cue_changed four times, no fight).
/// A creature that counts for nothing is cued by its name's Latin words only: the OCR tail is digits and Cyrillic look-alikes
/// that change every frame (live run 48, 27 Sept: "Pesky Cirrusfly Л Л4О", "Pesky Cirrusfiy 4 84О"; 6 of 12 decisions
/// were rejected target_cue_changed while the same Cirrusfly stayed selected).
func targetCue(_ name: String?, _ objectives: [Objective]) -> String? {
    name.map { name in
        objective(for: name, in: objectives)?.text
            ?? nameKey(name.split(separator: " ").filter { $0.allSatisfy { $0.isASCII && ($0.isLetter || $0 == "'") } }.joined(separator: " "))
    }
}

/// Whether most of a target frame's name is in an objective: at least 60% of its four-letter runs. The frame's font
/// loses a first letter and adds a stray tail (live run 25, 26 Sept: "luvenile Vuldren ЛОРAУ" and "Tuvenile Vuldren"
/// for Juvenile Vuldren, both taken for creatures that count for nothing), while another creature of one family
/// shares only its family word ("Vuldren Matriarch": 4 of 13 runs).
func mostlyIn(_ name: String, _ text: String) -> Bool {
    let n = Array(nameKey(name)), t = nameKey(text)
    guard n.count >= 6 else { return false }
    let runs = (0...(n.count - 4)).map { String(n[$0..<$0 + 4]) }
    return Double(runs.filter { t.contains($0) }.count) >= 0.6 * Double(runs.count)
}

/// The objectives in `wanted` not yet seen finished in `now`: finished is its own line read at done >= need,
/// or its quest's "Ready for turn-in" with no unfinished line under the same title (WoW never shows both,
/// so both is a misread). A line that has merely gone (an OCR miss, a collapsed tracker) stays remaining:
/// missing evidence is not a completion.
func remaining(_ wanted: [Objective], in now: [Objective]) -> [Objective] {
    wanted.filter { w in
        let quest = now.filter { nameKey($0.quest) == nameKey(w.quest) }
        let ready = quest.contains { $0.text == Objective.ready } && !quest.contains(where: \.unfinished)
        return !ready && !quest.contains { nameKey($0.text) == nameKey(w.text) && !$0.unfinished }
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
    // The owner's UI (23 Sept evening): plates are a fixed ~186x15 px at any distance, so a run much
    // shorter or longer is terrain or a body, not a plate.
    static let minRun = 120, width = 130...240, height = 10...20, bridge = 3
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

/// A hostile creature's name drawn without a plate: red text with a dark outline. The owner's UI shows
/// these beyond plate range (a plate's name is white), so one ahead is danger not yet reached. The owner,
/// 24 Sept: "the time you see plate means they are already in your danger zone". Capture pixels.
struct RedName: Equatable {
    var x0: Int, x1: Int, y0: Int, y1: Int
    var centre: Double { Double(x0 + x1) / 2 }
}

enum RedNameScan {
    static let cell = 8, hot = 4, bridge = 2  // cells with 4 red pixels; letters up to 2 cells apart join
    static let width = 24...360, maxHeight = 32, minPixels = 40
    static let maxFill = 0.5, solid = 0.85, maxSolidRows = 2  // a plate bar is solid; text is strokes
    static let maxMeanRun = 6.0, maxTextRows = 16, outline = 0.85, reach = 2
    static func red(_ r: Int, _ g: Int, _ b: Int) -> Bool { r >= 100 && r - g >= 55 && r - b >= 55 && g - b <= r / 6 && b - g <= 25 }
    static func dark(_ r: Int, _ g: Int, _ b: Int) -> Bool { r + g + b < 135 }
}

/// Every red name in the game view: cells of red whose green stays near its blue (orange wings and the
/// Juvenile Vuldren's red-brown fur have green well above blue) joined along a line, thin, made of short
/// strokes, nearly every red pixel within 2 px of the dark outline. Replayed on 975 saved frames: README M4h.
/// The red names that can be a hostile creature's: a hostile's name is drawn red only beyond plate range, so a red "name"
/// just under a neutral (yellow) plate is that creature's own red-brown body. Live runs 35 and 44 (27 Sept): walks to
/// quest places stopped DANGER_AHEAD at a level-1 Juvenile Vuldren, its body 59 px under its plate and up to 25 px right
/// of its end. A candidate whose centre lies within `margin` of a neutral plate's span and up to `below` px under it is
/// dropped; the review of #54 narrowed both (from 60 and 160), so a hostile name under another creature's plate stays.
func dangerNames(_ names: [RedName], plates: [PlateBar], margin: Double = 30, below: Int = 80) -> [RedName] {
    names.filter { n in
        !plates.contains { p in
            !p.hostile && n.centre >= Double(p.x0) - margin && n.centre <= Double(p.x1) + margin && n.y0 > p.y1 && n.y0 - p.y1 <= below
        }
    }
}

func redNames(_ image: RGBA) -> [RedName] {
    let w = image.width, h = image.height, s = RedNameScan.self
    guard image.pixels.count == w * h * 4 else { return [] }
    let top = Int(PlateScan.rows.lowerBound * Double(h)), rows = Int(PlateScan.rows.upperBound * Double(h)) - top
    let cols = Int(PlateScan.columns * Double(w)), cw = cols / s.cell, ch = rows / s.cell
    return image.pixels.withUnsafeBufferPointer { p -> [RedName] in
        func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = ((y + top) * w + x) * 4
            return (Int(p[i]), Int(p[i + 1]), Int(p[i + 2]))
        }
        var mask = [Bool](repeating: false, count: rows * cols)
        var count = [Int](repeating: 0, count: cw * ch)
        for y in 0..<ch * s.cell {
            for x in 0..<cw * s.cell {
                let (r, g, b) = px(x, y)
                if s.red(r, g, b) { mask[y * cols + x] = true; count[(y / s.cell) * cw + x / s.cell] += 1 }
            }
        }
        var seen = [Bool](repeating: false, count: cw * ch)
        var names: [RedName] = []
        for start in 0..<cw * ch where count[start] >= s.hot && !seen[start] {
            var stack = [start], cells: [Int] = []
            seen[start] = true
            while let c = stack.popLast() {
                cells.append(c)
                for dy in -1...1 {
                    for dx in -s.bridge...s.bridge {
                        let cy = c / cw + dy, cx = c % cw + dx, n = cy * cw + cx
                        if cy >= 0, cy < ch, cx >= 0, cx < cw, count[n] >= s.hot, !seen[n] { seen[n] = true; stack.append(n) }
                    }
                }
            }
            let x0 = cells.map { $0 % cw }.min()! * s.cell, x1 = (cells.map { $0 % cw }.max()! + 1) * s.cell
            let y0 = cells.map { $0 / cw }.min()! * s.cell, y1 = (cells.map { $0 / cw }.max()! + 1) * s.cell
            guard s.width.contains(x1 - x0), y1 - y0 <= s.maxHeight else { continue }
            var n = 0, solidRows = 0, runs = 0, first = Int.max, last = -1, outlined = 0
            for y in y0..<y1 {
                var inRow = 0, run = 0
                for x in x0..<x1 {
                    if mask[y * cols + x] {
                        inRow += 1; run += 1
                        let near = (max(0, y - s.reach)...min(rows - 1, y + s.reach)).contains { yy in
                            (max(0, x - s.reach)...min(cols - 1, x + s.reach)).contains { xx in let (r, g, b) = px(xx, yy); return s.dark(r, g, b) }
                        }
                        if near { outlined += 1 }
                    } else if run > 0 { runs += 1; run = 0 }
                }
                if run > 0 { runs += 1 }
                if inRow > 0 { first = min(first, y); last = y }
                if Double(inRow) >= s.solid * Double(x1 - x0) { solidRows += 1 }
                n += inRow
            }
            guard n >= s.minPixels, Double(n) <= s.maxFill * Double((x1 - x0) * (y1 - y0)), solidRows <= s.maxSolidRows,
                  Double(n) / Double(runs) <= s.maxMeanRun, last - first + 1 <= s.maxTextRows,
                  Double(outlined) >= s.outline * Double(n) else { continue }
            names.append(RedName(x0: x0, x1: x1, y0: y0 + top, y1: y1 + top))
        }
        return names
    }
}

/// The compass bearing of a point in the game view: the facing plus its angle off the view's centre.
func viewBearing(_ x: Double, facing: Double, width: Int) -> Double {
    (facing + (x / Double(width) - 0.5) * HuntLimits.viewDegrees + 360).truncatingRemainder(dividingBy: 360)
}

/// The walk's warnings (M4h): the compass bearings of the red names left as danger and of every hostile (red) plate in
/// view. The owner, 24 Sept: "the time you see plate means they are already in your danger zone". Live run 67 (27 Sept)
/// walked five seconds towards a Roiling Winds whose hostile plate stood nearly straight ahead, read no red name (a plate's
/// name is white), and met it in combat; the owner: red names and plates in view should stop the normal walk.
func walkWarnings(danger: [RedName], plates: [PlateBar], facing: Double, width: Int) -> [Double] {
    (danger.map(\.centre) + plates.filter(\.hostile).map(\.centre)).map { viewBearing($0, facing: facing, width: width) }
}

/// A creature whose nameplate was in view: its name, colour, compass bearing (facing plus the plate's
/// angle off the view's centre) and whether it stood low in view, which means near.
struct Seen: Equatable {
    var name: String
    var hostile: Bool
    var bearing: Double
    var near: Bool
}

/// An object on the ground the object detector (M5, ObjectReader) sees: its centre on screen and the detector's
/// confidence. Which object it is, only a hover's tooltip says (PICK_UP_OBJECT).
struct SeenObject: Equatable {
    var x: Double
    var y: Double
    var confidence: Double
}

func sighting(_ bar: PlateBar, name: String, facing: Double, width: Int, height: Int) -> Seen {
    return Seen(name: name, hostile: bar.hostile, bearing: viewBearing(bar.centre, facing: facing, width: width),
                near: Double(bar.y0) / Double(height) > HuntLimits.nearRow)
}

/// Sightings with one name and nearly one bearing are one creature; the newer one wins.
func merged(_ older: [Seen], _ newer: [Seen]) -> [Seen] {
    older.filter { o in !newer.contains { $0.name == o.name && abs(angleError($0.bearing, o.bearing)) < HuntLimits.sameCreature } } + newer
}

/// The unfinished objective a sighted creature counts for. Plate names are read small, so two shared
/// 4-letter runs suffice ("Rolling WWinds" is a Roiling Wind). For a kill objective each word of four letters or more in
/// its creature name must share one too: "Pesky Cirrusfly" shares "Cirrusfly" with "Cirrusfly Queen slain" but not "Queen"
/// (live run 48, 27 Sept: the Queen's hunt read every Pesky Cirrusfly as counting and walked toward them). A collect
/// objective names an item its creature drops ("Scrawny Ursera Claw"), so its words are not all on the plate (review of #60);
/// a whole word of the plate must be one of its words instead (M4ae: shared letters made Roiling Winds count for Windstones).
func counts(_ creature: Seen, _ objectives: [Objective]) -> Objective? {
    let plate = nameKey(creature.name)
    return objectives.first { o in
        guard o.unfinished, fuzzyNameMatch(o.text, [creature.name]) else { return false }
        var words = o.text.split(separator: " ").map { Array(nameKey(String($0))) }
        guard let last = words.last, ["slaln", "destroyed", "kllled", "defeated"].contains(String(last)) else {
            // Something to collect counts a creature that drops it: a whole word of its name is a word of the objective
            // ("Scrawny Ursera" for "Scrawny Ursera Claw"), or two of its words read apart ("Urs'anah" for "Head of Urs anah").
            // Shared letters are not a drop: live run 85 fought four Roiling Winds for "Windstone Cluster".
            let named = Set(words.map { String($0) } + zip(words, words.dropFirst()).map { String($0 + $1) })
            return creature.name.split(separator: " ").contains { let w = nameKey(String($0)); return w.count >= 4 && named.contains(w) }
        }
        words.removeLast()
        return words.filter { $0.count >= 4 }.allSatisfy { w in (0...(w.count - 4)).contains { plate.contains(String(w[$0..<$0 + 4])) } }
    }
}

struct HuntObs: Equatable {
    var stamp: ObservationStamp? = nil
    var objectives: [Objective] = []
    var player = 1.0
    var mana = 1.0
    var combat = false
    var target: String? = nil  // the target frame's name; nil when nothing is selected
    var targetAlive = false
    var targetInRange: Bool? = nil  // Lightning Bolt's key digit not red: the selected creature is within 30 yards; nil: unread
    var gameMenu = false
    var facing: Double? = nil  // the minimap arrow
    var area: QuestArea? = nil
    var areaRemembered = false  // the area is a remembered pick-up place, not the minimap's ring (M4aj)
    var here: NavObs? = nil  // coordinates and facing, as a walk reads them
    var seen: [Seen] = []  // this view's plates, plus a fresh LOOK_AROUND's
    var objects: [SeenObject] = []  // objects on the ground in view (M5); none without the detector's model
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
    case eatDrink = "EAT_DRINK"
    case pickUp = "PICK_UP_OBJECT"

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
        let steps = "Walks up to \(HuntLimits.stepLength) y units (\(Int(HuntLimits.stepSeconds)) s at most), steering round what it meets,"
        if let heading = compassHeading { return "\(steps) on compass heading \(Int(heading))° (0 north, 90 east), \(walk)" }
        switch self {
        case .fight:
            return "Fights the selected creature to the end: pull, spells, melee, healing and looting, each chosen in its own decisions. Costs mana and usually health."
        case .nextTarget:
            return "Clears the selection, then selects the nearest enemy in front of the character, if one is within about 40 yards."
        case .lookAround:
            return "Turns a full circle in four 90° steps without moving, listing the creatures whose nameplates come into view with their compass bearings, then selects the nearest enemy in front."
        case .toCreature:
            return "\(steps) towards the nearest creature in view that counts for an unfinished objective, \(walk)"
        case .toArea:
            return "\(steps) towards the selected quest's area on the minimap, \(walk)"
        case .detourLeft45, .detourRight45, .detourLeft90, .detourRight90:
            let side = rawValue.contains("LEFT") ? "left" : "right", by = rawValue.hasSuffix("45") ? 45 : 90
            return "\(steps) on a heading \(by)° \(side) of the selected quest's area, \(walk)"
        case .backTrack:
            return "\(steps) directly away from the selected quest's area, \(walk)"
        case .rest:
            return "Stands still for 20 s to regain health and mana, about 40% of each. A fight can start only at 90% health or more. Ends early if something attacks."
        case .eatDrink:
            return "Sits to drink water and eat bread for 20 s: restores health and mana to full, far faster than standing. Only out of combat; ends early if something attacks, and standing up stops it."
        case .pickUp:
            return "Rests the pointer on the nearest object on the ground in view. Only if the game's tooltip names an unfinished objective, right-clicks it: the character walks to it and picks it up, \(Int(HuntLimits.pickUpSeconds)) s at most. Stops early if attacked."
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
/// is to fight back. A fight starts on a creature that counts, at M3's start health (mana is Jev's call), and
/// not while another hostile creature is near (live hunt 5 died to a Roiling Wind that joined a
/// Convert fight). Below 60% health the character rests before walking on. Walks need a
/// readable position, stay within maxMoves, and never head within 25° of a heading blocked near here.
/// Outside the selected area the walks are M4a's, relative to the area's bearing: offered compass
/// headings, the real Jev backed away from a ridge instead of following it. Inside, the walks are
/// compass headings and the way to a creature that counts. NEXT_TARGET right after a walk or a look
/// would select the same creature: both end with a Tab.
/// What ends a hunt with a position read and nothing admissible: its walks spent, else nothing to do here. Live run 37,
/// 27 Sept: after 24 walks and three fights LOOK_AROUND was the last step, the empty request was refused, and the hunt
/// ended HUD_UNREADABLE on a readable frame.
func emptyHuntEnd(_ steps: [HuntStep]) -> String {
    steps.filter { $0.action.isWalk }.count >= HuntLimits.maxMoves ? "MOVE_LIMIT" : "NO_ADMISSIBLE_SKILL"
}

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
    if o.targetAlive && o.player >= FightLimits.startHealth && others.isEmpty
        && objective(for: o.target, in: o.objectives) != nil {
        out.append(.fight)
    }
    if !(last.map { $0.isWalk || $0 == .lookAround || $0 == .nextTarget } ?? false) { out.append(.nextTarget) }
    // Out of combat the hunt finds creatures by walking on (Tab and the plates see what is ahead), not by turning round on the
    // spot (the owner, 27 Sept: "don't stuck and 360 screen"); LOOK_AROUND is for an attacker behind, in combat, above.
    // An object on the ground in view while a collect objective is open (M5): the pointer rests on it, and it is right-clicked
    // only if its tooltip names that objective. Not after two that picked nothing up since the last walk: a Tab or a look
    // around does not make a false object worth hovering again (review of #59).
    let empty = steps.reversed().prefix { !$0.action.isWalk }.filter { $0.action == .pickUp && !$0.result.hasPrefix("picked up") }.count >= 2
    if !o.objects.isEmpty && o.objectives.contains(where: collects) && o.player >= HuntLimits.walkHealth && !empty {
        out.append(.pickUp)
    }
    if o.here != nil && o.player >= HuntLimits.walkHealth && steps.filter({ $0.action.isWalk }).count < HuntLimits.maxMoves {
        if let c = questCreature(o), open(c.bearing) { out.append(.toCreature) }
        if let a = o.area, !a.inside {
            out += ([.toArea] + HuntAction.detours).filter { open(a.bearing + $0.areaOffset!) && ($0 == .toArea || !repeated($0)) }
        } else {
            out += HuntAction.compass.filter { open($0.compassHeading!) && !repeated($0) }
        }
    }
    if o.player < HuntLimits.restHealth || o.mana < HuntLimits.restMana { out.append(.rest) }
    if o.player < HuntLimits.eatBelowHealth || o.mana < HuntLimits.eatBelowMana { out.append(.eatDrink) }
    return out
}

struct HuntStep {
    var action: HuntAction
    var result: String
    var json: [String: Any] { ["action": action.rawValue, "result": result] }
}

private struct PendingHuntExperience {
    let id: String
    let action: String
    let before: ExperienceFrame
    let reported: String
    let blocked: Bool?
    let elapsed: Double
}

private func experienceBand(_ value: Double, _ cuts: (Double, Double, Double)) -> String {
    value < cuts.0 ? "critical" : (value < cuts.1 ? "low" : (value < cuts.2 ? "medium" : "high"))
}

/// Small, observable situation buckets for retrieval. This is deliberately not a world model.
func huntExperienceFrame(_ o: HuntObs, blocked: [Double]) -> ExperienceFrame? {
    guard let stamp = o.stamp else { return nil }
    let targetKind: String
    if let target = o.target, o.targetAlive {
        targetKind = objective(for: target, in: o.objectives) == nil ? "other_alive" : "objective_alive"
    } else { targetKind = o.target == nil ? "none" : "not_alive" }
    let place = o.here.map { "\(Int(floor($0.x / 2))):\(Int(floor($0.y / 2)))" } ?? "unknown"
    let near = o.seen.filter { $0.hostile && $0.near }.count
    let objectives = o.objectives.filter(\.unfinished).map { nameKey($0.text) }.sorted().joined(separator: "|")
    let context: [String: String] = [
        "phase": o.combat ? "combat" : (o.player < HuntLimits.walkHealth ? "recover" : "hunt"),
        "health": experienceBand(o.player, (0.35, 0.60, 0.90)),
        "mana": experienceBand(o.mana, (0.20, 0.50, 0.80)),
        "target": targetKind,
        "target_name": o.target.map(nameKey) ?? "none",
        "quest_area": o.area.map { $0.inside ? "inside" : "outside" } ?? "unknown",
        "near_hostiles": near == 0 ? "0" : (near == 1 ? "1" : "many"),
        "blocked_near": blocked.isEmpty ? "0" : "some",
        "place_cell_2": place,
        "unfinished_objectives": objectives.isEmpty ? "none" : objectives,
    ]
    var progress: [String: Int] = [:]
    for item in o.objectives where item.text != Objective.ready {
        let key = nameKey(item.quest) + "::" + nameKey(item.text)
        progress[key] = max(progress[key] ?? 0, item.done)
    }
    return ExperienceFrame(context: context, progress: progress, capturedAt: stamp.capturedAt,
                           stream: stamp.stream, geometry: stamp.geometry)
}

let huntInstructions = "Which action most safely advances the unfinished `objectives`, given `selected_quest_area`, `creatures_in_view`, `objects_on_the_ground_in_view`, `blocked_headings_near_here`, `character`, `target` and `recent_actions`?"

func huntStatePacket(_ o: HuntObs, recent: [HuntStep], fights: [String], blocked: [Double]) -> [String: Any] {
    var target: [String: Any] = ["selected": o.target != nil]
    if let name = o.target {
        target["name"] = name
        target["alive"] = o.targetAlive
        target["counts_for_objective"] = objective(for: name, in: o.objectives)?.text ?? "none"
        if let inRange = o.targetInRange { target["in_lightning_bolt_range"] = inRange }
    }
    var area: [String: Any] = ["on_minimap": o.area != nil && !o.areaRemembered]
    if o.areaRemembered { area["remembered_from_pick_ups"] = true }
    if let a = o.area {
        area["character_inside"] = a.inside
        area["distance"] = roundTo(a.distance)
        area["bearing_deg"] = Int(a.bearing.rounded())
    }
    var character: [String: Any] = ["health_percent": Int(o.player * 100), "mana_percent": Int(o.mana * 100), "in_combat": o.combat,
                                    "can_start_a_fight": o.player >= FightLimits.startHealth]
    if let facing = o.facing { character["facing_deg"] = Int(facing.rounded()) }
    if let here = o.here { character["position"] = ["x": here.x, "y": here.y] }
    return [
        "goal": "Complete the unfinished quest objectives by defeating the creatures or picking up the objects they name: quests are how this character levels up. Only a creature or object named in an unfinished objective counts. Objects on the ground are seen by a learned detector that does not say what they are: PICK_UP_OBJECT rests the pointer on the one nearest the character's feet and right-clicks it only if its tooltip names an unfinished objective, then Click-to-Move walks there. Such creatures are mostly inside the selected quest's area on the minimap, but one that counts may be fought wherever it is: a selected creature that counts and is in Lightning Bolt range can be fought from here (live run 28, 26 Sept: six such targets were walked past towards the area). Choose where to go from what is known: whether the character is inside that area, which creatures are in view (a hostile creature attacks when approached, and several near each other are dangerous to fight at once), and which headings were blocked here. A fight starts only at 90% health or more, with no other hostile creature near; below 60% health the character rests or eats before walking on. Costs, as a skilled player knows them: a same-level fight takes about 10 s and 15-30% health; melee does most of the damage and costs no mana, so a fight can start on little mana; each Lightning Bolt costs about 15% mana; a melee creature runs as fast as the character, so walking away only gives it free hits; Skysight's Elemental Blessing, when active, adds 10% run speed, under 1 yard a second: about 7 s of hits to leave its reach and 30 s to open Lightning Bolt range; eating and drinking restore both to full in about 20 s, standing still takes minutes. The character must stay alive. The owner is supervising.",
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
        "objects_on_the_ground_in_view": o.objects.map {
            ["screen_x_percent": Int($0.x * 100 / Double(HUD.width)), "screen_y_percent": Int($0.y * 100 / Double(HUD.height)),
             "confidence": roundTo($0.confidence)] as [String: Any]
        },
        "blocked_headings_near_here": blocked.map { Int($0.rounded()) },
        "recent_actions": recent.suffix(HuntLimits.recent).map(\.json),
        "fights_so_far": fights,
        "units": "positions are zone-map percent (one x unit is 1.5 y units); walks steer on up to 1.5 y units (10 s at most), round what they bump; headings are compass degrees, 0 north, 90 east; an object's screen percent is 0 at the top left, and the character's feet are near x 50, y 60",
    ]
}

/// What a hunt needs from the world: SimHunt offline, the WoW window live. A hunt walks as M4a does, so
/// its host is a NavBody: `look` reads position and facing for the walk skill.
protocol HuntHost: NavBody {
    func knownBumps() -> [(at: MapPoint, heading: Double, side: Double)]  // M4ad: the steering walks' bump memory (none in a sim)
    func knownPlaces(_ objectives: [Objective]) -> [MapPoint]  // M4aj: where the unfinished collect objectives' objects were picked up
    func remember(place: MapPoint, for objective: String)
    func remember(bumps: [(at: MapPoint, heading: Double, side: Double)])
    func survey() -> HuntObs?  // everything, OCR included; nil when the tracker is unreadable
    func vitals() -> HuntObs?  // pixels only (no OCR), for polling; nil without a fresh frame
    func fight(jev: JevClient, inCombat: Bool) async -> FightResult
    /// PICK_UP_OBJECT: the nearest object in view hovered, and right-clicked only when its tooltip names an unfinished
    /// objective. A result that begins "picked up" counts it.
    func pickUp(objectives: [Objective]) async -> String
    var facingState: FacingState? { get }  // the live facing's readings, for a turn test; nil in a simulation
}

extension HuntHost {
    var facingState: FacingState? { nil }
    func knownBumps() -> [(at: MapPoint, heading: Double, side: Double)] { [] }
    func knownPlaces(_ objectives: [Objective]) -> [MapPoint] { [] }
    func remember(place: MapPoint, for objective: String) {}
    func remember(bumps: [(at: MapPoint, heading: Double, side: Double)]) {}
}

extension HuntHost {
    func readSurvey() -> Observation<HuntObs> {
        guard var o = survey(), let stamp = o.stamp,
              stamp.isFresh(at: now(), maximumAge: FightLimits.maxFrameAge) else { return .unavailable("hunt_unreadable") }
        // M4aj: with no area on the minimap, where this quest's objects were picked up before is the area to walk to.
        if o.area == nil, let here = o.here, let remembered = rememberedArea(from: here.point, places: knownPlaces(o.objectives)) {
            o.area = remembered
            o.areaRemembered = true
        }
        return .observed(o, stamp)
    }
}

func tap(_ host: HuntHost, _ code: UInt16) async {
    guard host.keys.press(code) else { return }
    await host.sleep(HuntLimits.tap)
    host.keys.lift(code)
    await host.sleep(HuntLimits.settle)
}

/// M4aj: an area from remembered pick-up places, for a collect objective whose area the minimap does not show (live runs
/// 85-89: the Windstones' clusters were found round Thendal Grove, but with no ring on the minimap each hunt searched by
/// compass). The nearest place is its centre.
func rememberedArea(from here: MapPoint, places: [MapPoint]) -> QuestArea? {
    guard let p = places.min(by: { distance(here, $0) < distance(here, $1) }) else { return nil }
    let d = distance(here, p)
    return QuestArea(bearing: bearing(from: here, to: p), distance: d, inside: d < HuntLimits.placeRadius)
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
        // No frame is no evidence of calm: stop rather than sit on through an unseen attack.
        guard let v = host.vitals() else { return "stopped after \(Int(host.now() - began)) s: no fresh frame" }
        if v.combat { return "attacked after \(Int(host.now() - began)) s" }
        if host.ownerTookFocus() { return "stopped after \(Int(host.now() - began)) s" }
    }
    return "rested \(Int(seconds)) s"
}

/// Water, then bread: each sits the character down; both restore over the same 20 s, which `rest`
/// waits out (an attack or the owner ends it, and the character stands up).
func eatDrink(_ host: HuntHost) async -> String {
    await tap(host, HuntLimits.drink)
    await tap(host, HuntLimits.eat)
    return (await rest(host, seconds: HuntLimits.eatSeconds)).replacingOccurrences(of: "rested", with: "ate and drank for")
}

/// One M4a walk (steering, block detection, safety stops) on a fixed heading, then a Tab. W is lifted:
/// Jev's next decision is not made on the run.
func walkOn(_ host: HuntHost, heading: Double, episode: inout NavEpisode) async -> String {
    guard let start = host.look() else { return "position unreadable; did not walk" }
    let heading = (heading + 360).truncatingRemainder(dividingBy: 360)
    let h = heading * .pi / 180
    // M4ad (the owner, 27 Sept: "you are climbing cliffs... rethink the entire pathfinding"): a short steering walk that way
    // (runSteer: the view's depth, a walled view turned from, the bumps remembered), not a blind 3 s run (live run 84: the
    // hunt's own moves climbed the rock slopes west of Thendal Village). The hunt's body reads no red names (as before): what
    // attacks on the way is fought by the hunt (review of #98).
    let to = NavDestination(label: "heading \(Int(heading))", x: start.x + HuntLimits.stepLength * sin(h) / mapAspect,
                            y: start.y - HuntLimits.stepLength * cos(h), arrive: 0.3, seconds: HuntLimits.stepSeconds)
    let walked = await runSteer(body: host, path: [], destination: to, known: host.knownBumps(), keepKeys: true)
    host.keys.lift(FightLimits.forward)
    host.remember(bumps: walked.bumps)
    for b in walked.bumps {  // each bump where it happened, so the hunt keeps off that heading there (blockedHeadings)
        var bump = NavAttempt(action: .goToward, from: start, to: NavObs(x: b.at.x, y: b.at.y, facing: b.heading), heading: b.heading,
                              before: HuntLimits.stepLength, after: HuntLimits.stepLength)
        bump.blocked = true
        episode.record(bump)
    }
    var attempt = NavAttempt(action: .goToward, from: start, to: walked.end ?? start, heading: heading,
                             before: HuntLimits.stepLength, after: distance((walked.end ?? start).point, to.point))
    // Blocked where it ended only when it could not get on at all; each bump is its own blocked attempt, where it happened
    // (review of #98: marking the end blocked on the first heading kept a way off at a place it was never blocked).
    attempt.blocked = walked.outcome == "NO_PROGRESS"
    attempt.warned = walked.outcome == "DANGER_AHEAD"
    attempt.arrived = walked.outcome == "ARRIVED"
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
        guard let v = host.vitals() else { return ("no fresh frame; stopped turning after \(step * 90)°", seen) }
        if v.combat {
            let tabbed = await selectNearest(host)
            if host.survey()?.targetAlive == true { return ("attacked; turned \(step * 90)° and " + tabbed, seen) }
        }
        host.keys.grant(FightLimits.turnRight, seconds: HuntLimits.lookSeconds + NavLimits.forwardWatchdog)  // lifted if this stalls
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
    var runtime: SkillResult? = nil
    var memory: TaskMemory? = nil
    var graphID: String? = nil
    var graphRecords: [[String: Any]] = []
    var experience: [String: Any]? = nil
    var experienceRecords: [[String: Any]] = []
    var experienceReviews: [[String: Any]] = []
}

func runHunt(host: HuntHost, jev: JevClient, graph: GraphSession? = nil,
             experience: ExperienceStore? = nil, experienceRun: String = UUID().uuidString,
             seconds: Double = HuntLimits.maxSeconds) async -> HuntResult {
    var r = HuntResult()
    r.graphID = graph?.graph.id
    r.experience = experience?.summary
    var executive = RuntimeExecutive(goal: "complete the initial unfinished objectives")
    executive.begin("hunt")
    var lastStamp: ObservationStamp?
    let began = host.now()
    var misses = 0, sinceFight = 0, experienceSerial = 0
    var panorama: (at: NavObs, seen: [Seen])?
    var pendingExperience: PendingHuntExperience?

    func persistPending(after: HuntObs?, blocked: [Double] = []) {
        guard let store = experience, let pending = pendingExperience else { return }
        let afterFrame = after.flatMap { huntExperienceFrame($0, blocked: blocked) }.flatMap {
            $0.capturedAt > pending.before.capturedAt ? $0 : nil
        }
        let item = ExperienceCase(id: pending.id, run: experienceRun, action: pending.action,
            before: pending.before, after: afterFrame, reported: pending.reported,
            blocked: pending.blocked, elapsed: pending.elapsed)
        do {
            if try store.record(item) {
                r.experienceRecords.append(item.json)
                host.emit("experience_recorded", item.json)
            }
        } catch {
            host.emit("experience_error", ["id": pending.id, "error": "\(error)"])
        }
        pendingExperience = nil
        r.experience = store.summary
    }

    func finish(_ outcome: String) -> HuntResult {
        persistPending(after: nil)
        host.keys.releaseAll()
        r.outcome = outcome
        r.holding = host.keys.holding
        r.codesPosted = host.keys.codesPosted
        let skill = SkillResult(skill: "hunt", status: skillStatus(outcome), code: outcome,
                                evidence: lastStamp, holdingInput: r.holding)
        executive.finish(skill)
        r.runtime = skill; r.memory = executive.memory; r.experience = experience?.summary
        host.emit("skill_result", skill.json)
        return r
    }

    guard let first = host.readSurvey().value else { return finish("HUD_UNREADABLE") }
    r.start = first.objectives
    let wanted = first.objectives.filter(\.unfinished)
    if wanted.isEmpty { return finish("NO_UNFINISHED_OBJECTIVE") }

    while r.decisions < HuntLimits.maxDecisions {
        if host.now() - began >= seconds { return finish("TIME_LIMIT") }
        if host.ownerTookFocus() { return finish("OWNER_TOOK_FOCUS") }
        guard var o = host.readSurvey().value else {
            misses += 1
            if misses >= HuntLimits.unreadableLimit { return finish("HUD_UNREADABLE") }
            await host.sleep(HuntLimits.settle)
            continue
        }
        // Nothing to offer without a position after LOOK_AROUND (no walk, no second look): read again, as a survey that did
        // not read (live run 31, 27 Sept: the empty request ended the hunt as HUD_UNREADABLE on one unread position).
        if o.here == nil && huntAdmissible(o, steps: r.steps).isEmpty {
            misses += 1
            if misses >= HuntLimits.unreadableLimit { return finish("HUD_UNREADABLE") }
            // live run 55 (27 Sept): the facing unread on every survey at the Windstones' area ended the hunt so
            if misses == HuntLimits.unreadableLimit - 1 && !o.combat {  // in combat a turn is the fight's (review of #63)
                await unstickTurn(host.keys, misses: misses, sleep: { await host.sleep($0) }, emit: host.emit,
                                  facing: host.facingState, reread: { _ = host.survey() }, now: host.now)
            }
            await host.sleep(HuntLimits.settle)
            continue
        }
        misses = 0
        lastStamp = o.stamp
        r.end = o.objectives
        if let p = panorama, let here = o.here, distance(p.at.point, here.point) <= HuntLimits.panoramaFor {
            o.seen = merged(p.seen, o.seen)
        }
        let blocked = o.here.map { r.walks.blockedHeadings(near: $0) } ?? []
        persistPending(after: o, blocked: blocked)
        if o.player < 0.01 && !o.combat { return finish("DEAD") }  // an empty health bar out of combat
        if remaining(wanted, in: o.objectives).isEmpty { return finish("OBJECTIVES_COMPLETE") }
        if !o.combat && r.fights.count >= HuntLimits.maxFights { return finish("FIGHT_LIMIT") }
        if !o.combat && sinceFight >= HuntLimits.searchLimit { return finish("NO_TARGET_FOUND") }

        let allowed = huntAdmissible(o, steps: r.steps, blocked: blocked)
        if allowed.isEmpty { return finish(emptyHuntEnd(r.steps)) }  // an empty request is no decision (live run 37)
        var state = huntStatePacket(o, recent: r.steps, fights: r.fights.map(\.outcome), blocked: blocked)
        let experienceFrame = huntExperienceFrame(o, blocked: blocked)
        let experienceContext = experienceFrame?.context ?? [:]
        let reviewTools = graph == nil ? [:] : (experience?.availableReviewTools(experienceContext) ?? [:])
        let graphSkills = Dictionary(uniqueKeysWithValues: allowed.map { ($0.rawValue, $0.facts) }).merging(reviewTools) { old, _ in old }
        if let experience {  // only with a store: without one, the flat and graph requests stay as before #25
            state["experience_index"] = experience.hint(experienceContext)
            state["experience_recall"] = experience.recall(experienceContext)
        }
        if graph != nil {
            state["task_memory"] = ["goal": executive.memory.goal, "revision": executive.memory.revision,
                "active_skill": executive.memory.activeSkill ?? "none", "recent": executive.memory.recent.map(\.json)]
        }
        var question = actionQuestion(allowed, instructions: huntInstructions)
        let asked = host.now()
        let candidates = allowed.map(\.rawValue) + reviewTools.keys.sorted()
        guard let stamp = o.stamp, let context = executive.request(stamp: stamp, candidates: candidates,
                policy: graph?.graph.id ?? "hunt-legacy-v1", now: asked, maximumAge: FightLimits.maxFrameAge,
                deadline: min(asked + HuntLimits.jevTimeout, began + seconds)) else { return finish("HUD_UNREADABLE") }
        let reply: [String: Any]
        let selectedName: String?
        func recordGraphCalls() {
            for call in graph?.lastTrace ?? [] { r.graphRecords.append(call); host.emit("graph_call", call) }
        }
        do {
            if let graph {
                let decision = try await graph.next(state: state, skills: graphSkills,
                    jev: jev, now: host.now, deadline: context.deadline, stopped: host.ownerTookFocus)
                reply = decision.response; state = decision.state; question = decision.question
                selectedName = decision.action
                recordGraphCalls()
            } else {
                reply = try await jev.ask(state: state, question: question)
                selectedName = parseChoice(reply, admissible: allowed, model: FightLimits.model)?.action.rawValue
            }
        } catch {
            recordGraphCalls()
            host.emit("jev_error", ["error": "\(error)"])
            return finish(error is GraphError ? "GRAPH_\(error)" : "JEV_FAILED")
        }
        r.latencies.append(host.now() - asked)
        r.decisions += 1
        let record: [String: Any] = ["decision": r.decisions, "t": asked, "state": state, "question": question,
                                     "admissible": candidates, "response": reply, "context": context.json]
        r.records.append(record)
        host.emit("decision", record)
        guard let selectedName else { return finish("INVALID_REPLY") }

        if let topic = ExperienceReview.topic(for: selectedName) {
            guard let store = experience, reviewTools[selectedName] != nil,
                  let review = store.reviewLatest(topic, context: experienceContext) else { return finish("INVALID_REPLY") }
            executive.invalidate()
            graph?.returnToRoot()
            r.experienceReviews.append(review.json)
            r.experience = store.summary
            host.emit("experience_review", review.json)
            continue
        }
        guard let action = HuntAction(rawValue: selectedName), allowed.contains(action) else { return finish("INVALID_REPLY") }

        var result: String
        sinceFight += 1
        // A reply takes seconds: re-read before acting. Without a fresh frame nothing is done; attacked
        // meanwhile, a non-combat action is not done (the next decision sees the attack) and a pull
        // starts as a fight already in combat.
        guard let fresh = host.vitals(), !(fresh.combat && !o.combat && action != .fight) else {
            result = "not done: attacked, or no fresh frame, while Jev decided"
            r.steps.append(HuntStep(action: action, result: result))
            host.emit("acted", ["action": action.rawValue, "result": result])
            continue
        }
        // Sightings are memory, as at the decision: a creature seen seconds ago has not gone because this frame's plate
        // OCR missed its name (live run 24, 26 Sept: ten GO_TO_QUEST_CREATURE in a row rejected, and no fight).
        let latest = host.readSurvey().value.map { l -> HuntObs in var l = l; l.seen = merged(o.seen, l.seen); return l }
        let latestAllowed = latest.map { huntAdmissible($0, steps: r.steps, blocked: blocked).map(\.rawValue) } ?? []
        if let rejection = executive.rejection(DecisionProposal(context: context, action: action.rawValue),
                current: latest?.stamp, candidates: latestAllowed, now: host.now(), maximumAge: FightLimits.maxFrameAge,
                ownerStopped: host.ownerTookFocus()) {
            host.emit("proposal_rejected", ["reason": rejection, "request": context.request])
            if rejection == "owner_stop" { return finish("OWNER_TOOK_FOCUS") }
            if rejection == "decision_expired" { return finish("DECISION_EXPIRED") }
            r.steps.append(HuntStep(action: action, result: "not done: " + rejection))
            continue
        }
        o = latest!
        lastStamp = o.stamp
        let actionBegan = host.now()
        let walksBefore = r.walks.attempts.count
        var terminal: String?
        switch action {
        case .fight:
            executive.begin("combat")
            let fight = await host.fight(jev: jev, inCombat: o.combat || fresh.combat)
            let skill = fight.runtime ?? SkillResult(skill: "combat", status: skillStatus(fight.outcome),
                code: fight.outcome, evidence: nil, holdingInput: fight.holdingKeys)
            executive.finish(skill)
            host.emit("task_resumed", ["goal": executive.memory.goal, "revision": executive.memory.revision,
                                       "active_skill": executive.memory.activeSkill ?? "none"])
            r.fights.append(fight)
            sinceFight = 0
            result = "the fight ended \(fight.outcome) after \(fight.decisions) decisions"
            if !HuntLimits.continueAfter.contains(fight.outcome) { terminal = "FIGHT_" + fight.outcome }
        case .nextTarget:
            result = await selectNearest(host)
        case .lookAround:
            let look = await lookAround(host)
            result = look.result
            if let here = host.look() { panorama = (here, look.seen) }
        case .pickUp:
            result = await host.pickUp(objectives: o.objectives)
            if result.hasPrefix("picked up") {
                sinceFight = 0  // progress, as a fight is
                // M4aj: remembered where it was, so a later hunt with no area on the minimap walks back here.
                if let here = host.look(), let picked = o.objectives.filter(collects).first(where: { result.contains($0.text) }) {
                    host.remember(place: here.point, for: picked.text)
                }
            }
        case .rest:
            result = await rest(host, seconds: HuntLimits.restSeconds)
        case .eatDrink:
            result = await eatDrink(host)
        case .toCreature:
            let heading = questCreature(o)?.bearing
            result = heading == nil ? "nothing to walk to" : await walkOn(host, heading: heading!, episode: &r.walks)
        case _ where action.areaOffset != nil:
            let heading = o.area.map { $0.bearing + action.areaOffset! }
            result = heading == nil ? "no area to walk by" : await walkOn(host, heading: heading!, episode: &r.walks)
        default:
            result = await walkOn(host, heading: action.compassHeading ?? 0, episode: &r.walks)
        }
        r.steps.append(HuntStep(action: action, result: result))
        host.emit("acted", ["action": action.rawValue, "result": result])
        if let before = experienceFrame, experience != nil {
            experienceSerial += 1
            let blockedResult = action.isWalk && r.walks.attempts.count > walksBefore ? r.walks.attempts.last?.blocked : nil
            pendingExperience = PendingHuntExperience(id: "\(experienceRun)-\(experienceSerial)", action: action.rawValue,
                before: before, reported: result, blocked: blockedResult, elapsed: max(0, host.now() - actionBegan))
        }
        if let terminal { return finish(terminal) }
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
    var platesMissed: [Bool] = []  // per survey, in order: true reads no plate (live run 24)
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
    var places: [MapPoint] = []  // M4aj: remembered pick-up places, offered while a collect objective is open
    var remembered: [(at: MapPoint, objective: String)] = []
    func knownPlaces(_ objectives: [Objective]) -> [MapPoint] { objectives.contains(where: collects) ? places : [] }
    func remember(place: MapPoint, for objective: String) { remembered.append((place, objective)) }
    var foughtInCombat: [Bool] = []  // each fight's inCombat, as the hunt passed it
    var surveyBlind = false
    var positionBlind = false  // surveys read, but not the place (the arrow unread)
    var frozen = false  // the capture has stalled: no fresh frame for vitals or a survey
    var readLines: ([String]) -> [String] = { $0 }  // what the tracker's OCR keeps of its lines
    var objects: [Mob] = []  // objects on the ground; one picked up is no longer alive
    var eating = false  // sitting with food or water: regain 5% a second until standing up or attacked

    init(world: SimNav, mobs: [Mob], objectives: [Objective]) {
        self.world = world
        self.mobs = mobs
        self.objectives = objectives
        world.pad.onDown = { [unowned self] code in
            if code == FightLimits.tab { self.selected = self.nearest() }
            if code == HuntLimits.drink || code == HuntLimits.eat { self.eating = true }
            if code == FightLimits.forward { self.eating = false }
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
    func look() -> NavObs? { frozen ? nil : world.look() }

    private func inView(_ m: Mob, within reach: Double) -> Bool {
        let here: MapPoint = (world.x, world.y)
        return m.alive && distance(here, m.point) <= reach && abs(angleError(bearing(from: here, to: m.point), world.facing)) <= 45
    }

    private func nearest() -> Int? {
        let here: MapPoint = (world.x, world.y)
        return mobs.indices.filter { inView(mobs[$0], within: 1.2) }.min { distance(here, mobs[$0].point) < distance(here, mobs[$1].point) }
    }

    /// Integrates the walk, then lets a hostile creature within 0.25 units attack; rest regains 2 % a second,
    /// eating and drinking 5 %.
    func sleep(_ seconds: Double) async {
        await world.sleep(seconds)
        let here: MapPoint = (world.x, world.y)
        if !world.combat, mobs.contains(where: { $0.alive && $0.hostile && distance(here, $0.point) <= 0.25 }) {
            world.combat = true  // as in WoW, an attacker is not selected for you
        }
        if world.combat { eating = false }
        if !world.combat {
            let rate = eating ? 0.05 : 0.02
            world.player = min(1, world.player + rate * seconds)
            mana = min(1, mana + rate * seconds)
        }
    }

    func vitals() -> HuntObs? { frozen ? nil : reading() }

    /// The tracker as WoW draws it: each quest's title, then its objective lines, or "Ready for turn-in"
    /// once all of them are done.
    var trackerLines: [String] {
        var quests: [String] = []
        for o in objectives where !quests.contains(o.quest) { quests.append(o.quest) }
        return quests.flatMap { quest -> [String] in
            let mine = objectives.filter { $0.quest == quest }
            return [quest] + (mine.contains(where: \.unfinished) ? mine.map { "- \($0.done)/\($0.need) \($0.text)" } : [Objective.ready])
        }
    }

    private func reading() -> HuntObs {
        var o = HuntObs(stamp: ObservationStamp(stream: "sim-hunt", geometry: "sim-layout", capturedAt: now(),
                                               target: selected.map { mobs[$0].name }),
                        player: world.player, mana: mana, combat: world.combat, facing: world.facing, here: world.look())
        if let a = area {
            let here: MapPoint = (world.x, world.y), centre: MapPoint = (a.x, a.y)
            let d = distance(here, centre)
            if d - a.radius <= 5 { o.area = QuestArea(bearing: bearing(from: here, to: centre), distance: d, inside: d < a.radius) }
        }
        return o
    }

    func survey() -> HuntObs? {
        guard !world.unreadable, !surveyBlind, !frozen else { return nil }
        var o = reading()
        if positionBlind { o.here = nil }
        o.objectives = parseTracker(readLines(trackerLines))
        o.target = selected.map { mobs[$0].name }
        o.targetAlive = selected.map { mobs[$0].alive } ?? false
        o.gameMenu = gameMenu
        let here: MapPoint = (world.x, world.y)
        o.seen = mobs.filter { inView($0, within: 1.2) }.map {
            Seen(name: $0.name, hostile: $0.hostile, bearing: bearing(from: here, to: $0.point), near: distance(here, $0.point) <= 0.7)
        }
        if !platesMissed.isEmpty, platesMissed.removeFirst() { o.seen = [] }  // a frame whose plates OCR did not read
        o.objects = objects.filter { inView($0, within: 1.2) }.map {
            SeenObject(x: 1280 + 20 * angleError(bearing(from: here, to: $0.point), world.facing), y: 800 - 300 * distance(here, $0.point),
                       confidence: 0.9)
        }
        return o
    }

    /// The nearest object in view: its name is the tooltip; one that counts is walked to and picked up, 3 s.
    func pickUp(objectives: [Objective]) async -> String {
        let here: MapPoint = (world.x, world.y)
        guard let i = objects.indices.filter({ inView(objects[$0], within: 1.2) })
                .min(by: { distance(here, objects[$0].point) < distance(here, objects[$1].point) }) else { return "no object in view" }
        guard let counted = objectTipObjective([objects[i].name], in: objectives), let k = self.objectives.firstIndex(of: counted) else {
            return "the tooltip read \"\(objects[i].name)\", which names no unfinished objective; not clicked"
        }
        (world.x, world.y) = (objects[i].x, objects[i].y)
        objects[i].alive = false
        self.objectives[k].done += 1
        clock.t += 3
        return "picked up \(objects[i].name), which counts for \"\(counted.text)\""
    }

    func fight(jev: JevClient, inCombat: Bool) async -> FightResult {
        fightsRun += 1
        foughtInCombat.append(inCombat)
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
