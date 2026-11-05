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

// Two looks: the whole playfield crop, then an enlarged sub-crop around the first answer.
// On 5 Nov night frames the first look was 25-40 px off (or on the orb); the second was within 4 px.
func jevLocateFloat(_ image: CGImage, key: String) async -> JevFloat? {
    let at = ProcessInfo.processInfo.systemUptime
    guard let first = await jevBox(image, key: key, note: "") else { return nil }
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

// Motion energy in the Jev box: mean absolute grey change between consecutive frames.
func boxEnergy(_ current: [Double], _ previous: [Double]) -> Double {
    zip(current, previous).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(max(current.count, 1))
}

// A bite is a spike far above the box's own calm history (bobbing included), not an absolute level.
// ponytail: 5 Nov night casts: bites 4.6, 8.5, 9.6; calm bobbing peaked at 2.96 (frames checked).
func motionSpike(_ history: [Double], _ energy: Double) -> Bool {
    guard history.count >= 10 else { return false }
    let median = history.sorted()[history.count/2]
    return energy > max(median*4, 4)
}

// Two frames in a row above 3x the calm median also count (a slower plunge).
func motionRise(_ history: [Double], _ energy: Double) -> Bool {
    guard history.count >= 10 else { return false }
    return energy > max(history.sorted()[history.count/2]*3, 3.3)
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
func maskedBoxEnergy(_ current: [UInt8], _ previous: [UInt8]) -> Double? {
    func orb(_ p: [UInt8], _ i: Int) -> Bool { let r = Int(p[i]), b = Int(p[i+2]); return b > 90 && b - r > 40 }
    func grey(_ p: [UInt8], _ i: Int) -> Double { 0.299*Double(p[i]) + 0.587*Double(p[i+1]) + 0.114*Double(p[i+2]) }
    var sum = 0.0, used = 0, total = 0
    for i in stride(from: 0, to: min(current.count, previous.count) - 3, by: 4) {
        total += 1
        if orb(current, i) || orb(previous, i) { continue }
        sum += abs(grey(current, i) - grey(previous, i)); used += 1
    }
    return used * 2 >= total ? sum / Double(used) : nil
}
