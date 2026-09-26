// M4c for issue #5: hand in a quest at its NPC. Scripts find the NPC's "?", open the dialogue, read
// each reward's tooltip and click; the reward follows the owner's rule. This file is the pure part:
// reward tooltips, the choice and the quest-marker search. QuestProbe.swift is the live shell.
import Foundation

/// One OCR line of a tooltip: text, left x and top y in capture pixels, and whether it is drawn red.
struct TipLine: Equatable {
    var text: String
    var x: Double
    var y: Double
    var red = false
}

struct Reward: Equatable {
    var name: String
    var slot: String?  // "Chest", "Legs", ...: nil for an item that is not worn
    var usable: Bool  // no red line in the item's own tooltip ("Mail" for a Shaman below 40, "Requires Level 12")
    var change: Double  // the game's own stat changes against the equipped item; an empty slot: the item's armour
    var sell: Int  // copper
}

/// The slot words a worn item's tooltip names.
let equipSlots: Set<String> = ["Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
                               "Legs", "Feet", "Finger", "Trinket", "Main Hand", "One-Hand", "Two-Hand", "Off Hand",
                               "Held In Off-hand", "Ranged"]

/// A reward's tooltip, read while the pointer rests on it. The game draws the equipped item beside it
/// ("Equipped", then "If you replace this item, the following stat changes will occur: +2 Armor"),
/// and the quest text shows through behind both: lines are kept by alignment, as in tooltipLines.
func parseReward(_ lines: [TipLine]) -> Reward? {
    guard let foot = lines.first(where: { isTooltipFooter($0.text) }) else { return nil }
    // The equipped item's box starts at its "Equipped" label or its "If you replace" line; live on 24 Sept
    // OCR missed the latter once, and the box's own lines were then read as the reward's.
    let compare = lines.first { $0.text.hasPrefix("If you replace this item") }
    let equipped = lines.filter { $0.text == "Equipped" || $0.text.hasPrefix("If you replace this item") }.map(\.x).min()
    let own = lines.filter {
        $0.y < foot.y && $0.x < (equipped ?? .infinity) - 12 && (abs($0.x - foot.x) <= 8 || $0.x >= foot.x + 150)
    }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    guard let name = own.first?.text else { return nil }
    let slot = own.map(\.text).first { equipSlots.contains($0) }
    let sell = own.first { $0.text.hasPrefix("Sell Price") }.flatMap { Int($0.text.filter(\.isNumber)) } ?? 0
    let change: Double
    if let compare {
        change = lines.filter { abs($0.x - compare.x) <= 8 && $0.y > compare.y }.compactMap { line -> Double? in
            guard let first = line.text.split(separator: " ").first, "+-".contains(first.prefix(1)) else { return nil }
            return Double(first)
        }.reduce(0, +)
    } else if equipped != nil {
        change = 0  // an equipped item, but its stat changes were not read: not an upgrade
    } else {
        change = own.lazy.compactMap { $0.text.hasSuffix(" Armor") ? Double($0.text.dropLast(6)) : nil }.first ?? 0
    }
    return Reward(name: name, slot: slot, usable: !own.contains(where: \.red), change: change, sell: sell)
}

/// The owner, 24 Sept: "choose if it benefit (eg armor better than now, take and equip). or take the
/// highest value (take and sell)." A deterministic rule, logged as controller RULE.
// ponytail: every stat change counts 1 per point; weigh stats when rewards carry more than armour.
func chooseReward(_ rewards: [Reward]) -> (index: Int, equip: Bool)? {
    let upgrades = rewards.indices.filter { rewards[$0].usable && rewards[$0].slot != nil && rewards[$0].change > 0 }
    if let best = upgrades.max(by: { (rewards[$0].change, rewards[$0].sell) < (rewards[$1].change, rewards[$1].sell) }) {
        return (best, true)
    }
    return rewards.indices.max { rewards[$0].sell < rewards[$1].sell }.map { ($0, false) }
}

/// The yellow "?" (quest ready) and "!" (quest offered). Zoomed out an NPC's is small and dim: (185-224,
/// 155-192, 40-48) in a screenshot on 24 Sept; the live capture drew a minimap "?" as (239, 236, 116), not
/// the screenshot's (248, 246, 58). So the test is the hue: parchment (R-B 55) and tan land (75) stay out.
func markYellow(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 170 && g > 140 && r - b > 90 && g - b > 80 }

/// The NPC's green name under its mark: (50-65, 150-198, 32-42) in a screenshot, (43-104, 121-172, 26-89)
/// in the live capture (24 Sept), which is the reference.
func nameGreen(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > 110 && g > r + 40 && g > b + 30 }

/// Centres of yellow quest marks in a box (x0, y0, x1, y1), nearest the view's centre first. A mark is
/// an upright blob (a "?" is about 10 x 18 px zoomed out) with a green NPC name 8-50 px below it
/// (farther below a taller mark, at a closer zoom): a
/// neutral creature's yellow nameplate bar is a flat strip, and a glowing Cirrusfly has no green name
/// (live frames: 305 green pixels under a near "?", about 60 under a distant one, 0-23 under the insects).
typealias Blob = (n: Int, sx: Int, sy: Int, x0: Int, x1: Int, y0: Int, y1: Int)

/// Yellow pixels of a box as connected blobs: pixels within `gap` px of each other join. (A fixed grid
/// merged three minimap "?" 14 px apart on 24 Sept.)
func yellowBlobs(_ image: RGBA, box: (Int, Int, Int, Int), gap: Int = 13) -> [Blob] {
    let x0 = max(0, box.0), y0 = max(0, box.1), x1 = min(box.2, image.width), y1 = min(box.3, image.height)
    let w = x1 - x0, h = y1 - y0
    guard w > 0, h > 0 else { return [] }
    var mask = [Bool](repeating: false, count: w * h)
    for y in y0..<y1 {
        for x in x0..<x1 {
            let i = (y * image.width + x) * 4
            if markYellow(Int(image.pixels[i]), Int(image.pixels[i + 1]), Int(image.pixels[i + 2])) { mask[(y - y0) * w + x - x0] = true }
        }
    }
    let reach = gap + 1
    var blobs: [Blob] = []
    for start in mask.indices where mask[start] {
        mask[start] = false
        var stack = [start], b: Blob = (0, 0, 0, .max, .min, .max, .min)
        while let p = stack.popLast() {
            let px = p % w, py = p / w, gx = px + x0, gy = py + y0
            b = (b.n + 1, b.sx + gx, b.sy + gy, min(b.x0, gx), max(b.x1, gx), min(b.y0, gy), max(b.y1, gy))
            for ny in max(0, py - reach)...min(h - 1, py + reach) {
                for nx in max(0, px - reach)...min(w - 1, px + reach) where mask[ny * w + nx] {
                    mask[ny * w + nx] = false
                    stack.append(ny * w + nx)
                }
            }
        }
        blobs.append(b)
    }
    return blobs
}

