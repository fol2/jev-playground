// Test B: one in-flight HTTP judgement; no retries or retained frame queue.
import Foundation

let jevModel = "jev-1.13.0"
let fishingQuestion: [String: Any] = [
    "type": "choice",
    "instructions": "Choose a fishing action from visual measurements. Rows are chronological [horizontal displacement in pixels, DOWNWARD displacement in pixels, coloured area relative to baseline]. Displacements are relative to the median of the earliest four observations. Positive vertical values mean DOWN; negative values mean UP. A bite is a sudden substantial DOWNWARD plunge relative to preceding small bobbing, or brief disappearance followed by return. Ordinary upward motion, gentle drifting, and colour-area changes alone are NOT bite evidence. Background_change is average pixel brightness change on a 0-255 scale; values around 1-3 are quiet water. No audio. Read the direction and magnitude carefully.",
    "criteria": ["WAIT": "Only small bobbing, upward movement or area variation; no downward plunge or submersion.",
                 "REEL": "A clear abrupt downward plunge or brief submersion and return against quiet water.",
                 "ABSTAIN": "Tracking or background motion makes the observations unreliable."]]


struct JevReply {
    let action: String
    let details: [String: Any]
}

final class JevClient: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: JevReply?
    private var task: URLSessionDataTask?
    private let key: String
    private let session: URLSession
    var calls = 0
    let limit: Int
    var busy: Bool { lock.lock(); defer { lock.unlock() }; return task != nil }
    init() throws {
        guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
            throw NSError(domain: "Missing TYPESAFE_API_KEY", code: 1)
        }
        self.key = key
        limit = Int(ProcessInfo.processInfo.environment["JEV_CALL_LIMIT"] ?? "120") ?? 120
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 1.5
        session = URLSession(configuration: configuration)
    }
    @MainActor func start(state: [String: Any], question: [String: Any], emit: @MainActor (String, [String: Any]) -> Void) throws {
        guard !busy, calls < limit else { throw NSError(domain: "Jev busy or call budget exhausted", code: 2) }
        let payload: [String: Any] = ["model": jevModel, "state": state, "questions": ["action": question]]
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        calls += 1
        emit("jev_request", ["request": payload, "call": calls])
        let at = ProcessInfo.processInfo.systemUptime
        let work = session.dataTask(with: request) { [self] data, response, error in
            var details: [String: Any] = ["request_seconds": ProcessInfo.processInfo.systemUptime-at]
            var action = "ERROR"
            if error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               body["model"] as? String == jevModel,
               let answers = body["answers"] as? [String: Any], let answer = answers["action"] as? [String: Any],
               answer["type"] as? String == "choice", let choice = answer["choice"] as? String,
               let criteria = question["criteria"] as? [String: String], criteria[choice] != nil,
               let probabilities = answer["probabilities"] as? [String: Double],
               Set(probabilities.keys) == Set(criteria.keys), probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
               abs(probabilities.values.reduce(0,+)-1) < 0.02,
               let confidence = answer["confidence"] as? Double, (0...1).contains(confidence) {
                action = choice; details["response"] = body
            } else {
                details["error"] = "request_or_schema_failed"
                details["http_status"] = (response as? HTTPURLResponse)?.statusCode ?? 0
            }
            lock.lock(); reply = JevReply(action: action, details: details); lock.unlock()
        }
        lock.lock(); task = work; lock.unlock()
        work.resume()
    }
    func take() -> JevReply? {
        lock.lock(); defer { lock.unlock() }
        guard let value = reply else { return nil }
        reply = nil; task = nil; return value
    }
    func cancel() { lock.lock(); task?.cancel(); task = nil; lock.unlock(); session.invalidateAndCancel() }
    @MainActor func decide(state: [String: Any], instructions: String, criteria: [String: String],
                emit: @MainActor (String, [String: Any]) -> Void) async throws -> String {
        try start(state: state, question: ["type": "choice", "instructions": instructions, "criteria": criteria], emit: emit)
        while true {
            if let value = take() {
                emit("jev_response", value.details)
                guard value.action != "ERROR" else { throw NSError(domain: "Jev pre-go request failed", code: 3) }
                return value.action
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

// Pilot-calibrated abstention threshold; not a claimed success probability.
func reelIsSupported(_ reply: JevReply) -> Bool {
    guard reply.action == "REEL",
          let response = reply.details["response"] as? [String: Any],
          let answers = response["answers"] as? [String: Any],
          let action = answers["action"] as? [String: Any],
          let probabilities = action["probabilities"] as? [String: Double] else { return false }
    return probabilities["REEL", default: 0] >= 0.85
}
