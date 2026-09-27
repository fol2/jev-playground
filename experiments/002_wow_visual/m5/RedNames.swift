// M5, red names: the walk's red-name rule (redNames, M4h) stops walks through the Juvenile Vuldren field (live runs 35,
// 44, 45, 27 Sept): a red-brown body, a glint or a far fleck reads as a red name, and far names are too small for OCR.
// So the rule's candidates are labelled by eye on contact sheets ("name", "text" or "none", RedRow), and a Create ML
// classifier learns them from a tight crop (redCrop). The walk drops only what it reads as "none" (RedNameReader,
// Reader.swift), and only a model that drops the false ones on held-out runs without dropping a real name is used.
// Frames, crops, labels and the model stay under runs/002_wow_visual/perception (private).
import Foundation
import ImageIO
import CoreGraphics
import CoreText
import CoreML
import CreateML
import UniformTypeIdentifiers
import Vision

let redCandidatesFile = perceptionDir.appendingPathComponent("red-candidates.jsonl")
let redFramesFile = perceptionDir.appendingPathComponent("red-frames.jsonl")
let redLabelsFile = perceptionDir.appendingPathComponent("red-labels.jsonl")
let redSheetIndex = perceptionDir.appendingPathComponent("red-sheet-index.json")

/// `--red-propose`: frame paths under runs/002_wow_visual on stdin; the rule's red names in each, appended. Resumable.
func redPropose() throws -> Int32 {
    try FileManager.default.createDirectory(at: perceptionDir, withIntermediateDirectories: true)
    let done = Set(rows(redFramesFile, FrameRow.self).map(\.frame))
    var frames = 0, total = 0
    while let line = readLine() {
        let path = line.hasPrefix("./") ? String(line.dropFirst(2)) : line
        guard !path.isEmpty, !done.contains(path), let image = loadImage(runsRoot.appendingPathComponent(path)),
              image.width == HUD.width, image.height == HUD.height else { continue }
        let found = redNames(pixels(image)).map { RedRow(frame: path, box: [$0.x0, $0.y0, $0.x1, $0.y1]) }
        try appendRows(found, to: redCandidatesFile)
        try appendRows([FrameRow(frame: path, candidates: found.count)], to: redFramesFile)
        frames += 1
        total += found.count
    }
    print("\(frames) frames read, \(total) red-name candidates")
    return 0
}

/// `--red-sheet N`: up to N candidates not yet labelled, 48 a sheet, each drawn from a context crop with its box outlined
/// and its id, for the auditor. With a model, they are grouped by what it reads (name, text, none), so a sheet is mostly
/// one label; the auditor still judges every crop. The ids index red-sheet-index.json.
func redSheet(limit: Int) throws -> Int32 {
    let labelled = Set(rows(redLabelsFile, RedRow.self).map { "\($0.frame)|\($0.box)" })
    var chosen = Array(rows(redCandidatesFile, RedRow.self).filter { !labelled.contains("\($0.frame)|\($0.box)") }.prefix(limit))
    let cellW = 200, cellH = 220, cols = 8, perSheet = 48
    var frames: [String: CGImage] = [:]
    if let reader = try? RedNameReader() {
        let order = ["name": 0, "text": 1, "none": 2]
        let read = chosen.map { c -> Int in
            if frames[c.frame] == nil { frames[c.frame] = loadImage(runsRoot.appendingPathComponent(c.frame)) }
            return frames[c.frame].flatMap { try? reader.read($0, box: c.box) }.flatMap { order[$0.label] } ?? 0
        }
        chosen = chosen.indices.sorted { (read[$0], $0) < (read[$1], $1) }.map { chosen[$0] }
    }
    for (s, start) in stride(from: 0, to: chosen.count, by: perSheet).enumerated() {
        let page = Array(chosen[start..<min(chosen.count, start + perSheet)])
        let rowsN = (page.count + cols - 1) / cols
        guard let ctx = CGContext(data: nil, width: cols * cellW, height: rowsN * cellH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cols * cellW, height: rowsN * cellH))
        for (i, c) in page.enumerated() {
            if frames[c.frame] == nil { frames[c.frame] = loadImage(runsRoot.appendingPathComponent(c.frame)) }
            guard let frame = frames[c.frame] else { continue }
            // the auditor sees more than the classifier: three widths a side, 96 px at least
            let view = min(max(96, 3 * (c.box[2] - c.box[0] + 1)), frame.width, frame.height), cx = (c.box[0] + c.box[2]) / 2, cy = (c.box[1] + c.box[3]) / 2
            let r = (x: max(0, min(frame.width - view, cx - view / 2)), y: max(0, min(frame.height - view, cy - view / 2)), w: view, h: view)
            guard let crop = frame.cropping(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h)) else { continue }
            let col = i % cols, row = i / cols, side = Double(cellW - 4), scale = side / Double(r.w)
            let top = Double(rowsN * cellH - row * cellH)  // CoreGraphics puts y = 0 at the bottom
            let origin = (x: Double(col * cellW + 2), y: top - 20 - side)
            ctx.draw(crop, in: CGRect(x: origin.x, y: origin.y, width: side, height: side))
            ctx.setStrokeColor(CGColor(red: 0, green: 1, blue: 1, alpha: 0.8))
            ctx.setLineWidth(1)
            ctx.stroke(CGRect(x: origin.x + Double(c.box[0] - r.x - 2) * scale, y: origin.y + side - Double(c.box[3] - r.y + 3) * scale,
                              width: Double(c.box[2] - c.box[0] + 5) * scale, height: Double(c.box[3] - c.box[1] + 5) * scale))
            let text = NSAttributedString(string: "\(start + i)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1)])
            ctx.textPosition = CGPoint(x: col * cellW + 4, y: Int(top) - 16)
            CTLineDraw(CTLineCreateWithAttributedString(text), ctx)
        }
        guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(
            perceptionDir.appendingPathComponent("red-sheet-\(s + 1).png") as CFURL, "public.png" as CFString, 1, nil) else { continue }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
    try JSONEncoder().encode(chosen).write(to: redSheetIndex)
    print("\(chosen.count) candidates on \((chosen.count + perSheet - 1) / perSheet) sheets in \(perceptionDir.path)")
    return 0
}

