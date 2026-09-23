// M2 perception for issue #5: find the game-designated target on screen from WoW's own UI.
// After Tab (target nearest enemy), WoW outlines only the current target's nameplate in
// white. Measured on three targets at 2560x1320 (23 September 2026): a near-white top edge
// ~107 px long and a bottom edge ~133 px (it includes the level badge), each 2-3 rows thick,
// 13 rows apart, around a coloured health bar. Non-target nameplates have dark outlines.
// The nameplate sits above the unit, so its x is the unit's bearing, and its row falls
// down the screen as the unit gets closer. It is UI evidence, not proof of unit identity.
import Foundation

/// RGBA bytes, row-major from the top-left.
struct RGBA {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

struct Plate: Equatable {
    let x0: Int  // top edge span: the bar without the level badge, centred on the unit
    let x1: Int
    let top: Int
    let bottom: Int
    var centre: Double { Double(x0 + x1) / 2 }
}

enum PlateLimits {
    static let white: UInt8 = 170  // every channel above this is near-white
    static let minRun = 0.03       // edge length, fraction of width (107 px measured = 0.042)
    static let maxThickness = 4    // rows; snow, sky and text blocks are thicker or shorter
    static let gap = 0.006...0.025 // rows between the edges, fraction of height (0.0098 measured)
    static let rows = 0.03..<0.72  // game view: below the title bar, above unit frames and bars
    static let columns = 0.88      // left of the minimap and quest tracker
}

/// The one white-outlined nameplate in the game view, or nil when there is none or more
/// than one: ambiguity is never resolved by guessing.
func findTargetPlate(_ image: RGBA) -> Plate? {
    let width = image.width, height = image.height
    let minRun = Int(PlateLimits.minRun * Double(width))
    let rows = Int(PlateLimits.rows.lowerBound * Double(height))..<Int(PlateLimits.rows.upperBound * Double(height))
    let columns = Int(PlateLimits.columns * Double(width))
    guard image.pixels.count == width * height * 4, minRun > 0, !rows.isEmpty else { return nil }

    var runs: [(y: Int, x0: Int, x1: Int)] = []
    image.pixels.withUnsafeBufferPointer { pixels in
        func white(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            return pixels[i] > PlateLimits.white && pixels[i + 1] > PlateLimits.white && pixels[i + 2] > PlateLimits.white
        }
        for y in rows {
            var x = 0
            while x < columns {
                guard white(x, y) else { x += 1; continue }
                let start = x
                while x < columns && white(x, y) { x += 1 }
                if x - start >= minRun { runs.append((y, start, x)) }
            }
        }
    }

    // Consecutive rows with overlapping spans form one edge.
    var edges: [(top: Int, bottom: Int, x0: Int, x1: Int)] = []
    for run in runs {
        if let i = edges.lastIndex(where: { run.y - $0.bottom == 1 && run.x0 < $0.x1 && $0.x0 < run.x1 }) {
            edges[i] = (edges[i].top, run.y, min(edges[i].x0, run.x0), max(edges[i].x1, run.x1))
        } else {
            edges.append((run.y, run.y, run.x0, run.x1))
        }
    }
    let thin = edges.filter { $0.bottom - $0.top < PlateLimits.maxThickness }
    let gap = Int((PlateLimits.gap.lowerBound * Double(height)).rounded(.down))...Int((PlateLimits.gap.upperBound * Double(height)).rounded(.up))

    var plates: [Plate] = []
    for upper in thin {
        for lower in thin where gap.contains(lower.top - upper.bottom) {
            let overlap = min(upper.x1, lower.x1) - max(upper.x0, lower.x0)
            guard Double(overlap) >= 0.8 * Double(upper.x1 - upper.x0) else { continue }
            // Between the edges lies the coloured bar, not more white.
            var inside = 0, whiteInside = 0
            for y in (upper.bottom + 2)..<max(upper.bottom + 2, lower.top - 1) {
                for x in (upper.x0 + 3)..<max(upper.x0 + 3, upper.x1 - 3) {
                    let i = (y * width + x) * 4
                    inside += 1
                    if image.pixels[i] > PlateLimits.white && image.pixels[i + 1] > PlateLimits.white
                        && image.pixels[i + 2] > PlateLimits.white { whiteInside += 1 }
                }
            }
            guard inside > 0, Double(whiteInside) < 0.2 * Double(inside) else { continue }
            plates.append(Plate(x0: upper.x0, x1: upper.x1, top: upper.top, bottom: lower.bottom))
        }
    }
    return plates.count == 1 ? plates[0] : nil
}