/// Quest pins' glyphs on the open world map ("?", "..."), as capture pixels. Pins sit 17 px apart
/// (Call of Earth and The Gift of Skysight, 24 Sept), and the map's corner buttons are outside the box.
func mapPins(_ image: RGBA, box: (Int, Int, Int, Int) = (70, 280, 730, 700)) -> [(x: Double, y: Double)] {
    yellowBlobs(image, box: box, gap: 2).filter { $0.n >= 10 && $0.x1 - $0.x0 <= 26 && $0.y1 - $0.y0 <= 26 }
        .map { (Double($0.sx) / Double($0.n), Double($0.sy) / Double($0.n)) }
}

/// A "?"'s dot joins its hook: a small round blob under a blob, overlapping it across, no further below than
/// the hook is tall, no wider than it and at most a third of its pixels. Far away `yellowBlobs`' 13 px gap
/// joins them; near, the gap grows with the mark (live run 6, 26 Sept: beside Dalia a 27 x 30 hook had its
/// 11 x 9 dot 18 px below, and neither read as a mark). `dotted`: a dot was joined here, the glyph's shape.
func withDots(_ blobs: [Blob]) -> [(blob: Blob, dotted: Bool)] {
    var out = blobs.map { (blob: $0, dotted: false) }, used = Set<Int>()
    for i in out.indices where !used.contains(i) {
        let hook = out[i].blob
        guard let j = out.indices.first(where: { j in
            let d = out[j].blob, dw = d.x1 - d.x0 + 1, dh = d.y1 - d.y0 + 1
            return j != i && !used.contains(j) && 3 * d.n <= hook.n && dw <= hook.x1 - hook.x0 + 1 && dw <= 2 * dh && dh <= 2 * dw
                && d.y0 > hook.y1 && d.y0 - hook.y1 <= hook.y1 - hook.y0 + 1 && d.x0 <= hook.x1 && d.x1 >= hook.x0
        }) else { continue }
        let d = out[j].blob
        out[i] = ((hook.n + d.n, hook.sx + d.sx, hook.sy + d.sy, min(hook.x0, d.x0), max(hook.x1, d.x1), hook.y0, d.y1), true)
        used.insert(j)
    }
    return out.indices.filter { !used.contains($0) }.map { out[$0] }
}

/// A quest mark and the green name under it. `body` is where to right-click: below the name by 2.4 mark
/// heights. `nameX` is the name's centre, which stands over the body when the "?" does not (live, 25 Sept:
/// Dalia's "?" was 30 px right of her; the click at its x found ground). `nameTop` bounds the name for OCR.
typealias QuestMark = (x: Double, y: Double, h: Double, body: Double, nameX: Double, nameTop: Double)

/// `body`: near, name bottom 577, body 608 under a 17-px "?"; a distant NPC's "?" was 4 x 6 px live, and a
/// fixed step landed on its name.
func questMarks(_ image: RGBA, box: (Int, Int, Int, Int), minPixels: Int = 5) -> [QuestMark] {
    let blobs = withDots(yellowBlobs(image, box: box))
    let cx = Double(image.width) / 2, cy = Double(image.height) / 2
    func greenBelow(_ x: Int, _ y: Int, reach: Int) -> (n: Int, top: Int, bottom: Int, x: Double, text: Bool) {
        // Names are in the world: the search stays in the box, never down into the HUD (25 Sept: a wider reach
        // from a yellow glow above the unit frame found the player's green health bar).
        let top = max(0, y + 8), end = min(image.height, y + reach, box.3)
        guard top < end else { return (0, y, y, Double(x), false) }
        var rows = [(n: Int, sx: Int, x0: Int, x1: Int)](repeating: (0, 0, .max, .min), count: end - top)
        for yy in top..<end {
            for xx in max(0, x - 50)..<min(image.width, x + 50) {
                let i = (yy * image.width + xx) * 4
                if nameGreen(Int(image.pixels[i]), Int(image.pixels[i + 1]), Int(image.pixels[i + 2])) {
                    let r = rows[yy - top]
                    rows[yy - top] = (r.n + 1, r.sx + xx, min(r.x0, xx), max(r.x1, xx))
                }
            }
        }
        guard let first = rows.firstIndex(where: { $0.n > 0 }), let last = rows.lastIndex(where: { $0.n > 0 }) else { return (0, y, y, Double(x), false) }
        // The centre is the name's own line, the green rows from the first down to a row without any: a
        // subtitle or another name further down does not pull it. A line of text is at least twice as wide as
        // it is tall; a creature's green glow is not (live, 24 Sept: a Cirrusfly's striped body over it read
        // as a 140 px "?" with its dot).
        let line = rows[first...].prefix { $0.n > 0 }
        let centre = Double(line.reduce(0) { $0 + $1.sx }) / Double(line.reduce(0) { $0 + $1.n })
        let wide = line.map(\.x1).max()! - line.map(\.x0).min()! + 1 >= 2 * line.count
        return (rows.reduce(0) { $0 + $1.n }, top + first, top + last, centre, wide)
    }
    return blobs.compactMap { found -> QuestMark? in
        let b = found.blob, w = b.x1 - b.x0 + 1, h = b.y1 - b.y0 + 1
        // Upright and at most 24 px wide; wider only with a dot joined below, up to 0.6 of its height: a "?"
        // with its dot is about half as wide as tall at every zoom (15 x 33, 27 x 56). A spell's tall glow is
        // wider than 24 px and has no dot (a Lightning Bolt read as a 288 px "?" without that rule).
        let widest = found.dotted ? max(24, 0.6 * Double(h)) : 24
        guard b.n >= minPixels, Double(w) <= widest, h >= 3, Double(h) >= 0.8 * Double(w) else { return nil }
        // How far below to look scales with the mark: its height stands for the NPC's distance. The name is UI
        // text of fixed size, so a small mark keeps a 50 px floor (96 accepted marks, h 3-10: name bottom 14-49
        // px below); a tall one's name sits 1.7-2.4 heights below (h 17-28), so 2.5 heights. 25 Sept, the owner's
        // closer zoom: a 33 px "?" (dot joined) had its name 54-63 px below, beyond the old fixed 50 px, and
        // the walk that reached the NPC read NO_QUEST_MARK_IN_VIEW.
        let name = greenBelow(b.sx / b.n, b.sy / b.n, reach: max(50, 5 * h / 2))
        guard name.n >= 40, name.text else { return nil }
        return (Double(b.sx) / Double(b.n), Double(b.sy) / Double(b.n), Double(h), Double(name.bottom) + 2.4 * Double(h), name.x, Double(name.top))
    }
     .sorted { hypot($0.x - cx, $0.y - cy) < hypot($1.x - cx, $1.y - cy) }
}

