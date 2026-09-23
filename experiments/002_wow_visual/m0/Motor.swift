// M0 motor core for issue #5: a fixed primitive allowlist, bounded plans, one-key input
// leases, a frame gate and the observe/pulse/observe batch. Pure Foundation with injected
// time, frames and key sink, so every path runs offline under fake time and fake input.
// Probe.swift supplies the native clock, window capture, key route and evidence files.
import Foundation

struct ProbeError: Error, Equatable, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum Primitive: String, CaseIterable {
    case turnLeft = "turn-left", turnRight = "turn-right", forward
}

/// Fixed key profiles. `arrows` and `wasd` are WoW's shipped defaults (A/D turn). `wqe` is
/// the owner's layout, where A/D strafe and Q/E turn: live check 1 sent A/D as "turns" and
/// strafed. A wrong profile sends the wrong action, so execution needs the owner-confirmed one.
enum KeyProfile: String, CaseIterable {
    case arrows, wasd, wqe
    func code(_ primitive: Primitive) -> UInt16 {
        switch (self, primitive) {
        case (.arrows, .turnLeft): return 123
        case (.arrows, .turnRight): return 124
        case (.arrows, .forward): return 126
        case (.wasd, .turnLeft): return 0
        case (.wasd, .turnRight): return 2
        case (.wasd, .forward): return 13
        case (.wqe, .turnLeft): return 12
        case (.wqe, .turnRight): return 14
        case (.wqe, .forward): return 13
        }
    }
}

struct Pulse: Equatable {
    let primitive: Primitive
    let milliseconds: Int
    var token: String { "\(primitive.rawValue):\(milliseconds)" }
}

enum Limits {
    static let durations: Set<Int> = [100, 200]  // proposed first amplitudes, not WoW constants
    static let maxPulses = 6                      // per process; one key held at a time
    static let maxFrameAge = 0.35                 // capture PTS to now, fishing's live bound
    static let releaseAttempts = 3
    static let firstFrameWait = 2.0
    static let baseline = 1.0                     // observation before every pulse
    static let settle = 1.0                       // visible motion must stop within this of key-up
    static let tail = 0.5                         // further observation showing that it stopped
    static let poll = 0.01
}

let envelopePlan = ["turn-left:100", "turn-right:100", "forward:100",
                    "turn-left:200", "turn-right:200", "forward:200"]

func parsePlan(_ tokens: [String]) throws -> [Pulse] {
    guard !tokens.isEmpty else { throw ProbeError("empty plan") }
    guard tokens.count <= Limits.maxPulses else { throw ProbeError("plan exceeds \(Limits.maxPulses) pulses") }
    return try tokens.map { token in
        let parts = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let primitive = Primitive(rawValue: parts[0]),
              let milliseconds = Int(parts[1]), Limits.durations.contains(milliseconds) else {
            throw ProbeError("invalid pulse '\(token.prefix(40))'; use turn-left|turn-right|forward:100|200")
        }
        return Pulse(primitive: primitive, milliseconds: milliseconds)
    }
}

enum Mode: String {
    case preflight = "--preflight", dryRun = "--dry-run", execute = "--execute", release = "--release"
}

struct Command: Equatable {
    let mode: Mode
    let profile: KeyProfile?
    let plan: [Pulse]
}

/// Parses everything before any effect. Missing or unknown arguments never default to input.
func parseCommand(_ arguments: [String]) throws -> Command {
    guard let first = arguments.first else { return Command(mode: .preflight, profile: nil, plan: []) }
    guard let mode = Mode(rawValue: first) else { throw ProbeError("unknown mode '\(first.prefix(40))'") }
    var profile: KeyProfile?
    var tokens: [String] = []
    var rest = arguments.dropFirst()
    while let argument = rest.popFirst() {
        if argument == "--keys" {
            guard profile == nil, let value = rest.popFirst(), let parsed = KeyProfile(rawValue: value) else {
                throw ProbeError("--keys needs exactly one of: arrows, wasd, wqe")
            }
            profile = parsed
        } else if argument.hasPrefix("-") {
            throw ProbeError("unexpected option '\(argument.prefix(40))'")
        } else {
            tokens.append(argument)
        }
    }
    switch mode {
    case .preflight:
        guard profile == nil, tokens.isEmpty else { throw ProbeError("--preflight takes no arguments") }
        return Command(mode: mode, profile: nil, plan: [])
    case .dryRun:
        return Command(mode: mode, profile: profile ?? .arrows, plan: try parsePlan(tokens.isEmpty ? envelopePlan : tokens))
    case .execute:
        guard let profile else { throw ProbeError("--execute requires --keys arrows|wasd|wqe, confirmed in-game") }
        guard !tokens.isEmpty else { throw ProbeError("--execute requires the explicit approved plan") }
        return Command(mode: mode, profile: profile, plan: try parsePlan(tokens))
    case .release:
        guard let profile, tokens.isEmpty else { throw ProbeError("--release requires --keys arrows|wasd|wqe and no pulses") }
        return Command(mode: mode, profile: profile, plan: [])
    }
}

