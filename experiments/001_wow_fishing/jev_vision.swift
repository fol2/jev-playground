// Jev vision acquisition: Jev finds the float in the cropped playfield (Box question);
// the existing pixel tracker and bite rule take over from that point.
// Turn on with JEV_LOCATE=1. Needs Jev 1.14 and the TypeSafe images header.
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct JevFloat { let x: Double; let y: Double; let visible: Double; let confidence: Double; let seconds: Double }

// ponytail: 0.7 from night frames on 5 Nov (float 0.92-0.93, empty water 0.59); tune on more casts.
let jevFloatMinimum = 0.7

private let jevScene = "A World of Warcraft screenshot of the water in front of a player who is fishing; it may be day or night, clear or rainy. A glowing blue-purple orb (a spell effect) may float in the air near the player. The fishing float (bobber) is a different, small object (red and white by day, dark at night) sitting on the water surface where the thin fishing line ends."

private func jevBox(_ image: CGImage, key: String, note: String) async -> (x: Double, y: Double, visible: Double, confidence: Double)? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    let ref = "f1a7e0c2-\(UUID().uuidString.prefix(8))"
    let body: [String: Any] = [
        "model": "jev-latest",
        "state": ["frame": ref, "context": jevScene + note],
        "assets": [ref: ["type": "image", "format": "jpg", "data_base64": (data as Data).base64EncodedString()]],
        "questions": [
            "visible": ["type": "noul", "instructions": "Is a fishing float (bobber) sitting on the water in `frame`?"],
            "float": ["type": "box", "instructions": "the small fishing float (bobber) on the water surface where the thin fishing line ends in `frame`, not the glowing orb"]]]
    var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!, timeoutInterval: 3)
    request.httpMethod = "POST"
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("true", forHTTPHeaderField: "TypeSafe-Danger-Zone-Images")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (reply, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
          let answers = json["answers"] as? [String: Any],
          let visible = (answers["visible"] as? [String: Any])?["noul"] as? Double,
          let float = answers["float"] as? [String: Any], let box = float["box"] as? [String: Double],
          let l = box["left"], let r = box["right"], let t = box["top"], let b = box["bottom"] else { return nil }
    return ((l+r)/2, (t+b)/2, visible, float["confidence"] as? Double ?? 0)
}