// MARK: - The quest plan (M4d)

/// What a quest's objective asks for, read from the quest log's text.
enum QuestKind: String {
    case handIn = "HAND_IN"  // "Ready for turn-in", or a "?" quest: talk to its NPC
    case kill = "KILL"  // "- 0/1 Cirrusfly Queen slain"
    case collect = "COLLECT"  // "- 12/15 Windstone Cluster": from creatures or objects
    case useAt = "USE_AT"  // "Use Skysight near the Elemental Convergence", "drink the Earth Sapta"
    case travel = "TRAVEL"  // "Report to Constable Aonda in Shen'dar Village."
}

struct PlannedQuest {
    var title: String
    var level: Int
    var ready: Bool  // the log shows "?" rather than "..."
    var objective: String
    var pin: MapPoint?  // from hovering the world map's pins
}

// MARK: - Working memory: the quest log (the owner, 25 Sept: remember what was read, to cut rescans)

/// The log as last read from the map: opening it and resting on each pin took 3-4 s of each 5-6 s read
/// (live run 4). It is kept under a key of the zone's name and the objective tracker's text, which change
/// when a quest is handed in, taken or advanced ("12/15" to "13/15").
struct LogMemory: Codable {
    struct Quest: Codable {
        var title: String, level: Int, ready: Bool, objective: String, pin: [Double]?
    }
    var key: String
    var quests: [Quest]
    var readAt: Double  // seconds since 1970
}

extension LogMemory.Quest {
    init(_ q: PlannedQuest) { self.init(title: q.title, level: q.level, ready: q.ready, objective: q.objective, pin: q.pin.map { [$0.x, $0.y] }) }
    var planned: PlannedQuest {
        PlannedQuest(title: title, level: level, ready: ready, objective: objective, pin: pin.flatMap { $0.count == 2 ? ($0[0], $0[1]) : nil })
    }
}

/// The memory's key: the zone's name by its letters (the clock beside it changes each minute), the tracker's
/// lines by letters and digits (OCR's stray apostrophes drop out). Either unread: no key, a full read. Zone
/// coordinates belong to their zone, so another zone's pins are never kept.
func logKey(zone: [String], tracker: [String]) -> String {
    let place = nameKey(zone.joined()), text = String(tracker.joined().lowercased().filter { $0.isLetter || $0.isNumber })
    return place.isEmpty || text.isEmpty ? "" : place + "|" + text
}

let logMemoryAge = 3600.0  // a quest left out of the tracker could change unseen: an hour at most

/// Whether the tracker shows every quest of the log read: only then does its text stand for the log. A
/// collapsed tracker ("All Objectives" alone), a filter or a list longer than the box would let two logs
/// share a key (review, 26 Sept), so such a read is not remembered.
func trackerShows(_ quests: [PlannedQuest], _ tracker: [String]) -> Bool {
    let text = nameKey(tracker.joined())
    return quests.allSatisfy { text.contains(nameKey($0.title)) }
}

/// Whether a map read may be remembered: a key; a log that is not empty; nothing the minimap named that the
/// log lacks; and the tracker and the log agree both ways (each quest in the tracker, and each tracker line in
/// a title or an objective). A read that parsed one quest of four passed a one-way test and would have been
/// kept for the hour, with `LOG_INCOMPLETE` every run (review, 26 Sept). OCR noise only costs a full read.
func rememberLog(_ quests: [PlannedQuest], tracker: [String], key: String, missing: [String]) -> Bool {
    let log = nameKey(quests.map { $0.title + " " + $0.objective }.joined(separator: " "))
    let lines = tracker.map(nameKey).filter { !$0.isEmpty }
    return !key.isEmpty && !quests.isEmpty && missing.isEmpty && !lines.isEmpty && trackerShows(quests, tracker)
        && lines.allSatisfy { log.contains($0) }
}

/// The remembered quests when the key is the same and the memory under an hour old; otherwise nil (read the map).
func keptLog(_ memory: LogMemory?, key: String, at time: Double) -> [PlannedQuest]? {
    guard let memory, !key.isEmpty, memory.key == key, time >= memory.readAt, time - memory.readAt < logMemoryAge else { return nil }
    return memory.quests.map(\.planned)
}

func questKind(_ q: PlannedQuest) -> QuestKind {
    let text = q.objective.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "- "))
    if text.contains("ready for turn-in") { return .handIn }
    if text.contains(" slain") { return .kill }
    if text.range(of: #"\d+/\d+"#, options: .regularExpression) != nil { return .collect }
    if text.hasPrefix("use ") || text.contains(" use ") || text.contains("drink ") { return .useAt }
    if ["report to", "speak to", "talk to", "return to", "bring "].contains(where: text.hasPrefix) {
        return .travel
    }
    return q.ready ? .handIn : .useAt
}

