// M5, stage two: m5-perceive --train. The audited candidates of the training and validation runs, never the test runs,
// are cropped into class folders under runs/002_wow_visual/perception/crops. Two Create ML image classifiers are made
// from them and written to perception/models: `detect` (mark or none, from context crops) and `kind` (exclamation or
// question, from the marks' shape crops). There is no augmentation, so the same labels make the same models.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CreateML

struct TrainError: Error, CustomStringConvertible { let description: String }

func train() throws -> Int32 {
    let crops = perceptionDir.appendingPathComponent("crops")
    try? FileManager.default.removeItem(at: crops)
    let current = Set(rows(candidatesFile, CandidateRow.self).map { "\($0.frame)|\($0.box)" })
    let taught = rows(labelsFile, MarkLabel.self).filter { $0.teacher == MarkLabels.teacher && current.contains("\($0.frame)|\($0.box)") }
    var frames: [String: CGImage] = [:], count: [String: Int] = [:]
    for l in truth(teacher: taught, audit: rows(auditFile, MarkLabel.self)) where runSplit(run(of: l.frame)) != .test {
        if frames[l.frame] == nil { frames[l.frame] = loadImage(runsRoot.appendingPathComponent(l.frame)) }
        guard let image = frames[l.frame] else { throw TrainError(description: "cannot read \(l.frame)") }
        let split = runSplit(run(of: l.frame)).rawValue, isMark = l.kind == "exclamation" || l.kind == "question"
        let c = glyphCrops(l.box, width: image.width, height: image.height)
        let name = (l.frame + "_" + l.box.map(String.init).joined(separator: "-")).replacingOccurrences(of: "/", with: "_") + ".png"
        try save(image, c.context, to: crops.appendingPathComponent("detect/\(split)/\(isMark ? "mark" : "none")/\(name)"))
        if isMark { try save(image, c.shape, to: crops.appendingPathComponent("kind/\(split)/\(l.kind)/\(name)")) }
        count["\(split) \(isMark ? l.kind : "none")", default: 0] += 1
    }
    print("crops: " + count.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    try FileManager.default.createDirectory(at: MarkReader.models, withIntermediateDirectories: true)
    for task in ["detect", "kind"] {
        var p = MLImageClassifier.ModelParameters()
        p.validation = .dataSource(.labeledDirectories(at: crops.appendingPathComponent("\(task)/validation")))
        p.augmentationOptions = []
        p.maxIterations = 100
        let model = try MLImageClassifier(trainingData: .labeledDirectories(at: crops.appendingPathComponent("\(task)/train")), parameters: p)
        try model.write(to: MarkReader.models.appendingPathComponent("\(task).mlmodel"))
        print("\(task): training accuracy \(String(format: "%.3f", 1 - model.trainingMetrics.classificationError)), "
              + "validation accuracy \(String(format: "%.3f", 1 - model.validationMetrics.classificationError))")
    }
    return 0
}

func save(_ image: CGImage, _ r: (x: Int, y: Int, w: Int, h: Int), to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let crop = image.cropping(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h)),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TrainError(description: "cannot crop \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(dest, crop, nil)
    guard CGImageDestinationFinalize(dest) else { throw TrainError(description: "cannot write \(url.path)") }
}
