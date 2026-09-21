// Deterministic clock/pixel/HTTP tests. FakeSession never opens a network connection.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class FakeTask: URLSessionDataTask, @unchecked Sendable {
    var cancelled = false
    override func resume() {}
    override func cancel() { cancelled = true }
}

final class FakeSession: URLSession, @unchecked Sendable {
    typealias Completion = @Sendable (Data?, URLResponse?, Error?) -> Void
    var requests: [(URLRequest, FakeTask, Completion)] = []
    override func dataTask(with request: URLRequest, completionHandler: @escaping Completion) -> URLSessionDataTask {
        let task = FakeTask()
        requests.append((request, task, completionHandler))
        return task
    }
    override func invalidateAndCancel() {}
    func respond(_ index: Int, model: String = jevModel, status: Int = 200, choice: String = "REEL",
                 probabilities: [String: Double] = ["WAIT": 0.05, "REEL": 0.9, "ABSTAIN": 0.05]) throws {
        let body: [String: Any] = ["model": model, "answers": ["action": [
            "type": "choice", "choice": choice, "probabilities": probabilities, "confidence": 0.7]],
            "usage": ["input_tokens": 100, "output_tokens": 20]]
        let response = HTTPURLResponse(url: requests[index].0.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        requests[index].2(try JSONSerialization.data(withJSONObject: body), response, nil)
    }
}

@main
struct CoreTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        checks += 1
    }
    static func blob(_ y: Double = 100) -> Blob { Blob(x: 100, y: y, area: 36) }
    static func feed(_ loop: inout FishingLoop, _ t: Double, _ y: Double = 100) {
        loop.observe(blob(y), capturedAt: t, now: t+0.01, background: 2)
    }
    static func warm() -> FishingLoop {
        var loop = FishingLoop()
        for i in 0...12 { feed(&loop, Double(i)/10) }
        return loop
    }
    static func texture(_ dx: Int = 0, _ dy: Int = 0) -> [Double] {
        var pixels = [Double](repeating: 20, count: 64*64)
        for y in 0..<20 { for x in 0..<20 {
            pixels[(y+22+dy)*64+x+22+dx] = Double((x*17+y*31+x*y*7)%251)
        }}
        return pixels
    }

    @MainActor static func main() throws {
        var loop = FishingLoop()
        for i in 0..<7 { feed(&loop, Double(i)/10) }
        check(loop.window == nil, "warm-up uses elapsed capture time, not seven fast frames")
        loop = warm()
        check(loop.window != nil && !loop.window!.rulesReel, "ordinary bobbing waits")
        feed(&loop, 1.3, 108)
        let signal = loop.window!
        check(signal.rulesReel, "downward onset remains detectable")
        check(loop.arm(signal, now: 1.31), "fresh evidence arms")
        check(!loop.arm(signal, now: 1.32), "an armed signal cannot be replaced")
        check(loop.takeClick(at: 1.32) == nil, "a dipped target is not clicked")
        feed(&loop, 1.4)
        check(loop.takeClick(at: 1.41) == nil, "moving rebound does not confirm recovery")
        feed(&loop, 1.5)
        check(loop.takeClick(at: 1.51) == nil, "one stable frame is insufficient")
        check(loop.takeClick(at: 1.52) == nil, "same frame cannot count twice")
        feed(&loop, 1.6)
        check(loop.takeClick(at: 1.61) != nil, "two distinct recovered frames permit one click")
        check(loop.takeClick(at: 1.62) == nil, "click is consumed exactly once")
        loop.invalidate()
        for i in 17...29 { feed(&loop, Double(i)/10) }
        check(!loop.arm(loop.window!, now: 2.91), "invalidation cannot resurrect a completed cast")

        loop = warm()
        let old = loop.window!
        check(loop.arm(old, now: 1.21), "prepare a pending response regression")
        loop.observe(nil, capturedAt: 1.3, now: 1.31, background: 2)
        check(loop.window == nil && !loop.armed, "tracker dropout clears history AND action")
        for i in 14...25 { feed(&loop, Double(i)/10) }
        check(loop.window != nil, "reacquisition requires a fresh warm-up")
        check(!loop.arm(old, now: 2.51), "old epoch rejected even inside the response deadline")

        loop = warm(); _ = loop.arm(loop.window!, now: 1.21)
        feed(&loop, 1.51)
        check(loop.window == nil && !loop.armed, "stream gap invalidates without a tracker dropout")
        loop = warm(); _ = loop.arm(loop.window!, now: 1.21)
        loop.observe(blob(), capturedAt: 1.3, now: 1.7, background: 2)
        check(loop.window == nil && !loop.armed, "stale capture clears an armed decision")
        loop = warm(); feed(&loop, 1.2)
        check(loop.window == nil, "duplicate capture cannot advance the evidence")
        loop = warm(); feed(&loop, 1.1)
        check(loop.window == nil, "out-of-order capture invalidates")
        loop = warm(); loop.observe(blob(), capturedAt: 1.4, now: 1.3, background: 2)
        check(loop.window == nil, "future capture timestamp rejected")
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            loop = warm(); loop.observe(blob(value), capturedAt: 1.3, now: 1.31, background: 2)
            check(loop.window == nil, "non-finite position rejected")
        }
        loop = warm(); var uncertain = blob(); uncertain.matchCorrelation = 0.3
        loop.observe(uncertain, capturedAt: 1.3, now: 1.31, background: 2)
        check(loop.window == nil, "poor appearance agreement is missing evidence")
        loop = warm(); let stale = loop.window!
        for i in 13...29 { feed(&loop, Double(i)/10) }
        check(!loop.arm(stale, now: 2.91), "response age measured from capture, not receipt")
        check(!loop.arm(loop.window!, now: .nan), "non-finite decision time rejected")
        loop = warm(); let delayed = loop.window!
        for i in 13...24 { feed(&loop, Double(i)/10) }
        check(loop.arm(delayed, now: 2.41), "a response within the deadline may arm")
        check(loop.expired(at: 3.21), "network time consumes the recovery allowance")
        check(loop.takeClick(at: 3.21) == nil, "expired signal cannot click")
        loop = FishingLoop()
        for t in [0, 0.11, 0.2, 0.32, 0.43, 0.51, 0.62, 0.73, 0.85, 0.98, 1.13] { feed(&loop, t) }
        let rows = loop.window!.state["sequence_seconds_dx_downward_dy_match"] as! [[Double]]
        check(abs(rows.last![0]-0.7) < 0.001, "provider receives the actual 0.7-second window")
        check(rows.count == 7 && rows.allSatisfy { $0.count == 4 }, "compact chronological schema")
        check(loop.window!.state["rules_reel"] == nil, "A verdict is not leaked to B")

        let anchor = texture(), centre = CGPoint(x: 32, y: 32)
        for dy in [0, 1, 4, 8, 4, 1, 0] {
            let match = pixelMotion(previous: anchor, current: texture(0, dy), width: 64, height: 64, centre: centre)
            check(match != nil && abs(match!.dy-Double(dy)) < 0.1, "fixed-anchor displacement \(dy)")
        }
        var ambiguous = texture(-10)
        let right = texture(10)
        for y in 22..<42 { for x in 32..<52 { ambiguous[y*64+x] = right[y*64+x] } }
        check(pixelMotion(previous: anchor, current: ambiguous, width: 64, height: 64, centre: centre) == nil,
              "equally plausible objects abstain")
        check(pixelMotion(previous: anchor, current: texture(0, 12), width: 64, height: 64, centre: centre) == nil,
              "search-boundary peak abstains rather than clipping motion")
        check(pixelMotion(previous: [], current: [], width: 0, height: 0, centre: centre) == nil, "empty image rejected")
        check(pixelMotion(previous: anchor, current: [], width: 64, height: 64, centre: centre) == nil, "bad image shape rejected")
        check(pixelMotion(previous: anchor, current: anchor, width: 64, height: 64,
                          centre: CGPoint(x: CGFloat.nan, y: 32)) == nil, "non-finite match centre rejected")
        let flat = [Double](repeating: 20, count: 64*64)
        check(pixelMotion(previous: flat, current: flat, width: 64, height: 64, centre: centre) == nil, "textureless water abstains")

        #if canImport(FoundationNetworking)
        let session = FakeSession(configuration: .ephemeral)
        #else
        let session = FakeSession()
        #endif
        let client = try JevClient(key: "offline-fixture", limit: 8, session: session)
        defer { client.cancel() }
        var events: [[String: Any]] = []
        let emit: @MainActor (String, [String: Any]) -> Void = { _, value in events.append(value) }
        try client.start(state: signal.state, question: fishingQuestion, emit: emit)
        check(client.busy && client.calls == 1, "one request occupies the reply slot")
        do {
            try client.start(state: [:], question: fishingQuestion, emit: emit)
            fatalError("second in-flight request accepted")
        } catch { checks += 1 }
        client.discardPending()
        check(session.requests[0].1.cancelled && !client.busy, "invalidated request is cancelled")
        try client.start(state: signal.state, question: fishingQuestion, emit: emit)
        try session.respond(0) // Intentionally complete an OLD request after a NEW one started.
        check(client.take() == nil && client.busy, "late cancelled callback cannot occupy the new reply slot")
        try session.respond(1)
        let reply = client.take()!
        check(reelIsSupported(reply) && !client.busy, "current provider reply is consumed normally")
        check(reply.details["request_id"] as? Int == 2, "response retains its request identity")
        try session.respond(0)
        check(client.take() == nil, "late completion cannot reappear after take")
        try client.start(state: signal.state, question: fishingQuestion, emit: emit)
        try session.respond(2, model: "wrong-model")
        check(client.take()?.action == "ERROR", "wrong model fails closed")
        try client.start(state: signal.state, question: fishingQuestion, emit: emit)
        try session.respond(3, status: 429)
        check(client.take()?.action == "ERROR", "HTTP failure is not retried or converted to a rule decision")
        try client.start(state: signal.state, question: fishingQuestion, emit: emit)
        try session.respond(4, probabilities: ["REEL": 1])
        check(client.take()?.action == "ERROR", "incomplete probability distribution rejected")
        try client.start(state: signal.state, question: fishingQuestion, emit: emit)
        try session.respond(5, choice: "CLICK_ANYWHERE")
        check(client.take()?.action == "ERROR", "unknown action rejected")
        let zero = try JevClient(key: "offline-fixture", limit: 0, session: session)
        do {
            try zero.start(state: [:], question: fishingQuestion, emit: emit)
            fatalError("exhausted budget accepted")
        } catch { checks += 1 }
        check(session.requests.count == 6, "all transport requests used the fake session, with no retries")
        check(!String(describing: events).contains("offline-fixture"), "request logging omits the API key")
        print("\(checks) pure Swift checks passed (synthetic pixels, fake clock and fake HTTP; no capture/input/provider).")
    }
}
