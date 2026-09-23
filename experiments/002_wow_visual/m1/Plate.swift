// M2 perception for issue #5: find the game-designated target on screen from WoW's own UI.
// After Tab (target nearest enemy), WoW outlines only the current target's nameplate in
// white. Measured on four targets at 2560x1320 (23 September 2026): the bar's near-white
// bottom edge is ~133 px long and 3 rows thick; its top edge, 13 rows above, is cut where the
// name's descenders cross it ("J" in Juvenile, "y" in Pesky); the level badge is a separate
// outlined box to the right. Non-target nameplates have dark outlines.
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
    let x0: Int  // the bar's span, without the level badge: centred on the unit
    let x1: Int
    let top: Int
    let bottom: Int
    var centre: Double { Double(x0 + x1) / 2 }
}

enum PlateLimits {
    static let white: UInt8 = 170  // every channel above this is near-white
    static let minRun = 0.03       // bottom edge length, fraction of width (133 px measured = 0.052)
    static let cover = 0.7         // top edge: white share of the bottom edge's span. Names' descenders
                                   // cut it ("Pesky Cirrusfly": 61 + 56 px, live M2 run 2); text is ~0.5
    static let bridge = 0.003      // cut bridged when measuring the bar (descender 6 px; badge gap 11+)
    static let maxThickness = 4    // rows; snow, sky and text blocks are thicker
    static let gap = 0.006...0.025 // rows between the edges, fraction of height (0.0098 measured)
    static let rows = 0.03..<0.72  // game view: below the title bar, above unit frames and bars
    static let columns = 0.88      // left of the minimap and quest tracker
}

