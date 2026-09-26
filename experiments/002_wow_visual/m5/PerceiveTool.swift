// M5 tool, run from the repository root. Frames, crops and labels stay under runs/002_wow_visual (private
// captures); the teacher that labels the candidates is its own binary (Teacher.swift).
//   m5-perceive --propose       frame paths under runs/002_wow_visual on stdin; candidates appended, resumable
//   m5-perceive --prelabel      the learned reader labels the candidates no labeller has (reader-v1); a mark only the
//                               rules see is "disputed", for the auditor
//   m5-perceive --sheet N       contact sheets of up to N labels not yet audited, 48 a sheet, for audit
//   m5-perceive --sheet-held N  the same, of held-out runs only; repeat until none is left: the test set is audited in full
//   m5-perceive --sheet-frames N  whole frames, every candidate not yet audited, in a fixed random order: frames to score
//   m5-perceive --audit FILE    the auditor's corrections to the last sheets ("id kind" lines); the rest confirmed
//   m5-perceive --train         two Create ML classifiers from the audited labels of the training runs (Train.swift)
//   m5-perceive --baseline      the teacher, the rule reader (questMarks) and the learned reader against the audited
//                               labels, by split; wrong frames to baseline-errors.txt
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
              image.width == HUD.width, [HUD.height, 1080, 1440].contains(image.height) else { continue }  // the game, a 21:9 or a 16:9 video
        let rgba = pixels(image)
        let found = Array(markCandidates(rgba, box: MarkLabels.world(height: rgba.height)).prefix(maxCandidates)).compactMap { g -> CandidateRow? in
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
func sheet(limit: Int, heldOnly: Bool = false, wholeFrames: Bool = false) throws -> Int32 {
    let done = Set(rows(auditFile, MarkLabel.self).map { "\($0.frame)|\($0.box)" })
    let current = Set(rows(candidatesFile, CandidateRow.self).map { "\($0.frame)|\($0.box)" })
    let all = rows(labelsFile, MarkLabel.self).filter { MarkLabels.teachers.contains($0.teacher) && current.contains("\($0.frame)|\($0.box)") }
        .filter { !done.contains("\($0.frame)|\($0.box)") && (!heldOnly || heldOut(run: String($0.frame.split(separator: "/").first ?? ""))) }
    let marks = all.filter { $0.kind != "none" }, rest = all.filter { $0.kind == "none" }
    let step = max(1, rest.count / max(1, limit - marks.count))
    let chosen = wholeFrames ? framesDrawn(all, limit: limit)
        : Array((marks + stride(from: 0, to: rest.count, by: step).map { rest[$0] }).prefix(limit))
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
    // A "refused" or "disputed" first label is no verdict: the auditor must settle each one, or nothing is recorded.
    let unsettled = unsettledLabels(shown, corrections: corrections)
    guard unsettled.isEmpty else {
        fputs("HOLD: labels \(unsettled.map(String.init).joined(separator: ", ")) need a verdict (exclamation, question or none)\n", stderr)
        return 2
    }
    try appendRows(audited(shown, corrections: corrections), to: auditFile)
    print("audited \(shown.count) labels: \(corrections.count) corrected, \(shown.count - corrections.count) confirmed")
    return 0
}

/// The teacher, candidate by candidate, and the rule reader, frame by frame, against the audited labels, split by run
/// into train and held out. Only a frame whose candidates are all audited is scored, those with no mark included
/// (a mark read there is a false one). A teacher's label no auditor has checked is never a truth.
func baseline() throws -> Int32 {
    let audit = rows(auditFile, MarkLabel.self)
    let current = Set(rows(candidatesFile, CandidateRow.self).map { "\($0.frame)|\($0.box)" })
    let taught = rows(labelsFile, MarkLabel.self).filter { MarkLabels.teachers.contains($0.teacher) && current.contains("\($0.frame)|\($0.box)") }
    let checked = truth(teacher: taught, audit: audit)
    let marks = Dictionary(grouping: checked.filter { ["exclamation", "question"].contains($0.kind) }, by: \.frame)
    let audited = Dictionary(grouping: checked, by: \.frame).mapValues(\.count)
    // The learned reader, when --train has made its models; each split scored apart, the test runs never trained on.
    // Frames of the live game and of videos are scored apart too: the game is what the reader must read.
    let reader = try? MarkReader()
    var rules: [String: MarkScore] = [:], learned: [String: MarkScore] = [:], framesRead = 0, errors: [String] = []
    for frame in rows(framesFile, FrameRow.self).filter({ (audited[$0.frame] ?? 0) >= $0.candidates }).map(\.frame) {
        guard let image = loadImage(runsRoot.appendingPathComponent(frame)) else { continue }
        let rgba = pixels(image), labels = marks[frame] ?? []
        let key = "\(frame.hasPrefix("yt_") ? "video" : "game") \(runSplit(run(of: frame)).rawValue)"
        let found = questMarks(rgba, box: MarkLabels.world(height: rgba.height)).map { (x: $0.x, y: $0.y) }
        let s = score(found: found, labels: labels.map(\.box))
        rules[key] = (rules[key] ?? MarkScore()) + s
        // The frames to look at again: a false mark may be a real one no candidate caught.
        if s.falseMarks + s.missed > 0 { errors.append("rules \(frame) found \(found.map { "\(Int($0.x)),\(Int($0.y))" }) labels \(labels.map(\.box))") }
        if let reader {  // a frame the reader cannot read stops the score (HOLD), never drops out of it
            let read = try reader.marks(image, rgba)
            let l = score(found: read.map { (x: $0.x, y: $0.y) }, labels: labels.map(\.box), foundKinds: read.map(\.kind), labelKinds: labels.map(\.kind))
            learned[key] = (learned[key] ?? MarkScore()) + l
            if l.falseMarks + l.missed + l.wrongKind > 0 { errors.append("learned \(frame) found \(read.map { "\($0.kind) \($0.box)" }) labels \(labels.map { "\($0.kind) \($0.box)" })") }
        }
        framesRead += 1
    }
    func show(_ s: MarkScore?) -> String {
        guard let s else { return "no frames" }
        return "hits \(s.hits), false \(s.falseMarks), missed \(s.missed), precision \(s.precision.map { String(format: "%.2f", $0) } ?? "-"), "
            + "recall \(s.recall.map { String(format: "%.2f", $0) } ?? "-")"
    }
    for name in [MarkLabels.teacher, MarkLabels.reader] {
        let s = teacherScore(teacher: taught.filter { $0.teacher == name }, audit: audit)
        print("first labeller \(name) against the audit, per candidate: " + show(s) + ", wrong kind \(s.wrongKind)")
    }
    print("on \(framesRead) fully audited frames (\(checked.count) of \(taught.count) candidates audited):")
    for key in Set(rules.keys).sorted() {
        print("  rule reader (questMarks), \(key): " + show(rules[key]))
        if reader != nil { print("  learned reader, \(key): " + show(learned[key]) + ", wrong kind \(learned[key]?.wrongKind ?? 0)") }
    }
    if reader == nil { print("  learned reader: no models (m5-perceive --train makes them)") }
    try? (errors.joined(separator: "\n") + "\n").write(to: perceptionDir.appendingPathComponent("baseline-errors.txt"), atomically: true, encoding: .utf8)
    return 0
}

/// `--prelabel`: the learned reader labels each current candidate no labeller has labelled yet (reader-v1), so the audit
/// sheets show its guess, marks first. Where the rule reader reads a mark on a candidate the learned reader calls none,
/// the label is "disputed", shown with the marks, and the auditor must settle it. A frame the reader cannot read stops
/// the run (HOLD); labels written before it are kept, and a rerun resumes.
func prelabel() throws -> Int32 {
    let reader = try MarkReader()
    let labelled = Set(rows(labelsFile, MarkLabel.self).filter { MarkLabels.teachers.contains($0.teacher) }.map { "\($0.frame)|\($0.box)" })
    let todo = Dictionary(grouping: rows(candidatesFile, CandidateRow.self).filter { !labelled.contains("\($0.frame)|\($0.box)") }, by: \.frame)
    var counts: [String: Int] = [:]
    for (frame, candidates) in todo.sorted(by: { $0.key < $1.key }) {
        guard let image = loadImage(runsRoot.appendingPathComponent(frame)) else { throw TrainError(description: "cannot read \(frame)") }
        let rgba = pixels(image)
        let ruled = questMarks(rgba, box: MarkLabels.world(height: rgba.height)).map { (x: $0.x, y: $0.y) }
        let labels = try candidates.map { c -> MarkLabel in
            let kind = try reader.mark(image, box: c.box)?.kind ?? (score(found: ruled, labels: [c.box]).hits > 0 ? "disputed" : "none")
            counts[kind, default: 0] += 1
            return MarkLabel(frame: frame, box: c.box, kind: kind, teacher: MarkLabels.reader, crop: c.hash)
        }
        try appendRows(labels, to: labelsFile)
    }
    print("prelabelled \(todo.values.map(\.count).reduce(0, +)) candidates of \(todo.count) frames: "
          + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
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
            case ("--baseline", 1): exit(try baseline())
            case ("--train", 1): exit(try train())
            case ("--prelabel", 1): exit(try prelabel())
            case ("--audit", 2): exit(try audit(args[1]))
            case ("--sheet-frames", 2):
                guard let n = Int(args[1]), (1...600).contains(n) else { break }
                exit(try sheet(limit: n, wholeFrames: true))
            case ("--sheet-held", 2):
                guard let n = Int(args[1]), (1...600).contains(n) else { break }
                exit(try sheet(limit: n, heldOnly: true))
            default: break
            }
        } catch {
            fputs("HOLD: \(error)\n", stderr)
            exit(2)
        }
        fputs("HOLD: usage: m5-perceive --propose | --prelabel | --sheet N | --sheet-held N | --sheet-frames N (1-600) | --audit FILE | --train | --baseline\n", stderr)
        exit(64)
    }
}
