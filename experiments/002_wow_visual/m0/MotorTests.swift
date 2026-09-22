// Offline M0 checks with fake time, fake frames and a recording sink. They prove argument,
// lease, gate and batch logic: DISPATCH INTENT ONLY. Nothing here shows that macOS delivers
// the events, that WoW applies them or that the avatar actually turns or moves.
import Foundation

final class FakeClock { var t = 0.0 }

final class Events {
    var rows: [(name: String, fields: [String: Any])] = []
    func named(_ name: String) -> [[String: Any]] { rows.filter { $0.name == name }.map(\.fields) }
}

final class FakeSink: KeySink {
    let clock: FakeClock
    var events: [(code: UInt16, down: Bool, at: Double)] = []
    var failDown = false
    var failUps = 0  // upcoming key-up posts that fail
    init(_ clock: FakeClock) { self.clock = clock }
    func post(_ code: UInt16, down: Bool) throws {
        if down && failDown { throw ProbeError("fake key-down failure") }
        if !down && failUps > 0 { failUps -= 1; throw ProbeError("fake key-up failure") }
        events.append((code, down, clock.t))
    }
    /// Whether a fake game would see a key held at time t.
    func held(at t: Double) -> Bool { events.last(where: { $0.at <= t })?.down ?? false }
    var firstDown: Double? { events.first(where: { $0.down })?.at }
    var lastUp: Double? { events.last(where: { !$0.down })?.at }
}

/// Fake time advances only through sleep; scheduled releases fire at their exact deadline
/// even while the observer is stalled, like the shell's independent release queue.
final class FakeDriver: ProbeDriver {
    let clock: FakeClock
    let sink: FakeSink
    let log: Events
    var scene: (Double, FakeSink) -> Frame?
    var faultAt: (Double) -> String? = { _ in nil }
    var observerStall = 0.0
    var snapshots: [String] = []
    private var tick = 0
    private var pending: [(at: Double, lease: InputLease)] = []
    let dispatchLabel = "fake_sink"

    init(clock: FakeClock, sink: FakeSink, log: Events, scene: @escaping (Double, FakeSink) -> Frame?) {
        self.clock = clock
        self.sink = sink
        self.log = log
        self.scene = scene
    }

    func now() -> Double { clock.t }
    func sleep(_ seconds: Double) async { advance(to: clock.t + seconds) }
    func advance(to end: Double) {
        while let index = pending.indices.min(by: { pending[$0].at < pending[$1].at }), pending[index].at <= end {
            let next = pending.remove(at: index)
            clock.t = max(clock.t, next.at)
            next.lease.expire()
        }
        clock.t = end
    }
    func frames() -> [Frame] {
        var out: [Frame] = []
        while Double(tick) / 30 <= clock.t {
            if let frame = scene(Double(tick) / 30, sink) { out.append(frame) }
            tick += 1
        }
        return out
    }
    func scheduleRelease(_ lease: InputLease, at deadline: Double) {
        pending.append((deadline, lease))
        if observerStall > 0 { advance(to: clock.t + observerStall) }
    }
    func fault() -> String? { faultAt(clock.t) }
    func snapshot(_ name: String) { snapshots.append(name) }
    func emit(_ event: String, _ fields: [String: Any]) { log.rows.append((event, fields)) }
}

func frame(_ pts: Double, stream: String = "s", width: Int = 64, diff: Double) -> Frame {
    Frame(stream: stream, pts: pts, width: width, height: 36, diff: diff)
}

func quiet(_ pts: Double) -> Double { 0.2 + Double(Int(pts * 30) % 3) * 0.05 }

/// A fake game whose whole-frame change follows the fake key state 50 ms late.
func game(_ pts: Double, _ sink: FakeSink) -> Frame? {
    frame(pts, diff: sink.held(at: pts - 0.05) ? 20 : quiet(pts))
}