protocol KeySink: AnyObject {
    func post(_ code: UInt16, down: Bool) throws
}

typealias Emit = (String, [String: Any]) -> Void

/// What one lease may ever send. M0 is the fixed six-pulse envelope; M1 passes a wider but
/// still capped budget, including total held time per primitive.
struct Budget {
    let maxPulses: Int
    let allows: (Pulse) -> Bool
    let maxTotalMs: [Primitive: Int]
    static let m0 = Budget(maxPulses: Limits.maxPulses, allows: { Limits.durations.contains($0.milliseconds) }, maxTotalMs: [:])
}

func ms(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }

/// Holds at most one key until its deadline. Expiry is idempotent, so an independent timer
/// and the observer may both call it. Cancellation releases and is sticky: a stopped batch
/// cannot resume in this process. A failed key-up stays held so exit paths retry it.
final class InputLease {
    struct Grant { let code: UInt16; let pulse: Pulse; let downAt: Double; let deadline: Double }
    struct Release { let at: Double; let reason: String }

    private let lock = NSLock()
    private let profile: KeyProfile
    private let sink: KeySink
    private let clock: () -> Double
    private let emit: Emit
    private let budget: Budget
    private var held: Grant?
    private var used = 0
    private var spent: [Primitive: Int] = [:]
    private var stop: String?
    private var released: Release?

    init(profile: KeyProfile, sink: KeySink, clock: @escaping () -> Double, emit: @escaping Emit, budget: Budget = .m0) {
        self.profile = profile
        self.sink = sink
        self.clock = clock
        self.emit = emit
        self.budget = budget
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var isHolding: Bool { locked { held != nil } }
    var stopReason: String? { locked { stop } }
    var lastRelease: Release? { locked { released } }
    var pulsesUsed: Int { locked { used } }
    var spentMs: [Primitive: Int] { locked { spent } }

    /// Why this pulse would be refused now; nil when acquire would post it.
    func refusal(_ pulse: Pulse) -> String? { locked { refusalLocked(pulse) } }

    private func refusalLocked(_ pulse: Pulse) -> String? {
        if let stop { return "stopped (\(stop))" }
        guard held == nil else { return "one key at a time" }
        guard used < budget.maxPulses else { return "command budget spent" }
        guard budget.allows(pulse) else { return "duration outside allowlist" }
        if let cap = budget.maxTotalMs[pulse.primitive], spent[pulse.primitive, default: 0] + pulse.milliseconds > cap {
            return "\(pulse.primitive.rawValue) time budget spent"
        }
        return nil
    }

    func acquire(_ pulse: Pulse) throws -> Grant {
        try locked {
            if let refusal = refusalLocked(pulse) { throw ProbeError("refused: " + refusal) }
            used += 1
            spent[pulse.primitive, default: 0] += pulse.milliseconds
            let now = clock()
            let grant = Grant(code: profile.code(pulse.primitive), pulse: pulse, downAt: now,
                              deadline: now + Double(pulse.milliseconds) / 1000)
            held = grant  // before posting: a partly delivered key-down must still be released
            do {
                try sink.post(grant.code, down: true)
            } catch {
                emit("key_down_failed", ["pulse": pulse.token, "error": "\(error)"])
                stop = "key_down_failed"
                releaseLocked("key_down_failed")
                throw ProbeError("key-down failed: \(error)")
            }
            emit("key_down", ["pulse": pulse.token, "code": Int(grant.code), "at": now, "deadline": grant.deadline])
            return grant
        }
    }

    /// Releases once the deadline has passed; true when this call released.
    @discardableResult func expire() -> Bool {
        locked {
            guard let held, clock() >= held.deadline else { return false }
            return releaseLocked("expired")
        }
    }

    /// Stops the batch, releasing first when a key is (or may still be) held.
    func cancel(_ reason: String) {
        locked {
            let first = stop == nil
            if first { stop = reason }
            releaseLocked("cancelled:" + reason)
            if first { emit("stopped", ["reason": reason, "at": clock()]) }
        }
    }

    @discardableResult private func releaseLocked(_ reason: String) -> Bool {
        guard let grant = held else { return false }
        for attempt in 1...Limits.releaseAttempts {
            do {
                try sink.post(grant.code, down: false)
                let at = clock()
                held = nil
                released = Release(at: at, reason: reason)
                emit("key_up", ["pulse": grant.pulse.token, "code": Int(grant.code), "at": at, "reason": reason,
                                "held_ms": ms(at - grant.downAt), "lateness_ms": ms(at - grant.deadline),
                                "attempt": attempt])
                return true
            } catch {
                emit("key_up_failed", ["pulse": grant.pulse.token, "attempt": attempt, "error": "\(error)"])
            }
        }
        if stop == nil { stop = "release_unconfirmed" }
        emit("release_unconfirmed", ["code": Int(grant.code),
                                     "recovery": "run --release --keys \(profile.rawValue), or bring WoW forward and tap the key"])
        return false
    }
}

/// One captured frame's identity and whole-frame change against its predecessor.
struct Frame {
    let stream: String
    let pts: Double
    let width: Int
    let height: Int
    let diff: Double
}

/// Admits only in-order, current frames from the stream and size fixed at start. Identity
/// and geometry changes are sticky. Stale, duplicate and reordered frames never refresh
/// evidence age, so a stalled or failed detector blocks new commands and stops the batch.
struct FrameGate {
    enum Verdict: String {
        case fresh, stale, future, invalid, duplicate, reordered
        case identity = "identity_changed", geometry = "geometry_changed"
    }