// With "Interact Key Icons: Show All", WoW draws a small gold gear icon above the one object the
// player can interact with: our own float, never another player's. 6 Nov: found in both icon casts
// (3-7 pixels, 53-58 px above the float) and in none of eight casts without the setting.
// Stormwind by day (7 Nov) is full of gold (lamps, roofs, flowers, tracker text), so a whole-frame
// centroid lands on the buildings. With a pre-cast `reference` frame of the same size, only gold that
// is new since the cast counts; the icon is then the densest 15 px cluster of those pixels.
func interactIconCentroid(_ image: CGImage, reference: [UInt8]? = nil) -> CGPoint? {
    let w = image.width, h = image.height, pixels = imagePixels(image, width: w, height: h)
    // Daylight icon pixels read R 135-220, R-B 95-110 (7 Nov); with a reference the looser colour is safe.
    let usable = reference.map { $0.count == pixels.count } ?? false
    func gold(_ p: [UInt8], _ i: Int) -> Bool {
        let r = Int(p[i]), g = Int(p[i+1]), b = Int(p[i+2])
        return usable ? r > 140 && g > 90 && b < 130 && r - b > 80 : r > 180 && g > 120 && b < 110 && r - b > 100
    }
    // Gold already within 2 px in the reference is scenery (a lamp shifts a pixel between frames).
    func oldGold(_ x: Int, _ y: Int) -> Bool {
        for dy in -2...2 { for dx in -2...2 {
            let xx = x+dx, yy = y+dy
            if xx >= 0, yy >= 0, xx < w, yy < h, gold(reference!, (yy*w+xx)*4) { return true }
        } }
        return false
    }
    // Count new gold per 8 px cell; the icon is a dense 3x3-cell patch with almost no gold around it.
    // Sunset glare (7 Nov) shimmers, so it is new gold every frame, but it spreads over a wide area.
    let cell = 8, cw = (w + cell - 1)/cell, ch = (h + cell - 1)/cell
    var count = [Int](repeating: 0, count: cw*ch), sx = count, sy = count, all = count
    var x0 = [Int](repeating: Int.max, count: cw*ch), y0 = x0, x1 = [Int](repeating: -1, count: cw*ch), y1 = x1
    for y in 0..<h { for x in 0..<w where gold(pixels, (y*w + x)*4) {
        let c = (y/cell)*cw + x/cell; all[c] += 1
        if !(usable && oldGold(x, y)) {
            count[c] += 1; sx[c] += x; sy[c] += y
            x0[c] = min(x0[c], x); x1[c] = max(x1[c], x); y0[c] = min(y0[c], y); y1[c] = max(y1[c], y)
        }
    } }
    func sum(_ cx: Int, _ cy: Int, _ r: Int, _ a: [Int]) -> Int {
        var t = 0
        for yy in max(cy-r, 0)...min(cy+r, ch-1) { for xx in max(cx-r, 0)...min(cx+r, cw-1) { t += a[yy*cw + xx] } }
        return t
    }
    var best: (n: Int, x: Int, y: Int)? = nil
    for cy in 0..<ch { for cx in 0..<cw where count[cy*cw + cx] > 0 {
        let local = sum(cx, cy, 1, count)
        // Isolation counts all gold, old or new: glare stays gold in every frame, the icon's water does not.
        // ponytail: at most half as much gold again in the 7x7 cells around; tune if a real icon fails.
        guard local >= 3, sum(cx, cy, 3, all) - sum(cx, cy, 1, all) <= local/2, local > (best?.n ?? 0) else { continue }
        // The icon is a round badge; a glare glint is a flat streak (7 Nov sunset: 25 x 5 px).
        var bx0 = Int.max, by0 = Int.max, bx1 = -1, by1 = -1
        for yy in max(cy-1, 0)...min(cy+1, ch-1) { for xx in max(cx-1, 0)...min(cx+1, cw-1) where count[yy*cw + xx] > 0 {
            let c = yy*cw + xx; bx0 = min(bx0, x0[c]); bx1 = max(bx1, x1[c]); by0 = min(by0, y0[c]); by1 = max(by1, y1[c])
        } }
        let bw = Double(bx1 - bx0 + 1), bh = Double(by1 - by0 + 1)
        guard bw <= 1.6*bh, bh <= 1.6*bw else { continue }   // icons read 8 x 7; glints 20-24 x 10
        best = (local, sum(cx, cy, 1, sx), sum(cx, cy, 1, sy))
    } }
    guard let best else { return nil }
    return CGPoint(x: Double(best.x)/Double(best.n), y: Double(best.y)/Double(best.n))
}