@main
struct MotorTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        checks += 1
    }
    static func fails(_ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch { return true }
    }

    static func main() async {
        print("M0 motor checks: fake clock, fake frames, recording sink.")
        print("DISPATCH-ONLY proof: not macOS event delivery, WoW handling or avatar movement.")
        arguments()
        leases()
        gates()
        responses()
        await batches()
        print("motor checks passed: \(checks)")
    }

    static func arguments() {
        let plan = try! parsePlan(envelopePlan)
        check(plan.count == 6 && plan.map(\.milliseconds) == [100, 100, 100, 200, 200, 200],
              "envelope: three primitives at 100 ms, then at 200 ms")
        let badPlans: [[String]] = [[], ["turn-left"], ["turn-left:150"], ["turn-left:0"], ["turn-left:-100"],
                                    ["turn-left:1e2"], ["turn-left:300"], ["jump:100"], ["strafe-left:100"],
                                    ["TURN-LEFT:100"], ["turn-left:100:1"], ["turn-left: 100"], ["forward:200 "],
                                    Array(repeating: "forward:100", count: 7)]
        for bad in badPlans { check(fails { _ = try parsePlan(bad) }, "invalid plan rejected: \(bad)") }

        check(try! parseCommand([]) == Command(mode: .preflight, profile: nil, plan: []), "no arguments is read-only preflight")
        check(try! parseCommand(["--dry-run"]) == Command(mode: .dryRun, profile: .arrows, plan: plan),
              "dry-run defaults to the envelope plan")
        check(try! parseCommand(["--execute", "--keys", "arrows", "turn-left:100"])
              == Command(mode: .execute, profile: .arrows, plan: [Pulse(primitive: .turnLeft, milliseconds: 100)]),
              "explicit execute parses")
        check(try! parseCommand(["--release", "--keys", "wasd"]) == Command(mode: .release, profile: .wasd, plan: []),
              "release parses")
        let badCommands: [[String]] = [
            ["--bogus"], ["execute"], ["--execute"], ["--execute", "turn-left:100"], ["--execute", "--keys", "arrows"],
            ["--execute", "--keys"], ["--execute", "--keys", "ijkl", "forward:100"],
            ["--execute", "--keys", "arrows", "--keys", "wasd", "forward:100"],
            ["--execute", "--keys", "arrows", "forward:300"], ["--execute", "--keys", "arrows", "--dry-run", "forward:100"],
            ["--release"], ["--release", "--keys", "arrows", "forward:100"], ["--preflight", "extra"],
            ["--preflight", "--keys", "arrows"], ["--dry-run", "--force"], ["--dry-run", "turn-left:250"]]
        for bad in badCommands { check(fails { _ = try parseCommand(bad) }, "invalid command rejected: \(bad)") }

        check(Primitive.allCases.map { KeyProfile.arrows.code($0) } == [123, 124, 126], "arrow allowlist is fixed")
        check(Primitive.allCases.map { KeyProfile.wasd.code($0) } == [0, 2, 13], "WASD allowlist is fixed")
    }

    static func makeLease(_ profile: KeyProfile = .arrows) -> (FakeClock, FakeSink, InputLease, Events) {
        let clock = FakeClock()
        let sink = FakeSink(clock)
        let events = Events()
        let lease = InputLease(profile: profile, sink: sink, clock: { clock.t }, emit: { events.rows.append(($0, $1)) })
        return (clock, sink, lease, events)
    }

    static func leases() {
        do {
            let (clock, sink, lease, events) = makeLease()
            let grant = try! lease.acquire(Pulse(primitive: .turnLeft, milliseconds: 100))
            check(sink.events.count == 1 && sink.events[0].down && sink.events[0].code == 123,
                  "dispatch-only: one key-down posted for turn-left")
            check(grant.deadline == 0.1, "deadline equals the pulse")
            clock.t = 0.099
            check(!lease.expire() && lease.isHolding, "no release before the deadline")
            clock.t = 0.1
            check(lease.expire() && !lease.isHolding, "release at the deadline")
            check(!lease.expire() && sink.events.count == 2 && !sink.events[1].down, "expiry is idempotent")
            let up = events.named("key_up").first
            check(up?["reason"] as? String == "expired" && up?["lateness_ms"] as? Int == 0 && up?["held_ms"] as? Int == 100,
                  "key-up records reason, hold and lateness")
        }
        do {
            let (_, sink, lease, _) = makeLease()
            _ = try! lease.acquire(Pulse(primitive: .turnLeft, milliseconds: 100))
            check(fails { _ = try lease.acquire(Pulse(primitive: .forward, milliseconds: 100)) }
                  && sink.events.count == 1 && lease.isHolding, "no compound input: one key at a time")
        }
        do {
            let (clock, sink, lease, events) = makeLease()
            _ = try! lease.acquire(Pulse(primitive: .forward, milliseconds: 200))
            clock.t = 0.05
            lease.cancel("operator_escape")
            check(sink.events.count == 2 && !sink.events[1].down && sink.events[1].at == 0.05,
                  "cancellation releases immediately")
            check(events.named("key_up").first?["reason"] as? String == "cancelled:operator_escape", "release reason recorded")
            check(lease.stopReason == "operator_escape", "stop reason recorded")
            check(fails { _ = try lease.acquire(Pulse(primitive: .forward, milliseconds: 100)) } && sink.events.count == 2,
                  "stop is sticky: no further commands")
            clock.t = 0.3
            lease.cancel("second")
            check(!lease.expire() && lease.stopReason == "operator_escape" && sink.events.count == 2,
                  "later expiry/cancel adds no input and keeps the first reason")
        }
        do {
            let (clock, sink, lease, _) = makeLease()
            for index in 0..<6 {
                _ = try! lease.acquire(Pulse(primitive: .turnRight, milliseconds: 100))
                clock.t += 0.1
                lease.expire()
                check(!lease.isHolding, "budget pulse \(index + 1) released")
            }
            check(fails { _ = try lease.acquire(Pulse(primitive: .turnRight, milliseconds: 100)) }
                  && sink.events.count == 12 && lease.pulsesUsed == 6, "command budget: a seventh pulse is refused")
        }
        do {
            let (_, sink, lease, _) = makeLease()
            check(fails { _ = try lease.acquire(Pulse(primitive: .forward, milliseconds: 1000)) } && sink.events.isEmpty,
                  "lease re-checks the duration allowlist")
        }
        do {
            let (_, sink, lease, _) = makeLease()
            sink.failDown = true
            check(fails { _ = try lease.acquire(Pulse(primitive: .forward, milliseconds: 100)) },
                  "key-down failure is an error")
            check(sink.events.count == 1 && !sink.events[0].down && !lease.isHolding,
                  "key-down failure still sends key-up")
            check(lease.stopReason == "key_down_failed", "key-down failure stops the batch")
        }
        do {
            let (clock, sink, lease, events) = makeLease()
            sink.failUps = 1
            _ = try! lease.acquire(Pulse(primitive: .forward, milliseconds: 100))
            clock.t = 0.1
            check(lease.expire() && events.named("key_up_failed").count == 1
                  && events.named("key_up").first?["attempt"] as? Int == 2, "a failed key-up is retried")
        }
        do {
            let (clock, sink, lease, events) = makeLease()
            sink.failUps = Limits.releaseAttempts
            _ = try! lease.acquire(Pulse(primitive: .forward, milliseconds: 100))
            clock.t = 0.1
            check(!lease.expire() && lease.isHolding && lease.stopReason == "release_unconfirmed"
                  && events.named("release_unconfirmed").count == 1, "persistent key-up failure is unconfirmed, not hidden")
            lease.cancel("exit")
            check(!lease.isHolding && sink.events.last?.down == false, "the exit path retries an unconfirmed release")
        }
        do {
            let (_, sink, lease, _) = makeLease(.wasd)
            _ = try! lease.acquire(Pulse(primitive: .turnRight, milliseconds: 100))
            check(sink.events[0].code == 2, "WASD profile maps turn-right to D")
        }
    }

    static func gates() {
        var gate = FrameGate(stream: "s", width: 64, height: 36)
        check(gate.blocker(now: 0) == "stale_or_stalled_frames", "no frame yet blocks commands")
        check(gate.admit(frame(1.0, diff: 1), now: 1.01) == .fresh && gate.blocker(now: 1.01) == nil, "current frame admits")
        check(gate.admit(frame(1.0, diff: 1), now: 1.02) == .duplicate, "duplicate frame detected")
        check(gate.admit(frame(0.9, diff: 1), now: 1.02) == .reordered, "reordered frame detected")
        check(gate.admit(frame(2.0, diff: 1), now: 1.5) == .future, "future frame rejected")
        check(gate.admit(frame(.nan, diff: 1), now: 1.5) == .invalid, "non-finite time rejected")
        check(gate.admit(frame(1.1, diff: .infinity), now: 1.5) == .invalid, "failed detector value rejected")
        check(gate.blocker(now: 1.34) == nil, "evidence stays current for 0.35 s")
        check(gate.blocker(now: 1.36) == "stale_or_stalled_frames", "rejected frames never refresh: a stall blocks")
        check(gate.admit(frame(1.2, diff: 1), now: 1.6) == .stale && gate.blocker(now: 1.6) != nil,
              "a 0.4 s old frame is stale and does not refresh")
        check(gate.admit(frame(1.7, diff: 1), now: 1.71) == .fresh && gate.blocker(now: 1.71) == nil, "new current frame restores")
        check(gate.admit(frame(1.8, width: 65, diff: 1), now: 1.81) == .geometry
              && gate.blocker(now: 1.81) == "geometry_changed", "geometry change blocks")
        check(gate.admit(frame(1.9, diff: 1), now: 1.91) == .fresh && gate.blocker(now: 1.91) == "geometry_changed",
              "geometry change is sticky")
        check(gate.counts["duplicate"] == 1 && gate.counts["reordered"] == 1 && gate.counts["invalid"] == 2,
              "gate counts every verdict")
        var other = FrameGate(stream: "s", width: 64, height: 36)
        _ = other.admit(frame(1.0, diff: 1), now: 1.0)
        check(other.admit(frame(1.1, stream: "restarted", diff: 1), now: 1.1) == .identity
              && other.admit(frame(1.2, diff: 1), now: 1.2) == .fresh && other.blocker(now: 1.2) == "identity_changed",
              "capture identity change is sticky")
        check(meanAbsoluteDifference([0, 10], [10, 0]) == 10 && meanAbsoluteDifference([1], [1, 2]).isNaN,
              "frame difference is mean absolute grey change; mismatched sizes are invalid")
    }

    static func series(until end: Double, moving: (Double) -> Bool) -> [Frame] {
        (1...Int(end * 30)).map { tick in
            let pts = Double(tick) / 30
            return frame(pts, diff: moving(pts) ? 20 : 0.25)
        }
    }

    static func responses() {
        let base = [0.2, 0.25, 0.3, 0.2, 0.25, 0.3]
        let settled = analyseResponse(baseline: base, after: series(until: 1.6) { $0 >= 0.05 && $0 < 0.15 }, downAt: 0, upAt: 0.1)
        check(settled.verdict == "effect_then_settled" && settled.responseMs == 67 && settled.lastMotionAfterUpMs == 33,
              "visible response and settling are timed from frame PTS")
        check(analyseResponse(baseline: base, after: series(until: 1.6) { _ in false }, downAt: 0, upAt: 0.1).verdict
              == "no_effect_resolved", "no visible change is INCONCLUSIVE, not success")
        check(analyseResponse(baseline: base, after: series(until: 1.6) { $0 >= 0.05 && $0 < 1.3 }, downAt: 0, upAt: 0.1).verdict
              == "release_unclear", "motion continuing past the settle window is an unclear release")
        check(analyseResponse(baseline: base, after: series(until: 0.9) { $0 >= 0.05 && $0 < 0.15 }, downAt: 0, upAt: 0.1).verdict
              == "observation_incomplete", "a short observation cannot confirm settling")
        check(analyseResponse(baseline: Array(base.prefix(4)), after: series(until: 1.6) { _ in true }, downAt: 0, upAt: 0.1).verdict
              == "insufficient_baseline", "too few baseline frames")
        check(analyseResponse(baseline: [0, 10, 0, 10, 0, 10], after: series(until: 1.6) { $0 < 0.15 }, downAt: 0, upAt: 0.1).verdict
              == "no_effect_resolved", "a noisy scene raises the threshold instead of inventing an effect")
    }

    static func run(_ plan: [String] = envelopePlan,
                    scene: @escaping (Double, FakeSink) -> Frame? = game,
                    configure: (FakeDriver, FakeSink, InputLease) -> Void = { _, _, _ in })
        async -> (BatchResult, FakeSink, FakeDriver, InputLease) {
        let clock = FakeClock()
        let sink = FakeSink(clock)
        let log = Events()
        let driver = FakeDriver(clock: clock, sink: sink, log: log, scene: scene)
        let lease = InputLease(profile: .arrows, sink: sink, clock: { clock.t }, emit: driver.emit)
        configure(driver, sink, lease)
        let result = await runBatch(try! parsePlan(plan), lease: lease,
                                    gate: FrameGate(stream: "s", width: 64, height: 36), driver: driver)
        return (result, sink, driver, lease)
    }

    static func pairs(_ sink: FakeSink) -> [(down: Double, up: Double)] {
        stride(from: 0, to: sink.events.count - 1, by: 2).map { (sink.events[$0].at, sink.events[$0 + 1].at) }
    }

    static func batches() async {
        do {
            let (result, sink, driver, lease) = await run(configure: { driver, _, _ in driver.observerStall = 0.4 })
            check(result.outcome == "COMPLETED_PENDING_MANUAL_LABELS", "full plan completes pending manual labels")
            check(sink.events.map(\.code) == [123, 123, 124, 124, 126, 126, 123, 123, 124, 124, 126, 126]
                  && sink.events.enumerated().allSatisfy { $0.element.down == ($0.offset % 2 == 0) },
                  "dispatch-only: six isolated down/up pairs in plan order")
            check(zip(pairs(sink), [0.1, 0.1, 0.1, 0.2, 0.2, 0.2]).allSatisfy { abs($0.0.up - $0.0.down - $0.1) < 1e-9 },
                  "each key-up lands at its deadline while the observer is stalled for 400 ms")
            check(result.pulses.allSatisfy { $0["visual_effect"] as? String == "effect_then_settled" }
                  && result.pulses.allSatisfy { ($0["visible_response_ms"] as? Int).map { (50...90).contains($0) } ?? false },
                  "fake-game response timed after each key-down")
            check(result.pulses.allSatisfy { $0["avatar_movement"] as? String == "UNLABELLED" && $0["dispatch"] as? String == "fake_sink" },
                  "reports keep dispatch, visual effect and avatar movement separate")
            check(driver.snapshots.count == 12 && lease.pulsesUsed == 6 && !lease.isHolding, "evidence frames and budget accounted")
            let trace = result.pulses[0]["trace"] as? [[Double]] ?? []
            check(trace.count == (result.pulses[0]["baseline_frames"] as? Int ?? -1) + (result.pulses[0]["window_frames"] as? Int ?? -1)
                  && trace.allSatisfy { $0.count == 3 && $0[1] >= 0 } && trace.contains { $0[0] > 0 && $0[2] == 20 },
                  "per-frame trace keeps capture time, admission age and change for audit")
        }
        do {
            let (result, sink, _, _) = await run(["forward:200", "turn-left:100"], scene: { pts, sink in
                sink.firstDown.map { pts < $0 + 0.02 } ?? true ? game(pts, sink) : nil
            })
            check(result.outcome == "STOPPED_stale_or_stalled_frames" && sink.events.count == 2,
                  "detector stall mid-hold stops the batch after one pulse")
            check(abs(pairs(sink)[0].up - pairs(sink)[0].down - 0.2) < 1e-9,
                  "key-up does not wait for the stalled detector")
        }
        for (name, scene) in [("geometry_changed", { (pts: Double, sink: FakeSink) -> Frame? in
                                    let late = sink.firstDown.map { pts >= $0 + 0.05 } ?? false
                                    return frame(pts, width: late ? 65 : 64, diff: quiet(pts)) }),
                              ("identity_changed", { (pts: Double, sink: FakeSink) -> Frame? in
                                    let late = sink.firstDown.map { pts >= $0 + 0.05 } ?? false
                                    return frame(pts, stream: late ? "restarted" : "s", diff: quiet(pts)) })] {
            let (result, sink, driver, _) = await run(["forward:200", "turn-left:100"], scene: scene)
            check(result.outcome == "STOPPED_" + name && sink.events.count == 2, "\(name) mid-hold stops the batch")
            check(pairs(sink)[0].up - pairs(sink)[0].down < 0.1, "\(name) releases before the 200 ms deadline")
            check(driver.log.named("key_up").first?["reason"] as? String == "cancelled:" + name, "\(name) release reason")
        }
        do {
            let (result, sink, _, _) = await run(["forward:200", "turn-left:100"], configure: { driver, sink, _ in
                driver.faultAt = { t in sink.firstDown.map { t >= $0 + 0.03 } ?? false ? "focus_changed" : nil }
            })
            check(result.outcome == "STOPPED_focus_changed" && sink.events.count == 2
                  && pairs(sink)[0].up - pairs(sink)[0].down < 0.1, "focus change mid-hold releases early and stops")
        }
        do {
            let (result, sink, _, _) = await run(configure: { driver, _, _ in driver.faultAt = { _ in "operator_escape" } })
            check(result.outcome == "STOPPED_operator_escape" && sink.events.isEmpty, "emergency stop before input sends nothing")
        }
        do {
            let (result, sink, driver, _) = await run(scene: { _, _ in nil })
            check(result.outcome == "STOPPED_stale_or_stalled_frames" && sink.events.isEmpty && driver.clock.t >= Limits.firstFrameWait,
                  "no frames: waits the bounded first-frame window, then stops without input")
        }
        let blocked: [(String, (Double, FakeSink) -> Frame?, String)] = [
            ("duplicate", { _, _ in frame(0, diff: 1) }, "duplicate"),
            ("reordered", { pts, _ in frame(pts == 0 ? 0 : -0.01, diff: 1) }, "reordered"),
            ("future", { pts, _ in frame(pts + 1, diff: 1) }, "future"),
            ("stale", { pts, _ in frame(pts - 0.5, diff: 1) }, "stale"),
            ("geometry before input", { pts, _ in frame(pts, width: pts > 0.5 ? 65 : 64, diff: 1) }, "geometry_changed")]
        for (name, scene, verdict) in blocked {
            let (result, sink, _, _) = await run(scene: scene)
            check(result.outcome.hasPrefix("STOPPED_") && sink.events.isEmpty && (result.frameCounts[verdict] ?? 0) > 0,
                  "\(name) frames block every command")
        }
        do {
            let (result, sink, _, _) = await run(["turn-left:100", "turn-right:100"], scene: { pts, sink in
                let lingering = sink.lastUp.map { pts < $0 + 1.2 } ?? false
                return frame(pts, diff: sink.held(at: pts - 0.05) || lingering ? 20 : quiet(pts))
            })
            check(result.outcome == "STOPPED_release_unclear" && sink.events.count == 2,
                  "motion after key-up stops the batch as an unclear release")
        }
        do {
            let (result, sink, _, lease) = await run(scene: { pts, _ in frame(pts, diff: quiet(pts)) })
            check(result.outcome == "INCONCLUSIVE" && sink.events.count == 12 && lease.pulsesUsed == 6,
                  "no visible effect: INCONCLUSIVE after the fixed plan, never a longer pulse")
        }
        do {
            let (result, sink, _, lease) = await run(configure: { _, sink, _ in sink.failUps = 1000 })
            check(result.outcome == "HOLD_RELEASE_UNCONFIRMED" && sink.events.count == 1 && lease.isHolding,
                  "unconfirmed release is reported as a HOLD and stops further input")
            sink.failUps = 0
            lease.cancel("exit")
            check(!lease.isHolding && sink.events.count == 2, "exit path releases once the sink recovers")
        }
        do {
            let (result, sink, _, _) = await run(["forward:100"], configure: { _, _, lease in
                _ = try! lease.acquire(Pulse(primitive: .forward, milliseconds: 100))
                lease.cancel("earlier_stop")
            })
            check(result.outcome == "STOPPED_earlier_stop" && sink.events.count == 2, "a stopped lease refuses a new batch")
        }
        do {
            let (result, sink, _, _) = await run(["forward:100"], configure: { driver, _, lease in
                for _ in 0..<Limits.maxPulses {
                    _ = try! lease.acquire(Pulse(primitive: .forward, milliseconds: 100))
                    driver.clock.t += 0.1
                    lease.expire()
                }
            })
            check(result.outcome == "STOPPED_acquire_refused" && sink.events.count == 12,
                  "a spent command budget refuses the batch's pulse")
        }
    }
}
