// M5, objects on the ground: a quest may ask the player to pick up objects (Harvesting Windstones, 27 Sept: pale cyan
// crystals). The owner's line (26 and 27 Sept): the engine sees world objects through a learned model, not a pixel rule.
// So a Create ML object detector learns "object" from boxes audited by eye on saved frames, in tiles (ObjectTiles: a
// far crystal would shrink to 2 px in a whole frame), and is scored on held-out runs. A colour hint proposes boxes for the
// auditor only (objectHints); the engine's eye is ObjectReader (Reader.swift). Frames, tiles, labels and the model stay
// under runs/002_wow_visual/perception (private).
import Foundation
import CoreGraphics
import ImageIO
import CreateML

let objCandidatesFile = perceptionDir.appendingPathComponent("obj-candidates.jsonl")
let objFramesFile = perceptionDir.appendingPathComponent("obj-frames.jsonl")
let objLabelsFile = perceptionDir.appendingPathComponent("obj-labels.jsonl")
let objSheetIndex = perceptionDir.appendingPathComponent("obj-sheet-index.json")

/// The labelling aid, never the engine's eye: pale cyan blobs (the Windstone Clusters of live run 46) on the ground in
/// view, off the character's figure (its pale hair). It only chooses what the auditor looks at; an object it misses
/// stays unlabelled, so a detector's "false" object can be a real one it never proposed.
func objectHints(_ image: RGBA) -> [[Int]] {
    let s = Double(image.height) / 1320, w = ObjectTiles.world
    // Left out: the character's figure, the player frame's portrait (the same hair) and letters of a line of text (a
    // zone's name, "Thendal Village (Sanctuary)", is drawn pale blue): three or more blobs of a height on one baseline.
    let skip = [(1180, Int(560 * s), 1380, Int(830 * s)), (440, Int(950 * s), 940, Int(1050 * s))]
    let blobs = yellowBlobs(image, box: (w.0, Int(Double(w.1) * s), w.2, Int(Double(w.3) * s)), gap: 3,
                            colour: { r, g, b in r >= 110 && g >= 180 && b >= 190 && r <= 215 && g - r >= 30 })
        .filter { (15...2500).contains($0.n) }
        .filter { b in
            let cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2
            return !skip.contains { cx >= $0.0 && cx <= $0.2 && cy >= $0.1 && cy <= $0.3 }
        }
    func line(_ b: Blob) -> Bool {
        let h = b.y1 - b.y0 + 1
        return blobs.filter { o in abs(o.y1 - b.y1) <= 4 && abs((o.y1 - o.y0 + 1) - h) <= h / 2 && abs(o.x0 - b.x0) <= 6 * h }.count >= 3
    }
    return blobs.filter { !line($0) }.map { [$0.x0, $0.y0, $0.x1, $0.y1] }
}

/// `--obj-propose`: frame paths under runs/002_wow_visual on stdin (2560 wide); the hints in each, appended. Resumable.
func objPropose() throws -> Int32 {
    try FileManager.default.createDirectory(at: perceptionDir, withIntermediateDirectories: true)
    let done = Set(rows(objFramesFile, FrameRow.self).map(\.frame))
    var frames = 0, total = 0
    while let line = readLine() {
        let path = line.hasPrefix("./") ? String(line.dropFirst(2)) : line
        guard !path.isEmpty, !done.contains(path), let image = loadImage(runsRoot.appendingPathComponent(path)),
              image.width == HUD.width else { continue }
        let found = objectHints(pixels(image)).map { BoxRow(frame: path, box: $0) }
        try appendRows(found, to: objCandidatesFile)
        try appendRows([FrameRow(frame: path, candidates: found.count)], to: objFramesFile)
        frames += 1
        total += found.count
    }
    print("\(frames) frames read, \(total) object hints")
    return 0
}