/// Zones are clusters of quest pins that are near each other (single linkage).
func questZones(_ quests: [PlannedQuest], within: Double) -> [[PlannedQuest]] {
    var zones: [[PlannedQuest]] = []
    for q in quests {
        guard let p = q.pin else { continue }
        let near = zones.indices.filter { z in zones[z].contains { distance($0.pin!, p) <= within } }
        var merged = near.flatMap { zones[$0] } + [q]
        for z in near.reversed() { zones.remove(at: z) }
        merged.sort { $0.title < $1.title }
        zones.append(merged)
    }
    return zones
}

/// The owner, 24 Sept: "finish all available quests in the same zone, accumulate all quests in next zone
/// for the next priority." The player's zone comes first, walked nearest-first; the other zones follow,
/// nearest first. A finished quest without a pin counts as here (its NPC is usually at this hub); any
/// other pinless quest goes last (live, 24 Sept: an unread pin put a Shen'dar quest in Thendal's zone).
/// A RULE, logged as such.
// ponytail: nearest-neighbour order, not an optimal tour; a hub has a handful of quests.
func questPlan(_ quests: [PlannedQuest], from player: MapPoint, zoneRadius: Double = 12) -> [PlannedQuest] {
    let located = quests.map { q -> PlannedQuest in var q = q; if q.pin == nil && questKind(q) == .handIn { q.pin = player }; return q }
    var zones = questZones(located, within: zoneRadius)
    var plan: [PlannedQuest] = []
    var here = player
    while !zones.isEmpty {
        let nearest = zones.indices.min { a, b in
            zones[a].map { distance(here, $0.pin!) }.min()! < zones[b].map { distance(here, $0.pin!) }.min()!
        }!
        var zone = zones.remove(at: nearest)
        while !zone.isEmpty {
            let next = zone.indices.min { distance(here, zone[$0].pin!) < distance(here, zone[$1].pin!) }!
            let q = zone.remove(at: next)
            plan.append(q)
            here = q.pin!
        }
    }
    return plan + located.filter { $0.pin == nil }
}

/// The "Accept" button of a quest offered in the dialogue (a follow-up shown on completion): the whole
/// line, never a word inside the quest's text. The owner, 24 Sept: "always accept quests" (RULE).
func acceptButton(_ dialog: [TipLine]) -> TipLine? {
    dialog.first { $0.text.trimmingCharacters(in: .whitespaces) == "Accept" }
}

/// A panel is open when the box holds one of a panel's own buttons, a whole line. The world shows through
/// the box when nothing is open (live, 25 Sept: a vendor's green name and title, after Click-to-Move had
/// turned the camera, were taken for her dialogue, and Esc was pressed; Esc with nothing open is the Game Menu).
let panelButtons: Set<String> = ["Accept", "Decline", "Complete Quest", "Continue", "Cancel", "Goodbye"]
func panelOpen(_ lines: [TipLine]) -> Bool {
    lines.contains { panelButtons.contains($0.text.trimmingCharacters(in: .whitespaces)) }
}

/// Whether the position has read within one coordinate step (0.1) of the latest for `window` seconds.
/// Walking steps the coordinates every 0.2-0.3 s (live run 3, 25 Sept), so a step's tolerance absorbs a
/// reading that flickers while standing and still ends within a second of walking. Unreadable reads (a
/// name over the text) count neither way; the window needs a readable read at each end.
func stoodStill(_ track: [(t: Double, at: MapPoint?)], for window: Double) -> Bool {
    let read = track.compactMap { r in r.at.map { (t: r.t, at: $0) } }
    guard let last = read.last else { return false }
    let near = read.reversed().prefix { abs($0.at.x - last.at.x) <= 0.11 && abs($0.at.y - last.at.y) <= 0.11 }
    return last.t - near.last!.t >= window
}

/// Whether the game's unit tooltip names the NPC whose green name was read in the world. OCR can drop a
/// letter or two at the ends ("alia the Collector", live 25 Sept); a part of the name ("Dalia", "Collector")
/// or a neighbour's name is not the NPC. Five letters at least.
func sameUnit(_ tooltip: String, _ name: String) -> Bool {
    let a = nameKey(tooltip), b = nameKey(name)
    let (short, long) = a.count <= b.count ? (a, b) : (b, a)
    guard short.count >= 5, long.count - short.count <= 2 else { return false }
    return long.contains(short)
}

/// Whether a line read in the quest dialogue is the quest's title. The title is drawn in a decorative
/// capital face that OCR misreads a letter at a time (live run 5, 25 Sept: "HARVEStinG WinostonES" for
/// Harvesting Windstones, and the open page was taken for another quest's and closed). One letter in
/// eight may differ, as an edit; a title under eight letters must match exactly.
func sameTitle(_ line: String, _ title: String) -> Bool {
    let a = Array(nameKey(line)), b = Array(nameKey(title)), slack = b.count / 8
    guard !a.isEmpty, !b.isEmpty, abs(a.count - b.count) <= slack else { return false }
    var previous = Array(0...b.count)
    for (i, ca) in a.enumerated() {
        var current = [i + 1]
        for (j, cb) in b.enumerated() {
            current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1)))
        }
        previous = current
    }
    return previous[b.count] <= slack
}

/// The NPC's own name among the OCR lines of the box around it: level with the green name's top (within
/// one line of UI text) and starting left of the name's centre, the nearest such start. A name beside it at
/// the same depth starts right of the centre, or further left than this one.
func nameLine(_ lines: [TipLine], nameX: Double, nameTop: Double) -> TipLine? {
    lines.filter { abs($0.y - nameTop) <= 8 && $0.x <= nameX }.max { $0.x < $1.x }
}

/// Where to rest the pointer on the NPC under a mark, best first, all in the mark's own scale: below the
/// name's centre at the chest, the waist and the legs, then half a mark height and a whole one to each
/// side (live, 25 Sept: Dalia's body stood 17 px left of her name's centre under a 33 px "?"); last, below
/// the "?" itself, where the click went before.
func hoverPoints(_ m: QuestMark) -> [(x: Double, y: Double)] {
    let name = m.body - 2.4 * m.h  // the name's bottom
    let rows = [name + 1.4 * m.h, m.body, name + 3.4 * m.h]
    let columns = [0, -0.5, 0.5, -1, 1].map { m.nameX + $0 * m.h }
    return columns.flatMap { x in rows.map { (x, $0) } } + [(m.x, m.body)]
}

