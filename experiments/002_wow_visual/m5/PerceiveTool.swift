// M5 tool, run from the repository root. Frames, crops and labels stay under runs/002_wow_visual (private
// captures); the teacher that labels the candidates is its own binary (Teacher.swift).
//   m5-perceive --propose       frame paths under runs/002_wow_visual on stdin; candidates appended, resumable
//   m5-perceive --sheet N       contact sheets of up to N labels not yet audited, 48 a sheet, for audit
//   m5-perceive --sheet-held N  the same, of held-out runs only: those are audited in full, as the test set
//   m5-perceive --audit FILE    the auditor's corrections to the last sheets ("id kind" lines); the rest confirmed
//   m5-perceive --baseline      the teacher and the rule reader (questMarks) against the audited labels; wrong frames
//                               to baseline-errors.txt
import Foundation
import ImageIO
import CoreGraphics
import CoreText
import CryptoKit

let runsRoot = URL(fileURLWithPath: "runs/002_wow_visual")
let perceptionDir = runsRoot.appendingPathComponent("perception")
let candidatesFile = perceptionDir.appendingPathComponent("candidates.jsonl")
let framesFile = perceptionDir.appendingPathComponent("frames.jsonl")  // one row per frame proposed, for resuming
let labelsFile = perceptionDir.appendingPathComponent("marks.jsonl")  // the teacher's
let auditFile = perceptionDir.appendingPathComponent("audit.jsonl")  // the auditor's, from --audit
let maxCandidates = 40  // per frame; a frame of flames can have 80

struct FrameRow: Codable { var frame: String; var candidates: Int }
struct CandidateRow: Codable { var frame: String; var box: [Int]; var crop: [Int]; var hash: String }

func loadImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func pixels(_ image: CGImage) -> RGBA {
    let w = image.width, h = image.height
    var p = [UInt8](repeating: 0, count: w * h * 4)
    p.withUnsafeMutableBytes { raw in
        let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return RGBA(width: w, height: h, pixels: p)
}

/// The crop's own pixels hashed: the teacher's cache key, whatever file or frame it came from.
func cropHash(_ image: RGBA, _ r: (x: Int, y: Int, w: Int, h: Int)) -> String {
    var hasher = SHA256()
    for y in r.y..<(r.y + r.h) {
        let start = (y * image.width + r.x) * 4
        image.pixels[start..<(start + r.w * 4)].withUnsafeBytes { hasher.update(bufferPointer: $0) }
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func rows<T: Decodable>(_ url: URL, _ type: T.Type) -> [T] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
}

func appendRows<T: Encodable>(_ new: [T], to url: URL) throws {
    guard !new.isEmpty else { return }
    var data = Data()
    for row in new { data.append(try JSONEncoder().encode(row)); data.append(0x0A) }
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
}

func propose() throws -> Int32 {
    try FileManager.default.createDirectory(at: perceptionDir, withIntermediateDirectories: true)
    let done = Set(rows(framesFile, FrameRow.self).map(\.frame))
    var frames = 0, total = 0
    while let line = readLine() {
        let path = line.hasPrefix("./") ? String(line.dropFirst(2)) : line
        guard !path.isEmpty, !done.contains(path), let image = loadImage(runsRoot.appendingPathComponent(path)),
              image.width == HUD.width, image.height == HUD.height else { continue }
        let rgba = pixels(image)
        let found = Array(markCandidates(rgba).prefix(maxCandidates)).compactMap { g -> CandidateRow? in
            let r = teacherCrop(g, width: rgba.width, height: rgba.height)
            guard r.w > 0, r.h > 0 else { return nil }
            return CandidateRow(frame: path, box: [g.x0, g.y0, g.x1 - g.x0 + 1, g.y1 - g.y0 + 1], crop: [r.x, r.y, r.w, r.h], hash: cropHash(rgba, r))
        }
        try appendRows(found, to: candidatesFile)
        try appendRows([FrameRow(frame: path, candidates: found.count)], to: framesFile)
        frames += 1
        total += found.count
    }
    print("\(frames) frames proposed, \(total) candidates")
    return 0
}

/// Up to `limit` labels not yet audited, of the current candidates: every mark and refusal first, then a spread of
/// the rest, drawn 48 a sheet with each one's id and the teacher's kind, for an auditor to check by eye. The ids
/// index sheet-index.json.
func sheet(limit: Int, heldOnly: Bool = false) throws -> Int32 {
    let done = Set(rows(auditFile, MarkLabel.self).map { "\($0.frame)|\($0.box)" })
    let current = Set(rows(candidatesFile, CandidateRow.self).map { "\($0.frame)|\($0.box)" })
    let all = rows(labelsFile, MarkLabel.self).filter { $0.teacher == MarkLabels.teacher && current.contains("\($0.frame)|\($0.box)") }
        .filter { !done.contains("\($0.frame)|\($0.box)") && (!heldOnly || heldOut(run: String($0.frame.split(separator: "/").first ?? ""))) }
    let marks = all.filter { $0.kind != "none" }, rest = all.filter { $0.kind == "none" }
    let step = max(1, rest.count / max(1, limit - marks.count))
    let chosen = Array((marks + stride(from: 0, to: rest.count, by: step).map { rest[$0] }).prefix(limit))
    let cellW = 180, cellH = 140, cols = 8, perSheet = 48
    var frames: [String: CGImage] = [:]
    for (s, start) in stride(from: 0, to: chosen.count, by: perSheet).enumerated() {
        let page = Array(chosen[start..<min(chosen.count, start + perSheet)])
        let rowsN = (page.count + cols - 1) / cols
        guard let ctx = CGContext(data: nil, width: cols * cellW, height: rowsN * cellH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cols * cellW, height: rowsN * cellH))
        for (i, l) in page.enumerated() {
            if frames[l.frame] == nil { frames[l.frame] = loadImage(runsRoot.appendingPathComponent(l.frame)) }
            guard let frame = frames[l.frame] else { continue }
            let g: Blob = (1, 0, 0, l.box[0], l.box[0] + l.box[2] - 1, l.box[1], l.box[1] + l.box[3] - 1)
            let r = teacherCrop(g, width: frame.width, height: frame.height)
            guard let crop = frame.cropping(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h)) else { continue }
            let col = i % cols, row = i / cols
            let scale = min(Double(cellW - 4) / Double(r.w), Double(cellH - 20) / Double(r.h), 2)
            let top = Double(rowsN * cellH - row * cellH)  // CoreGraphics puts y = 0 at the bottom
            ctx.draw(crop, in: CGRect(x: Double(col * cellW + 2), y: top - 20 - Double(r.h) * scale,
                                      width: Double(r.w) * scale, height: Double(r.h) * scale))
            let text = NSAttributedString(string: "\(start + i) \(l.kind)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 13, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1)])
            ctx.textPosition = CGPoint(x: col * cellW + 4, y: Int(top) - 16)
            CTLineDraw(CTLineCreateWithAttributedString(text), ctx)
        }
        guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(
            perceptionDir.appendingPathComponent("sheet-\(s + 1).png") as CFURL, "public.png" as CFString, 1, nil) else { continue }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
    try JSONEncoder().encode(chosen).write(to: perceptionDir.appendingPathComponent("sheet-index.json"))
    print("\(chosen.count) labels on \((chosen.count + perSheet - 1) / perSheet) sheets in \(perceptionDir.path) (\(marks.count) marks, \(rest.count) none)")
    return 0
}

/// `--audit FILE`: the auditor's pass over the last sheets. FILE lists "id kind" for each label the auditor found
/// wrong; every other label on the sheets is confirmed as the teacher gave it. A later pass over a label wins.
func audit(_ path: String) throws -> Int32 {
    let shown = try JSONDecoder().decode([MarkLabel].self, from: Data(contentsOf: perceptionDir.appendingPathComponent("sheet-index.json")))
    var corrections: [Int: String] = [:]
    for line in try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n") {
        let f = line.split(separator: " ").map(String.init)
        guard f.count == 2, let id = Int(f[0]), shown.indices.contains(id), ["exclamation", "question", "none"].contains(f[1]) else {
            fputs("HOLD: bad audit line \"\(line)\"\n", stderr)
            return 2
        }
        corrections[id] = f[1]
    }
    try appendRows(audited(shown, corrections: corrections), to: auditFile)
    print("audited \(shown.count) labels: \(corrections.count) corrected, \(shown.count - corrections.count) confirmed")
    return 0
}

/// The rule reader against the labels, split by run into train and held out: every frame proposed whose
/// candidates the teacher has all labelled, those with none included (a mark read there is a false one). An
/// audited label replaces the teacher's.
func baseline() -> Int32 {
    let audit = rows(auditFile, MarkLabel.self)
    let current = Set(rows(candidatesFile, CandidateRow.self).map { "\($0.frame)|\($0.box)" })
    let taught = rows(labelsFile, MarkLabel.self).filter { $0.teacher == MarkLabels.teacher && current.contains("\($0.frame)|\($0.box)") }
    let all = merged(teacher: taught, audit: audit)
    // The teacher against the auditor, candidate by candidate: how good a first filter it is.
    let isMark = { (k: String) in k == "exclamation" || k == "question" }
    var teacher = MarkScore()
    for (t, a) in zip(taught, all) where a.teacher == "audit" {
        switch (isMark(t.kind), isMark(a.kind)) {
        case (true, true): teacher.hits += 1
        case (true, false): teacher.falseMarks += 1
        case (false, true): teacher.missed += 1
        default: break
        }
    }
    let marks = Dictionary(grouping: all.filter { ["exclamation", "question"].contains($0.kind) }, by: \.frame)  // refused is no mark
    let labelled = Dictionary(grouping: all, by: \.frame).mapValues(\.count)
    var train = MarkScore(), held = MarkScore(), framesRead = 0, errors: [String] = []
    for frame in rows(framesFile, FrameRow.self).filter({ (labelled[$0.frame] ?? 0) >= $0.candidates }).map(\.frame) {
        guard let image = loadImage(runsRoot.appendingPathComponent(frame)) else { continue }
        let found = questMarks(pixels(image), box: MarkLabels.world).map { (x: $0.x, y: $0.y) }
        let s = score(found: found, labels: (marks[frame] ?? []).map(\.box))
        // The frames to look at again: a false mark may be a real one no candidate caught.
        if s.falseMarks + s.missed > 0 { errors.append("\(frame) found \(found.map { "\(Int($0.x)),\(Int($0.y))" }) labels \((marks[frame] ?? []).map(\.box))") }
        if heldOut(run: String(frame.split(separator: "/").first ?? "")) { held = held + s } else { train = train + s }
        framesRead += 1
    }
    func show(_ s: MarkScore) -> String {
        "hits \(s.hits), false \(s.falseMarks), missed \(s.missed), precision \(s.precision.map { String(format: "%.2f", $0) } ?? "-"), "
            + "recall \(s.recall.map { String(format: "%.2f", $0) } ?? "-")"
    }
    print("teacher (\(MarkLabels.teacher)) against the audit, per candidate: " + show(teacher))
    print("rule reader (questMarks) against \(all.filter { $0.teacher == "audit" }.count) audited labels of \(all.count), on \(framesRead) frames")
    print("  train:    " + show(train))
    print("  held out: " + show(held))
    try? (errors.joined(separator: "\n") + "\n").write(to: perceptionDir.appendingPathComponent("baseline-errors.txt"), atomically: true, encoding: .utf8)
    return 0
}

@main
struct PerceiveTool {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            switch (args.first, args.count) {
            case ("--propose", 1): exit(try propose())
            case ("--sheet", 2):
                guard let n = Int(args[1]), (1...600).contains(n) else { break }
                exit(try sheet(limit: n))
            case ("--baseline", 1): exit(baseline())
            case ("--audit", 2): exit(try audit(args[1]))
            case ("--sheet-held", 2):
                guard let n = Int(args[1]), (1...600).contains(n) else { break }
                exit(try sheet(limit: n, heldOnly: true))
            default: break
            }
        } catch {
            fputs("HOLD: \(error)\n", stderr)
            exit(2)
        }
        fputs("HOLD: usage: m5-perceive --propose | --sheet N | --sheet-held N (1-600) | --audit FILE | --baseline\n", stderr)
        exit(64)
    }
}
