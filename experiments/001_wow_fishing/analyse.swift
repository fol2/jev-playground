// Stream the pilot clip into small colour/motion measurements; optionally ask Jev four times.
// This fixed ROI is calibrated for the first pilot, not a general bobber tracker.
//
//   analyse VIDEO [--jev]   # FFmpeg decodes; --jev sends the four checkpoint states, no retries
//   analyse --self-test     # the provisional rules on synthetic rows; no video, no provider
//
// Built by build.sh with dotenv.swift and ../002_wow_visual/runtime/JSON.swift, whose ordered JSON writes
// the bytes the Python analyse.py wrote.
import CryptoKit
import Foundation

let analyseRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let analyseModel = "jev-1.13.0"
let checkpointTimes = [8.0, 12.0, 19.5, 20.0]
let pilotChoices = ["WAIT", "REEL", "ABSTAIN"]
let pilotQuestion = JSON.object([
    ("type", .string("choice")),
    ("instructions", .string("Choose a fishing response from the recent measured observations only. "
        + "A bite may produce an abrupt downward bobber movement and temporary disappearance. "
        + "A fixed colour mask is not a verified object tracker: lighting, cursor overlap and "
        + "occlusion can confound it. Do not invent splash or audio evidence. "
        + "Downward movement increases y_px. All changes use 0–255 RGB intensity units. "
        + "Do not treat ordinary gradual bobbing as a bite.")),
    ("criteria", .object([
        ("WAIT", .string("The target remains visible and its movement is consistent with ordinary waiting.")),
        ("REEL", .string("The recent sequence provides clear evidence of an abrupt bite-like movement at the target.")),
        ("ABSTAIN", .string("The target or evidence is absent, unreliable, conflicting or insufficient."))]))])

struct PilotRow {
    var t = 0.0
    var orange = 0
    var y: Double?
    var targetChange = 0.0
    var background = 0.0

    var json: JSON {
        .object([("t_s", .double(t)), ("orange_pixels", .int(orange)), ("y_px", y.map(JSON.double) ?? .null),
                 ("target_change", .double(targetChange)), ("background_change", .double(background))])
    }
}

func median(_ values: [Double]) -> Double {
    let s = values.sorted(), n = s.count
    return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}

/// The provisional rules: REEL on a local downward drop with the orange area halved against still water.
func pilotRules(_ history: [PilotRow]) -> String {
    guard history.count >= 6 else { return "ABSTAIN" }
    let current = history.last!, prior = history.dropLast()
    if prior.contains(where: { $0.orange < 100 }) { return "ABSTAIN" }
    let baselineY = median(prior.map { $0.y ?? .nan }), baselineArea = median(prior.map { Double($0.orange) })
    if let y = current.y, y - baselineY >= 6, Double(current.orange) < baselineArea * 0.5, current.background < 4 {
        return "REEL"
    }
    return current.orange >= 100 ? "WAIT" : "ABSTAIN"
}


struct AnalyseError: Error, CustomStringConvertible { let description: String }

func run(_ tool: String, _ args: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + args
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw AnalyseError(description: "\(tool) failed") }
    return data
}

