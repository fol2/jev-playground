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
    static func classify(_ model: VNCoreMLModel, _ image: CGImage) throws -> (label: String, confidence: Double)? {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results as? [VNClassificationObservation])?.first.map { ($0.identifier, Double($0.confidence)) }
    }

    /// The quest marks of a frame: every candidate the detector calls a mark, with the kind the shape says.
    func marks(_ image: CGImage, _ rgba: RGBA, limit: Int = 40) throws -> [LearnedMark] {
        try markCandidates(rgba, box: MarkLabels.world(height: rgba.height)).prefix(limit).compactMap { g in
            try mark(image, box: [g.x0, g.y0, g.x1 - g.x0 + 1, g.y1 - g.y0 + 1])
        }
    }

    /// One candidate glyph (x, y, width, height): a mark of its kind, or nil when the detector says none.
    func mark(_ image: CGImage, box: [Int]) throws -> LearnedMark? {
        let c = glyphCrops(box, width: image.width, height: image.height)
        guard let context = image.cropping(to: CGRect(x: c.context.x, y: c.context.y, width: c.context.w, height: c.context.h)),
              let seen = try Self.classify(detect, context), seen.label == "mark",
              let which = try glyphKind(image, box: box) else { return nil }
        return LearnedMark(box: box, kind: which.label, confidence: seen.confidence)
    }

    /// Which mark a glyph box is, from its shape crop: "exclamation" or "question". It names the kind of the rule reader's
    /// marks too, which have none (live run 31, 27 Sept: a hand-in clicked a giver's "!" beside it).
    func glyphKind(_ image: CGImage, box: [Int]) throws -> (label: String, confidence: Double)? {
        let c = glyphCrops(box, width: image.width, height: image.height).shape
        guard let shape = image.cropping(to: CGRect(x: c.x, y: c.y, width: c.w, height: c.h)) else { return nil }
        return try Self.classify(kind, shape)
    }
}

/// The red-name classifier (m5-perceive --red-train, RedNames.swift): what a red-name candidate of the walk's rule
/// (redNames) is, from its crop (redCrop): "name" (a hostile creature's), "text" (other red text, such as the UI's
/// error line) or "none" (a body, a ring, terrain). The walk drops only what redDrops allows.
struct RedNameReader {
    let model: VNCoreMLModel

    init(models dir: URL = MarkReader.models) throws {
        model = try VNCoreMLModel(for: MLModel(contentsOf: MLModel.compileModel(at: dir.appendingPathComponent("redname.mlmodel"))))
    }

    /// The top class and its confidence for one candidate box (x0, y0, x1, y1); nil off the frame.
    func read(_ image: CGImage, box: [Int]) throws -> (label: String, confidence: Double)? {
        let r = redCrop(box, width: image.width, height: image.height)
        guard let crop = image.cropping(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h)) else { return nil }
        return try MarkReader.classify(model, crop)
    }
}
