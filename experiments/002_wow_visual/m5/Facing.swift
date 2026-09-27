// M5, the facing: the minimap arrow's bearing, learnt rather than decoded (the owner, 26-27 Sept: the engine sees through
// learned models, not pixel rules). The walk's rule (arrowFacing) reads the arrow well in the open: on 33 frames where
// the character's own motion over 1.5-4 s gave the bearing, it was within 25 degrees on 32 (median 3). It fails beside
// the minimap's icons: live run 52 (27 Sept) stood by the Elemental Convergence, its bearings jumped 19, 129, 350, 147
// and then none, and the walk ended WALK_HUD_UNREADABLE. So the rule's steady readings teach a classifier, and every
// labelled crop is also turned to other bearings (turnedCrop), so the classifier learns the arrow at every bearing on
// many backgrounds. The rows, crops and model stay under runs/002_wow_visual/perception (private).
import Foundation
import CoreGraphics
import ImageIO
import CreateML

let facingRowsFile = perceptionDir.appendingPathComponent("facing-rows.jsonl")

struct FacingRow: Codable { var frame: String; var facing: Double }

/// `--facing-labels`: every saved walk and hunt frame whose rule bearing the next look (within 0.6 s, the same walk or
/// hunt) repeats within 8 degrees: a steady reading, not one of the rule's jumps. Written anew each time.
func facingLabels() throws -> Int32 {
    let fm = FileManager.default
    var out: [FacingRow] = []
    for run in try fm.contentsOfDirectory(atPath: runsRoot.path).filter({ $0.hasPrefix("m4_") }).sorted() {
        let dir = runsRoot.appendingPathComponent(run)
        guard let text = try? String(contentsOf: dir.appendingPathComponent("events.jsonl"), encoding: .utf8) else { continue }
        let looks = text.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard let row = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], row["event"] as? String == "look",
                  row["frame"] is Int else { return nil }
            return row
        }
        let entries = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        // A walk's looks carry no tracker, a hunt's do; each walk or hunt numbers its frames 0, 1, 2 ... in its own folder
        // (walk1, hunt1, ...). A quest read's position looks (their own count, frames in the run's folder) fall between
        // them, so a folder's looks are a chain that starts at 0 and goes up by one. A run whose chains do not match its
        // folders one for one (their number, and each chain's last frame against its folder's last file) is left out.
        let kinds: [(kind: String, prefix: String, hunt: Bool)] = [("walk", "f", false), ("hunt", "h", true)]
        for (kind, prefix, hunt) in kinds {
            func number(_ name: String) -> Int? { name.hasPrefix(kind) ? Int(name.dropFirst(kind.count)) : nil }
            let folders = entries.filter { number($0) != nil }.sorted { number($0)! < number($1)! }
            let mine = looks.filter { ($0["tracker"] != nil) == hunt }
            let chains = lookChains(mine.map { $0["frame"] as! Int })
            guard chains.count == folders.count else { continue }
            let fitting = zip(chains, folders).allSatisfy { chain, folder in
                let files = ((try? fm.contentsOfDirectory(atPath: dir.appendingPathComponent(folder).path)) ?? [])
                    .compactMap { $0.hasPrefix(prefix) && $0.hasSuffix(".jpg") ? Int($0.dropFirst(prefix.count).dropLast(4)) : nil }
                return files.max().map { $0 <= chain.count - 1 && $0 >= chain.count - 2 } ?? false
            }
            guard fitting else { continue }
            func value(_ row: [String: Any], _ key: String) -> Double? { (row[key] as? NSNumber)?.doubleValue }
            for (chain, folder) in zip(chains, folders) {
                for (i, j) in zip(chain, chain.dropFirst()) {
                    let a = mine[i], b = mine[j]
                    // The rule's own reading: a look since #63 logs it apart from the fused facing it acted on.
                    func rule(_ row: [String: Any]) -> Double? { row.keys.contains("facing_rule") ? value(row, "facing_rule") : value(row, "facing") }
                    guard let fa = rule(a), let fb = rule(b), let ta = value(a, "t"), let tb = value(b, "t"),
                          tb - ta <= 0.6, abs(angleError(fa, fb)) <= 8 else { continue }
                    let path = "\(run)/\(folder)/\(prefix)\(String(format: "%03d", a["frame"] as! Int)).jpg"
                    if fm.fileExists(atPath: runsRoot.appendingPathComponent(path).path) { out.append(FacingRow(frame: path, facing: fa)) }
                }
            }
        }
    }
    try? fm.removeItem(at: facingRowsFile)
    try fm.createDirectory(at: perceptionDir, withIntermediateDirectories: true)
    try appendRows(out, to: facingRowsFile)
    let split = Dictionary(grouping: out) { runSplit(run(of: $0.frame)) }.mapValues(\.count)
    print("\(out.count) steady frames: " + Split.allCases.map { "\($0.rawValue) \(split[$0] ?? 0)" }.joined(separator: ", "))
    return 0
}

