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

/// Character slot IDs for GetInventoryItemLink, by the slot word on the tooltip.
let equipSlots: [String: Int] = ["Head": 1, "Neck": 2, "Shoulder": 3, "Chest": 5, "Waist": 6, "Legs": 7, "Feet": 8,
                                 "Wrist": 9, "Hands": 10, "Finger": 11, "Trinket": 13, "Back": 15, "Main Hand": 16,
                                 "One-Hand": 16, "Two-Hand": 16, "Off Hand": 17, "Held In Off-hand": 17, "Ranged": 18]

/// A reward's tooltip, read while the pointer rests on it. The game draws the equipped item beside it
/// ("Equipped", then "If you replace this item, the following stat changes will occur: +2 Armor"),
/// and the quest text shows through behind both: lines are kept by alignment, as in tooltipLines.
func parseReward(_ lines: [TipLine]) -> Reward? {
    guard let foot = lines.first(where: { isTooltipFooter($0.text) }) else { return nil }
    let compare = lines.first { $0.text.hasPrefix("If you replace this item") }
    let own = lines.filter {
        $0.y < foot.y && $0.x < (compare?.x ?? .infinity) - 8 && (abs($0.x - foot.x) <= 8 || $0.x >= foot.x + 150)
    }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    guard let name = own.first?.text else { return nil }
    let slot = own.map(\.text).first { equipSlots[$0] != nil }
    let sell = own.first { $0.text.hasPrefix("Sell Price") }.flatMap { Int($0.text.filter(\.isNumber)) } ?? 0
    let change: Double
    if let compare {
        change = lines.filter { abs($0.x - compare.x) <= 8 && $0.y > compare.y }.compactMap { line -> Double? in
            guard let first = line.text.split(separator: " ").first, "+-".contains(first.prefix(1)) else { return nil }
            return Double(first)
        }.reduce(0, +)
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

/// The yellow "?" (quest ready) and "!" (quest offered) over an NPC's head. Zoomed out it is small and
/// dim: (185-224, 155-192, 40-48) on 24 Sept, so the test is the hue, not a bright threshold.
func markYellow(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 175 && g > 140 && b < 80 && r - b > 110 && g - b > 90 }

/// The NPC's green name under its mark: (50-65, 150-198, 32-42) on 24 Sept.
func nameGreen(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > 150 && g > r + 60 && g > b + 60 }

/// Centres of yellow quest marks in a box (x0, y0, x1, y1), nearest the view's centre first. A mark is
/// an upright blob (a "?" is about 10 x 18 px zoomed out) with a green NPC name 8-50 px below it: a
/// neutral creature's yellow nameplate bar is a flat strip, and a glowing Cirrusfly has no green name
/// (live frames: 305 green pixels under the real "?", 0-23 under the insects).
func questMarks(_ image: RGBA, box: (Int, Int, Int, Int), minPixels: Int = 20) -> [(x: Double, y: Double)] {
    typealias Blob = (n: Int, sx: Int, sy: Int, x0: Int, x1: Int, y0: Int, y1: Int)
    var cells: [Int: Blob] = [:]  // 12-px cells, merged into blobs below
    for y in box.1..<min(box.3, image.height) {
        for x in box.0..<min(box.2, image.width) {
            let i = (y * image.width + x) * 4
            guard markYellow(Int(image.pixels[i]), Int(image.pixels[i + 1]), Int(image.pixels[i + 2])) else { continue }
            let key = (y / 12) * 10_000 + x / 12
            let c = cells[key] ?? (0, 0, 0, x, x, y, y)
            cells[key] = (c.n + 1, c.sx + x, c.sy + y, min(c.x0, x), max(c.x1, x), min(c.y0, y), max(c.y1, y))
        }
    }
    var blobs: [Blob] = []
    for c in cells.values.sorted(by: { ($0.y0, $0.x0) < ($1.y0, $1.x0) }) {
        if let j = blobs.firstIndex(where: { c.x0 <= $0.x1 + 13 && c.x1 >= $0.x0 - 13 && c.y0 <= $0.y1 + 13 && c.y1 >= $0.y0 - 13 }) {
            let b = blobs[j]
            blobs[j] = (b.n + c.n, b.sx + c.sx, b.sy + c.sy, min(b.x0, c.x0), max(b.x1, c.x1), min(b.y0, c.y0), max(b.y1, c.y1))
        } else {
            blobs.append(c)
        }
    }
    let cx = Double(image.width) / 2, cy = Double(image.height) / 2
    func greenBelow(_ x: Int, _ y: Int) -> Int {
        var n = 0
        for yy in max(0, y + 8)..<min(image.height, y + 50) {
            for xx in max(0, x - 50)..<min(image.width, x + 50) {
                let i = (yy * image.width + xx) * 4
                if nameGreen(Int(image.pixels[i]), Int(image.pixels[i + 1]), Int(image.pixels[i + 2])) { n += 1 }
            }
        }
        return n
    }
    return blobs.filter { b in
        let w = b.x1 - b.x0 + 1, h = b.y1 - b.y0 + 1
        return b.n >= minPixels && w <= 24 && h >= 10 && Double(h) >= 0.8 * Double(w)
            && greenBelow(b.sx / b.n, b.sy / b.n) >= 80
    }.map { (x: Double($0.sx) / Double($0.n), y: Double($0.sy) / Double($0.n)) }
     .sorted { hypot($0.x - cx, $0.y - cy) < hypot($1.x - cx, $1.y - cy) }
}
