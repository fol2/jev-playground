// Offline M1 checks with fake time, a simulated world and synthetic images. They prove the
// argument, budget, tracker and loop logic: SIMULATION ONLY. Nothing here shows that WoW
// applies the keys, that the tracker follows a real 3D object or that the avatar faces it.
import Foundation

final class FakeClock { var t = 0.0 }

/// A sink that can fail key-ups, wrapping the simulated world.
final class Flaky: KeySink {
    let inner: KeySink
    var failUps = 0
    init(_ inner: KeySink) { self.inner = inner }
    func post(_ code: UInt16, down: Bool) throws {
        if !down && failUps > 0 { failUps -= 1; throw ProbeError("fake key-up failure") }
        try inner.post(code, down: down)
    }
}

/// Fake time advances only through sleep; scheduled releases fire at their exact deadline
/// even while the observer is stalled, like the shell's independent release queue.
final class FakeSeekDriver: SeekDriver {
    let clock: FakeClock
    let world: SimWorld
    var rows: [(name: String, fields: [String: Any])] = []
    var frameAt: (Double) -> Frame? = { Frame(stream: "s", pts: $0, width: 64, height: 36, diff: 0.2) }
    var faultAt: (Double) -> String? = { _ in nil }
    var observerStall = 0.0
    var predictions: [Prediction] = []
    var earlyFramesOffered = 0  // frames older than notBefore that reached sight: must stay 0
    private var tick = 0
    private var lastFrame: Double?
    private var pending: [(at: Double, lease: InputLease)] = []
    let dispatchLabel = "fake_world"

    init(clock: FakeClock, world: SimWorld) {
        self.clock = clock
        self.world = world
    }

    func named(_ name: String) -> [[String: Any]] { rows.filter { $0.name == name }.map(\.fields) }
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
            if let frame = frameAt(Double(tick) / 30) {
                out.append(frame)
                lastFrame = frame.pts
            }
            tick += 1
        }
        return out
    }
    func sight(_ prediction: Prediction?, notBefore: Double) -> Sighting? {
        if let prediction { predictions.append(prediction) }
        guard let lastFrame else { return nil }
        guard lastFrame >= notBefore else { earlyFramesOffered += 1; return nil }  // the shell's rule
        return world.sighting(at: lastFrame)
    }
    func scheduleRelease(_ lease: InputLease, at deadline: Double) {
        pending.append((deadline, lease))
        if observerStall > 0 { advance(to: clock.t + observerStall) }
    }
    func fault() -> String? { faultAt(clock.t) }
    func snapshot(_ name: String) {}
    func emit(_ event: String, _ fields: [String: Any]) { rows.append((event, fields)) }
}

/// Deterministic texture: smooth enough to match at nearby scales, varied enough to be unique.
func texture(width: Int, height: Int, seed: UInt64) -> Grey {
    var state = seed
    var noise = (0..<(width * height)).map { _ -> Float in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 56)
    }
    for _ in 0..<2 {  // box blur twice
        var blurred = noise
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                var sum: Float = 0
                for j in -1...1 { for i in -1...1 { sum += noise[(y + j) * width + x + i] } }
                blurred[y * width + x] = sum / 9
            }
        }
        noise = blurred
    }
    return Grey(width: width, height: height, pixels: noise)
}

func paste(_ patch: Grey, into image: Grey, x: Int, y: Int) -> Grey {
    var pixels = image.pixels
    for j in 0..<patch.height { for i in 0..<patch.width { pixels[(y + j) * image.width + x + i] = patch.pixels[j * patch.width + i] } }
    return Grey(width: image.width, height: image.height, pixels: pixels)
}