/// `--facing-train [final]`: a Create ML classifier of the arrow's crop into bearings every 10 degrees, on the training
/// runs' rows, each crop also turned by 60, 120 ... 300 degrees and half of them with quest-icon dots beside the arrow;
/// validated on the validation runs as they are (no turn, no dots).
/// `final`: training and validation runs together. The test runs are never learnt from. Written to models/facing.mlmodel.
func facingTrain(final: Bool = false) throws -> Int32 {
    let crops = perceptionDir.appendingPathComponent("crops-facing")
    try? FileManager.default.removeItem(at: crops)
    var count: [String: Int] = [:]
    for r in rows(facingRowsFile, FacingRow.self) where runSplit(run(of: r.frame)) != .test {
        guard let image = loadImage(runsRoot.appendingPathComponent(r.frame)) else { throw TrainError(description: "cannot read \(r.frame)") }
        let split = final ? "train" : runSplit(run(of: r.frame)).rawValue
        for turn in split == "train" ? stride(from: 0.0, to: 360, by: 60).map { $0 } : [0] {
            // Half the training crops get one or two quest-icon dots within 10 px of the centre (seeded by the name).
            var seed: UInt64 = 0xcbf29ce484222325
            for byte in "\(r.frame)\(turn)".utf8 { seed = (seed ^ UInt64(byte)) &* 0x100000001b3 }
            func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
            let dots = split == "train" && next() < 0.5
                ? (0..<(next() < 0.7 ? 1 : 2)).map { _ in (x: next() * 20 - 10, y: next() * 20 - 10, r: 2 + next() * 2.5) } : []
            guard let crop = turnedCrop(image, degrees: turn, dots: dots) else { continue }
            let label = FacingCrop.label(r.facing + turn)
            let name = r.frame.replacingOccurrences(of: "/", with: "_") + "_\(Int(turn)).png"
            try save(crop, (0, 0, crop.width, crop.height), to: crops.appendingPathComponent("\(split)/\(label)/\(name)"))
            count[split, default: 0] += 1
        }
    }
    print("crops: " + count.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    try FileManager.default.createDirectory(at: MarkReader.models, withIntermediateDirectories: true)
    let p = MLImageClassifier.ModelParameters(
        validation: final ? .none : .dataSource(.labeledDirectories(at: crops.appendingPathComponent("validation"))), maxIterations: 200, augmentation: [],
        algorithm: .transferLearning(featureExtractor: .scenePrint(revision: 2), classifier: .logisticRegressor))
    let model = try MLImageClassifier(trainingData: .labeledDirectories(at: crops.appendingPathComponent("train")), parameters: p)
    try model.write(to: MarkReader.models.appendingPathComponent("facing.mlmodel"))
    print("facing: training accuracy \(String(format: "%.3f", 1 - model.trainingMetrics.classificationError))"
          + (final ? " (training and validation runs)" : ", validation accuracy \(String(format: "%.3f", 1 - model.validationMetrics.classificationError))"))
    return 0
}

/// `--facing-baseline`: every row, split by run: the reader's bearing against the rule's steady one, within 15 degrees,
/// with the ms a frame takes.
func facingBaseline() throws -> Int32 {
    let reader = try FacingReader()
    var within: [Split: Int] = [:], total: [Split: Int] = [:], ms: [Double] = []
    for r in rows(facingRowsFile, FacingRow.self) {
        guard let image = loadImage(runsRoot.appendingPathComponent(r.frame)) else { continue }
        let began = Date()
        let read = try reader.facing(image)
        ms.append(Date().timeIntervalSince(began) * 1000)
        let split = runSplit(run(of: r.frame))
        total[split, default: 0] += 1
        if let read, abs(angleError(read.bearing, r.facing)) <= 15 { within[split, default: 0] += 1 }
    }
    for split in Split.allCases { print("\(split.rawValue): within 15 degrees \(within[split] ?? 0) of \(total[split] ?? 0)") }
    if !ms.isEmpty { print("a frame: \(String(format: "%.1f", ms.sorted()[ms.count / 2])) ms median") }
    return 0
}

/// `--facing-read FRAME...`: each frame's bearing by the reader (and its confidence) and by the rule, for frames no row
/// labels, such as those where the rule failed.
func facingRead(_ frames: [String]) throws -> Int32 {
    let reader = try FacingReader()
    for f in frames {
        guard let image = loadImage(URL(fileURLWithPath: f)) else { print("\(f): unreadable"); continue }
        let read = try reader.facing(image), rule = arrowFacing(pixels(image))
        print("\(f): reader \(read.map { "\(Int($0.bearing)) (\(String(format: "%.2f", $0.confidence)))" } ?? "none"), rule \(rule.map { String(Int($0)) } ?? "none")")
    }
    return 0
}
