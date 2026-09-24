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
/// an upright blob (a "?" is about 10 x 18 px zoomed out) with a green NPC name 8-50 px below it: a
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

/// `body` is where to right-click: below the green name by 2.4 mark heights (near: name bottom 577, body
/// 608 under a 17-px "?"; a distant NPC's "?" was 4 x 6 px live, and a fixed step landed on its name).
func questMarks(_ image: RGBA, box: (Int, Int, Int, Int), minPixels: Int = 5) -> [(x: Double, y: Double, h: Double, body: Double)] {
    let blobs = yellowBlobs(image, box: box)
    let cx = Double(image.width) / 2, cy = Double(image.height) / 2
    func greenBelow(_ x: Int, _ y: Int) -> (n: Int, bottom: Int) {
        var n = 0, bottom = y
        for yy in max(0, y + 8)..<min(image.height, y + 50) {
            for xx in max(0, x - 50)..<min(image.width, x + 50) {
                let i = (yy * image.width + xx) * 4
                if nameGreen(Int(image.pixels[i]), Int(image.pixels[i + 1]), Int(image.pixels[i + 2])) { n += 1; bottom = yy }
            }
        }
        return (n, bottom)
    }
    return blobs.compactMap { b -> (x: Double, y: Double, h: Double, body: Double)? in
        let w = b.x1 - b.x0 + 1, h = b.y1 - b.y0 + 1
        guard b.n >= minPixels, w <= 24, h >= 3, Double(h) >= 0.8 * Double(w) else { return nil }
        let name = greenBelow(b.sx / b.n, b.sy / b.n)
        guard name.n >= 40 else { return nil }
        return (Double(b.sx) / Double(b.n), Double(b.sy) / Double(b.n), Double(h), Double(name.bottom) + 2.4 * Double(h))
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

/// The Map & Quest Log's list, as OCR lines: "[4] Call of Earth" titles, objectives indented under
/// them, zone headers ("Camping") to their left. Pins are added from the map afterwards.
func parseQuestLog(_ lines: [TipLine]) -> [PlannedQuest] {
    var out: [PlannedQuest] = []
    var titleX = Double.infinity
    for line in lines.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
        let text = line.text.trimmingCharacters(in: .whitespaces)
        if let m = text.range(of: #"^\[(\d+)\]\s*"#, options: .regularExpression),
           let level = Int(text[m].filter(\.isNumber)) {
            out.append(PlannedQuest(title: String(text[m.upperBound...]), level: level, ready: false, objective: "", pin: nil))
            titleX = line.x
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

/// A north-up minimap pixel to zone coordinates, from the player at its centre (M4a: 19 px per y unit).
func minimapPoint(_ px: Double, _ py: Double, player: MapPoint) -> MapPoint {
    (player.x + (px - Double(MinimapHUD.cx)) / MinimapHUD.unitPx / mapAspect, player.y + (py - Double(MinimapHUD.cy)) / MinimapHUD.unitPx)
}

/// Quest icons ("?", "!") on the minimap: a hub's hand-ins sit together under the world map's arrow, and
/// the minimap's larger scale separates them (24 Sept).
func minimapPins(_ image: RGBA) -> [(x: Double, y: Double)] {
    let r = MinimapHUD.radius, cx = MinimapHUD.cx, cy = MinimapHUD.cy
    let icons = glyphs(yellowBlobs(image, box: (cx - r, cy - r, cx + r, cy + r), gap: 0))
        .filter { $0.n >= 8 && $0.x1 - $0.x0 <= 20 && $0.y1 - $0.y0 <= 20 && $0.y1 - $0.y0 >= $0.x1 - $0.x0 }  // upright: not an area's dashed edge
    // Four or more on one baseline are the letters of a tooltip's yellow title, not icons.
    return icons.filter { i in icons.filter { abs($0.y1 - i.y1) <= 3 }.count < 4 }
        .map { (Double($0.sx) / Double($0.n), Double($0.sy) / Double($0.n)) }
        .filter { hypot($0.x - Double(cx), $0.y - Double(cy)) <= Double(r) - 4 }
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