@main
struct SeekTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        checks += 1
    }
    static func fails(_ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch { return true }
    }

    static func main() async {
        print("M1 seek checks: fake clock, simulated world, synthetic images.")
        print("SIMULATION-ONLY proof: not WoW input handling, real-object tracking or avatar facing.")
        arguments()
        budgets()
        tracking()
        await loops()
        print("seek checks passed: \(checks)")
    }

    static func arguments() {
        check(try! parseSeek([]).mode == .preflight, "no arguments is the read-only preflight")
        check(try! parseSeek(["--dry-run"]).mode == .dryRun, "dry-run parses")
        check(try! parseSeek(["--look"]).mode == .look, "look parses")
        let good = ["--execute", "--keys", "wqe", "--look", "f.png", "--box", "10,20,40,30"]
        let command = try! parseSeek(good)
        check(command.profile == .wqe && command.look == "f.png" && command.box == Box(x: 10, y: 20, width: 40, height: 30)
              && command.growth == 1.6, "execute carries keys, frame, box and the default visible stop")
        check(try! parseSeek(good + ["--stop-growth", "2"]).growth == 2, "stop growth is settable within bounds")
        let box = ["--execute", "--keys", "wqe", "--look", "f.png", "--box"]
        let refused: [[String]] = [["--bogus"], ["--dry-run", "x"], ["--look", "--keys", "wqe"], ["--execute"],
                    ["--execute", "--look", "f.png", "--box", "1,1,20,20"],
                    ["--execute", "--keys", "wqe", "--box", "1,1,20,20"],
                    ["--execute", "--keys", "wqe", "--look", "f.png"],
                    ["--execute", "--keys", "qwe", "--look", "f.png", "--box", "1,1,20,20"],
                    good + ["--keys", "wqe"], good + ["--stop-growth", "3"], good + ["--stop-growth", "nan"],
                    good + ["--stop-growth"], good + ["--extra", "1"],
                    box + ["1,1,8,20"],
                    box + ["-1,1,20,20"],
                    box + ["1,1,20"],
                    box + ["1,1,20.5,20"],
                    box + ["10,20,foo,40,30"],
                    box + ["10,20,40,30,"],
                    ["--execute", "--keys", "--look", "f.png", "--box", "1,1,20,20"]]
        for bad in refused {
            check(fails { _ = try parseSeek(bad) }, "refused before any effect: \(bad)")
        }
    }

    static func budgets() {
        let clock = FakeClock()
        let world = SimWorld(profile: .wqe, clock: { clock.t }, bearing: 0, distance: 20)
        let m0 = InputLease(profile: .wqe, sink: world, clock: { clock.t }, emit: { _, _ in })
        check(m0.refusal(Pulse(primitive: .forward, milliseconds: 250)) == "duration outside allowlist",
              "M0's default budget still refuses durations outside its fixed plan")
        let lease = InputLease(profile: .wqe, sink: world, clock: { clock.t }, emit: { _, _ in }, budget: SeekLimits.budget)
        check(lease.refusal(Pulse(primitive: .forward, milliseconds: 250)) == nil
              && lease.refusal(Pulse(primitive: .forward, milliseconds: 200)) != nil, "forward is one fixed pulse")
        check(lease.refusal(Pulse(primitive: .turnLeft, milliseconds: 60)) == nil
              && lease.refusal(Pulse(primitive: .turnRight, milliseconds: 250)) == nil
              && lease.refusal(Pulse(primitive: .turnLeft, milliseconds: 59)) != nil
              && lease.refusal(Pulse(primitive: .turnRight, milliseconds: 251)) != nil, "turns lie within 60-250 ms")
        for _ in 0..<10 {
            _ = try! lease.acquire(Pulse(primitive: .forward, milliseconds: 250))
            clock.t += 0.25
            lease.expire()
        }
        check(lease.refusal(Pulse(primitive: .forward, milliseconds: 250)) == "forward time budget spent"
              && fails { _ = try lease.acquire(Pulse(primitive: .forward, milliseconds: 250)) },
              "total forward time is capped at 2.5 s")
        for _ in 0..<5 {
            _ = try! lease.acquire(Pulse(primitive: .turnLeft, milliseconds: 240))
            clock.t += 0.24
            lease.expire()
        }
        check(lease.refusal(Pulse(primitive: .turnLeft, milliseconds: 60)) == "turn-left time budget spent"
              && lease.refusal(Pulse(primitive: .turnRight, milliseconds: 60)) == nil, "each turn direction has its own cap")
        for _ in 0..<5 {
            _ = try! lease.acquire(Pulse(primitive: .turnRight, milliseconds: 60))
            clock.t += 0.06
            lease.expire()
        }
        check(lease.pulsesUsed == 20 && lease.refusal(Pulse(primitive: .turnRight, milliseconds: 60)) == "command budget spent",
              "at most 20 pulses per lease")
        check(lease.spentMs == [.forward: 2500, .turnLeft: 1200, .turnRight: 300], "spent time is accounted per primitive")
    }

    static func tracking() {
        let scene = texture(width: 160, height: 90, seed: 7)
        let target = cropped(texture(width: 60, height: 60, seed: 99), Box(x: 20, y: 20, width: 16, height: 16))!
        check(cropped(scene, Box(x: 150, y: 0, width: 16, height: 16)) == nil, "a box outside the frame is refused")
        check(resized(target, width: 24, height: 20).pixels.count == 480, "resampling yields the requested size")
        let designated = paste(target, into: scene, x: 40, y: 30)
        let found = locate(target, in: designated, scales: [1], near: (80, 45), reach: (160, 90))!
        check(abs(found.x - 48) < 0.01 && abs(found.y - 38) < 0.01 && found.score > 0.99 && found.runnerUp < 0.9,
              "full search finds the designation, uniquely")

        let tracker = Tracker(template: target, start: found, minScore: 0.6)
        let turned = paste(target, into: scene, x: 100, y: 32)
        let turn = Prediction(x: 48.0 / 160 - 0.5, shift: 0.4)
        let after = tracker.sight(turned, turn)!
        check(abs(after.x - 108) < 1 && abs(after.y - 40) < 1 && after.score > 0.95, "the predicted shift guides a large turn")
        let again = tracker.sight(turned, turn)!
        check(abs(again.x - 108) < 1 && again.score > 0.95,
              "searching another frame after the same pulse does not apply the shift twice (live run 2)")
        // Approach grows the target a little per step; the search follows up to 1.2x per sighting.
        _ = tracker.sight(paste(resized(target, width: 19, height: 19), into: scene, x: 98, y: 30), nil)
        let grown = tracker.sight(paste(resized(target, width: 23, height: 23), into: scene, x: 96, y: 28), nil)!
        check(abs(grown.scale - 1.44) <= 0.06 && grown.score > 0.8 && abs(grown.x - 107.5) < 2,
              "apparent growth is measured against the designation, step by step")
        let before = tracker.last.x
        let hidden = tracker.sight(scene, nil)
        check(hidden.map { $0.score < 0.6 } ?? true, "an occluded target scores below the loss threshold")
        check(tracker.last.x == before, "an unseen frame does not move the tracker")

        let twice = paste(target, into: designated, x: 110, y: 50)
        let repeated = locate(target, in: twice, scales: [1], near: (80, 45), reach: (160, 90))!
        check(repeated.score - repeated.runnerUp < 0.05, "a repeated pattern shows no margin, so it is not designated")
        let flat = Grey(width: 16, height: 16, pixels: [Float](repeating: 90, count: 256))
        check(locate(flat, in: scene, scales: [1], near: (80, 45), reach: (160, 90)) == nil, "a flat designation is refused")
    }

    static func seek(bearing: Double, distance: Double = 25, config: SeekConfig = SeekConfig(),
                     setup: (FakeSeekDriver, SimWorld, Flaky, InputLease) -> Void = { _, _, _, _ in })
        async -> (result: SeekResult, driver: FakeSeekDriver, world: SimWorld, lease: InputLease) {
        let clock = FakeClock()
        let world = SimWorld(profile: .wqe, clock: { clock.t }, bearing: bearing, distance: distance)
        let sink = Flaky(world)
        let driver = FakeSeekDriver(clock: clock, world: world)
        let lease = InputLease(profile: .wqe, sink: sink, clock: { clock.t }, emit: driver.emit, budget: SeekLimits.budget)
        setup(driver, world, sink, lease)
        let result = await runSeek(config, lease: lease, gate: FrameGate(stream: "s", width: 64, height: 36), driver: driver)
        return (result, driver, world, lease)
    }

    static func sound(_ run: (result: SeekResult, driver: FakeSeekDriver, world: SimWorld, lease: InputLease)) -> Bool {
        let presses = run.world.held
        let spent = run.lease.spentMs
        let released: Bool = !run.lease.isHolding && presses.allSatisfy { $0.up != nil } && presses.count == run.lease.pulsesUsed
        let bounded: Bool = presses.count <= 20 && spent[.forward, default: 0] <= 2500
            && spent[.turnLeft, default: 0] <= 1200 && spent[.turnRight, default: 0] <= 1200
        let onTime: Bool = run.driver.named("key_up").allSatisfy { ($0["lateness_ms"] as? Int ?? 99) <= 0 }
        let settled: Bool = run.result.pulses.allSatisfy { record in
            guard let after = record["after"] as? [String: Any], let pts = after["pts"] as? Double,
                  let up = record["up_at"] as? Double else { return true }
            return pts >= up + 0.3 - 1e-9  // decisions only on settled frames
        }
        return released && bounded && onTime && settled
    }

    static func phases(_ result: SeekResult) -> [String] { result.pulses.compactMap { $0["phase"] as? String } }
    static func keys(_ result: SeekResult) -> [String] { result.pulses.compactMap { $0["pulse"] as? String } }

    static func loops() async {
        do {
            let run = await seek(bearing: -25)
            check(run.result.outcome == "VISIBLE_STOP_REACHED_PENDING_LABELS" && sound(run), "left target: reached, released, bounded")
            check(keys(run.result).first?.hasPrefix("turn-left:") == true && phases(run.result).first == "centre",
                  "a target left of centre is centred with turn-left")
            check(run.result.facing?["verdict"] as? String == "consistent" && phases(run.result).contains("facing"),
                  "facing is checked separately after centring")
            check((run.result.final?.scale ?? 0) >= 1.6 && abs(run.result.final?.x ?? 1) <= 0.06,
                  "the visible stop is apparent growth with the target still centred")
            check(run.driver.earlyFramesOffered > 0,
                  "frames captured before the settle point are withheld from tracking, not just ignored after it")
            check(run.driver.predictions.first.map { $0.x < -0.2 && $0.shift > 0 } == true,
                  "a left turn predicts a rightward shift from the target's pre-pulse position")
            let turns = run.result.pulses.filter { ($0["phase"] as? String) == "centre" }
            check(turns.allSatisfy { record in
                guard let token = record["pulse"] as? String, let milliseconds = Int(token.split(separator: ":")[1]) else { return false }
                return SeekLimits.turnMs.contains(milliseconds)
            } && turns.count <= 6, "centring pulses stay within the turn allowlist and phase cap")
        }
        do {
            let run = await seek(bearing: 30)
            check(run.result.outcome == "VISIBLE_STOP_REACHED_PENDING_LABELS" && sound(run)
                  && keys(run.result).first?.hasPrefix("turn-right:") == true, "right target: centred with turn-right and reached")
        }
        do {
            let run = await seek(bearing: 0.5)
            check(run.result.outcome == "VISIBLE_STOP_REACHED_PENDING_LABELS" && phases(run.result).first == "facing"
                  && !keys(run.result).contains { $0.hasPrefix("turn") }, "an already centred target needs no turn")
        }
        do {
            let run = await seek(bearing: -25) { driver, _, _, _ in driver.observerStall = 0.4 }
            check(run.result.outcome == "VISIBLE_STOP_REACHED_PENDING_LABELS" && sound(run),
                  "a 400 ms observer stall after each key-down does not delay any release")
        }
        do {
            var window = (0.0, 0.0)
            let run = await seek(bearing: 0) { driver, world, _, _ in
                world.hidden = { t in
                    if window.0 == 0, let first = world.held.first(where: { $0.primitive == .forward })?.up { window = (first + 0.25, first + 0.85) }
                    return t >= window.0 && t < window.1
                }
            }
            let downs = run.world.held.map(\.down)
            check(run.result.outcome == "VISIBLE_STOP_REACHED_PENDING_LABELS" && sound(run)
                  && !run.driver.named("target_reacquired").isEmpty, "a 0.5 s occlusion is waited out and the loop resumes")
            check(!downs.contains { $0 >= window.0 && $0 < window.1 }, "no key is pressed while the target is unseen")
        }
        do {
            var lostAt = 0.0
            let run = await seek(bearing: 0) { _, world, _, _ in
                world.hidden = { t in
                    if lostAt == 0, let first = world.held.first(where: { $0.primitive == .forward })?.up { lostAt = first + 0.25 }
                    return lostAt > 0 && t >= lostAt
                }
            }
            check(run.result.outcome == "STOPPED_target_lost" && sound(run) && !run.world.held.contains { $0.down >= lostAt },
                  "a longer loss stops with no further input")
        }
        do {
            let run = await seek(bearing: -25) { _, world, _, _ in world.turnsApplied = false }
            check(run.result.outcome == "STOPPED_no_visible_turn_response" && sound(run) && run.lease.pulsesUsed == 2,
                  "turns with no visible effect stop after two pulses, never longer ones")
        }
        do {
            let run = await seek(bearing: -30) { _, world, _, _ in world.turnRate = 900 }
            let outcome = run.result.outcome
            check((outcome == "STOPPED_centring_not_converged" || outcome == "STOPPED_target_lost") && sound(run)
                  && run.lease.pulsesUsed <= 6, "a badly fitted turn rate stops instead of oscillating")
        }
        do {
            let run = await seek(bearing: 0) { _, world, _, _ in world.forwardSkew = 180 }
            check(run.result.outcome == "STOPPED_facing_inconsistent" && sound(run) && run.lease.pulsesUsed == 1,
                  "forward that shrinks the centred target fails the facing check")
        }
        do {
            let run = await seek(bearing: 0) { _, world, _, _ in world.forwardSkew = 90 }
            check(run.result.outcome != "VISIBLE_STOP_REACHED_PENDING_LABELS" && sound(run),
                  "walking sideways never reports the visible stop")
        }
        do {
            let run = await seek(bearing: 0, distance: 80)
            check(run.result.outcome == "STOPPED_budget_spent_before_visible_stop" && sound(run)
                  && run.lease.spentMs[.forward] == 2500, "a far target spends the forward budget and stops short")
        }
        do {
            let run = await seek(bearing: -25) { driver, world, _, _ in
                driver.faultAt = { t in world.held.first.map { t >= $0.down + 0.03 } == true ? "focus_changed" : nil }
            }
            let up = run.driver.named("key_up").first
            check(run.result.outcome == "STOPPED_focus_changed" && sound(run) && run.lease.pulsesUsed == 1
                  && (up?["reason"] as? String) == "cancelled:focus_changed", "a focus change mid-pulse releases at once and stops")
        }
        do {
            let run = await seek(bearing: -25) { driver, _, _, _ in
                driver.frameAt = { pts in pts < 2 ? Frame(stream: "s", pts: pts, width: 64, height: 36, diff: 0.2) : nil }
            }
            check(run.result.outcome == "STOPPED_stale_or_stalled_frames" && sound(run), "stalled capture stops the loop")
        }
        do {
            let run = await seek(bearing: -25) { driver, _, _, _ in
                driver.frameAt = { pts in Frame(stream: "s", pts: pts, width: pts < 1.5 ? 64 : 80, height: 36, diff: 0.2) }
            }
            check(run.result.outcome == "STOPPED_geometry_changed" && sound(run), "a window geometry change stops the loop")
        }
        do {
            let run = await seek(bearing: -25) { driver, _, _, _ in driver.frameAt = { _ in nil } }
            check(run.result.outcome == "STOPPED_stale_or_stalled_frames" && run.world.held.isEmpty, "no frame, no input")
        }
        do {
            let run = await seek(bearing: -25) { _, world, _, _ in world.hidden = { _ in true } }
            check(run.result.outcome == "STOPPED_target_lost" && run.world.held.isEmpty, "an unseen designation sends nothing")
        }
        do {
            let run = await seek(bearing: -25) { _, _, sink, _ in sink.failUps = 1000 }
            check(run.result.outcome == "HOLD_RELEASE_UNCONFIRMED" && run.lease.isHolding && run.world.held.count == 1,
                  "an unconfirmed release is a HOLD and nothing further is pressed")
        }
    }
}
