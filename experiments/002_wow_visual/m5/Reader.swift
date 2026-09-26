// M5, stage two: the learned mark reader. The candidate glyphs (markCandidates) are classified by two Create ML
// image classifiers that m5-perceive --train makes from audited labels: `detect` says from a context crop whether a
// candidate is a quest mark, `kind` says from a shape crop which mark. The models are made from private captures and
// stay under runs/002_wow_visual/perception/models. Core ML and Vision run on the Mac; no provider call.
import Foundation
import CoreGraphics
import CoreML
import Vision

struct LearnedMark {
    var box: [Int]  // x, y, width, height of the glyph
    var kind: String  // exclamation or question
    var confidence: Double  // the detector's, that it is a mark
    var x: Double { Double(box[0]) + Double(box[2] - 1) / 2 }
    var y: Double { Double(box[1]) + Double(box[3] - 1) / 2 }
}

struct MarkReader {
    static let models = URL(fileURLWithPath: "runs/002_wow_visual/perception/models")
    let detect: VNCoreMLModel, kind: VNCoreMLModel

    init(models dir: URL = MarkReader.models) throws {
        func load(_ name: String) throws -> VNCoreMLModel {
            try VNCoreMLModel(for: MLModel(contentsOf: MLModel.compileModel(at: dir.appendingPathComponent("\(name).mlmodel"))))
        }
        detect = try load("detect")
        kind = try load("kind")
    }

    /// The top class and its confidence. The crops are square, so filling the model's square input keeps their shape.
    func classify(_ model: VNCoreMLModel, _ image: CGImage) throws -> (label: String, confidence: Double)? {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results as? [VNClassificationObservation])?.first.map { ($0.identifier, Double($0.confidence)) }
    }

    /// The quest marks of a frame: every candidate the detector calls a mark, with the kind the shape says.
    func marks(_ image: CGImage, _ rgba: RGBA, limit: Int = 40) throws -> [LearnedMark] {
        try markCandidates(rgba).prefix(limit).compactMap { g in
            let box = [g.x0, g.y0, g.x1 - g.x0 + 1, g.y1 - g.y0 + 1]
            let c = glyphCrops(box, width: image.width, height: image.height)
            guard let context = image.cropping(to: CGRect(x: c.context.x, y: c.context.y, width: c.context.w, height: c.context.h)),
                  let seen = try classify(detect, context), seen.label == "mark",
                  let shape = image.cropping(to: CGRect(x: c.shape.x, y: c.shape.y, width: c.shape.w, height: c.shape.h)),
                  let which = try classify(kind, shape) else { return nil }
            return LearnedMark(box: box, kind: which.label, confidence: seen.confidence)
        }
    }
}