/// `--obj-sheet N [RUN]`: up to N hints not yet labelled (of the runs whose names start with RUN), on contact sheets
/// (obj-sheet-1.png ...); ids index obj-sheet-index.json. Whole frames only, so a scored frame has every hint audited,
/// and one frame in four by a hash of its name: neighbouring frames are near copies.
func objSheet(limit: Int, run prefix: String = "") throws -> Int32 {
    let labelled = Set(rows(objLabelsFile, BoxRow.self).map { "\($0.frame)|\($0.box)" })
    func sampled(_ frame: String) -> Bool {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in frame.utf8 { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        return h % 4 == 0
    }
    var chosen: [BoxRow] = []
    let open = rows(objCandidatesFile, BoxRow.self)
        .filter { $0.frame.hasPrefix(prefix) && sampled($0.frame) && !labelled.contains("\($0.frame)|\($0.box)") }
    for (_, hints) in Dictionary(grouping: open, by: \.frame).sorted(by: { $0.key < $1.key }) where chosen.count + hints.count <= limit {
        chosen += hints
    }
    var frames: [String: CGImage] = [:]
    contactSheets(chosen, name: "obj", minView: 160, frames: &frames)
    try JSONEncoder().encode(chosen).write(to: objSheetIndex)
    print("\(chosen.count) hints on \((chosen.count + 47) / 48) sheets in \(perceptionDir.path)")
    return 0
}

/// `--obj-audit FILE`: the auditor's "yes" (a quest object on the ground) and "no" for the last sheets, appended.
func objAudit(_ path: String) throws -> Int32 {
    let shown = try JSONDecoder().decode([BoxRow].self, from: Data(contentsOf: objSheetIndex))
    guard let labels = redAuditLabels(try String(contentsOfFile: path, encoding: .utf8), count: shown.count, kinds: ["yes", "no"]) else {
        fputs("HOLD: every id of the last sheets needs one label, yes or no\n", stderr)
        return 2
    }
    try appendRows(shown.indices.map { i in var r = shown[i]; r.label = labels[i]; return r }, to: objLabelsFile)
    print("labelled \(shown.count): \(labels.values.filter { $0 == "yes" }.count) objects")
    return 0
}

/// `--obj-train [final]`: a Create ML object detector on tiles (ObjectTiles) of the training runs, one around each audited box
/// (a "no" box's tile is a hard negative), with every "yes" box whole inside the tile annotated "object". `final`: the
/// training and validation runs together. The test runs are never learnt from. Written to models/objects.mlmodel.
func objTrain(final: Bool = false) throws -> Int32 {
    let tiles = perceptionDir.appendingPathComponent("tiles-obj")
    try? FileManager.default.removeItem(at: tiles)
    var entries: [String: [[String: Any]]] = [:], count: [String: Int] = [:]
    let labelled = Dictionary(grouping: rows(objLabelsFile, BoxRow.self).filter { $0.label != nil }, by: \.frame)
    for (frame, boxes) in labelled.sorted(by: { $0.key < $1.key }) where runSplit(run(of: frame)) != .test {
        guard let image = loadImage(runsRoot.appendingPathComponent(frame)) else { throw TrainError(description: "cannot read \(frame)") }
        let split = final ? "train" : runSplit(run(of: frame)).rawValue
        var seed: UInt64 = 0xcbf29ce484222325
        for byte in frame.utf8 { seed = (seed ^ UInt64(byte)) &* 0x100000001b3 }
        for (i, b) in boxes.enumerated() {
            let t = ObjectTiles.around(b.box, seed: seed &+ UInt64(i), width: image.width, height: image.height)
            let side = ObjectTiles.side
            let inside = boxes.filter { $0.label == "yes" && $0.box[0] >= t.x && $0.box[1] >= t.y && $0.box[2] < t.x + side && $0.box[3] < t.y + side }
            let name = frame.replacingOccurrences(of: "/", with: "_") + "_\(i).jpg"
            try save(image, (t.x, t.y, side, side), to: tiles.appendingPathComponent("\(split)/\(name)"))
            entries[split, default: []].append(["image": name, "annotations": inside.map { o -> [String: Any] in
                ["label": "object", "coordinates": ["x": Double(o.box[0] + o.box[2]) / 2 - Double(t.x), "y": Double(o.box[1] + o.box[3]) / 2 - Double(t.y),
                                                    "width": Double(o.box[2] - o.box[0] + 1), "height": Double(o.box[3] - o.box[1] + 1)]]
            }])
            count["\(split) \(inside.isEmpty ? "empty" : "with objects")", default: 0] += 1
        }
    }
    for (split, list) in entries {
        // Tiles with objects first: Create ML fails ("tc_flex_SequenceType index out of bounds") when the file opens with an
        // empty tile (27 Sept).
        let has = { (e: [String: Any]) in !((e["annotations"] as? [Any])?.isEmpty ?? true) }
        try JSONSerialization.data(withJSONObject: list.filter(has) + list.filter { !has($0) })
            .write(to: tiles.appendingPathComponent("\(split)/annotations.json"))
    }
    print("tiles: " + count.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    try FileManager.default.createDirectory(at: MarkReader.models, withIntermediateDirectories: true)
    let p = MLObjectDetector.ModelParameters(
        validation: final || entries["validation"] == nil ? .none
            : .dataSource(.directoryWithImagesAndJsonAnnotation(at: tiles.appendingPathComponent("validation"))),
        batchSize: 16, maxIterations: 1000, algorithm: .transferLearning(.objectPrint(revision: 1)))
    let model = try MLObjectDetector(trainingData: .directoryWithImagesAndJsonAnnotation(at: tiles.appendingPathComponent("train")),
                                     parameters: p, annotationType: .boundingBox(units: .pixel, origin: .topLeft, anchor: .center))
    try model.write(to: MarkReader.models.appendingPathComponent("objects.mlmodel"))
    print("objects: trained on \(entries["train"]?.count ?? 0) tiles" + (final ? " (training and validation runs)" : ""))
    return 0
}

/// `--obj-baseline`: every audited frame, split by run: ObjectReader's objects against the audited boxes (ObjectScore),
/// with the ms a frame takes.
func objBaseline() throws -> Int32 {
    let reader = try ObjectReader()
    var scores: [Split: ObjectScore] = [:], near: [Split: ObjectScore] = [:], ms: [Double] = []
    for (frame, boxes) in Dictionary(grouping: rows(objLabelsFile, BoxRow.self).filter { $0.label != nil }, by: \.frame).sorted(by: { $0.key < $1.key }) {
        guard let image = loadImage(runsRoot.appendingPathComponent(frame)) else { continue }
        let began = Date()
        let found = try reader.objects(image)
        ms.append(Date().timeIntervalSince(began) * 1000)
        scores[runSplit(run(of: frame)), default: ObjectScore()].add(found: found.map(\.box), labelled: boxes)
        // near objects only: a "yes" box under 16 px high (far off) is left out of this score
        let nearBoxes = boxes.map { b -> BoxRow in var r = b; if r.label == "yes" && r.box[3] - r.box[1] + 1 < 16 { r.label = "small" }; return r }
        near[runSplit(run(of: frame)), default: ObjectScore()].add(found: found.map(\.box), labelled: nearBoxes)
    }
    for split in Split.allCases {
        let s = scores[split] ?? ObjectScore()
        print("\(split.rawValue): hits \(s.hits), missed \(s.missed), false \(s.falseFound)")
        let n = near[split] ?? ObjectScore()
        print("  16 px high or more: hits \(n.hits), missed \(n.missed), false \(n.falseFound)")
    }
    if !ms.isEmpty { print("a frame: \(Int(ms.sorted()[ms.count / 2])) ms median, \(Int(ms.max()!)) ms at most") }
    return 0
}