/// Whether the NPC's tooltip has gone: the last two reads, both on fresh frames, lack its name. An
/// unreadable frame (nil) proves nothing, and one OCR miss is not "gone" (review, 25 Sept).
func tooltipGone(_ reads: [Bool?]) -> Bool {
    reads.count >= 2 && reads.suffix(2).allSatisfy { $0 == false }
}

/// Whether an unconfirmed click would repeat the last unconfirmed one: within half a mark height of it
/// (live run 4: three clicks at one point below Dalia's "?" found the ground). A new mark after
/// Click-to-Move has moved the character is a new point.
func repeatsClick(_ p: (x: Double, y: Double), _ last: (x: Double, y: Double)?, h: Double) -> Bool {
    guard let last else { return false }
    return abs(p.x - last.x) <= h / 2 && abs(p.y - last.y) <= h / 2
}

/// The plan's quests in the player's own zone: those chained within `zoneRadius` of the player. Any other
/// zone is road travel, which is not built (live, 24 Sept: with the hub's two hand-ins unread, the nearest
/// zone was Shen'dar, 20 units south, and the walk ran for a cliff).
func thisZone(_ plan: [PlannedQuest], from player: MapPoint, zoneRadius: Double = 12) -> [PlannedQuest] {
    let me = PlannedQuest(title: "\u{0}", level: 0, ready: false, objective: "", pin: player)
    let zone = questZones([me] + plan, within: zoneRadius).first { $0.contains { $0.title == me.title } } ?? []
    return plan.filter { q in zone.contains { $0.title == q.title } }
}

/// The minimap's quest icons by shape. A "!" is a giver: its tooltip names a quest not yet taken. A "?"
/// names a quest the log must hold, so only a "?" tooltip counts towards `missingFromLog`.
func sortIcons(_ icons: [(at: MapPoint, offer: Bool, read: [String])])
    -> (givers: [Giver], hints: [(names: [String], at: MapPoint)], tooltips: [[String]]) {
    var givers: [Giver] = [], hints: [(names: [String], at: MapPoint)] = [], tooltips: [[String]] = []
    for icon in icons {
        if icon.offer {
            givers.append(Giver(names: icon.read.filter { nameKey($0).count >= 4 }, pin: icon.at))  // "18 m" is not a name
        } else {
            hints.append((icon.read.map(nameKey), icon.at))
            tooltips.append(icon.read)
        }
    }
    return (givers, hints, tooltips)
}

/// Names in the minimap's "?" tooltips, one tooltip per icon, whose quest the log read lacks ("18 m"
/// distance lines are not names). Any at all means the log read is incomplete (live, 24 Sept: one quest of
/// four): do not plan on it. A tooltip that names a quest the log holds is accounted for, and its other
/// lines are NPC names: 25 Sept, live, near the NPCs, "Dalia the Collector" above "Harvesting Windstones"
/// stopped the run LOG_INCOMPLETE. (So a second quest of that same NPC missing from the log goes unseen.)
func missingFromLog(_ tooltips: [[String]], _ quests: [PlannedQuest]) -> [String] {
    let known = Set(quests.map { nameKey($0.title) })
    var missing: [String] = []
    for tip in tooltips where !tip.contains(where: { known.contains(nameKey($0)) }) {
        for name in tip where nameKey(name).count >= 4 && !missing.contains(name) { missing.append(name) }
    }
    return missing
}