    let stream: String
    let width: Int
    let height: Int
    private(set) var counts: [String: Int] = [:]
    private var lastPTS: Double?
    private var freshPTS: Double?
    private var broken: String?

    init(stream: String, width: Int, height: Int) {
        self.stream = stream
        self.width = width
        self.height = height
    }

    mutating func admit(_ frame: Frame, now: Double) -> Verdict {
        let verdict: Verdict
        if frame.stream != stream { verdict = .identity }
        else if frame.width != width || frame.height != height { verdict = .geometry }
        else if !frame.pts.isFinite || !frame.diff.isFinite { verdict = .invalid }
        else if frame.pts > now { verdict = .future }
        else if let last = lastPTS, frame.pts <= last { verdict = frame.pts == last ? .duplicate : .reordered }
        else {
            lastPTS = frame.pts
            verdict = now - frame.pts <= Limits.maxFrameAge ? .fresh : .stale
        }
        if verdict == .fresh { freshPTS = frame.pts }
        if verdict == .identity || verdict == .geometry, broken == nil { broken = verdict.rawValue }
        counts[verdict.rawValue, default: 0] += 1
        return verdict
    }

    /// Why a command must not start or continue now; nil while current evidence exists.
    func blocker(now: Double) -> String? {
        if let broken { return broken }
        guard let freshPTS, now - freshPTS <= Limits.maxFrameAge else { return "stale_or_stalled_frames" }
        return nil
    }
}

func meanAbsoluteDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return .nan }
    return Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
}

struct Response {
    let verdict: String
    let threshold: Double?
    let responseMs: Int?
    let lastMotionAfterUpMs: Int?
    var fields: [String: Any] {
        ["visual_effect": verdict, "threshold": threshold as Any? ?? NSNull(),
         "visible_response_ms": responseMs as Any? ?? NSNull(),
         "last_motion_after_up_ms": lastMotionAfterUpMs as Any? ?? NSNull()]
    }
}

/// Heuristic visual-effect timing from whole-frame change against the pre-pulse baseline.
/// Whole-frame change cannot separate avatar movement from camera-only or scene motion.
func analyseResponse(baseline: [Double], after frames: [Frame], downAt: Double, upAt: Double) -> Response {
    guard baseline.count >= 5 else {
        return Response(verdict: "insufficient_baseline", threshold: nil, responseMs: nil, lastMotionAfterUpMs: nil)
    }
    let mean = baseline.reduce(0, +) / Double(baseline.count)
    let spread = (baseline.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(baseline.count)).squareRoot()
    // ponytail: fixed 6-sigma/3x-mean threshold; recalibrate from labelled live traces.
    let threshold = max(mean + 6 * spread, 3 * mean, 0.5)
    let moving = frames.filter { $0.pts > downAt && $0.diff > threshold }
    let response = moving.first.map { ms($0.pts - downAt) }
    let lastAfterUp = moving.last.flatMap { $0.pts > upAt ? ms($0.pts - upAt) : nil }
    let verdict: String
    if (frames.last?.pts ?? -.infinity) < upAt + Limits.settle { verdict = "observation_incomplete" }
    else if response == nil { verdict = "no_effect_resolved" }
    else if let lastAfterUp, Double(lastAfterUp) > Limits.settle * 1000 { verdict = "release_unclear" }
    else { verdict = "effect_then_settled" }
    return Response(verdict: verdict, threshold: threshold, responseMs: response, lastMotionAfterUpMs: lastAfterUp)
}