func measurements(_ video: URL, _ each: (PilotRow) throws -> Void) throws {
    let probe = try JSON.parse(String(decoding: try run("ffprobe", [
        "-v", "error", "-read_intervals", "%+36", "-select_streams", "v:0", "-show_frames", "-show_streams",
        "-show_entries", "stream=width,height,time_base:frame=best_effort_timestamp_time", "-of", "json", video.path]), as: UTF8.self))
    let streams = probe["streams"]?.items ?? []
    guard streams.count == 1, streams[0]["width"] == .int(680), streams[0]["height"] == .int(440),
          let timeBase = streams[0]["time_base"]?.string else {
        throw AnalyseError(description: "The pilot ROI requires a 680 x 440 recording")
    }
    let times = try (probe["frames"]?.items ?? []).map { frame -> Double in
        guard let t = frame["best_effort_timestamp_time"]?.string.flatMap(Double.init) else {
            throw AnalyseError(description: "a frame without a timestamp")
        }
        return t
    }
    guard let first = times.first, times.last! - first <= 35 else {
        throw AnalyseError(description: "Use the short pilot clip (at most 35 seconds)")
    }
    let width = 180, size = 180 * 160 * 3
    let ffmpeg = Process()
    ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    ffmpeg.arguments = ["ffmpeg", "-v", "error", "-threads", "1", "-i", video.path, "-map", "0:v:0", "-vf", "crop=180:160:60:200",
                        "-fps_mode", "passthrough", "-enc_time_base", timeBase, "-pix_fmt", "rgb24", "-threads", "1",
                        "-f", "rawvideo", "pipe:1"]
    let pipe = Pipe()
    ffmpeg.standardOutput = pipe
    try ffmpeg.run()
    defer { if ffmpeg.isRunning { ffmpeg.terminate() } }
    var previous: [UInt8]?
    var nextSample = 0.0
    for timestamp in times {
        var frame = Data()
        while frame.count < size, let chunk = try pipe.fileHandleForReading.read(upToCount: size - frame.count), !chunk.isEmpty {
            frame.append(chunk)
        }
        guard frame.count == size else { throw AnalyseError(description: "Incomplete decoded frame") }
        let t = timestamp - first
        if t < nextSample { continue }
        nextSample = t + 0.1
        let pixels = [UInt8](frame)
        // Rows 45..<105 and columns 40..<115 of the crop hold the bobber; its top-right corner is open water.
        var count = 0, ySum = 0
        for row in 45..<105 {
            for col in 40..<115 {
                let i = (row * width + col) * 3
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                if r > 100 && r - g > 15 && g - b > 15 { count += 1; ySum += row - 45 }
            }
        }
        func change(_ rows: Range<Int>, _ cols: Range<Int>) -> Double {
            guard let previous else { return 0 }
            var sum = 0
            for row in rows { for col in cols { for c in 0..<3 {
                let i = (row * width + col) * 3 + c
                sum += abs(Int(pixels[i]) - Int(previous[i]))
            } } }
            return Double(sum) / Double(rows.count * cols.count * 3)
        }
        try each(PilotRow(t: JSON.round(t, 4), orange: count,
                          y: count > 0 ? JSON.round(Double(ySum) / Double(count) + 245, 2) : nil,
                          targetChange: JSON.round(change(45..<105, 40..<115), 3), background: JSON.round(change(0..<40, 120..<180), 3)))
        previous = pixels
    }
    _ = pipe.fileHandleForReading.readDataToEndOfFile()
    ffmpeg.waitUntilExit()
    guard ffmpeg.terminationStatus == 0 else { throw AnalyseError(description: "Video decoding failed") }
}

/// One request, no retry. A failure keeps only its type and HTTP status: never a body or a message
/// that could carry the credential.
func askPilot(_ state: JSON, key: String) async -> JSON {
    let request = JSON.object([("model", .string(analyseModel)), ("state", state),
                               ("questions", .object([("action", pilotQuestion)]))])
    let start = ProcessInfo.processInfo.systemUptime
    var http = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!, timeoutInterval: 10)
    http.httpMethod = "POST"
    http.httpBody = Data(request.text().utf8)
    http.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    http.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var status = JSON.null
    func seconds() -> JSON { .double(JSON.round(ProcessInfo.processInfo.systemUptime - start, 4)) }
    do {
        let (data, response) = try await URLSession.shared.data(for: http)
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            status = .int(code)
            throw URLError(.badServerResponse)
        }
        let result = try JSON.parse(String(decoding: data, as: UTF8.self))
        guard let answer = result["answers"]?["action"], answer["type"] == .string("choice"),
              let choice = answer["choice"]?.string, pilotChoices.contains(choice),
              let probs = answer["probabilities"]?.pairs, Set(probs.map(\.0)) == Set(pilotChoices), probs.count == pilotChoices.count,
              probs.allSatisfy({ $0.1.number.map { (0...1).contains($0) } ?? false }),
              abs(probs.reduce(0) { $0 + $1.1.number! } - 1) <= 0.02,
              let confidence = answer["confidence"]?.number, (0...1).contains(confidence),
              result["model"] == .string(analyseModel) else {
            throw AnalyseError(description: "Unexpected answer schema or model")
        }
        return .object([("request", request), ("response", result), ("request_seconds", seconds())])
    } catch {
        return .object([("request", request), ("error", .string(String(describing: type(of: error)))),
                        ("http_status", status), ("request_seconds", seconds())])
    }
}

func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

func analyseSelfTest() -> Int {
    var checks = 0
    func check(_ condition: Bool, _ name: String) {
        guard condition else { FileHandle.standardError.write(Data("FAIL: \(name)\n".utf8)); exit(1) }
        checks += 1
    }
    func state(area: Int = 380, y: Double? = 289, background: Double = 2) -> [PilotRow] {
        Array(repeating: PilotRow(orange: 380, y: 289, background: 2), count: 5) + [PilotRow(orange: area, y: y, background: background)]
    }
    check(pilotRules(state(y: 291)) == "WAIT", "waits during ordinary bobbing")
    check(pilotRules(state(area: 112, y: 300)) == "REEL", "recommends REEL on a local downward area drop")
    check(pilotRules(state(area: 0, y: nil)) == "ABSTAIN", "no target: ABSTAIN")
    check(pilotRules(state(area: 112, y: 300, background: 10)) != "REEL", "moving water is not a bite")
    var missing = state(area: 112, y: 300)
    missing[0] = PilotRow(orange: 0, y: nil)
    check(pilotRules(missing) == "ABSTAIN", "an unstable history abstains")
    check(pilotRules([]) == "ABSTAIN", "no history abstains")
    check(median([3, 1, 2]) == 2 && median([4, 1, 2, 3]) == 2.5, "median averages the middle pair, as Python's does")
    check(JSON.round(0.12345, 4) == 0.1235 && JSON.round(2.675, 2) == 2.67, "round from the exact binary value, as Python's does")
    check(PilotRow(t: 8.1167, orange: 380, y: nil, targetChange: 1.25, background: 0).json.text()
          == #"{"t_s": 8.1167, "orange_pixels": 380, "y_px": null, "target_change": 1.25, "background_change": 0.0}"#,
          "an observation row keeps Python's key order and float repr")
    return checks
}

