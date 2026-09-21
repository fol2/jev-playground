// Test B: one in-flight HTTP judgement; no retries or retained frame queue.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let jevModel = "jev-1.13.0"
let fishingQuestion: [String: Any] = [
    "type": "choice",
    "instructions": "Judge a fishing bite from seven chronological [seconds since first sample, dx pixels, DOWNWARD dy pixels, appearance correlation] rows. Displacements are relative to the median of the first four rows; positive dy is DOWN. A bite is an abrupt substantial downward plunge after small bobbing. Upward motion, gradual drift and match scores alone are not bite evidence. Correlation is image agreement, not bite probability. Background_change is mean brightness change (0-255; about 1-3 is quiet). Missing/stale observations invalidate the entire sequence before it reaches you. No images or audio are supplied.",
    "criteria": ["WAIT": "Only ordinary bobbing, upward movement or gradual drift; no abrupt downward plunge.",
                 "REEL": "A clear abrupt downward plunge after stable bobbing, against quiet water.",
                 "ABSTAIN": "Movement or image agreement is ambiguous, or background motion makes the evidence unreliable."]]

struct JevReply {
    let action: String
    let details: [String: Any]
}

final class JevClient: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: JevReply?
    private var task: URLSessionDataTask?
    private var activeCall: Int?
    private let key: String
    private let session: URLSession
    var calls = 0
    let limit: Int
    var busy: Bool { lock.lock(); defer { lock.unlock() }; return activeCall != nil }
    init(key: String? = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"],
         limit: Int? = nil, session: URLSession? = nil) throws {
        guard let key, !key.isEmpty else { throw NSError(domain: "Missing TYPESAFE_API_KEY", code: 1) }
        guard let budget = limit ?? Int(ProcessInfo.processInfo.environment["JEV_CALL_LIMIT"] ?? "120"),
              (0...120).contains(budget) else { throw NSError(domain: "JEV_CALL_LIMIT must be 0...120", code: 2) }
        self.key = key; self.limit = budget
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 1.5
        self.session = session ?? URLSession(configuration: configuration)
    }
    @MainActor func start(state: [String: Any], question: [String: Any], emit: @MainActor (String, [String: Any]) -> Void) throws {
        guard !busy, calls < limit else { throw NSError(domain: "Jev busy or call budget exhausted", code: 2) }
        guard let criteria = question["criteria"] as? [String: String], !criteria.isEmpty else {
            throw NSError(domain: "Missing choice criteria", code: 2)
        }
        let payload: [String: Any] = ["model": jevModel, "state": state, "questions": ["action": question]]
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        calls += 1
        let call = calls
        emit("jev_request", ["request": payload, "call": call])
        let at = ProcessInfo.processInfo.systemUptime
        let work = session.dataTask(with: request) { [self] data, response, error in
            var details: [String: Any] = ["request_seconds": ProcessInfo.processInfo.systemUptime-at, "request_id": call]
            var action = "ERROR"
            if error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               body["model"] as? String == jevModel,
               let answers = body["answers"] as? [String: Any], let answer = answers["action"] as? [String: Any],
               answer["type"] as? String == "choice", let choice = answer["choice"] as? String,
               criteria[choice] != nil,
               let probabilities = answer["probabilities"] as? [String: Double],
               Set(probabilities.keys) == Set(criteria.keys), probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
               abs(probabilities.values.reduce(0,+)-1) < 0.02,
               let confidence = answer["confidence"] as? Double, (0...1).contains(confidence) {
                action = choice; details["response"] = body
            } else {
                details["error"] = "request_or_schema_failed"
                details["http_status"] = (response as? HTTPURLResponse)?.statusCode ?? 0
            }
            lock.lock(); defer { lock.unlock() }
            // Cancellation may complete after a newer request: never publish into its slot.
            if activeCall == call { reply = JevReply(action: action, details: details) }
        }
        lock.lock(); task = work; activeCall = call; lock.unlock()
        work.resume()
    }
    func take() -> JevReply? {
        lock.lock(); defer { lock.unlock() }
        guard let value = reply else { return nil }
        reply = nil; task = nil; activeCall = nil; return value
    }
    func discardPending() {
        lock.lock()
        let old = task
        task = nil; reply = nil; activeCall = nil
        lock.unlock()
        old?.cancel()
    }
    func cancel() { discardPending(); session.invalidateAndCancel() }
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
