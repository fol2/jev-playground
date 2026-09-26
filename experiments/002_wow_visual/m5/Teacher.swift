// M5 teacher: Apple's on-device model labels each candidate quest mark that m5-perceive --propose listed.
// A binary of its own: it needs Swift 6.4 and the macOS 27 SDK (the Xcode 27 toolchain), and FoundationModels'
// Observation module would clash with the runtime's Observation type. No provider call; no pixel leaves the Mac.
//   m5-teach        reads runs/002_wow_visual/perception/candidates.jsonl, appends marks.jsonl; resumable
import Foundation
import ImageIO
import CoreGraphics

/// The arguments, checked first, so a wrong call is refused (exit 64) with or without the model, and before any call.
func checkedArguments() -> [String] {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.isEmpty || (args.count == 2 && args[0] == "--eval") else {
        fputs("HOLD: usage: m5-teach [--eval SET]\n", stderr)
        exit(64)
    }
    return args
}

#if compiler(>=6.4) && canImport(FoundationModels)
import FoundationModels

let teacherVersion = "fm-marks-v2"  // MarkLabels.teacher: a cached verdict is reused only under it
let root = URL(fileURLWithPath: "runs/002_wow_visual")
let dir = root.appendingPathComponent("perception")

struct Candidate: Codable { var frame: String; var box: [Int]; var crop: [Int]; var hash: String }
struct Label: Codable { var frame: String; var box: [Int]; var kind: String; var teacher: String; var crop: String }

@Generable
enum MarkKind { case exclamation, question, none }

/// The description comes first: guided generation writes the fields in order, and a verdict written after a
/// look at the shape was right more often (26 Sept, 91 hand-checked crops: 8 of 60 false marks, against 13 with
/// the verdict alone; reference images made it worse, 35).
@Generable
struct MarkVerdict {
    @Guide(description: "At most eight words: the small yellow or orange shape near the top centre, its outline, and what is directly under it")
    var looks: String
    @Guide(description: "exclamation or question only for a quest mark floating over a character's green name; otherwise none")
    var kind: MarkKind
}

/// The crop scaled down, never up, so its longest side is at most `longest` pixels.
func fitted(_ image: CGImage, longest: Int) -> CGImage {
    let scale = Double(longest) / Double(max(image.width, image.height))
    guard scale < 1, let ctx = CGContext(data: nil, width: Int(Double(image.width) * scale), height: Int(Double(image.height) * scale),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    return ctx.makeImage() ?? image
}

/// One crop, one fresh session: a session's context is 8k tokens, and no crop should see another's verdict.
@available(macOS 27, *)
func teach(_ crop: CGImage) async throws -> String {
    let crop = fitted(crop, longest: 400)  // a crop past about 400 px overflowed the 8k context (26 Sept)
    let session = LanguageModelSession(instructions: "You label crops of World of Warcraft screenshots.")
    let reply = try await session.respond(generating: MarkVerdict.self, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 60)) {  // the same crop, the same verdict; a greedy loop is cut short
        "Near the top centre of this crop is a small yellow or orange shape. Is it a quest mark floating above a "
            + "character's head: an exclamation mark (!) or a question mark (?)? Answer none if it is anything else: "
            + "a flame, a lamp, a flower, grass, an insect, a spell effect, a number, text, a nameplate, or part of the interface."
        Attachment(crop)
    }
    return "\(reply.content.kind)"
}