/// The one white-outlined nameplate in the game view, or nil when there is none or more
/// than one: ambiguity is never resolved by guessing. Anchored on the uninterrupted bottom
/// edge; the top edge only needs coverage, because a name's descenders cross it.
func findTargetPlate(_ image: RGBA) -> Plate? {
    let width = image.width, height = image.height
    let minRun = Int(PlateLimits.minRun * Double(width))
    let bridge = Int(PlateLimits.bridge * Double(width))
    let rows = Int(PlateLimits.rows.lowerBound * Double(height))..<Int(PlateLimits.rows.upperBound * Double(height))
    let columns = Int(PlateLimits.columns * Double(width))
    guard image.pixels.count == width * height * 4, minRun > 0, !rows.isEmpty else { return nil }

    return image.pixels.withUnsafeBufferPointer { pixels -> Plate? in
        func white(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            return pixels[i] > PlateLimits.white && pixels[i + 1] > PlateLimits.white && pixels[i + 2] > PlateLimits.white
        }
        func coverage(_ y: Int, _ x0: Int, _ x1: Int) -> Double {
            guard y >= 0, x1 > x0 else { return 0 }
            return Double((x0..<x1).filter { white($0, y) }.count) / Double(x1 - x0)
        }

        var runs: [(y: Int, x0: Int, x1: Int)] = []
        for y in rows {
            var x = 0
            while x < columns {
                guard white(x, y) else { x += 1; continue }
                let start = x
                while x < columns && white(x, y) { x += 1 }
                if x - start >= minRun { runs.append((y, start, x)) }
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
        let gap = Int((PlateLimits.gap.lowerBound * Double(height)).rounded(.down))...Int((PlateLimits.gap.upperBound * Double(height)).rounded(.up))

        var plates: [Plate] = []
        for lower in edges where lower.bottom - lower.top < PlateLimits.maxThickness {
            // The top edge: the nearest well-covered band above, itself thin.
            guard let near = gap.first(where: { coverage(lower.top - $0, lower.x0, lower.x1) >= PlateLimits.cover }) else { continue }
            let bandBottom = lower.top - near
            var bandTop = bandBottom
            while bandBottom - (bandTop - 1) < PlateLimits.maxThickness + 1,
                  coverage(bandTop - 1, lower.x0, lower.x1) >= PlateLimits.cover { bandTop -= 1 }
            guard bandBottom - bandTop < PlateLimits.maxThickness else { continue }
            // Between the edges lies the coloured bar, not more white.
            let inside = (bandBottom + 2)..<max(bandBottom + 2, lower.top - 1)
            guard !inside.isEmpty,
                  inside.map({ coverage($0, lower.x0 + 3, lower.x1 - 3) }).reduce(0, +) / Double(inside.count) < 0.2 else { continue }
            // The bar is the top edge's first span, cuts bridged; the level badge follows a wider gap.
            var x0 = lower.x0
            while x0 < lower.x1 && !white(x0, bandBottom) { x0 += 1 }
            var x1 = x0, dark = 0
            while x1 < lower.x1 && dark <= bridge {
                dark = white(x1, bandBottom) ? 0 : dark + 1
                x1 += 1
            }
            plates.append(Plate(x0: x0, x1: x1 - dark, top: bandTop, bottom: lower.bottom))
        }
        return plates.count == 1 ? plates[0] : nil
    }
}

enum RingLimits {
    static let gap = 0.005           // first row searched under the plate, fraction of height; the
                                     // search runs to the game view's bottom so any stop row is observable
    static let minPixels = 0.00001   // fraction of the frame; smaller (far) circles read as not yet visible
    static let maxAspect = 8.0       // wider than this is another unit's health bar, not a circle
    static let offCentre = 0.75      // blob centre within this many plate widths of the plate's centre:
                                     // live M2 run 5 stopped early on a neighbour's glow 238 px aside
}

/// Neutral (yellow) selection-circle colour, measured mean RGB 144-162, 152-168, 59-73.
func ringColour(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
    r > 120 && g > 120 && Double(b) < 0.55 * Double(min(r, g)) && abs(Int(r) - Int(g)) < 70
}

/// The bottom row of the target's selection circle under its nameplate. Unlike the nameplate,
/// which floats near camera height, this ground point falls down the screen as the unit gets
/// closer (live M2 run 3: 0.29 to 0.37 of the height over ~15 yd). Of the circle-coloured
/// blobs that are large enough, not bar-shaped and centred under the plate, the lowest bottom
/// wins: the body and grass split the circle, and reading low stops early, never late.
/// Neutral circles only; nil when none qualifies (absent, far or elsewhere).
func findGround(_ image: RGBA, below plate: Plate) -> Int? {
    let width = image.width, height = image.height, span = plate.x1 - plate.x0
    let x0 = max(0, plate.x0 - span), x1 = min(width, plate.x1 + span)
    let y0 = min(height, plate.bottom + Int(RingLimits.gap * Double(height)))
    let y1 = Int(PlateLimits.rows.upperBound * Double(height))  // above the unit frames' yellow bars
    guard image.pixels.count == width * height * 4, x1 > x0, y1 > y0 else { return nil }
    let w = x1 - x0, h = y1 - y0
    var mask = [Bool](repeating: false, count: w * h)
    for y in y0..<y1 {
        for x in x0..<x1 {
            let i = (y * width + x) * 4
            mask[(y - y0) * w + (x - x0)] = ringColour(image.pixels[i], image.pixels[i + 1], image.pixels[i + 2])
        }
    }
    // 8-connected blobs; neighbouring units bring their own yellow, so only centred ones count.
    let reach = RingLimits.offCentre * Double(span)
    let minPixels = RingLimits.minPixels * Double(width * height)
    var lowest: Int?
    var seen = [Bool](repeating: false, count: w * h)
    for start in mask.indices where mask[start] && !seen[start] {
        var stack = [start], count = 0
        var (left, right, top, bottom) = (w, 0, h, 0)
        seen[start] = true
        while let index = stack.popLast() {
            count += 1
            let (x, y) = (index % w, index / w)
            (left, right, top, bottom) = (min(left, x), max(right, x), min(top, y), max(bottom, y))
            for dy in -1...1 {
                for dx in -1...1 where (dx, dy) != (0, 0) {
                    let (nx, ny) = (x + dx, y + dy)
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let next = ny * w + nx
                    if mask[next] && !seen[next] { seen[next] = true; stack.append(next) }
                }
            }
        }
        let centred = abs(Double(x0) + Double(left + right) / 2 - plate.centre) <= reach
        let circular = Double(right - left + 1) <= RingLimits.maxAspect * Double(bottom - top + 1)
        if centred && circular && Double(count) >= minPixels { lowest = max(lowest ?? 0, y0 + bottom) }
    }
    return lowest
}