@main
struct Analyse {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--self-test"] {
            let checks = analyseSelfTest()
            guard checks >= 9 else { fail("the analyse self-test lost checks (\(checks))") }
            print("analyse checks passed: \(checks)")
            return
        }
        let files = args.filter { $0 != "--jev" }
        guard files.count == 1, !files[0].hasPrefix("-") else { fail("usage: analyse VIDEO [--jev] | analyse --self-test") }
        var key: String?
        if args.contains("--jev") {
            guard let found = typesafeKey(root: analyseRoot) else { fail("Set TYPESAFE_API_KEY in the environment or local .env") }
            key = found
        }
        do {
            try await analyse(URL(fileURLWithPath: files[0]), key: key)
        } catch {
            fail("\(error)")
        }
    }

    static func analyse(_ video: URL, key: String?) async throws {
        let clock = DateFormatter()
        clock.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        clock.timeZone = TimeZone(identifier: "UTC")
        clock.locale = Locale(identifier: "en_US_POSIX")
        let id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8)
        let folder = analyseRoot.appendingPathComponent("runs/001_wow_fishing/\(clock.string(from: Date()))_\(id)")
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        var history: [PilotRow] = [], checkpoints: [JSON] = [], reelTimes: [Double] = []
        let started = ProcessInfo.processInfo.systemUptime
        var lines = ""
        try measurements(video) { row in
            history = Array((history + [row]).suffix(6))
            let state = JSON.object([
                ("target", .string("manually located bobber region in the pilot recording")),
                ("measurement", .string("fixed orange colour mask, not object tracking; cursor may overlap")),
                ("audio", .string("not used")), ("recent_observations", .array(history.map(\.json)))])
            let action = pilotRules(history)
            lines += row.json.setting("rules", .string(action)).text() + "\n"
            // Pilot comparison ends before the observed retrieval/loot response.
            if action == "REEL" && row.t <= 20.8 { reelTimes.append(row.t) }
            if checkpoints.count < checkpointTimes.count && row.t >= checkpointTimes[checkpoints.count] {
                checkpoints.append(.object([("t_s", .double(row.t)), ("state", state), ("rules", .string(action))]))
            }
        }
        try lines.write(to: folder.appendingPathComponent("observations.jsonl"), atomically: true, encoding: .utf8)
        let analysisSeconds = JSON.round(ProcessInfo.processInfo.systemUptime - started, 4)
        var comparison = ""
        for var item in checkpoints {
            if let key { item = item.setting("jev", await askPilot(item["state"]!, key: key)) }
            comparison += item.text() + "\n"
            let answer = item["jev"]?["response"]?["answers"]?["action"]
            print(JSON.object([("t_s", item["t_s"]!), ("rules", item["rules"]!), ("jev", answer?["choice"] ?? .null),
                               ("confidence", answer?["confidence"] ?? .null), ("error", item["jev"]?["error"] ?? .null)]).text())
        }
        try comparison.write(to: folder.appendingPathComponent("comparison.jsonl"), atomically: true, encoding: .utf8)
        let summary = JSON.object([
            ("video", .string(video.relativePath)), ("sha256", .string(sha256(try Data(contentsOf: video)))),
            ("script_sha256", .string(sha256(try Data(contentsOf: URL(fileURLWithPath: #filePath))))),
            ("analysis_seconds", .double(analysisSeconds)), ("rules_reel_times_before_retrieval", .array(reelTimes.map(JSON.double))),
            ("first_accepted_reel", reelTimes.first.map(JSON.double) ?? .null), ("api_calls", .int(key == nil ? 0 : checkpoints.count)),
            ("limitation", .string("One development clip; fixed ROI and provisional thresholds, no held-out test"))])
        try (summary.text(indent: 2) + "\n").write(to: folder.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        print(summary.text(indent: 2))
        print("Results: \(folder.path)")
    }

    static func fail(_ why: String) -> Never {
        FileHandle.standardError.write(Data((why + "\n").utf8))
        exit(1)
    }
}