/// The Map & Quest Log's list, as OCR lines: "[4] Call of Earth" titles, objectives indented under
/// them, zone headers ("Camping") to their left. Pins are added from the map afterwards.
/// OCR misreads the level's frame (live run 7, 26 Sept): "]" as "1" ("[51 The Next Step"), and the "?"
/// icon before it as ")" (") [6] The Adventurer"); the log then read empty. So up to three characters that
/// are not letters, digits or "-" may come before "[" (text before it is an objective's, "to [4] Camp"),
/// and the closing bracket may read as 1, l, I or | when a space follows: the character before the space
/// closes the level. `prefixed`: the line started before the title column.
func questTitle(_ text: String) -> (level: Int, title: String, prefixed: Bool)? {
    guard let m = text.firstMatch(of: try! Regex(#"^([^\[\p{L}\d-]{0,3})\[(\d{1,2})(?:\]\s*|[1lI|]\s+)"#)),
          let digits = m.output[2].substring, let level = Int(digits) else { return nil }
    let title = String(text[m.range.upperBound...])
    return title.isEmpty ? nil : (level, title, !(m.output[1].substring?.isEmpty ?? true))
}

func parseQuestLog(_ lines: [TipLine]) -> [PlannedQuest] {
    var out: [PlannedQuest] = []
    var titleX = Double.infinity, column: Double? = nil  // the x of titles read without a prefix
    for line in lines.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
        let text = line.text.trimmingCharacters(in: .whitespaces)
        if let (level, title, prefixed) = questTitle(text) {
            out.append(PlannedQuest(title: title, level: level, ready: false, objective: "", pin: nil))
            if !prefixed { column = line.x }
            titleX = prefixed ? column ?? line.x : line.x  // a prefix starts left of the column the objectives are measured from
        } else if (line.x >= titleX + 6 || text.hasPrefix("-")), titleX.isFinite, !out.isEmpty {  // live: "- Ready for turn-in" starts at the title's x
            out[out.count - 1].objective += (out[out.count - 1].objective.isEmpty ? "" : " ") + text
            out[out.count - 1].ready = out[out.count - 1].objective.lowercased().contains("ready for turn-in")
        } else {
            titleX = .infinity  // a zone header ends the quest above it
        }
    }
    return out
}

/// World-map pixels to zone coordinates: the Map & Quest Log at 2560x1320 (24 Sept; 7.42 px per x unit
/// and 4.99 per y unit, as measured in M4a).
// ponytail: one zone's map, one UI scale; read the transform from two known points when zones change.
let mapOrigin = (x: 20.0, y: 224.3), mapScale = (x: 7.42, y: 4.99)
func zonePoint(_ px: Double, _ py: Double) -> MapPoint { ((px - mapOrigin.x) / mapScale.x, (py - mapOrigin.y) / mapScale.y) }
func mapPixel(_ p: MapPoint) -> (x: Double, y: Double) { (mapOrigin.x + p.x * mapScale.x, mapOrigin.y + p.y * mapScale.y) }

/// The map's own "Cursor: 42.3, 22.9" line, in zone coordinates whatever map it shows (live, 26 Sept: a new
/// character's map opened on Thendal Village, not Zephras Isle, so the fixed transform above did not hold).
func mapCursor(_ lines: [String]) -> MapPoint? {
    let text = lines.joined(separator: " ")
    guard let m = text.range(of: #"Cursor:?\s*\d{1,2}\.\d\s*,\s*\d{1,2}\.\d"#, options: .regularExpression) else { return nil }
    let numbers = text[m].split { !$0.isNumber && $0 != "." }.compactMap { Double($0) }
    return numbers.count == 2 ? (numbers[0], numbers[1]) : nil
}

/// A north-up minimap pixel to zone coordinates, from the player at its centre (M4a: 19 px per y unit).
func minimapPoint(_ px: Double, _ py: Double, player: MapPoint) -> MapPoint {
    (player.x + (px - Double(MinimapHUD.cx)) / MinimapHUD.unitPx / mapAspect, player.y + (py - Double(MinimapHUD.cy)) / MinimapHUD.unitPx)
}

/// Quest icons on the minimap: a hub's hand-ins sit together under the world map's arrow, and the minimap's
/// larger scale separates them (24 Sept). `offer` marks a "!" (a quest to take): its bar is 2-5 px wide on
/// the 23 Sept Thendal frames, where a "?" hook is 6-7 px on the 24 Sept live scans.
// ponytail: width alone; add the bar's fill (solid, where a hook has a gap) if a 5-6 px glyph turns up.
func minimapPins(_ image: RGBA) -> [(x: Double, y: Double, offer: Bool)] {
    let r = MinimapHUD.radius, cx = MinimapHUD.cx, cy = MinimapHUD.cy
    let icons = glyphs(yellowBlobs(image, box: (cx - r, cy - r, cx + r, cy + r), gap: 0))
        .filter { $0.n >= 8 && $0.x1 - $0.x0 <= 20 && $0.y1 - $0.y0 <= 20 && $0.y1 - $0.y0 >= $0.x1 - $0.x0 }  // upright: not an area's dashed edge
    // Four or more on one baseline are the letters of a tooltip's yellow title, not icons.
    return icons.filter { i in icons.filter { abs($0.y1 - i.y1) <= 3 }.count < 4 }
        .map { (Double($0.sx) / Double($0.n), Double($0.sy) / Double($0.n), $0.x1 - $0.x0 + 1 <= 5) }
        .filter { hypot($0.0 - Double(cx), $0.1 - Double(cy)) <= Double(r) - 4 }
}

/// "?" and "!" as a hook or bar with a dot under it. Three minimap "?" sat so close on 24 Sept that one's
/// dot was as near another's hook as its own, so a dot joins the part just above it, within its width.
func glyphs(_ parts: [Blob]) -> [Blob] {
    var hooks = parts.filter { $0.y1 - $0.y0 > 3 }
    for dot in parts where dot.y1 - dot.y0 <= 3 {
        let cx = dot.sx / dot.n
        guard let j = hooks.indices.filter({ hooks[$0].y1 < dot.y0 && dot.y0 - hooks[$0].y1 <= 4
                                            && cx >= hooks[$0].x0 - 2 && cx <= hooks[$0].x1 + 2 })
            .min(by: { dot.y0 - hooks[$0].y1 < dot.y0 - hooks[$1].y1 }) else { continue }
        let h = hooks[j]
        hooks[j] = (h.n + dot.n, h.sx + dot.sx, h.sy + dot.sy, min(h.x0, dot.x0), max(h.x1, dot.x1), h.y0, max(h.y1, dot.y1))
    }
    return hooks
}

// M4f: Jev chooses each quest step through a decision graph (runtime/skyborne-quest.graph.json). Local code
// reads the log, offers only the steps it can run here and runs the chosen one. The owner's zone-first
// order is a reference Jev may read, not a queue the script works through.

/// A quest giver's "!" on the minimap: what its tooltip read (not yet known whether that is the giver's or
/// the quest's name) and where it stands.
struct Giver {
    var names: [String]
    var pin: MapPoint
    var inView = false  // no minimap "!": a yellow mark in the world view (a giver a few yards away is under the arrow)
    var key: String { String(format: "%.1f,%.1f", pin.x, pin.y) }
}

/// One read of the Map & Quest Log, the minimap's quest icons and the player's position.
struct QuestRead {
    var quests: [PlannedQuest]
    var player: MapPoint
    var missing: [String]  // named by a "?" tooltip but absent from the log read
    var givers: [Giver] = []
}

protocol QuestHost: AnyObject {
    func readQuests() async -> QuestRead?  // nil: the position was unreadable
    func handIn(_ quest: PlannedQuest) async -> String  // walk to its pin, then M4c's hand-in; the outcome
    func accept(_ giver: Giver) async -> String  // walk to its "!", open its offer and press Accept
    func retreat() async -> String  // walk back to where the last walk began; RETREATED, NO_WAY_BACK or a WALK_ outcome
    func fightBack() async -> String  // attacked on a walk: one M3 fight; its outcome (M4i)
    func hunt(_ quest: PlannedQuest, seconds: Double) async -> String  // walk to its area, then one M4b hunt: huntOutcome
    func now() -> Double
    func ownerTookFocus() -> Bool
    func emit(_ event: String, _ fields: [String: Any])
}

enum QuestLimits {
    static let slots = 4  // HAND_IN_1 to HAND_IN_4 in the graph
    static let giverSlots = 3  // ACCEPT_1 to ACCEPT_3
    static let huntSlots = 2  // HUNT_1 and HUNT_2
    static let maxSteps = 12
    // The run envelope allows 30 min a run. No step starts after 25 min; a hunt gets what is left of
    // them, at most its own 15, so the last step's walk and fights have 5 min of margin.
    static let runSeconds = 1500.0
    // A hunt that ends at one of its limits with no count risen fails its step; any other code that is
    // not HUNTED ends the run (death, the owner, the HUD, Jev, a lost fight, keys held).
    static let huntFails: Set<String> = ["HUNT_DECISION_LIMIT", "HUNT_FIGHT_LIMIT", "HUNT_TIME_LIMIT",
                                         "HUNT_NO_TARGET_FOUND", "HUNT_NO_UNFINISHED_OBJECTIVE"]
    static let maxLeg = 12.0  // a hub is smaller: a longer walk is zone travel, which waits for roads
    static let decisionSeconds = 20.0  // chosen standing in a hub, with up to four graph calls
    // After a right-click on an NPC, Click-to-Move walks there: the box is read every `clickPoll` s until a
    // panel opens or the character has stood still for `standStill` s. Walking steps the coordinates every
    // 0.2-0.3 s, but a background click can leave the capture quiet for 1-2 s (QuestRun.frame), hence 2 s.
    // `clickWalk` bounds the wait: 3 units, 15 s of running, beyond the walk's 0.5 and a pin's error.
    static let clickPoll = 0.5, standStill = 2.0, clickWalk = 15.0
    // One hover sweep over an NPC's points (QuestRun.onUnit) stops starting points after 12 s: a read takes
    // 0.7 s, or up to 2.9 s when a background move stalls the capture.
    static let hoverSeconds = 12.0
    // Only a kill lets a quest run go on after a fight back. Not the hunt's JEV_STOP: M3 cannot select an
    // attacker behind (Tab looks ahead), and walking on while still attacked would only fight again.
    static let fightWon: Set<String> = ["KILLED_AND_LOOTED", "KILLED_NO_CORPSE"]
}

/// A step local code can run here: a hand-in, a quest to take, a hunt for a quest's creatures, or a way
/// back from danger (M4h).
enum QuestStep {
    case handIn(PlannedQuest)
    case accept(Giver)
    case hunt(PlannedQuest)
    case retreat
    var name: String {
        switch self {
        case .handIn(let q): return q.title
        case .accept(let g): return g.names.first.map { "\"!\" \($0)" } ?? "\"!\" at \(g.key)"
        case .hunt(let q): return "hunt: " + q.title
        case .retreat: return "retreat"
        }
    }
    var key: String {  // what a failure is remembered by
        switch self {
        case .handIn(let q), .hunt(let q): return q.title
        case .accept(let g): return "!" + g.key
        case .retreat: return "RETREAT"
        }
    }
}

/// A hunt's code as a quest step. HUNTED: its objectives are complete. HUNTED_SOME: a limit ended it after
/// a count rose or a quest became ready, so the step may be offered again. Otherwise "HUNT_" and its code.
func huntOutcome(_ code: String, start: [Objective], end: [Objective]) -> String {
    if code == "OBJECTIVES_COMPLETE" { return "HUNTED" }
    let rose = end.contains { e in
        start.contains { s in s.unfinished && s.quest == e.quest && (e.text == Objective.ready || (s.text == e.text && e.done > s.done)) }
    }
    return rose && QuestLimits.huntFails.contains("HUNT_" + code) ? "HUNTED_SOME" : "HUNT_" + code
}

/// The steps local code offers, none already failed this run and each within one walk of the player:
/// hand-ins for quests a hand-in can finish (ready, or a delivery to someone), in the owner's order; then
/// the minimap's "!" givers, nearest first (the owner: always accept quests); then hunts for kill and
/// collect quests, in the owner's order. A hunt fights for every unfinished objective the tracker shows,
/// so quests that share a place finish together. A quest whose area the map did not show is hunted from
/// here, by the minimap's quest area. After a walk stopped for a red name ahead, RETREAT comes first (the
/// owner: survive first). Use-at quests have no skill yet and are not offered.
func questOffers(_ read: QuestRead, failed: Set<String>, danger: Bool = false) -> [(skill: String, step: QuestStep, criterion: String)] {
    func away(_ p: MapPoint) -> String { String(format: "%.1f", distance(read.player, p)) }
    let open = questPlan(read.quests, from: read.player).filter { q in
        [.handIn, .travel].contains(questKind(q)) && !failed.contains(q.title)
            && q.pin.map { distance(read.player, $0) <= QuestLimits.maxLeg } == true
    }
    let handIns = open.prefix(QuestLimits.slots).enumerated().map { i, q in
        ("HAND_IN_\(i + 1)", QuestStep.handIn(q), "Walk to the quest giver of \"\(q.title)\" (level \(q.level), \(away(q.pin!)) units away) "
            + "and hand it in. The log reads: \(q.objective.isEmpty ? "(no objective line)" : q.objective)")
    }
    let givers = read.givers.filter { !failed.contains("!" + $0.key) && distance(read.player, $0.pin) <= QuestLimits.maxLeg }
        .sorted { distance(read.player, $0.pin) < distance(read.player, $1.pin) }
    let accepts = givers.prefix(QuestLimits.giverSlots).enumerated().map { i, g in
        ("ACCEPT_\(i + 1)", QuestStep.accept(g), g.inView
            ? "Walk to the yellow quest mark in view and accept the quest its NPC offers. The minimap showed no \"!\": a giver a few "
                + "yards away is drawn under the player's arrow. A \"?\" of a quest to hand in looks alike, and offers nothing to accept."
            : "Walk to the quest giver shown by a \"!\" on the minimap (\(away(g.pin)) units away; its tooltip read "
                + "\(g.names.isEmpty ? "nothing" : g.names.joined(separator: ", "))) and accept the quest it offers.")
    }
    let hunted = questPlan(read.quests, from: read.player).filter { q in
        [.kill, .collect].contains(questKind(q)) && !failed.contains(q.title)
            && q.pin.map { distance(read.player, $0) <= QuestLimits.maxLeg } != false
    }
    let hunts = hunted.prefix(QuestLimits.huntSlots).enumerated().map { i, q in
        ("HUNT_\(i + 1)", QuestStep.hunt(q), (q.pin.map { "Walk to the area of \"\(q.title)\" (level \(q.level), \(away($0)) units away), then hunt" }
            ?? "Hunt for \"\(q.title)\" (level \(q.level)) from here, by the minimap's quest area (the map showed no area),")
            + " the creatures that the tracker's unfinished objectives name: fight, loot, rest and eat as the hunt chooses, up to "
            + "\(HuntLimits.maxFights) fights. Objects on the ground are not picked up. The log reads: \(q.objective)")
    }
    let back = danger && !failed.contains("RETREAT") ? [("RETREAT", QuestStep.retreat, "Walk back to where the last walk began: "
        + "a hostile creature's red name came into view ahead of it.")] : []
    return back + handIns + accepts + hunts
}

/// Jev's input: the goal and position; the log (every quest in the owner's zone-first order) and the steps
/// taken are READ resources, loaded only when Jev asks for them.
func questState(_ read: QuestRead, steps: [(quest: String, outcome: String)]) -> [String: Any] {
    let plan = questPlan(read.quests, from: read.player)
    let zone = Set(thisZone(plan, from: read.player).map(\.title))
    return ["goal": "Finish the quests of the player's zone; the next zone's quests come after (the owner's order).",
            "player": [read.player.x, read.player.y],
            "units": "zone-map coordinates; distances in y units, about 5 s of running each",
            "quest_log": plan.map { q -> [String: Any] in
                ["title": q.title, "level": q.level, "kind": questKind(q).rawValue, "objective": q.objective,
                 "in_this_zone": zone.contains(q.title),
                 "distance": q.pin.map { roundTo(distance(read.player, $0), 10) } as Any? ?? NSNull()] },
            "givers": read.givers.map { ["tooltip": $0.names, "distance": roundTo(distance(read.player, $0.pin), 10)] },
            "recent_steps": steps.suffix(6).map { ["quest": $0.quest, "outcome": $0.outcome] }]
}

struct QuestResult {
    var outcome = ""
    var steps: [(quest: String, outcome: String)] = []
    var graphRecords: [[String: Any]] = []
}

/// Read, offer, let Jev choose, run, and read again: a hand-in changes the log. A walk that stops for
/// combat, health, the owner or the HUD ends the run; the second NO_PROGRESS ends it (the run envelope).
/// A walk that stops for a red name ahead fails only its step, and RETREAT is offered next; a retreat that
/// does not get back ends the run. A walk that is attacked hands over to one M3 fight at once (SAFETY: in
/// combat the only choice is to fight back); a won fight lets the run go on, and the interrupted step may
/// be offered again. A failed step is not offered again this run. A hunt that completes or counts some kills
/// lets the run go on; one that ends at a limit with nothing counted fails its step; any other hunt code
/// ends the run. No step starts after `runSeconds`. There is no rules fallback when Jev fails.
func runQuests(host: QuestHost, jev: JevClient, graph: GraphSession) async -> QuestResult {
    var r = QuestResult()
    var failed: Set<String> = []
    var stuck = 0
    let began = host.now()
    func finish(_ outcome: String) -> QuestResult {
        r.outcome = outcome
        host.emit("quests_done", ["outcome": outcome, "steps": r.steps.map { ["quest": $0.quest, "outcome": $0.outcome] }])
        return r
    }
    while r.steps.count < QuestLimits.maxSteps {
        if host.ownerTookFocus() { return finish("OWNER_TOOK_FOCUS") }
        if host.now() - began >= QuestLimits.runSeconds { return finish("TIME_LIMIT") }
        guard let read = await host.readQuests() else { return finish("POSITION_UNREADABLE") }
        guard read.missing.isEmpty else { return finish("LOG_INCOMPLETE") }  // see quest-log.png
        let offers = questOffers(read, failed: failed, danger: r.steps.last?.outcome == "WALK_DANGER_AHEAD")
        if offers.isEmpty {
            let deliveries = read.quests.filter { [.handIn, .travel, .kill, .collect].contains(questKind($0)) && !failed.contains($0.title) }
            return finish(deliveries.isEmpty ? "NOTHING_TO_HAND_IN_OR_TAKE" : "NEXT_ZONE_NEEDS_ROADS")
        }
        let decision: GraphDecision
        do {
            decision = try await graph.next(state: questState(read, steps: r.steps),
                skills: Dictionary(uniqueKeysWithValues: offers.map { ($0.skill, $0.criterion) }), jev: jev,
                now: host.now, deadline: host.now() + QuestLimits.decisionSeconds, stopped: host.ownerTookFocus)
        } catch {
            for call in graph.lastTrace { r.graphRecords.append(call); host.emit("graph_call", call) }
            return finish(error is GraphError ? "GRAPH_\(error)" : "JEV_FAILED")
        }
        for call in graph.lastTrace { r.graphRecords.append(call); host.emit("graph_call", call) }
        guard let offer = offers.first(where: { $0.skill == decision.action }) else { return finish("INVALID_REPLY") }
        host.emit("quest_step", ["controller": "JEV", "skill": offer.skill, "step": offer.step.name])
        let outcome: String
        switch offer.step {
        case .handIn(let q): outcome = await host.handIn(q)
        case .accept(let g): outcome = await host.accept(g)
        case .hunt(let q): outcome = await host.hunt(q, seconds: min(HuntLimits.maxSeconds, QuestLimits.runSeconds - (host.now() - began)))
        case .retreat: outcome = await host.retreat()
        }
        r.steps.append((offer.step.name, outcome))
        if outcome == "WALK_COMBAT" {  // the owner: survive first, inside the engine
            host.emit("quest_step", ["controller": "SAFETY", "skill": "FIGHT_BACK", "step": "fight back"])
            let fought = await host.fightBack()
            r.steps.append(("fight back", fought))
            guard QuestLimits.fightWon.contains(fought) else { return finish("FIGHT_" + fought) }
            continue
        }
        if outcome.hasPrefix("COMPLETED") || outcome.hasPrefix("ACCEPTED") || outcome.hasPrefix("HUNTED") || outcome == "RETREATED" { continue }
        if case .retreat = offer.step { return finish("RETREAT_" + outcome) }  // no way back from danger: the owner takes over
        failed.insert(offer.step.key)
        if outcome == "WALK_NO_PROGRESS" {
            stuck += 1
            if stuck >= 2 { return finish("NO_PROGRESS_TWICE") }
        } else if outcome.hasPrefix("WALK_") && outcome != "WALK_DANGER_AHEAD" {  // danger: the step is not offered again
            return finish(outcome)
        } else if outcome.hasPrefix("HUNT_") && !QuestLimits.huntFails.contains(outcome) {
            return finish(outcome)
        }
    }
    return finish("STEP_LIMIT")
}