// Two looks: the whole playfield crop, then an enlarged sub-crop around the first answer.
// On 5 Nov night frames the first look was 25-40 px off (or on the orb); the second was within 4 px.
func jevLocateFloat(_ image: CGImage, key: String, reference: [UInt8]? = nil) async -> JevFloat? {
    let at = ProcessInfo.processInfo.systemUptime
    // Our float sits just below the interact icon: start the enlarged look there, so other players'
    // floats are outside the crop. Without the icon, Jev's whole-playfield look decides as before.
    let first: (x: Double, y: Double)
    if let icon = interactIconCentroid(image, reference: reference) {
        first = (icon.x / Double(image.width), (icon.y + 45) / Double(image.height))
    } else {
        guard let look = await jevBox(image, key: key, note: "") else { return nil }
        first = (look.x, look.y)
    }
    let side = Double(min(200, image.width, image.height))
    let sub = CGRect(x: min(max(first.x*Double(image.width)-side/2, 0), Double(image.width)-side),
                     y: min(max(first.y*Double(image.height)-side/2, 0), Double(image.height)-side),
                     width: side, height: side).integral
    guard let patch = image.cropping(to: sub),
          let context = CGContext(data: nil, width: 448, height: 448, bitsPerComponent: 8, bytesPerRow: 448*4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(patch, in: CGRect(x: 0, y: 0, width: 448, height: 448))
    guard let enlarged = context.makeImage(),
          let second = await jevBox(enlarged, key: key, note: " This is an enlarged close crop.") else { return nil }
    return JevFloat(x: sub.minX + second.x*sub.width, y: sub.minY + second.y*sub.height, visible: second.visible,
                    confidence: second.confidence, seconds: ProcessInfo.processInfo.systemUptime-at)
}

// A bite is a spike far above the box's own calm history (bobbing included), not an absolute level.
// ponytail: 5 Nov night replay: real bites peak 4.47-9.8; bob animation 3.55, orb masked; 19/22 fire, 0/4 false.
// The first 2.2 s after the lock are the float settling: 5 of 14 uncaught reels fired there, 2 of 65 catches.
func motionSpike(_ history: [Double], _ energy: Double) -> Bool {
    guard history.count >= 22 else { return false }
    let median = history.sorted()[history.count/2]
    // Floor 5: ring ripples and the bob reached 3.55-4.96 (frames checked); catches 4.47 once, else 5.3-12.8.
    if energy > max(median*4, 5) { return true }
    // Adaptive to the water: choppy shallow water (Darkshore, 7 Nov) lifts the median to 4-5 and a bite
    // reaches only 2x it. Compare the last three frames' mean with this cast's own p95 before them:
    // 15 eye-labelled Darkshore bites reached 1.2-1.7x, wave noise 1.0-1.15x. Replay: 14/15 bites, 2 false
    // fires in 17 casts; the 38 calm-water catches fire at the same frame as before.
    let base = history.dropLast(2).sorted()
    let p95 = base[min(base.count-1, Int(0.95*Double(base.count)))], baseMedian = base[base.count/2]
    let last3 = Array(history.suffix(2)) + [energy]
    return last3.reduce(0, +)/3 > max(p95*1.15, 5) && last3.allSatisfy { $0 > baseMedian }
}

// The whole-picture change the click tolerates: 3 in calm water, but choppy water alone reaches 2.5-4.2
// during bites (7 Nov), so allow 1.5x this cast's own median.
func sceneSteady(_ history: [Double], _ background: Double) -> Bool {
    let median = history.isEmpty ? 0 : history.sorted()[history.count/2]
    return background < max(3, median*1.5)
}

// The spell orb is bright blue-purple; the float and night water never are. A box frame that
// contains orb pixels (or follows one) says nothing about the float. ponytail: colour floor
// from 5 Nov frames; re-check if the orb or water colour changes.
func orbInBox(_ rgba: [UInt8]) -> Bool {
    var count = 0
    for i in stride(from: 0, to: rgba.count - 3, by: 4) {
        let r = Int(rgba[i]), b = Int(rgba[i+2])
        if b > 170 && b - r > 60 { count += 1; if count >= 3 { return true } }
    }
    return false
}

// Box change with orb pixels masked out: a pixel counts only when it is not orb-coloured
// (core or dim glow) in either frame. Returns nil when over half the box is orb.
// Daylight Stormwind water (7 Nov) is itself "orb-coloured": when the playfield is broadly that colour,
// the water is blue and the cast runs without the orb mask (mask: false).
func orbColouredFraction(_ rgba: [UInt8]) -> Double {
    var hits = 0, total = 0
    for i in stride(from: 0, to: rgba.count - 3, by: 4) {
        total += 1; if orbColoured(rgba, i) { hits += 1 }
    }
    return total == 0 ? 0 : Double(hits)/Double(total)
}
func orbColoured(_ p: [UInt8], _ i: Int) -> Bool { let r = Int(p[i]), b = Int(p[i+2]); return b > 90 && b - r > 40 }

func maskedBoxEnergy(_ current: [UInt8], _ previous: [UInt8], mask: Bool = true) -> Double? {
    func orb(_ p: [UInt8], _ i: Int) -> Bool { mask && orbColoured(p, i) }
    func grey(_ p: [UInt8], _ i: Int) -> Double { 0.299*Double(p[i]) + 0.587*Double(p[i+1]) + 0.114*Double(p[i+2]) }
    var sum = 0.0, used = 0, total = 0
    for i in stride(from: 0, to: min(current.count, previous.count) - 3, by: 4) {
        total += 1
        if orb(current, i) || orb(previous, i) { continue }
        sum += abs(grey(current, i) - grey(previous, i)); used += 1
    }
    return used * 2 >= total ? sum / Double(used) : nil
}

private func scaled(_ image: CGImage, _ rect: CGRect, width: Int) -> CGImage? {
    guard let patch = image.cropping(to: rect.integral) else { return nil }
    let height = max(280, Int(Double(width) * rect.height / rect.width))
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(patch, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

private func jevAnyBox(_ image: CGImage, key: String, context: String, instructions: String,
                       requirePresent: Bool = true) async -> (l: Double, t: Double, r: Double, b: Double)? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    let ref = "b4a9e1c3-\(UUID().uuidString.prefix(8))"
    let body: [String: Any] = ["model": "jev-latest", "state": ["screen": ref, "context": context],
        "assets": [ref: ["type": "image", "format": "jpg", "data_base64": (data as Data).base64EncodedString()]],
        "questions": ["target": ["type": "box", "instructions": instructions],
                      "present": ["type": "noul", "instructions": "Is the thing described here visible in `screen`: " + instructions + "?"]]]
    var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!, timeoutInterval: 5)
    request.httpMethod = "POST"
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("true", forHTTPHeaderField: "TypeSafe-Danger-Zone-Images")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (reply, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
          let target = (json["answers"] as? [String: Any])?["target"] as? [String: Any],
          let box = target["box"] as? [String: Double],
          let l = box["left"], let r = box["right"], let t = box["top"], let b = box["bottom"] else { return nil }
    // A box is always returned; without the thing on screen it points somewhere else (6 Nov: the action bar).
    let present = ((json["answers"] as? [String: Any])?["present"] as? [String: Any])?["noul"] as? Double ?? 0
    return !requirePresent || present >= 0.7 ? (l, t, r, b) : nil
}

// B toggles the bag, so its state is unknown: ask first (open bag: 0.98 on 6 Nov).
func jevBagOpen(_ small: CGImage, key: String) async -> Bool {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, small, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return false }
    let ref = "c7d2a9f0-\(UUID().uuidString.prefix(8))"
    let body: [String: Any] = ["model": "jev-latest", "state": ["screen": ref],
        "assets": [ref: ["type": "image", "format": "jpg", "data_base64": (data as Data).base64EncodedString()]],
        "questions": ["open": ["type": "noul", "instructions": "Is the player's bag (an inventory panel with a grid of item slots) open in this World of Warcraft screenshot `screen`?"]]]
    var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!, timeoutInterval: 5)
    request.httpMethod = "POST"
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("true", forHTTPHeaderField: "TypeSafe-Danger-Zone-Images")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (reply, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
          let open = ((json["answers"] as? [String: Any])?["open"] as? [String: Any])?["noul"] as? Double else { return false }
    return open >= 0.7
}

// Two looks, as for the float: a panel in the whole window, then the item in the enlarged panel.
// Rod in bag on 6 Nov offline: (0.986, 0.818) against the true slot (0.988, 0.817). Returns window
// fractions; callers still confirm the tooltip before clicking anything.
func jevLocateInPanel(_ screen: CGImage, key: String, panel panelText: String, item itemText: String) async -> CGPoint? {
    let full = CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
    guard let small = scaled(screen, full, width: 1400),
          let panel = await jevAnyBox(small, key: key, context: "A World of Warcraft screenshot.",
              instructions: panelText + " in `screen`") else { return nil }
    let w = Double(screen.width), h = Double(screen.height), pad = 0.01
    let rect = CGRect(x: max(0, panel.l - pad) * w, y: max(0, panel.t - pad) * h,
                      width: (min(1, panel.r + pad) - max(0, panel.l - pad)) * w,
                      height: (min(1, panel.b + pad) - max(0, panel.t - pad)) * h)
    guard let enlarged = scaled(screen, rect, width: 1100),
          // The panel step guards against an unopened panel; inside it a small slot's presence score wavers
          // (6 Nov: a main-hand slot dropped below 0.7), and the caller's tooltip OCR confirms anyway.
          let item = await jevAnyBox(enlarged, key: key, context: "An enlarged crop of a World of Warcraft interface panel.",
              instructions: itemText + " in `screen`", requirePresent: false) else { return nil }
    return CGPoint(x: (rect.minX + (item.l + item.r) / 2 * rect.width) / w, y: (rect.minY + (item.t + item.b) / 2 * rect.height) / h)
}

func jevLocateRodInBag(_ screen: CGImage, key: String) async -> CGPoint? {
    let full = CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
    guard let small = scaled(screen, full, width: 1400), await jevBagOpen(small, key: key) else { return nil }
    return await jevLocateInPanel(screen, key: key, panel: "the whole open bag (inventory) panel with its grid of item slots",
                                  item: "the single item slot holding a fishing pole (a long thin fishing rod with a line and hook)")
}

// The character sheet moves with level and UI scale; find the main-hand slot instead of a fixed point.
func jevLocateMainHandSlot(_ screen: CGImage, key: String) async -> CGPoint? {
    await jevLocateInPanel(screen, key: key, panel: "the open character sheet panel (equipment slots around the character model)",
                           item: "the main hand weapon slot (the left of the weapon slots along the bottom edge, below the character model)")
}
