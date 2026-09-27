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

/// A reward's tooltip, read while the pointer rests on it, or a bag item's (M4x). The game draws the equipped item beside it
/// ("Equipped", then "If you replace this item, the following stat changes will occur: +2 Armor"), and whatever is behind
/// shows through (the quest text; the backpack's title and search box, world text): lines are kept by alignment, as in
/// tooltipLines, from the name down.
func parseReward(_ lines: [TipLine]) -> Reward? {
    guard let foot = lines.first(where: { isTooltipFooter($0.text) }) else { return nil }
    // The equipped item's box starts at its "Equipped" label or its "If you replace" line; live on 24 Sept
    // OCR missed the latter once, and the box's own lines were then read as the reward's. It sits right of a quest reward's
    // box, and left of a bag item's by the screen's right edge (live, 27 Sept): only on the right does it bound the item's lines.
    let compare = lines.first { $0.text.hasPrefix("If you replace this item") }
    let equipped = lines.filter { $0.text == "Equipped" || $0.text.hasPrefix("If you replace this item") }.map(\.x).min()
    let right = equipped.map { $0 > foot.x ? $0 - 12 : .infinity } ?? .infinity
    // The name is tooltipName's (live, 27 Sept: the backpack's title stood 2 px above a belt's name, off its left edge).
    guard let name = tooltipName(lines, foot: foot, slack: 8) else { return nil }
    let own = lines.filter {
        $0.y >= name.y - 4 && $0.y < foot.y && $0.x < right && (abs($0.x - foot.x) <= 8 || $0.x >= foot.x + 150)
    }
    let slot = own.map(\.text).first { equipSlots.contains($0) }
    let sell = own.first { $0.text.hasPrefix("Sell Price") }.flatMap { Int($0.text.filter(\.isNumber)) } ?? 0
    let change: Double
    if let compare {
        change = lines.filter { abs($0.x - compare.x) <= 8 && $0.y > compare.y }.compactMap { line -> Double? in
            // "+5 Armor"; live on 27 Sept OCR read "-3 Armor" as "- 3 Armor"
            guard let sign = line.text.first, "+-".contains(sign) else { return nil }
            return Double(String(sign) + line.text.dropFirst().drop { $0 == " " }.prefix { $0.isNumber || $0 == "." })
        }.reduce(0, +)
    } else if equipped != nil {
        change = 0  // an equipped item, but its stat changes were not read: not an upgrade
    } else {
        change = own.lazy.compactMap { $0.text.hasSuffix(" Armor") ? Double($0.text.dropLast(6)) : nil }.first ?? 0
    }
    return Reward(name: name.text, slot: slot, usable: !own.contains(where: \.red), change: change, sell: sell)
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

/// The bag items to put on (M4x, the owner, 27 Sept: "i don't see you equip?"; "we should always wear better gear first when
/// non-battle"): the owner's reward rule (24 Sept) applied to what the bags hold. Each usable item with a slot whose game
/// comparison is an upgrade (change > 0; an empty slot counts its armour) is worn; for two items of one slot, the larger
/// change. In bag order.
func equipChoices(_ items: [(name: String, reward: Reward)]) -> [String] {
    var best: [String: (index: Int, change: Double)] = [:]
    for (i, item) in items.enumerated() {
        guard item.reward.usable, let slot = item.reward.slot, item.reward.change > 0 else { continue }
        if best[slot].map({ item.reward.change > $0.change }) ?? true { best[slot] = (i, item.reward.change) }
    }
    return best.values.map(\.index).sorted().map { items[$0].name }
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
func yellowBlobs(_ image: RGBA, box: (Int, Int, Int, Int), gap: Int = 13,
                 colour: (Int, Int, Int) -> Bool = markYellow) -> [Blob] {
    let x0 = max(0, box.0), y0 = max(0, box.1), x1 = min(box.2, image.width), y1 = min(box.3, image.height)
    let w = x1 - x0, h = y1 - y0
    guard w > 0, h > 0 else { return [] }
    var mask = [Bool](repeating: false, count: w * h)
    for y in y0..<y1 {
        for x in x0..<x1 {
            let i = (y * image.width + x) * 4
            if colour(Int(image.pixels[i]), Int(image.pixels[i + 1]), Int(image.pixels[i + 2])) { mask[(y - y0) * w + x - x0] = true }
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
/// A quest in progress has "..." on a dark disc: three yellow dots of 2-3 px, 3 px apart, which join only with a wider gap,
/// as a flat row 11-15 px wide (live run 33, 27 Sept: Infestation Investigation's pin and two others were not found, so
/// the hunt had no area and found no Cirrusfly). Each spot is hovered, and only a tooltip naming a quest pins it.
func mapPins(_ image: RGBA, box: (Int, Int, Int, Int) = (70, 280, 730, 700)) -> [(x: Double, y: Double)] {
    let centre = { (b: Blob) in (x: Double(b.sx) / Double(b.n), y: Double(b.sy) / Double(b.n)) }
    let glyphs = yellowBlobs(image, box: box, gap: 2).filter { $0.n >= 10 && $0.x1 - $0.x0 <= 26 && $0.y1 - $0.y0 <= 26 }.map(centre)
    let dots = yellowBlobs(image, box: box, gap: 4).filter { b in b.n >= 6 && (9...16).contains(b.x1 - b.x0 + 1) && b.y1 - b.y0 + 1 <= 5 }
        .map(centre).filter { d in !glyphs.contains { hypot($0.x - d.x, $0.y - d.y) < 12 } }
    return glyphs + dots
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

/// A mark the learned reader (M5) found, as a click target: its glyph box (x, y, width, height) with the NPC's name
/// and body placed below it as questMarks places them for a mark of that height (the name about one height under
/// the glyph, the body 4 heights). The rules miss a near mark (live run 21, 26 Sept: Rorian's 21 x 46 px "?" beside
/// him, which the learned reader read), so the learned reader adds click targets; a hover must confirm each one.
func learnedMark(_ box: [Int]) -> QuestMark {
    let h = Double(box[3]), x = Double(box[0]) + Double(box[2] - 1) / 2, y = Double(box[1]) + (h - 1) / 2
    return (x, y, h, y + 4 * h, x, y + 0.9 * h)
}

/// A rule mark's glyph as a box (x, y, width, height) for the learned reader's shape crop: square, its height each way,
/// since that crop's side follows the longer of the two, and a mark is never wider than tall.
func glyphBox(_ m: QuestMark) -> [Int] {
    let h = Int(m.h.rounded())
    return [Int((m.x - m.h / 2).rounded()), Int((m.y - m.h / 2).rounded()), h, h]
}

/// The learned marks the rules did not find: none within a mark's height of a rule mark.
func extraMarks(_ learned: [QuestMark], beside rules: [QuestMark]) -> [QuestMark] {
    learned.filter { l in !rules.contains { hypot($0.x - l.x, $0.y - l.y) <= max(12, max($0.h, l.h)) } }
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
    var ender: String? = nil  // who takes it in, from the quest knowledge (M4v)
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
/// A quest with no pin is not kept either: standing on its NPC, the pin hides under the player's arrow, and a kept
/// read without it offered nothing for the hour (live runs 19-20, 26 Sept).
func rememberLog(_ quests: [PlannedQuest], tracker: [String], key: String, missing: [String]) -> Bool {
    let log = nameKey(quests.map { $0.title + " " + $0.objective }.joined(separator: " "))
    let lines = tracker.map(nameKey).filter { !$0.isEmpty }
    return !key.isEmpty && !quests.isEmpty && missing.isEmpty && !lines.isEmpty && trackerShows(quests, tracker)
        && lines.allSatisfy { log.contains($0) } && quests.allSatisfy { $0.pin != nil }
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
    // Live run 15, 26 Sept: "Speak with Rorian the Dayseeker in Thendal Grove." (Coming of Age) was taken for a use-at.
    if ["report to", "speak to", "speak with", "talk to", "talk with", "return to", "bring "].contains(where: text.hasPrefix) {
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

/// A greeting's quest entry: its icon, then a title (capitalised, three letters at least). OCR reads the yellow icon as one
/// character, not always the same: "!" (live run 14, 26 Sept: "! Coming of Age" below "Hello, shaman."), "?" (run 31:
/// "? The Gift of Skysight") and "g" (run 33: "g Elemental Unrest"). The title, or nil for another line: the NPC's name,
/// the greeting's text, a bare icon.
func questEntry(_ text: String) -> String? {
    let parts = text.split(separator: " ", maxSplits: 1)
    guard parts.count == 2, parts[0].count == 1, let first = parts[1].first, first.isUppercase,
          parts[1].filter(\.isLetter).count >= 3 else { return nil }
    return String(parts[1])
}

/// The greeting's entry the minimap's tooltip named. The panel's title is the NPC's name, which a "!" tooltip names too
/// (live run 32, 27 Sept: Ventaari Brightwish's title was clicked and his offer left), so only a quest entry is it.
func namedEntry(_ dialog: [TipLine], names: [String]) -> TipLine? {
    dialog.first { l in questEntry(l.text).map { t in names.contains { nameKey($0) == nameKey(t) } } ?? false }
}

/// The quest an NPC's greeting offers to take: the first entry whose quest is not in the log (`ours`). An entry of the
/// log's is one to hand in, whatever its icon read as; the page must still show Accept.
func offeredEntry(_ dialog: [TipLine], ours: [String]) -> TipLine? {
    dialog.first { l in questEntry(l.text).map { t in !ours.contains { sameTitle(t, $0) } } ?? false }
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

/// Whether the unit tooltip is an NPC's: a level line that is not a player's. Only NPCs carry quest marks, so an NPC's
/// tooltip under a mark is its giver even when the green name was misread (live run 17, 26 Sept: Rorian the Dayseeker's
/// name read "Befeshgar h a depafeke" among four players, and his own tooltip, "Level 20", was not taken).
func npcTip(_ tooltip: [String]) -> Bool {
    let lines = tooltip.map { $0.lowercased() }
    return lines.contains { $0.hasPrefix("level ") } && !lines.contains { $0.contains("(player)") }
}

/// Whether a misread green name is still this unit's name: most of the shorter name's letters appear in order in the
/// longer (a longest common subsequence), 60% at least. On live hovers Rorian the Dayseeker's misread names scored 0.62-1.00
/// ("coen ce badeeke", "Lorian the Dry", "Roriee") and names over other units 0.15-0.56 ("Windshaper Boro" over "Fireflies": 0.22).
/// Rorian's worst reads ("Befeshgar h a depafeke" 0.39, "Recian de Deyrestar Ved" 0.50) do not confirm; the click goes to the mark.
func likeName(_ a: String, _ b: String) -> Bool {
    let x = Array(nameKey(a)), y = Array(nameKey(b))
    guard min(x.count, y.count) >= 3 else { return false }
    var row = [Int](repeating: 0, count: y.count + 1)
    for c in x {
        var diagonal = 0
        for j in y.indices {
            let up = row[j + 1]
            row[j + 1] = c == y[j] ? diagonal + 1 : max(row[j + 1], row[j])
            diagonal = up
        }
    }
    return Double(row[y.count]) >= 0.6 * Double(min(x.count, y.count))
}

enum UnitCheck: Equatable { case confirmed, declined, other }

/// What a hover's unit tooltip says of the NPC under a quest mark, whose green name read `name`. A declined NPC (its panel
/// was opened and closed as someone else's) is never confirmed. The tooltip confirms by a line that is the name, or by an
/// NPC's tooltip (npcTip) whose name line is like the green name, or any NPC's when no name was read. Review of #53: an
/// NPC tooltip alone confirmed any unit with a level line (live: "Fireflies", Level 1, under Windshaper Boro's mark).
func unitCheck(_ tooltip: [String], name: String, declined: [String]) -> UnitCheck {
    if tooltip.contains(where: { line in declined.contains { sameUnit(line, $0) } }) { return .declined }
    if tooltip.contains(where: { sameUnit($0, name) }) { return .confirmed }
    guard npcTip(tooltip), let unit = tooltip.first, !unit.lowercased().hasPrefix("level") else { return .other }
    return nameKey(name).count < 3 || likeName(unit, name) ? .confirmed : .other
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

/// Whether an unconfirmed click would repeat the last unconfirmed one: within half a mark height of it
/// (live run 4: three clicks at one point below Dalia's "?" found the ground). A new mark after
/// Click-to-Move has moved the character is a new point.
func repeatsClick(_ p: (x: Double, y: Double), _ last: (x: Double, y: Double)?, h: Double) -> Bool {
    guard let last else { return false }
    return abs(p.x - last.x) <= h / 2 && abs(p.y - last.y) <= h / 2
}

/// The plan's quests in the player's own zone: those chained within `zoneRadius` of the player. Any other
/// zone is road travel (ROAD_1, ROAD_2): a straight walk does not get there (live, 24 Sept: with the hub's two
/// hand-ins unread, the nearest zone was Shen'dar, 20 units south, and the walk ran for a cliff).
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
/// icon before it as ")" (") [6] The Adventurer"); the log then read empty. The "..." icon of a quest in progress reads as
/// "..• " or ".•) " (live run 43, 27 Sept: two of three quests dropped from the log). So up to five characters that
/// are not letters, digits or "-" may come before "[" (text before it is an objective's, "to [4] Camp"),
/// and the closing bracket may read as 1, l, I or | when a space follows: the character before the space
/// closes the level. `prefixed`: the line started before the title column.
func questTitle(_ text: String, bare: Bool = false) -> (level: Int, title: String, prefixed: Bool)? {
    // "[4] Title". `bare`: also a level without its brackets before a capital, as OCR read a ready quest's title beside its "?"
    // (live run 75, 27 Sept: "4 Return to Rorian", and the run stopped LOG_INCOMPLETE). An objective can read so too ("8
    // Cirrusflies slain"): only readQuestLog asks for it, and takes it only when the log's own count then matches.
    guard let m = text.firstMatch(of: try! Regex(#"^([^\[\p{L}\d-]{0,5})(?:\[(\d{1,2})(?:\]\s*|[1lI|]\s+)|(\d{1,2})\s+(?=\p{Lu}))"#)),
          let digits = m.output[2].substring ?? (bare ? m.output[3].substring : nil), let level = Int(digits) else { return nil }
    let title = String(text[m.range.upperBound...])
    return title.isEmpty ? nil : (level, title, !(m.output[1].substring?.isEmpty ?? true))
}

/// The log's own count, "Quests: 3/40" above its list. A read that parses fewer quests than this missed some (live run 43,
/// 27 Sept: two of three titles led by "..• " went unread, and the run ended with nothing left to do). nil: not read.
func questCount(_ lines: [String]) -> Int? {
    guard let m = lines.joined(separator: " ").firstMatch(of: #/Quests:?\s*(\d{1,2})\s*\/\s*\d{2}/#) else { return nil }
    return Int(m.output.1)
}

/// The log's quests (M4d) against its own count ("Quests: 3/40"): a read short of it is read again with bare levels
/// (questTitle), and that read stands only when it matches the count (review of #80). `bare`: whether it stood.
func readQuestLog(_ lines: [TipLine], shown: Int?) -> (quests: [PlannedQuest], bare: Bool) {
    let strict = parseQuestLog(lines)
    guard let shown, shown > strict.count else { return (strict, false) }
    let loose = parseQuestLog(lines, bare: true)
    return loose.count == shown ? (loose, true) : (strict, false)
}

func parseQuestLog(_ lines: [TipLine], bare: Bool = false) -> [PlannedQuest] {
    var out: [PlannedQuest] = []
    var titleX = Double.infinity, column: Double? = nil  // the x of titles read without a prefix
    for line in lines.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
        let text = line.text.trimmingCharacters(in: .whitespaces)
        if let (level, title, prefixed) = questTitle(text, bare: bare) {
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
/// OCR reads a "6" as "G" and the comma as a dot (live run 34, 27 Sept: "Cursor: 42.G. 22.9" and "45.8. 27.1", so no pin
/// was placed and the hunt had no area). A dot between the numbers needs one decimal on each side, so it reads one way.
func mapCursor(_ lines: [String]) -> MapPoint? {
    let text = String(lines.joined(separator: " ").map { ["G": "6", "З": "3"][$0] ?? $0 })
    let patterns = [#"Cursor:?\s*(\d{1,3}(?:\.\d+)?)\s*,\s*(\d{1,3}(?:\.\d+)?)"#, #"Cursor:?\s*(\d{1,3}\.\d)\s*\.\s*(\d{1,3}\.\d)(?!\d)"#]
    for pattern in patterns {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = try? NSRegularExpression(pattern: pattern).firstMatch(in: text, range: range),
              let a = Range(m.range(at: 1), in: text).flatMap({ Double(text[$0]) }),
              let b = Range(m.range(at: 2), in: text).flatMap({ Double(text[$0]) }) else { continue }
        return (0...100).contains(a) && (0...100).contains(b) ? (a, b) : nil
    }
    return nil
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
    var key: String { inView ? "in view" : String(format: "%.1f,%.1f", pin.x, pin.y) }  // a mark in view has no place of its own
}

/// One read of the Map & Quest Log, the minimap's quest icons and the player's position.
struct QuestRead {
    var quests: [PlannedQuest]
    var player: MapPoint
    var missing: [String]  // named by a "?" tooltip but absent from the log read
    var givers: [Giver] = []
    var items: [String] = []  // the bags' item names, read when a use-at quest may name one (M4m)
    var abilities: [String] = []  // the bar's skills with no fight role ("Skysight"), which a use-at quest may name (M4m)
    var level: Int? = nil  // the character's, from its own unit tooltip (M4u)
    var trainedAt: Int? = nil  // the level at the last visit to the class trainer, from the character's memory (M4u)
    var bagsUsed: Int? = nil  // the bags' slots with an item, when read (M4u)
    var gearSettled = true  // M4x: no upgrade may lie in the bags unworn, so junk may be sold
    var history: [String: StepMemory] = [:]  // the steps' records across runs, by step key (M4y)
}

/// A step's record across runs (M4y; the owner, 27 Sept: "can the engine self-improve? eg path finding, hunt"): how often it
/// has failed since it last worked, how it last ended, and the character's level then. Kept in the character's memory
/// (private), and read by Jev in the step's criterion: Jev still chooses.
struct StepMemory: Equatable {
    var fails: Int
    var last: String
    var level: Int?
}

/// What a step's outcome teaches: one that worked forgets the step's failures; one that says nothing about the step leaves
/// them: the owner's takeover however it is prefixed ("WALK_OWNER_TOOK_FOCUS", "HUNT_OWNER_TOOK_FOCUS", "OWNER_OR_TIME"; review
/// of #81), the clock, combat or danger on the way, the engine's own faults (keys held, a handoff, a HUD unread), nothing to
/// sell or learn yet, gear unsettled. Any other adds one.
func recordStep(_ memory: [String: StepMemory], key: String, outcome: String, level: Int?) -> [String: StepMemory] {
    var memory = memory
    let worked = ["COMPLETED", "ACCEPTED", "HUNTED", "BY_ROAD", "USED", "SOLD", "TRAINED", "RETREATED", "KILLED"].contains { outcome.hasPrefix($0) }
    let silent = ["OWNER", "TIME_LIMIT", "COMBAT", "DANGER", "KEYS_HELD", "HANDOFF", "UNREADABLE", "JEV_FAILED", "LOW_HEALTH"].contains { outcome.contains($0) }
        || ["GEAR_UNSETTLED", "NO_JUNK"].contains(outcome) || outcome.hasPrefix("NOTHING_TO_") || outcome.hasPrefix("BACK_")
    if worked { memory[key] = nil } else if !silent { memory[key] = StepMemory(fails: (memory[key]?.fails ?? 0) + 1, last: outcome, level: level) }
    return memory
}

/// The records as the character's memory holds them (JSON: {"steps": {key: {"fails", "last", "level"}}}); a record without
/// its count is dropped, a missing or partial file reads as none.
func stepHistory(_ memory: [String: Any]) -> [String: StepMemory] {
    ((memory["steps"] as? [String: Any]) ?? [:]).compactMapValues { value in
        (value as? [String: Any]).flatMap { d in
            (d["fails"] as? Int).map { StepMemory(fails: $0, last: d["last"] as? String ?? "", level: d["level"] as? Int) }
        }
    }
}

/// A step's criterion with its record, so Jev can leave a step that keeps failing the same way (live runs 77 and 78: the
/// Windstones hunt ended HUNT_NO_TARGET_FOUND in each, and was chosen first each time).
func withHistory(_ criterion: String, _ memory: StepMemory?) -> String {
    guard let m = memory else { return criterion }
    return criterion + " Earlier runs: this step failed \(m.fails == 1 ? "once" : "\(m.fails) times") since it last worked, the last time as "
        + m.last + (m.level.map { " at level \($0)" } ?? "")
        + "; a step that failed the same way rarely works unless something has changed since (a level, a skill, an item)."
}

protocol QuestHost: AnyObject {
    func readQuests() async -> QuestRead?  // nil: the position was unreadable
    func handIn(_ quest: PlannedQuest) async -> String  // walk to its pin, then M4c's hand-in; the outcome
    func accept(_ giver: Giver) async -> String  // walk to its "!", open its offer and press Accept
    func retreat() async -> String  // walk back to where the last walk began; RETREATED, NO_WAY_BACK or a WALK_ outcome
    func fightAhead() async -> String  // one M3 fight at its start health: runFight's outcome; "BACK_" + it when fought in combat (M4p)
    func fightBack() async -> String  // attacked on a walk: one M3 fight; its outcome (M4i)
    func hunt(_ quest: PlannedQuest, until deadline: Double) async -> String  // walk to its area, then one M4b hunt to the deadline: huntOutcome
    func walkRoad(to quest: PlannedQuest, by legs: [MapPoint], until deadline: Double) async -> String  // walkLegs: BY_ROAD, ROAD_TIME_LIMIT or a WALK_ outcome
    func useItem(_ quest: PlannedQuest, item: String) async -> String  // right-click the bag item the quest names: USED or why not (M4m)
    func visit(_ npc: TownNPC) async -> String  // walk to a town NPC and sell the junk or train there: SOLD, TRAINED, NOTHING_TO_ or why not (M4u)
    func remember(_ key: String, outcome: String, level: Int?)  // a step's outcome into the character's memory (M4y): recordStep
    func now() -> Double
    func ownerTookFocus() -> Bool
    func emit(_ event: String, _ fields: [String: Any])
}

enum QuestLimits {
    static let slots = 4  // HAND_IN_1 to HAND_IN_4 in the graph
    static let giverSlots = 3  // ACCEPT_1 to ACCEPT_3
    static let huntSlots = 2  // HUNT_1 and HUNT_2
    static let useSlots = 1  // USE_1 (M4m)
    static let roadSlots = 2  // ROAD_1 and ROAD_2
    static let roadGapSeconds = 600.0  // a walk round a gap by road: its legs, each bounded by its own walk
    // Where a run's end walks to (the owner, 27 Sept: "error exit should still try best to leave danger zone"; between
    // runs 56 and 57 the character stood idle among level 2-3 hostiles and was killed): the Zephras villages, by their
    // NPCs' places in the town research (learning/research/zephras_services_route.md).
    static let safePlaces: [(name: String, at: MapPoint)] = [("Thendal Village", (43.2, 24.0)), ("Shen'dar Village", (43.4, 44.8)),
                                                            ("Valanaar", (58.2, 78.4))]
    static let safeArrive = 1.0
    static let safeReach = 12.0  // one walk: a safe place farther than this is a run of its own
    static let safeWalks = 4  // walks on the way to safety, and a fight back after each that meets combat
    static let envelopeSeconds = 1800.0  // the owner's run envelope: 30 minutes from the start, the way to safety included
    static let safeWalkSeconds = 20.0  // a shorter walk to safety is not started
    static let reviveClicks = 6  // death recovery's clicks, retries included (M4s)
    static let reviveWait = 10.0  // after Release Spirit, for the gossip (live: about 6 s); after the others, half
    static let reviveSeconds = 90.0  // kept from the way to safety for death recovery: its clicks and their waits
    static let maxSteps = 12
    // The run envelope allows 30 min a run. No step starts after 20 min; a hunt gets what is left of them, at most its
    // own 15. The last step's walk (3 min) and its fight back (2.5) end by 25:30, and the way to safety has the rest,
    // one fight at least (review of #72: 25 min left a fight back after the last walk running past 30).
    static let runSeconds = 1200.0
    // A hunt that ends at one of its limits with no count risen fails its step; any other code that is
    // not HUNTED ends the run (death, the owner, the HUD, Jev, a lost fight, keys held).
    static let huntFails: Set<String> = ["HUNT_DECISION_LIMIT", "HUNT_FIGHT_LIMIT", "HUNT_TIME_LIMIT",
                                         "HUNT_NO_TARGET_FOUND", "HUNT_NO_UNFINISHED_OBJECTIVE", "HUNT_MOVE_LIMIT",
                                         "HUNT_NO_ADMISSIBLE_SKILL"]
    static let maxLeg = 12.0  // a hub is smaller: a longer walk is zone travel, by the learned roads (Roads.swift)
    static let decisionSeconds = 20.0  // chosen standing in a hub, with up to four graph calls
    // After a right-click on an NPC, Click-to-Move walks there: the box is read every `clickPoll` s until a
    // panel opens or the character has stood still for `standStill` s. Walking steps the coordinates every
    // 0.2-0.3 s, but a background click can leave the capture quiet for 1-2 s (QuestRun.frame), hence 2 s.
    // `clickWalk` bounds the wait: 3 units, 15 s of running, beyond the walk's 0.5 and a pin's error.
    static let clickPoll = 0.5, standStill = 2.0, clickWalk = 15.0
    // One hover sweep over an NPC's points (QuestRun.onUnit) stops starting points after 12 s: a read takes
    // 0.7 s, or up to 2.9 s when a background move stalls the capture.
    static let hoverSeconds = 12.0
    /// The learned reader names a mark's kind reliably from this height (px) up: 20 of 20 on saved frames, 27 Sept. Below
    /// it, far marks of 3-5 px, it named a "!" as "?" at confidence 1.00, so a small mark keeps its place whatever it reads.
    static let kindMinHeight = 6.0
    // Only a kill lets a quest run go on after a fight back. Not a JEV_STOP (in combat STOP is not offered, but a reply Jev
    // cannot give ends the fight so): walking on while still attacked would only fight again.
    static let fightWon: Set<String> = ["KILLED_AND_LOOTED", "KILLED_NO_CORPSE"]
    // A fight ahead out of combat that did not start (health under the fight's start) or that Jev stopped ends nothing: the
    // stop stands (M4p). A fight in combat ("BACK_" outcomes: attacked since the stop, or after a JEV_STOP) follows M4i: only
    // a kill goes on (review of #66).
    static let fightAheadHeld: Set<String> = ["HOLD_PLAYER_HEALTH", "JEV_STOP"]
}

/// A step local code can run here: a hand-in, a quest to take, a hunt for a quest's creatures, or a way
/// back from danger (M4h).
enum QuestStep {
    case handIn(PlannedQuest)
    case accept(Giver)
    case hunt(PlannedQuest)
    case road(PlannedQuest, legs: [MapPoint])  // bound to the route found from the position read
    case use(PlannedQuest, item: String)  // the bag item the quest names (M4m)
    case retreat
    case fightAhead  // the creature whose red name or plate stopped the last walk (M4p, M4t)
    case town(TownNPC)  // sell the junk at a vendor, or train at the class trainer (M4u)
    var name: String {
        switch self {
        case .handIn(let q): return q.title
        case .accept(let g): return g.names.first.map { "\"!\" \($0)" } ?? "\"!\" at \(g.key)"
        case .hunt(let q): return "hunt: " + q.title
        case .road(let q, _): return "road: " + q.title
        case .use(_, let item): return "use: " + item
        case .retreat: return "retreat"
        case .fightAhead: return "fight ahead"
        case .town(let n): return (n.role == "vendor" ? "sell: " : "train: ") + n.name
        }
    }
    var key: String {  // what a failure is remembered by
        switch self {
        case .handIn(let q): return q.title
        // Its own key: a hunt that fails once its quest is done must not block the hand-in (live run 39, 27 Sept: the last
        // Cirrusfly was killed, the hunt ended NO_TARGET_FOUND, and "Ready for turn-in" was never offered).
        case .hunt(let q): return "HUNT " + q.title
        case .accept(let g): return "!" + g.key
        case .road(let q, _): return "ROAD " + q.title
        case .use(let q, _): return "USE " + q.title
        case .retreat: return "RETREAT"
        case .fightAhead: return "FIGHT_AHEAD"
        case .town(let n): return "TOWN " + n.name
        }
    }
}

/// The key a quest's step here fails by: its hunt's while it has creatures or objects to take, else its hand-in's.
func stepKey(_ q: PlannedQuest) -> String {
    [.kill, .collect].contains(questKind(q)) ? QuestStep.hunt(q).key : QuestStep.handIn(q).key
}

/// Whether a quest in the Map & Quest Log's list is tracked: its checkbox, right of the title at `x`, holds the yellow tick.
/// Live, 27 Sept: after a logout no quest was tracked, the objectives tracker was empty, and a hunt read no objective
/// (HUD_UNREADABLE). On the saved logs a ticked box held 29-33 yellow pixels, an empty one none.
func questTracked(_ image: RGBA, x: Double, y: Double) -> Bool {
    var yellow = 0
    for py in Int(y) - 13..<Int(y) + 13 where py >= 0 && py < image.height {
        for px in Int(x) - 13..<Int(x) + 13 where px >= 0 && px < image.width {
            let i = (py * image.width + px) * 4
            if markYellow(Int(image.pixels[i]), Int(image.pixels[i + 1]), Int(image.pixels[i + 2])) { yellow += 1 }
        }
    }
    return yellow >= 10
}

// MARK: - Quest items in the bags (M4m)

/// A bag slot's item, read from its tooltip while the pointer rests on the slot. The tooltip is an item's only with the
/// game's footer ("Press F6 to submit an issue for this Item"), and its topmost line in the footer's column is the name. It is
/// drawn just above the slot, over the backpack's title (live, 27 Sept: "Humming Recall Crystal", "Unique", "«Right Click to
/// Read»", then the footer, all from x 2089). nil: an empty slot, or no tooltip read.
func bagItemName(_ tooltip: [TipLine]) -> String? {
    // The tooltip's own lines start at its footer's left edge; world text or the backpack's title elsewhere in the box do not.
    guard let foot = tooltip.first(where: { isTooltipFooter($0.text) && $0.text.lowercased().hasSuffix("item") }),
          let name = tooltipName(tooltip, foot: foot, slack: 12),
          name.text.filter(\.isLetter).count >= 3 else { return nil }
    return name.text
}

/// A tooltip's name: its top line on the footer's left edge, climbing from the footer while the lines stay close (a line
/// every 15 px or so, the footer 34 below the last). World text on that edge above the tooltip is not its name (live run 76,
/// 27 Sept: an NPC's "<Rangers of Thendal Grove>" over a cloak's tooltip was read as the cloak's name, and it stayed unworn).
func tooltipName(_ lines: [TipLine], foot: TipLine, slack: Double) -> TipLine? {
    var top: TipLine?, y = foot.y
    for line in lines.filter({ abs($0.x - foot.x) <= slack && $0.y < foot.y }).sorted(by: { $0.y > $1.y }) {
        guard y - line.y <= 45 else { break }
        top = line
        y = line.y
    }
    return top
}

/// The bag item a use-at quest asks for: its objective names it ("Examine the Humming Recall Crystal then speak with
/// Windshaper Boro in Thendal Grove."). The longest name wins, so "Crystal" alone would not stand for it.
func questItem(_ quest: PlannedQuest, items: [String]) -> String? {
    let objective = nameKey(quest.objective)
    return items.filter { nameKey($0).count >= 5 && objective.contains(nameKey($0)) }.max { nameKey($0).count < nameKey($1).count }
}

/// Whether a use-at quest's use belongs to a place: "Use Skysight near the Elemental Convergence" (walk to its pin first).
func usesNear(_ q: PlannedQuest) -> Bool { q.objective.lowercased().contains(" near ") }

/// Whether a use-at quest sends the player to someone once its item is used: "... then speak with Windshaper Boro".
func talksAfterUse(_ q: PlannedQuest) -> Bool {
    let text = q.objective.lowercased()
    return ["then speak with", "then talk to", "then talk with", "then return to", "then report to"].contains { text.contains($0) }
}

/// Whether a step whose walk stopped may start from where the character stands: FROM_HERE is offered, and Jev chooses it
/// or not (the owner, 27 Sept: Jev decides, not a script). A walk stops at a red name ahead, and near a kill quest's pin
/// red names are most likely its creatures (live run 35: 1.9 from the pin, two level-1 Juvenile Vuldren). Near a place
/// where an ability is used, they may be what guards it (live run 48: Al'Aketh Converts 1.8 from the Elemental
/// Convergence, and Skysight was never cast). Any other stop, or further away, offers nothing new.
func stepStartsNear(_ stop: String, at: MapPoint?, pin: MapPoint) -> Bool {
    stop == "WALK_DANGER_AHEAD" && at.map { distance($0, pin) <= HuntLimits.startNear } == true
}

/// Whether a quest walk from `at` to `pin` starts. No position: WALK_HUD_UNREADABLE (never "arrived" unseen). Within
/// `arrive`: there already. Beyond one walk: TOO_FAR_NEEDS_ROADS, unless it is a leg of a learned road (the road bends
/// nowhere on it); the walk's own stops (danger, combat, the owner, the HUD, no progress, its limits) hold either way.
enum WalkStart: Equatable { case walk, there, refused(String) }
func walkStart(at: MapPoint?, to pin: MapPoint, road: Bool, arrive: Double = 0.5) -> WalkStart {
    guard let at else { return .refused("WALK_HUD_UNREADABLE") }
    guard distance(at, pin) > arrive else { return .there }
    return road || distance(at, pin) <= QuestLimits.maxLeg ? .walk : .refused("TOO_FAR_NEEDS_ROADS")
}

/// A road's legs in turn, each one quest walk (`walk` gives nil on arrival, else the outcome that ends the step).
/// No leg starts at or after `deadline`: the run's clock bounds a road as it bounds a hunt.
func walkLegs(_ legs: [MapPoint], until deadline: Double, now: () -> Double, walk: (Int, MapPoint) async -> String?) async -> String {
    for (i, leg) in legs.enumerated() {
        if now() >= deadline { return "ROAD_TIME_LIMIT" }
        if let stop = await walk(i, leg) { return stop }
    }
    return "BY_ROAD"
}

/// A walk round a gap by the roads (M4q): the route's legs in turn (walkLegs), the last to the caller's `arrive` and the
/// others to RoadLimits.gapArrive; nil on arrival, else the first outcome that ends it. No leg starts at or after
/// `deadline`, the run's (review of #69).
func roadGapWalk(_ legs: [MapPoint], arrive: Double, until deadline: Double, now: () -> Double,
                 walk: (Int, MapPoint, Double) async -> String?) async -> String? {
    let outcome = await walkLegs(legs, until: deadline, now: now) { i, leg in
        await walk(i, leg, i == legs.count - 1 ? arrive : RoadLimits.gapArrive)
    }
    return outcome == "BY_ROAD" ? nil : outcome
}

/// Whether a quest run that ended so walks to a safe place before it exits: every end but the owner's takeover, keys
/// held, a failed input handoff and death.
func leavesDanger(_ outcome: String) -> Bool {
    !(outcome.contains("OWNER") || outcome.hasSuffix("KEYS_HELD") || outcome.contains("HANDOFF") || outcome.contains("DEAD")
      || outcome.hasPrefix("DEATH"))
}

/// SAFETY's clicks to resurrect at the Spirit Healer (M4s). The owner, 27 Sept: resurrect there, automatically, inside the
/// envelope (below level 10 it costs nothing).
enum DeathStep: String {
    case release = "RELEASE_SPIRIT", talk = "TALK_TO_SPIRIT_HEALER", returnToLife = "RETURN_ME_TO_LIFE", accept = "ACCEPT"
    /// The steps that may show once this one is clicked.
    var follows: [DeathStep] {
        switch self {
        case .release: return [.returnToLife, .talk]
        case .talk: return [.returnToLife]
        case .returnToLife: return [.accept]
        case .accept: return []
        }
    }
}
typealias ScreenText = (text: String, x: Double, y: Double)  // an OCR line and its middle, in capture pixels
typealias WorldName = (text: String, x: Double, bottom: Double, height: Double)  // a name over a unit: its middle x, bottom, height
typealias DeathClick = (step: DeathStep, x: Double, y: Double)

/// The next death-recovery click the screen shows, from the top popup's lines, the left gossip panel's and the names in the
/// world, or nil. Live, 27 Sept: "Release Spirit" in the popup; after it the Spirit Healer's gossip, with "Return me to life."
/// (after run 65 it opened by itself; after run 66 it did not, and the healer was right-clicked); then a popup that says
/// where to resurrect, with Accept and Cancel. Accept is taken only there and only after "Return me to life." or an Accept:
/// a party invite's, a summons' or another player's offer to resurrect (Accept and Decline) never is. Lines are read in
/// Latin letters: Vision read that Accept with a Cyrillic A (replay of the live frames).
func deathStep(popup: [ScreenText], dialog: [ScreenText], world: [WorldName] = [], last: DeathStep?) -> DeathClick? {
    func key(_ text: String) -> String { nameKey(text.applyingTransform(.toLatin, reverse: false) ?? text) }
    func find(_ lines: [ScreenText], _ label: String) -> ScreenText? { lines.first { key($0.text).contains(key(label)) } }
    if let b = find(popup, "Release Spirit") { return (.release, b.x, b.y) }
    if last == .returnToLife || last == .accept, find(popup, "resurrect") != nil, find(popup, "Cancel") != nil,
       let b = popup.first(where: { key($0.text) == key("Accept") }) { return (.accept, b.x, b.y) }
    if let b = find(dialog, "Return me to life") { return (.returnToLife, b.x, b.y) }
    // Only the dead see a Spirit Healer, so its name in view is a ghost beside it: its body is right-clicked, seven name
    // heights below the name (live, 27 Sept: name 38 px tall, bottom at 209, the gossip opened on a click at 470). The whole
    // line must be its name: a chat bubble or a sign that mentions one is no ghost (review of #73), and the click stays in
    // the view above the bars.
    if let n = world.first(where: { key($0.text) == key("Spirit Healer") && $0.height <= 60 }) {
        return (.talk, n.x, min(n.bottom + 7 * n.height, 1000))
    }
    return nil
}

/// What the screen showed after a death-recovery click.
enum DeathSeen { case shown(DeathClick), cleared, unknown }

/// What the fresh frames after a click show (`reads`: each frame's next click, nil for none; a frame that did not come is no
/// read): a step that may follow, at once; after Accept, `cleared` only on two frames in a row with nothing to click. nil
/// until `timedOut` (read on); then the last frame's step, clicked again if it is the same, or `unknown`: no frame, or a
/// last frame with nothing, proves nothing (review of #73: a quiet capture after Accept was taken for a resurrection).
func deathSeen(after step: DeathStep, _ reads: [DeathClick?], timedOut: Bool) -> DeathSeen? {
    if let last = reads.last, let c = last, step.follows.contains(c.step) { return .shown(c) }
    if step == .accept, reads.count >= 2, reads.suffix(2).allSatisfy({ $0 == nil }) { return .cleared }
    guard timedOut else { return nil }
    if let last = reads.last, let c = last { return .shown(c) }
    return .unknown
}

/// Death recovery's clicks in turn (M4s): a click, then what the screen shows after it (`seen`, deathSeen). REVIVED only when
/// an Accept left nothing to click. A step still shown is clicked again, at most `clicks` in all; anything else stops it where
/// it stands, "DEATH_AFTER_" the step last clicked. Nil when no death shows.
func revive(_ first: DeathClick?, clicks: Int, click: (DeathClick) async -> Bool, seen: (DeathStep) async -> DeathSeen) async -> String? {
    guard var todo = first else { return nil }
    for _ in 0..<clicks {
        guard await click(todo) else { return "DEATH_CLICK_FAILED" }
        switch await seen(todo.step) {
        case .cleared: return todo.step == .accept ? "REVIVED" : "DEATH_AFTER_" + todo.step.rawValue
        case .unknown: return "DEATH_AFTER_" + todo.step.rawValue
        case .shown(let c):
            guard c.step == todo.step || todo.step.follows.contains(c.step) else { return "DEATH_AFTER_" + todo.step.rawValue }
            todo = c
        }
    }
    return "DEATH_CLICK_LIMIT"
}

/// The way to safety (M4r): in combat, a fight back first (SAFETY's, as M4i's); out of it, a walk; a walk that met
/// combat is fought, then walked again, at most `walks` walks. "SAFE" on arrival; a fight not won ends it with "FIGHT_"
/// and its outcome, a walk's other end with "WALK_" and its. Everything ends by `end`: a fight starts only with its
/// whole `FightLimits.maxSeconds` left, and a walk gets what is left, at most `NavLimits.maxSeconds` (reviews of #72).
/// Live run 65 (27 Sept): the walk to safety met combat at once and ended, the character stood among hostiles, and died.
func leaveDangerRounds(_ walks: Int, until end: Double, now: () -> Double, inCombat: () async -> Bool,
                       fightBack: () async -> String, walk: (Double) async -> String) async -> String {
    var walked = 0
    for _ in 0...(2 * walks) {
        let left = end - now()
        if await inCombat() {
            guard left >= FightLimits.maxSeconds else { return "SAFE_TIME_LIMIT_IN_COMBAT" }
            let fought = await fightBack()
            guard QuestLimits.fightWon.contains(fought) else { return "FIGHT_" + fought }
            continue
        }
        guard walked < walks else { return "SAFE_ROUNDS" }
        guard left >= QuestLimits.safeWalkSeconds else { return "SAFE_TIME_LIMIT" }
        walked += 1
        let outcome = await walk(min(NavLimits.maxSeconds, left))
        if outcome == "ARRIVED" { return "SAFE" }
        if outcome != "COMBAT" { return "WALK_" + outcome }
    }
    return "SAFE_ROUNDS"
}

/// The nearest safe place within one walk of `at`, unless the character is already at one.
func safePlace(from at: MapPoint) -> MapPoint? {
    if QuestLimits.safePlaces.contains(where: { distance(at, $0.at) <= QuestLimits.safeArrive }) { return nil }
    return QuestLimits.safePlaces.map(\.at).filter { distance(at, $0) <= QuestLimits.safeReach }.min { distance(at, $0) < distance(at, $1) }
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
/// owner: survive first). A use-at quest is offered as a use when its objective names an item in the bags or an ability
/// on the bar (M4m). Only when none of these is left
/// (the owner: this zone first) are the quests beyond one walk offered, each by the route `roads` give from here.
func questOffers(_ read: QuestRead, failed: Set<String>, stopped: QuestStep? = nil, roads: RoadGraph? = nil, used: Set<String> = [])
    -> [(skill: String, step: QuestStep, criterion: String)] {
    func away(_ p: MapPoint) -> String { String(format: "%.1f", distance(read.player, p)) }
    let open = questPlan(read.quests, from: read.player).filter { q in
        // A use-at quest whose item was used this run, and which then sends the player to someone, is a hand-in now: its log
        // line does not change (live run 42, 27 Sept: "Examine the Humming Recall Crystal then speak with Windshaper Boro").
        ([.handIn, .travel].contains(questKind(q)) || (questKind(q) == .useAt && used.contains(q.title) && talksAfterUse(q)))
            && !failed.contains(q.title)
            && q.pin.map { distance(read.player, $0) <= QuestLimits.maxLeg } != false  // no pin: its NPC may stand here
    }
    let handIns = open.prefix(QuestLimits.slots).enumerated().map { i, q in
        ("HAND_IN_\(i + 1)", QuestStep.handIn(q), (q.pin.map { "Walk to the quest giver of \"\(q.title)\"\(q.ender.map { ", \($0)," } ?? "") (level \(q.level), \(away($0)) units away) " }
            ?? "Find the quest giver of \"\(q.title)\" (level \(q.level)) near here: the map showed no pin, which hides under the "
                + "player's arrow when its NPC stands here, ")
            + "and hand it in. The log reads: \(q.objective.isEmpty ? "(no objective line)" : q.objective)")
    }
    // A mark in view is offered only with no hand-in here: beside a quest to hand in, it is most likely that "?" (review of #47).
    // A "!" offers a quest not yet taken: an icon whose tooltip names a quest in the log is that quest's "?", misread
    // by its width (live run 21, 26 Sept: Rorian's "Coming of Age" offered as ACCEPT_1 beside its own hand-in).
    let logged = Set(read.quests.map { nameKey($0.title) })
    let givers = read.givers.filter { !failed.contains("!" + $0.key) && distance(read.player, $0.pin) <= QuestLimits.maxLeg && (!$0.inView || handIns.isEmpty)
        && !$0.names.contains { logged.contains(nameKey($0)) } }
        .sorted { distance(read.player, $0.pin) < distance(read.player, $1.pin) }
    let accepts = givers.prefix(QuestLimits.giverSlots).enumerated().map { i, g in
        ("ACCEPT_\(i + 1)", QuestStep.accept(g), g.inView
            ? "Walk to the yellow quest mark in view and accept the quest its NPC offers. The minimap showed no \"!\": a giver a few "
                + "yards away is drawn under the player's arrow. A \"?\" of a quest to hand in looks alike, and offers nothing to accept."
            : "Walk to the quest giver shown by a \"!\" on the minimap (\(away(g.pin)) units away; its tooltip read "
                + "\(g.names.isEmpty ? "nothing" : g.names.joined(separator: ", "))) and accept the quest it offers.")
    }
    let hunted = questPlan(read.quests, from: read.player).filter { q in
        [.kill, .collect].contains(questKind(q)) && !failed.contains(stepKey(q))
            && q.pin.map { distance(read.player, $0) <= QuestLimits.maxLeg } != false
    }
    let hunts = hunted.prefix(QuestLimits.huntSlots).enumerated().map { i, q in
        ("HUNT_\(i + 1)", QuestStep.hunt(q), (q.pin.map { "Walk to the area of \"\(q.title)\" (level \(q.level), \(away($0)) units away), then hunt" }
            ?? "Hunt for \"\(q.title)\" (level \(q.level)) from here, by the minimap's quest area (the map showed no area),")
            + " the creatures that the tracker's unfinished objectives name: fight, loot, rest and eat as the hunt chooses, up to "
            + "\(HuntLimits.maxFights) fights. Objects on the ground that the objectives name are picked up only where the object "
            + "detector sees them (PICK_UP_OBJECT). The log reads: \(q.objective)")
    }
    let back = stopped != nil && !failed.contains("RETREAT") ? [("RETREAT", QuestStep.retreat, "Walk back to where the last walk began: "
        + "a hostile creature's red name or plate came into view ahead of it.")] : []
    // The owner, 26-27 Sept: level like a human, who fights what stands in the way. Runs 48-56 stopped at red names on nearly
    // every walk round Thendal (level 2-3 Roiling Winds and Al'Aketh Converts, the character level 2).
    let fightAhead = stopped != nil && !failed.contains("FIGHT_AHEAD") ? [("FIGHT_AHEAD", QuestStep.fightAhead, "Fight the hostile creature whose red name or plate stopped the last "
        + "walk: one bounded fight (select it with Tab, pull, melee and heal as the fight chooses), started only at 90% health or more. "
        + "A kill clears the way, so the stopped step is offered again, and its experience is how the character levels; it may be a "
        + "level above the character, and others near it may join.")] : []
    // The stopped step, from here, when it stopped within startNear of its place: its quest without the pin, so no walk.
    let here: [(String, QuestStep, String)] = {
        func near(_ q: PlannedQuest) -> PlannedQuest? {
            guard let pin = q.pin, stepStartsNear("WALK_DANGER_AHEAD", at: read.player, pin: pin) else { return nil }
            var h = q
            h.pin = nil
            return h
        }
        let why = "the walk there stopped for a hostile creature's red name or plate ahead"
        switch stopped {
        case .hunt(let q)?: return near(q).map { [("FROM_HERE", QuestStep.hunt($0), "Hunt for \"\(q.title)\" from here: \(why), "
            + "\(away(q.pin!)) units from its area. Near a kill quest's area such creatures are most likely the ones it names. The hunt "
            + "reads each plate's name, fights only what the tracker's unfinished objectives name, and fights back when attacked. "
            + "The log reads: \(q.objective)")] } ?? []
        case .use(let q, let item)? where usesNear(q): return near(q).map { [("FROM_HERE", QuestStep.use($0, item: item),
            "Use \"\(item)\" from here, as \"\(q.title)\" asks: \(why), \(away(q.pin!)) units from its place. Hostile creatures "
            + "may be near, and may attack. The log reads: \(q.objective)")] } ?? []
        default: return []
        }
    }()
    let usable = questPlan(read.quests, from: read.player).compactMap { q -> (PlannedQuest, String)? in
        guard questKind(q) == .useAt, !failed.contains(QuestStep.use(q, item: "").key) else { return nil }
        return questItem(q, items: read.items + read.abilities).map { (q, $0) }
    }
    let uses = usable.prefix(QuestLimits.useSlots).enumerated().map { i, u in
        ("USE_\(i + 1)", QuestStep.use(u.0, item: u.1), (read.abilities.contains(u.1)
            ? "Use \"\(u.1)\" from the bar (its key)" : "Open the bags and use \"\(u.1)\" (right-click it)")
            + (usesNear(u.0) && u.0.pin != nil ? ", at the quest's place (\(away(u.0.pin!)) units away), " : ", here, ")
            + "as \"\(u.0.title)\" (level \(u.0.level)) asks. The log reads: \(u.0.objective)")
    }
    let offers = back + fightAhead + here + handIns + accepts + uses + hunts
    guard offers.isEmpty, let roads else { return offers }
    // ponytail: no map check; the run envelope is Zephras Isle, where the roads were learned. Compare the zone's
    // name above the minimap with roads.subzones before runs leave it.
    let far = questPlan(read.quests, from: read.player).filter { q in
        [.handIn, .travel, .kill, .collect].contains(questKind(q)) && !failed.contains(stepKey(q)) && !failed.contains("ROAD " + q.title)
            && q.pin.map { distance(read.player, $0) > QuestLimits.maxLeg } == true
    }
    let routed = far.lazy.compactMap { q in route(roads, from: read.player, to: q.pin!).map { (q, $0) } }.prefix(QuestLimits.roadSlots)
    return routed.enumerated().map { i, r in
        let (q, legs) = r, length = zip([read.player] + legs, legs).map { distance($0, $1) }.reduce(0, +)
        return ("ROAD_\(i + 1)", QuestStep.road(q, legs: legs), "Walk by the roads other players walked to the quest \"\(q.title)\" "
            + "(level \(q.level), \(away(q.pin!)) units away; \(String(format: "%.1f", length)) units by road in \(legs.count) legs), in another zone: "
            + "nothing is left within one walk here. Each leg stops for a hostile creature's red name ahead. The log reads: \(q.objective)")
    }
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
/// ends the run. A road step walks its legs in turn, each a walk as above; arriving lets the run go on. With
/// nothing left here and no learned road to the rest, the run ends NEXT_ZONE_NEEDS_ROADS. No step starts after
/// `runSeconds`, and a hunt ends by then. There is no rules fallback when Jev fails.
/// `seconds`: the run's steps' window; a live run passes what is left of its own after setup and a revive at the start
/// (review of #73: one clock for the whole envelope).
func runQuests(host: QuestHost, jev: JevClient, graph: GraphSession, roads: RoadGraph? = nil,
               seconds: Double = QuestLimits.runSeconds, town: [TownNPC] = []) async -> QuestResult {
    var r = QuestResult()
    var failed: Set<String> = [], used: Set<String> = []  // used: quests whose item was used this run (M4m)
    var stuck = 0
    var danger: QuestStep?  // the step a red name stopped, while that stop stands (M4h, M4o, M4p)
    let deadline = host.now() + seconds
    func finish(_ outcome: String) -> QuestResult {
        r.outcome = outcome
        host.emit("quests_done", ["outcome": outcome, "steps": r.steps.map { ["quest": $0.quest, "outcome": $0.outcome] }])
        return r
    }
    // Jev's steps are counted, not SAFETY's fight backs: run 65 spent its twelve on five walks attacked and their fights
    // back, and ended STEP_LIMIT in combat among hostiles (review of #72).
    while r.steps.filter({ $0.quest != "fight back" }).count < QuestLimits.maxSteps {
        if host.ownerTookFocus() { return finish("OWNER_TOOK_FOCUS") }
        if host.now() >= deadline { return finish("TIME_LIMIT") }
        guard let read = await host.readQuests() else { return finish("POSITION_UNREADABLE") }
        guard read.missing.isEmpty else { return finish("LOG_INCOMPLETE") }  // see quest-log.png
        let stopped = danger, stoppedKey = danger?.key
        // M4y: each step's record across runs goes into its criterion.
        let offers = (questOffers(read, failed: failed, stopped: stopped, roads: roads, used: used) + townOffers(read, npcs: town, failed: failed))
            .map { (skill: $0.skill, step: $0.step, criterion: withHistory($0.criterion, read.history[$0.step.key])) }
        if offers.isEmpty {
            let deliveries = read.quests.filter { [.handIn, .travel, .kill, .collect].contains(questKind($0)) && !failed.contains(stepKey($0)) }
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
        if host.now() >= deadline { return finish("TIME_LIMIT") }  // a decision takes up to 20 s: none starts after the deadline
        host.emit("quest_step", ["controller": "JEV", "skill": offer.skill, "step": offer.step.name])
        let outcome: String
        switch offer.step {
        case .handIn(let q): outcome = await host.handIn(q)
        case .accept(let g): outcome = await host.accept(g)
        case .hunt(let q): outcome = await host.hunt(q, until: deadline)
        case .road(let q, let legs): outcome = await host.walkRoad(to: q, by: legs, until: deadline)
        case .use(let q, let item): outcome = await host.useItem(q, item: item)
        case .retreat: outcome = await host.retreat()
        case .fightAhead: outcome = await host.fightAhead()
        case .town(let n): outcome = await host.visit(n)
        }
        r.steps.append((offer.step.name, outcome))
        // A retreat or a fight ahead is about the creature there, and a giver's key is where its "!" showed this time (review
        // of #81): none is a step to remember across runs.
        switch offer.step {
        case .retreat, .fightAhead, .accept: break
        default: host.remember(offer.step.key, outcome: outcome, level: read.level)
        }
        if outcome == "WALK_DANGER_AHEAD" {
            danger = offer.step
            failed.remove(QuestStep.fightAhead.key)  // a new stop may be fought
        } else if case .fightAhead = offer.step, QuestLimits.fightAheadHeld.contains(outcome) {
            failed.insert(QuestStep.fightAhead.key)  // the stop stands: RETREAT is offered again, this fight not (review of #66)
        } else {
            danger = nil
        }
        // The walk that stopped failed this step's key; a hunt from here that took some is the step going on, not failed, so
        // its HUNT is offered again (review of #58: after four fights of eight it was never offered again).
        if offer.skill == "FROM_HERE" && outcome.hasPrefix("HUNTED") { failed.remove(offer.step.key) }
        if case .fightAhead = offer.step {  // M4p: a kill clears the way for the stopped step; a loss ends the run
            let back = outcome.hasPrefix("BACK_"), fought = back ? String(outcome.dropFirst(5)) : outcome
            if QuestLimits.fightWon.contains(fought) {
                if let stoppedKey { failed.remove(stoppedKey) }
                continue
            }
            if !back && QuestLimits.fightAheadHeld.contains(fought) { continue }
            return finish("FIGHT_" + fought)
        }
        if case .town = offer.step, !outcome.hasPrefix("WALK_") {  // one visit a run, whatever it found (M4u)
            failed.insert(offer.step.key)
            continue
        }
        if outcome == "WALK_COMBAT" {  // the owner: survive first, inside the engine
            host.emit("quest_step", ["controller": "SAFETY", "skill": "FIGHT_BACK", "step": "fight back"])
            let fought = await host.fightBack()
            r.steps.append(("fight back", fought))
            guard QuestLimits.fightWon.contains(fought) else { return finish("FIGHT_" + fought) }
            continue
        }
        if outcome.hasPrefix("COMPLETED") || outcome.hasPrefix("ACCEPTED") || outcome.hasPrefix("HUNTED") || outcome == "RETREATED" || outcome == "BY_ROAD" { continue }
        if outcome == "USED" || outcome == "USED_ABILITY" {  // used once: what the log still names is not used again
            failed.insert(offer.step.key)
            // An item's use has its evidence (its panel), so its quest may be handed in now; an ability's has none (review of #54).
            if outcome == "USED", case .use(let q, _) = offer.step { used.insert(q.title) }
            continue
        }
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

// MARK: M4u — the town stop

/// A town's service NPC (`learning/knowledge/zephras-town.json`): its name as the game draws it over the NPC, what it does,
/// and where to stand to talk to it (live, 27 Sept: the character stood there, facing it, when its window opened by hand).
struct TownNPC: Codable, Equatable {
    let name: String
    let role: String  // "vendor" (Sell All Junk Items) or "trainer" (the class's spells)
    let hub: String
    let at: [Double]
    var point: MapPoint { (at[0], at[1]) }
    static let file = "experiments/002_wow_visual/learning/knowledge/zephras-town.json"
    static func load(_ path: String = file) throws -> [TownNPC] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        struct Book: Codable { let npcs: [TownNPC] }
        let npcs = try JSONDecoder().decode(Book.self, from: Data(contentsOf: URL(fileURLWithPath: path))).npcs
        guard npcs.allSatisfy({ $0.at.count == 2 && ["vendor", "trainer"].contains($0.role) }) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: path])
        }
        return npcs
    }
}

enum TownLimits {
    static let sellAt = 8  // bag slots in use from which a vendor is offered: a human empties the bags before they fill
    static let trainRows = 6  // Train clicks in one visit, at most
}

/// The character's level in its portrait's tooltip ("Level 3 Windshaper Skyborne (Player)"): the number after "Level" on a
/// "(Player)" line. An NPC's tooltip still showing from before the pointer reached the portrait is not it (live run 78, 27 Sept:
/// "Level 5" alone was read as a level-4 character's).
func tooltipLevel(_ lines: [String]) -> Int? {
    for line in lines where line.lowercased().contains("player") {
        let words = line.split(separator: " ")
        if let i = words.firstIndex(where: { $0.lowercased() == "level" }), i + 1 < words.count, let n = Int(words[i + 1]) { return n }
    }
    return nil
}

/// Copper from a money line's numbers, read from the right: copper, then silver, then gold ("63" is 63, "1 • 25 •" is 125).
/// Nil without a number, with more than three, or with a copper or silver part over 99.
func copper(_ text: String) -> Int? {
    let parts = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.reversed().map { $0 }
    guard !parts.isEmpty, parts.count <= 3, parts[0] <= 99, parts.count < 2 || parts[1] <= 99 else { return nil }
    return parts.enumerated().reduce(0) { $0 + $1.element * [1, 100, 10000][$1.offset] }
}

/// Whether the trainer's own window is open, not its gossip (review of #77: both carry the trainer's name as their title):
/// the title, no "Goodbye" (the gossip's button), and a spell row's "Rank" or "Requires" line (live, 27 Sept).
func trainerOpen(_ lines: [TipLine], trainer: String) -> Bool {
    lines.contains { sameUnit($0.text, trainer) || likeName($0.text, trainer) }
        && !lines.contains { nameKey($0.text) == nameKey("Goodbye") }
        && lines.contains { $0.text.contains("(Rank") || $0.text.lowercased().hasPrefix("requires") }
}

/// Whether an NPC's window is open at the left, not just its name in the world there (review of #77): its title, and a
/// line only such a window has: the gossip's "Goodbye", a trainer row's "Rank" or "Requires", the merchant's "Buyback"
/// tab or its "Page N of M" (live, 27 Sept). Esc is pressed only then: with nothing open it is the Game Menu.
func npcWindowOpen(_ lines: [TipLine], name: String) -> Bool {
    lines.contains { sameUnit($0.text, name) || likeName($0.text, name) } && npcWindowShown(lines)
}

/// A town NPC's name as the view search reads it (M4u): the name, or one like it of about its length. Live run 78, 27 Sept: a
/// player's longer name ("aria Darkwina Darkbloom") shares nine letters in order with "Windshaper Boro" and was taken for him;
/// the hover then read a player, and the visit ended NPC_NOT_OPENED.
func townNameHit(_ text: String, _ name: String) -> Bool {
    sameUnit(text, name) || (likeName(text, name) && abs(nameKey(text).count - nameKey(name).count) <= 3)
}

/// Such a line, whoever's window it is (M4x: a right-click on a bag item with a merchant's window open sells the item).
func npcWindowShown(_ lines: [TipLine]) -> Bool {
    lines.contains { l in
        let k = nameKey(l.text)
        return k == nameKey("Goodbye") || k == nameKey("Buyback") || l.text.contains("(Rank") || l.text.lowercased().hasPrefix("requires")
            || (k.hasPrefix("page") && l.text.contains(" of "))
    }
}

/// The trainer window's spell rows to try, top to bottom (live, 27 Sept): each name line with five letters or more, with
/// its "Requires: Level N" line under it when there is one. A row whose level reads above `level` is left out; a misread
/// level ("Level G") is tried: the game's Train does nothing for a row it does not allow.
func trainerRows(_ lines: [TipLine], level: Int) -> [TipLine] {
    func requirement(_ l: TipLine) -> Bool { l.text.lowercased().hasPrefix("requires") }
    return lines.filter { !requirement($0) && $0.text.filter(\.isLetter).count >= 5 }.sorted { $0.y < $1.y }.filter { row in
        guard let req = lines.first(where: { requirement($0) && $0.y > row.y && $0.y - row.y <= 30 }) else { return true }
        let words = req.text.split(separator: " ")
        guard let i = words.firstIndex(where: { $0.lowercased().hasPrefix("level") }), i + 1 < words.count,
              let need = Int(words[i + 1].filter(\.isNumber)) else { return true }
        return need <= level
    }
}

/// The town steps within one walk (M4u), for Jev to weigh against the quests: TRAIN at the class trainer when the level
/// read is above the level of the last visit (or none is remembered), SELL_JUNK at a vendor when the bags hold
/// `TownLimits.sellAt` items or more. Each is offered once a run (its key fails after a visit).
func townOffers(_ read: QuestRead, npcs: [TownNPC], failed: Set<String>) -> [(skill: String, step: QuestStep, criterion: String)] {
    let near = npcs.filter { distance(read.player, $0.point) <= QuestLimits.maxLeg && !failed.contains(QuestStep.town($0).key) }
        .sorted { distance(read.player, $0.point) < distance(read.player, $1.point) }
    func away(_ n: TownNPC) -> String { String(format: "%.1f", distance(read.player, n.point)) }
    var out: [(skill: String, step: QuestStep, criterion: String)] = []
    if let t = near.first(where: { $0.role == "trainer" }), let level = read.level, read.trainedAt.map({ level > $0 }) ?? true {
        out.append(("TRAIN", .town(t), "Walk to \(t.name), the class trainer in \(t.hub) (\(away(t)) units away), choose \"I'd like "
            + "training!\" and learn each spell the window offers that the level and the money allow. The character is level \(level); "
            + (read.trainedAt.map { "it last trained at level \($0)." } ?? "no visit is remembered.")
            + " New spells go to the bar by themselves."))
    }
    // The bags are read only for a use-at quest; unread, they may be full of loot, so the vendor is offered and Jev weighs it
    // (review of #77: a count required before offering left SELL_JUNK unoffered on every run without a use-at quest).
    // M4x: not while an upgrade may lie in the bags unworn, as Sell All Junk sells grey gear (second review of #80: a refused
    // visit counted as the run's one, and the vendor was never offered again once the gear settled).
    if read.gearSettled, let v = near.first(where: { $0.role == "vendor" }), (read.bagsUsed ?? TownLimits.sellAt) >= TownLimits.sellAt {
        out.append(("SELL_JUNK", .town(v), "Walk to \(v.name), a vendor in \(v.hub) (\(away(v)) units away), and sell every grey item "
            + "in the bags with one Sell All Junk Items (the game asks to confirm). "
            + (read.bagsUsed.map { "\($0) bag slots are in use" } ?? "The bags were not read this step")
            + "; the money buys training."))
    }
    return out
}

// MARK: M4v — quest enders from the wiki

/// Who takes a quest in, and where they stand (`learning/knowledge/zephras-quests.json`, from warcraft.wiki.gg; M4v). Live runs
/// 67-69 (27 Sept): "Agitators" was ready, the map showed no pin for it from the village, and each hand-in sought a "?" where
/// the character stood; its ender, Yala Windwatcher, stands in Thendal Grove.
struct QuestEnder: Codable, Equatable {
    let title: String
    let ender: String
    let at: [Double]
    static let file = "experiments/002_wow_visual/learning/knowledge/zephras-quests.json"
    static func load(_ path: String = file) throws -> [QuestEnder] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        struct Book: Codable { let quests: [QuestEnder] }
        let quests = try JSONDecoder().decode(Book.self, from: Data(contentsOf: URL(fileURLWithPath: path))).quests
        guard quests.allSatisfy({ $0.at.count == 2 }) else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: path]) }
        return quests
    }
}

/// The log's quests with their enders named from the knowledge. Only a quest ready to hand in (or a delivery) with no map pin
/// takes its ender's place: a quest in progress keeps its own area, or none (review of #78: "Harvesting Windstones" at 0/15
/// would have walked to Dalia in the village). A map pin stays: it is what the game shows now.
func withEnders(_ quests: [PlannedQuest], _ enders: [QuestEnder]) -> [PlannedQuest] {
    quests.map { q in
        guard let e = enders.first(where: { sameTitle($0.title, q.title) }) else { return q }
        var named = q
        named.ender = e.ender
        if named.pin == nil, [.handIn, .travel].contains(questKind(q)) { named.pin = (e.at[0], e.at[1]) }
        return named
    }
}

// MARK: Heal before a walk (the owner, 27 Sept: "buff/heal ... are needed when needed")

enum RecoverLimits {
    static let until = 0.6  // out of combat, a walk starts at 60% health or more: healed first
    static let casts = 3
    static let castSeconds = 2.5  // Healing Wave's 1.5 s cast and the rest of the global cooldown
    static let manaFloor = 0.2  // below it no cast is tried (Healing Wave: 25 mana of 148 at level 3)
}

/// Heal before walking on, as a human does out of combat (live run 70, 27 Sept: a hunt ended out of combat under 30% health,
/// the way to safety set off at once, got stuck on the ground, and the character died there). `read` gives a fresh HUD (nil:
/// none). Before the first cast `aim` selects the character itself: a heal goes to the selected unit, which after a talk is a
/// friendly NPC (review of #79); after the last, `clear` drops that selection. `cast` presses the heal and waits for it, false
/// when the owner took over. NOT_HURT, HEALED, IN_COMBAT (the fight's to answer), NO_MANA, UNREAD, OWNER or STILL_HURT after
/// `RecoverLimits.casts` casts.
func recover(read: () async -> Obs?, aim: () async -> Void, cast: () async -> Bool, clear: () async -> Void) async -> String {
    var casts = 0
    var end = "STILL_HURT"
    for n in 0...RecoverLimits.casts {
        guard let o = await read() else { end = "UNREAD"; break }
        if o.combat { end = "IN_COMBAT"; break }
        if o.player >= RecoverLimits.until { end = n == 0 ? "NOT_HURT" : "HEALED"; break }
        if o.mana < RecoverLimits.manaFloor { end = "NO_MANA"; break }
        if n == RecoverLimits.casts { break }
        if casts == 0 { await aim() }
        guard await cast() else { end = "OWNER"; break }
        casts += 1
    }
    if casts > 0 { await clear() }
    return end
}