/// `--red-audit FILE`: the auditor's labels for the last sheets (redAuditLabels), appended to red-labels.jsonl.
func redAudit(_ path: String) throws -> Int32 {
    let shown = try JSONDecoder().decode([RedRow].self, from: Data(contentsOf: redSheetIndex))
    guard let labels = redAuditLabels(try String(contentsOfFile: path, encoding: .utf8), count: shown.count) else {
        fputs("HOLD: every id of the last sheets needs one label, name, text or none\n", stderr)
        return 2
    }
    try appendRows(shown.indices.map { i in var r = shown[i]; r.label = labels[i]; return r }, to: redLabelsFile)
    print("labelled \(shown.count): \(labels.values.filter { $0 == "name" }.count) names")
    return 0
}

/// `--red-train`: a Create ML classifier (name, text or none) on the labelled crops of the training runs, validated on
/// the validation runs, which choose between designs. `--red-train final`: the chosen design fitted on the training
/// and validation runs together. The test runs are never learnt from. Written to models/redname.mlmodel.
func redTrain(final: Bool = false) throws -> Int32 {
    let crops = perceptionDir.appendingPathComponent("crops-red")
    try? FileManager.default.removeItem(at: crops)
    var frames: [String: CGImage] = [:], count: [String: Int] = [:]
    for l in rows(redLabelsFile, RedRow.self) where runSplit(run(of: l.frame)) != .test {
        guard let label = l.label else { continue }
        if frames[l.frame] == nil { frames[l.frame] = loadImage(runsRoot.appendingPathComponent(l.frame)) }
        guard let image = frames[l.frame] else { throw TrainError(description: "cannot read \(l.frame)") }
        let split = final ? "train" : runSplit(run(of: l.frame)).rawValue
        let name = (l.frame + "_" + l.box.map(String.init).joined(separator: "-")).replacingOccurrences(of: "/", with: "_") + ".png"
        try save(image, redCrop(l.box, width: image.width, height: image.height), to: crops.appendingPathComponent("\(split)/\(label)/\(name)"))
        count["\(split) \(label)", default: 0] += 1
    }
    print("crops: " + count.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    try FileManager.default.createDirectory(at: MarkReader.models, withIntermediateDirectories: true)
    let p = MLImageClassifier.ModelParameters(
        validation: final ? .none : .dataSource(.labeledDirectories(at: crops.appendingPathComponent("validation"))), maxIterations: 100, augmentation: [],
        algorithm: .transferLearning(featureExtractor: .scenePrint(revision: 2), classifier: .logisticRegressor))
    let model = try MLImageClassifier(trainingData: .labeledDirectories(at: crops.appendingPathComponent("train")), parameters: p)
    try model.write(to: MarkReader.models.appendingPathComponent("redname.mlmodel"))
    print("redname: training accuracy \(String(format: "%.3f", 1 - model.trainingMetrics.classificationError))"
          + (final ? " (training and validation runs)" : ", validation accuracy \(String(format: "%.3f", 1 - model.validationMetrics.classificationError))"))
    return 0
}

/// `--red-baseline`: on the labelled candidates, split by run, the rule alone (every candidate a danger) against the
/// classifier (a candidate it reads as "none" at RedNameReader.drop or more is dropped, as the walk does). A real name
/// dropped is the cost that matters: the owner, survive first.
func redBaseline() throws -> Int32 {
    let reader = try RedNameReader()
    var frames: [String: CGImage] = [:], scores: [Split: RedScore] = [:], decided: [Split: [(frame: String, label: String, kept: Bool)]] = [:]
    for l in rows(redLabelsFile, RedRow.self) {
        guard let label = l.label else { continue }
        if frames[l.frame] == nil { frames[l.frame] = loadImage(runsRoot.appendingPathComponent(l.frame)) }
        guard let image = frames[l.frame] else { continue }
        let top = try reader.read(image, box: l.box), dropped = RedNameReader.drops(top)
        scores[runSplit(run(of: l.frame)), default: RedScore()].add(label: label, kept: !dropped)
        decided[runSplit(run(of: l.frame)), default: []].append((l.frame, label, !dropped))
        if label == "name" && dropped { print("name dropped: \(l.frame) \(l.box) none \(String(format: "%.2f", top?.confidence ?? 0))") }
    }
    for split in Split.allCases {
        let s = scores[split] ?? RedScore()
        print("\(split.rawValue): names kept \(s.namesKept), names dropped \(s.namesDropped); false kept \(s.falseKept), false dropped \(s.falseDropped)")
        let f = RedFrames(decided[split] ?? [])
        print("  frames with a name \(f.named), missed \(f.missed); frames without one \(f.clear), still stopping \(f.falseStops)")
    }
    return 0
}