/// `--eval SET`: the teacher on a hand-checked set, lines of "frame x y w h truth" (truth: exclamation, question or
/// none), frames under runs/002_wow_visual. Prints what it found and what it missed, to compare prompts.
@available(macOS 27, *)
func evaluate(_ path: String) async -> Int32 {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fputs("HOLD: cannot read \(path)\n", stderr); return 2 }
    var found = 0, marks = 0, falseMarks = 0, blanks = 0, wrongKind = 0, refused = 0
    let began = Date()
    for line in text.split(separator: "\n") {
        let f = line.split(separator: " ").map(String.init)
        guard f.count == 6, let x = Int(f[1]), let y = Int(f[2]), let w = Int(f[3]), let h = Int(f[4]),
              let image = CGImageSourceCreateWithURL(root.appendingPathComponent(f[0]) as CFURL, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }),
              let crop = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else { continue }
        // A refusal is no mark, as in the labelling run; it is counted apart.
        guard let got = try? await teach(crop) else { refused += 1; if f[5] != "none" { marks += 1 } else { blanks += 1 }; continue }
        if f[5] == "none" { blanks += 1; if got != "none" { falseMarks += 1 } } else {
            marks += 1
            if got != "none" { found += 1; if got != f[5] { wrongKind += 1 } }
        }
    }
    print("\(teacherVersion): marks found \(found)/\(marks) (wrong kind \(wrongKind)), false marks \(falseMarks)/\(blanks), refused \(refused), \(Int(Date().timeIntervalSince(began))) s")
    return 0
}

func rows<T: Decodable>(_ url: URL, _ type: T.Type) -> [T] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
}

@main
struct Teacher {
    static func main() async {
        let args = checkedArguments()
        guard #available(macOS 27, *), case .available = SystemLanguageModel.default.availability else {
            fputs("HOLD: the on-device model is not available here\n", stderr)
            exit(2)
        }
        if args.count == 2 { exit(await evaluate(args[1])) }
        let out = dir.appendingPathComponent("marks.jsonl")
        if !FileManager.default.fileExists(atPath: out.path) { FileManager.default.createFile(atPath: out.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: out) else { fputs("HOLD: cannot write \(out.path)\n", stderr); exit(2) }
        _ = try? handle.seekToEnd()
        var known = Dictionary(rows(out, Label.self).filter { $0.teacher == teacherVersion }.map { ($0.crop, $0.kind) }) { a, _ in a }
        let labelled = Set(rows(out, Label.self).filter { $0.teacher == teacherVersion }.map { "\($0.frame)|\($0.box)" })
        var frames: (path: String, image: CGImage?) = ("", nil)
        var asked = 0, written = 0
        let began = Date()
        for c in rows(dir.appendingPathComponent("candidates.jsonl"), Candidate.self) where !labelled.contains("\(c.frame)|\(c.box)") {
            let kind: String
            if let k = known[c.hash] {
                kind = k
            } else {
                if frames.path != c.frame {
                    frames = (c.frame, CGImageSourceCreateWithURL(root.appendingPathComponent(c.frame) as CFURL, nil)
                        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
                }
                guard let crop = frames.image?.cropping(to: CGRect(x: c.crop[0], y: c.crop[1], width: c.crop[2], height: c.crop[3])) else { continue }
                // The model's guardrails refuse some game crops (6 % on 26 Sept): kept as "refused", for the auditor.
                do { kind = try await teach(crop) } catch { fputs("refused \(c.frame) \(c.box): \(error)\n", stderr); kind = "refused" }
                known[c.hash] = kind
                asked += 1
            }
            guard var line = try? JSONEncoder().encode(Label(frame: c.frame, box: c.box, kind: kind, teacher: teacherVersion, crop: c.hash)) else { continue }
            line.append(0x0A)
            try? handle.write(contentsOf: line)
            written += 1
            if asked > 0 && asked % 100 == 0 { fputs("\(asked) teacher calls, \(Int(Date().timeIntervalSince(began))) s\n", stderr) }
        }
        try? handle.close()
        print("\(written) labels written; \(asked) teacher calls; \(Int(Date().timeIntervalSince(began))) s")
    }
}
#else
@main
struct Teacher {
    static func main() {
        _ = checkedArguments()
        fputs("HOLD: the teacher needs Swift 6.4 and the macOS 27 SDK (the Xcode 27 toolchain)\n", stderr)
        exit(2)
    }
}
#endif