protocol ProbeDriver: AnyObject {
    var dispatchLabel: String { get }
    func now() -> Double
    func sleep(_ seconds: Double) async
    func frames() -> [Frame]                                    // delivered since the previous call
    func scheduleRelease(_ lease: InputLease, at deadline: Double)  // must not depend on the observer
    func fault() -> String?                                     // process, window, focus or operator stop
    func snapshot(_ name: String)
    func emit(_ event: String, _ fields: [String: Any])
}

struct BatchResult {
    let outcome: String
    let pulses: [[String: Any]]
    let frameCounts: [String: Int]
}

let stopVerdicts: Set<String> = ["release_unclear", "observation_incomplete", "insufficient_baseline"]

/// Observe, pulse, observe for each planned pulse. Every stop cancels the lease, which
/// releases a held key before this returns; no release waits for this observer loop.
func runBatch(_ plan: [Pulse], lease: InputLease, gate start: FrameGate, driver: ProbeDriver) async -> BatchResult {
    var gate = start
    var history: [(frame: Frame, age: Double)] = []  // in-order frames with their age on admission
    var pulses: [[String: Any]] = []
    var verdicts: [String] = []

    func check() -> String? {
        let now = driver.now()
        for frame in driver.frames() {
            let verdict = gate.admit(frame, now: now)
            if verdict == .fresh || verdict == .stale { history.append((frame, now - frame.pts)) }  // stale: real, late
            if verdict != .fresh && verdict != .stale {
                driver.emit("frame_rejected", ["verdict": verdict.rawValue, "pts": frame.pts.isFinite ? frame.pts : -1])
            }
        }
        return lease.stopReason ?? gate.blocker(now: now) ?? driver.fault()
    }
    func observe(until end: Double) async -> String? {
        repeat {
            if let reason = check() { return reason }
            lease.expire()  // backstop only; the driver's scheduled release is primary
            await driver.sleep(Limits.poll)
        } while driver.now() < end
        return check()
    }

    let waitEnd = driver.now() + Limits.firstFrameWait
    var reason = check()
    while reason == "stale_or_stalled_frames" && driver.now() < waitEnd {
        await driver.sleep(Limits.poll)
        reason = check()
    }
    if let reason { lease.cancel(reason) }

    for (index, pulse) in plan.enumerated() where lease.stopReason == nil {
        let name = "p\(index + 1)"
        let baselineStart = driver.now()
        if let reason = await observe(until: baselineStart + Limits.baseline) { lease.cancel(reason); break }
        driver.snapshot(name + "-before")
        let grant: InputLease.Grant
        do { grant = try lease.acquire(pulse) } catch {
            driver.emit("refused", ["pulse": pulse.token, "error": "\(error)"])
            lease.cancel("acquire_refused")
            break
        }
        driver.scheduleRelease(lease, at: grant.deadline)
        if let reason = await observe(until: grant.deadline + Limits.settle + Limits.tail) { lease.cancel(reason) }
        driver.snapshot(name + "-after")
        let up = lease.lastRelease.flatMap { $0.at >= grant.downAt ? $0 : nil }
        let traced = history.filter { $0.frame.pts >= baselineStart }
        let baseline = traced.filter { $0.frame.pts < grant.downAt }.map(\.frame.diff)
        let window = traced.map(\.frame).filter { $0.pts > grant.downAt }
        let response = analyseResponse(baseline: baseline, after: window, downAt: grant.downAt, upAt: up?.at ?? .infinity)
        var record: [String: Any] = [
            "index": index + 1, "pulse": pulse.token, "key_code": Int(grant.code),
            "down_at": grant.downAt, "requested_up_at": grant.deadline,
            "up_at": up?.at as Any? ?? NSNull(), "up_reason": up?.reason as Any? ?? NSNull(),
            "baseline_frames": baseline.count, "window_frames": window.count,
            "dispatch": driver.dispatchLabel, "avatar_movement": "UNLABELLED",
            // [capture PTS minus key-down, frame age when admitted, grey change] per frame
            "trace": traced.map { [Double(ms($0.frame.pts - grant.downAt)), Double(ms($0.age)), ($0.frame.diff * 100).rounded() / 100] },
        ]
        record.merge(response.fields) { current, _ in current }
        pulses.append(record)
        verdicts.append(response.verdict)
        driver.emit("pulse_report", record)
        if lease.stopReason == nil, stopVerdicts.contains(response.verdict) { lease.cancel(response.verdict) }
    }
    if lease.isHolding { lease.cancel("batch_end_holding") }

    let outcome: String
    if lease.isHolding { outcome = "HOLD_RELEASE_UNCONFIRMED" }
    else if let stop = lease.stopReason { outcome = "STOPPED_" + stop }
    else if verdicts.contains("no_effect_resolved") { outcome = "INCONCLUSIVE" }
    else { outcome = "COMPLETED_PENDING_MANUAL_LABELS" }
    return BatchResult(outcome: outcome, pulses: pulses, frameCounts: gate.counts)
}
