// M1 closed-loop core for issue #5: from one manually designated target, turn until it is
// centred, check that a forward pulse keeps it centred and does not shrink it (facing, not
// only camera), then approach until a visible stop condition. Pure Foundation with injected
// time, frames, sightings and key sink; it reuses M0's lease, budget and frame gate.
// The tracker matches the designation's own pixels: an oracle that removes recognition as a
// confound, never proof of target identity. SeekProbe.swift supplies capture, keys and files.
import Foundation

/// Controller constants. Turn rate and dead time are fitted to M0 run 2 (Q/E held 100 and
/// 200 ms shifted distant scenery 0.09-0.16 and 0.33 screen widths). The loop re-observes
/// after every pulse, so fit error costs pulses; a bad fit stops, it never lengthens pulses.
struct SeekConfig {
    var turnRate = 2.1          // screen widths per second of held turn after the dead time
    var dead = 0.04             // seconds of each hold with no visible turn
    var gain = 0.8              // aim short: overshoot costs a pulse and a direction change
    var tolerance = 0.03        // centred: |x| within this (x runs -0.5 left edge ... 0.5 right)
    var approachTolerance = 0.06
    var growth = 1.6            // visible stop: apparent size vs the designation, not a distance
    var stopRow: Double?        // M2 visible stop instead: the target's ground row (y, from the middle) reaching this;
                                // an unseen ground row is -0.5, the top: not yet
    var minScore = 0.6          // tracker correlation below this is an unseen target
    var settle = 0.3            // decide only on frames this long after key-up (M0: motion ended <= 68 ms)
    var lossWait = 1.0          // short occlusion allowance, with no input, before stopping
    var maxCentring = 6         // turn pulses per centring phase

    /// What approach should increase: apparent scale (M1) or the selection circle's row (M2),
    /// which falls down the screen as the unit gets closer.
    func progress(_ sighting: Sighting) -> Double { stopRow == nil ? sighting.scale : sighting.y }
    func reached(_ sighting: Sighting) -> Bool { progress(sighting) >= (stopRow ?? growth) }
    var slack: Double { stopRow == nil ? 0.03 : 0.005 }  // how far a forward pulse may set progress back
}

enum SeekLimits {
    static let turnMs = 60...250
    static let forwardMs = 250
    static let growth = 1.2...2.5
    static let stopRow = 0.25...0.65  // M2 stop row, fraction of the height from the top
    static let boxSide = 16...240  // designation box side in look-frame pixels
    // ponytail: ~15 yards of forward at WoW's 7 yd/s; widen only with new owner authority.
    static let budget = Budget(maxPulses: 20, allows: { pulse in
        pulse.primitive == .forward ? pulse.milliseconds == forwardMs : turnMs.contains(pulse.milliseconds)
    }, maxTotalMs: [.turnLeft: 1200, .turnRight: 1200, .forward: 2500])
}

struct Box: Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct SeekCommand: Equatable {
    enum Mode: String {
        case preflight = "--preflight", dryRun = "--dry-run", look = "--look", execute = "--execute", target = "--target"
    }
    let mode: Mode
    var profile: KeyProfile?
    var look: String?
    var box: Box?
    var growth = SeekConfig().growth
    var stopRow = 0.45  // --target only: the selection circle's bottom row, fraction of the height from the top
}

/// Parses everything before any effect. Missing or unknown arguments never default to input.
func parseSeek(_ arguments: [String]) throws -> SeekCommand {
    guard let first = arguments.first else { return SeekCommand(mode: .preflight) }
    guard let mode = SeekCommand.Mode(rawValue: first) else { throw ProbeError("unknown mode '\(first.prefix(40))'") }
    var command = SeekCommand(mode: mode)
    var seen: Set<String> = []
    var rest = arguments.dropFirst()
    while let option = rest.popFirst() {
        guard mode == .execute || mode == .target else { throw ProbeError("\(mode.rawValue) takes no arguments") }
        guard seen.insert(option).inserted, let value = rest.popFirst(), !value.hasPrefix("-") else {
            throw ProbeError("'\(option.prefix(40))' is repeated or has no value")
        }
        switch option {
        case "--keys":
            guard let profile = KeyProfile(rawValue: value) else { throw ProbeError("--keys needs exactly one of: arrows, wasd, wqe") }
            command.profile = profile
        case "--look" where mode == .execute:
            command.look = value
        case "--stop-row" where mode == .target:
            guard let row = Double(value), SeekLimits.stopRow.contains(row) else {
                throw ProbeError("--stop-row must lie within \(SeekLimits.stopRow) of the height from the top")
            }
            command.stopRow = row
        case "--box" where mode == .execute:
            let parts = value.split(separator: ",", omittingEmptySubsequences: false).map { Int($0) ?? -1 }
            guard parts.count == 4, parts[0] >= 0, parts[1] >= 0,
                  SeekLimits.boxSide.contains(parts[2]), SeekLimits.boxSide.contains(parts[3]) else {
                throw ProbeError("--box needs X,Y,W,H in look-frame pixels with sides \(SeekLimits.boxSide)")
            }
            command.box = Box(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        case "--stop-growth" where mode == .execute:
            guard let growth = Double(value), SeekLimits.growth.contains(growth) else {
                throw ProbeError("--stop-growth must lie within \(SeekLimits.growth)")
            }
            command.growth = growth
        default:
            throw ProbeError("unexpected option '\(option.prefix(40))'")
        }
    }
    if mode == .execute || mode == .target {
        guard command.profile != nil else { throw ProbeError("\(mode.rawValue) requires --keys arrows|wasd|wqe, confirmed in-game") }
    }
    if mode == .execute {
        guard command.look != nil, command.box != nil else {
            throw ProbeError("--execute requires --look FRAME and --box X,Y,W,H designating the target")
        }
    }
    return command
}

/// A grey image, row-major from the top-left.
struct Grey {
    let width: Int
    let height: Int
    let pixels: [Float]
}

func cropped(_ image: Grey, _ box: Box) -> Grey? {
    guard box.x >= 0, box.y >= 0, box.width > 0, box.height > 0,
          box.x + box.width <= image.width, box.y + box.height <= image.height else { return nil }
    var pixels: [Float] = []
    pixels.reserveCapacity(box.width * box.height)
    for y in box.y..<(box.y + box.height) {
        let start: Int = y * image.width + box.x
        pixels.append(contentsOf: image.pixels[start..<(start + box.width)])
    }
    return Grey(width: box.width, height: box.height, pixels: pixels)
}

func resized(_ image: Grey, width: Int, height: Int) -> Grey {
    var pixels = [Float](repeating: 0, count: width * height)
    let sx = Double(image.width) / Double(width), sy = Double(image.height) / Double(height)
    for y in 0..<height {
        let fy = min(max((Double(y) + 0.5) * sy - 0.5, 0), Double(image.height - 1))
        let y0 = Int(fy), y1 = min(y0 + 1, image.height - 1), wy = Float(fy - Double(y0))
        for x in 0..<width {
            let fx = min(max((Double(x) + 0.5) * sx - 0.5, 0), Double(image.width - 1))
            let x0 = Int(fx), x1 = min(x0 + 1, image.width - 1), wx = Float(fx - Double(x0))
            let top = image.pixels[y0 * image.width + x0] * (1 - wx) + image.pixels[y0 * image.width + x1] * wx
            let bottom = image.pixels[y1 * image.width + x0] * (1 - wx) + image.pixels[y1 * image.width + x1] * wx
            pixels[y * width + x] = top * (1 - wy) + bottom * wy
        }
    }
    return Grey(width: width, height: height, pixels: pixels)
}

/// Best template centre (image pixels) and scale. runnerUp is the best score centred outside
/// the matched box: a small margin means a repeated pattern, not a unique target.
struct Match {
    let x: Double
    let y: Double
    let scale: Double
    let score: Double
    let runnerUp: Double
}

/// Normalised cross-correlation of the designation, resampled to each scale, over centres
/// within `reach` of `near`. ponytail: brute force, ~0.1 s at 320 px with -O; use an
/// image pyramid if live tracking ever needs every frame.
func locate(_ template: Grey, in image: Grey, scales: [Double], near: (x: Double, y: Double),
            reach: (x: Double, y: Double)) -> Match? {
    var candidates: [(score: Double, x: Double, y: Double, scale: Double, halfWidth: Double, halfHeight: Double)] = []
    for scale in scales {
        let tw = Int((Double(template.width) * scale).rounded()), th = Int((Double(template.height) * scale).rounded())
        guard tw >= 4, th >= 4, tw <= image.width, th <= image.height else { continue }
        let resampled = resized(template, width: tw, height: th).pixels
        let mean = resampled.reduce(0, +) / Float(resampled.count)
        let zero = resampled.map { Double($0 - mean) }
        let norm = zero.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 1e-3 else { continue }  // a flat template matches everything and nothing
        let n = Double(tw * th)
        let x0 = max(0, Int((near.x - reach.x - Double(tw) / 2).rounded(.down)))
        let x1 = min(image.width - tw, Int((near.x + reach.x - Double(tw) / 2).rounded(.up)))
        let y0 = max(0, Int((near.y - reach.y - Double(th) / 2).rounded(.down)))
        let y1 = min(image.height - th, Int((near.y + reach.y - Double(th) / 2).rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { continue }
        image.pixels.withUnsafeBufferPointer { pixels in
            zero.withUnsafeBufferPointer { centred in
                for oy in y0...y1 {
                    for ox in x0...x1 {
                        var sum = 0.0, squares = 0.0, cross = 0.0
                        for j in 0..<th {
                            let row = (oy + j) * image.width + ox, templateRow = j * tw
                            for i in 0..<tw {
                                let value = Double(pixels[row + i])
                                sum += value
                                squares += value * value
                                cross += value * centred[templateRow + i]
                            }
                        }
                        let variance = squares - sum * sum / n
                        let score = variance > 1e-6 ? cross / (variance.squareRoot() * norm) : 0
                        candidates.append((score, Double(ox) + Double(tw) / 2, Double(oy) + Double(th) / 2, scale,
                                           Double(tw) / 2, Double(th) / 2))
                    }
                }
            }
        }
    }
    guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }
    let runnerUp = candidates.filter { abs($0.x - best.x) > best.halfWidth || abs($0.y - best.y) > best.halfHeight }
        .map(\.score).max() ?? -1
    return Match(x: best.x, y: best.y, scale: best.scale, score: best.score, runnerUp: runnerUp)
}

/// Where to search after a pulse: the target's x before it (fraction from the middle) and the
/// shift the controller predicts. Absolute, so searching several frames after one pulse never
/// applies the shift twice (live run 2 lost its target that way).
struct Prediction {
    let x: Double
    let shift: Double
}

/// Follows the designation: around the prediction, else its last confident match. Only
/// confident matches move it, so an occluder cannot drag the search away.
final class Tracker {
    let template: Grey
    let minScore: Double
    private(set) var last: Match

    init(template: Grey, start: Match, minScore: Double) {
        self.template = template
        self.last = start
        self.minScore = minScore
    }

    func sight(_ image: Grey, _ prediction: Prediction?) -> Match? {
        let width = Double(image.width)
        let match = locate(template, in: image, scales: [0.95, 1, 1.05, 1.1, 1.15, 1.2].map { $0 * last.scale },
                           near: (prediction.map { ($0.x + $0.shift + 0.5) * width } ?? last.x, last.y),
                           reach: (0.06 * width + 0.5 * abs(prediction?.shift ?? 0) * width, 0.12 * Double(image.height)))
        if let match, match.score >= minScore { last = match }
        return match
    }
}

/// The designated target in one frame: centre as a fraction of the frame from its middle
/// (x: -0.5 left edge ... 0.5 right edge), apparent scale against the designation, score.
struct Sighting {
    let pts: Double
    let x: Double
    let y: Double
    let scale: Double
    let score: Double
}

func r3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

func fields(_ sighting: Sighting) -> [String: Any] {
    ["pts": sighting.pts, "x": r3(sighting.x), "y": r3(sighting.y), "scale": r3(sighting.scale), "score": r3(sighting.score)]
}

protocol SeekDriver: ProbeDriver {
    /// The target in the newest frame, searched around the prediction (else its last confident
    /// position). nil before any frame and for a frame captured before `notBefore`, which must
    /// not update tracking state: a mid-pulse frame would shift the next search's scale and height.
    func sight(_ prediction: Prediction?, notBefore: Double) -> Sighting?
}

struct SeekResult {
    let outcome: String
    let pulses: [[String: Any]]
    let facing: [String: Any]?
    let final: Sighting?
    let frameCounts: [String: Int]
}

/// Centre, check facing, approach. Every decision uses a confident sighting from a fresh frame
/// captured `settle` after the previous key-up; every stop cancels the lease, which releases
/// a held key first. No release waits for this loop or the tracker.
func runSeek(_ config: SeekConfig, lease: InputLease, gate start: FrameGate, driver: SeekDriver) async -> SeekResult {
    var gate = start
    var pulses: [[String: Any]] = []
    var facing: [String: Any]?
    var latest: Sighting?
    var reached = false

    func check() -> String? {
        let now = driver.now()
        for frame in driver.frames() {
            let verdict = gate.admit(frame, now: now)
            if verdict != .fresh && verdict != .stale {
                driver.emit("frame_rejected", ["verdict": verdict.rawValue, "pts": frame.pts.isFinite ? frame.pts : -1])
            }
        }
        return lease.stopReason ?? gate.blocker(now: now) ?? driver.fault()
    }

    /// No input is sent while waiting, so a short occlusion costs time, never a blind pulse.
    func sighting(after since: Double, _ prediction: Prediction?) async -> Sighting? {
        let from = since + config.settle
        var unseenFrom: Double?
        var lastPTS = -Double.infinity
        while true {
            if let reason = check() { lease.cancel(reason); return nil }
            lease.expire()
            let now = driver.now()
            if now >= from, let seen = driver.sight(prediction, notBefore: from), seen.pts >= from, seen.pts > lastPTS,
               now - seen.pts <= Limits.maxFrameAge {
                lastPTS = seen.pts
                if seen.score >= config.minScore {
                    if let unseenFrom { driver.emit("target_reacquired", ["unseen_ms": ms(seen.pts - unseenFrom)]) }
                    latest = seen
                    return seen
                }
                if unseenFrom == nil {
                    unseenFrom = seen.pts
                    driver.emit("target_unseen", fields(seen))
                }
            }
            if now - (unseenFrom ?? from) > config.lossWait {
                lease.cancel(unseenFrom == nil ? "no_fresh_sighting" : "target_lost")
                return nil
            }
            await driver.sleep(Limits.poll)
        }
    }

    func step(_ primitive: Primitive, _ milliseconds: Int, phase: String, from before: Sighting, expect: Double) async -> Sighting? {
        let pulse = Pulse(primitive: primitive, milliseconds: milliseconds)
        if let refusal = lease.refusal(pulse) {
            driver.emit("refused", ["pulse": pulse.token, "why": refusal])
            lease.cancel(refusal.hasSuffix("budget spent") ? "budget_spent_before_visible_stop" : "refused")
            return nil
        }
        let name = String(format: "p%02d", pulses.count + 1)
        driver.snapshot(name + "-before")
        let grant: InputLease.Grant
        do { grant = try lease.acquire(pulse) } catch {
            driver.emit("refused", ["pulse": pulse.token, "error": "\(error)"])
            lease.cancel("acquire_refused")
            return nil
        }
        driver.scheduleRelease(lease, at: grant.deadline)
        while lease.isHolding {
            if let reason = check() { lease.cancel(reason); return nil }
            lease.expire()  // backstop only; the driver's scheduled release is primary
            await driver.sleep(Limits.poll)
        }
        guard let up = lease.lastRelease, up.at >= grant.downAt, lease.stopReason == nil else { return nil }
        let after = await sighting(after: up.at, Prediction(x: before.x, shift: expect))
        driver.snapshot(name + (after == nil ? "-end" : "-after"))
        let record: [String: Any] = [
            "index": pulses.count + 1, "phase": phase, "pulse": pulse.token, "key_code": Int(grant.code),
            "down_at": grant.downAt, "up_at": up.at, "up_reason": up.reason, "lateness_ms": ms(up.at - grant.deadline),
            "expected_dx": r3(expect), "before": fields(before), "after": after.map(fields) ?? NSNull(),
            "dispatch": driver.dispatchLabel,
        ]
        pulses.append(record)
        driver.emit("pulse_report", record)
        return after
    }

    func centre(_ start: Sighting, phase: String) async -> Sighting? {
        var current = start
        var misses = 0
        for _ in 0..<config.maxCentring {
            if abs(current.x) <= config.tolerance { return current }
            let left = current.x < 0  // Q/turn-left moves the scene, and the target, rightwards
            let wanted = Int(((config.dead + config.gain * abs(current.x) / config.turnRate) * 1000).rounded())
            let milliseconds = min(max(wanted, SeekLimits.turnMs.lowerBound), SeekLimits.turnMs.upperBound)
            let expect = (left ? 1 : -1) * config.turnRate * max(0, Double(milliseconds) / 1000 - config.dead)
            guard let next = await step(left ? .turnLeft : .turnRight, milliseconds, phase: phase, from: current, expect: expect) else {
                return nil
            }
            // A turn that barely moves the target means the input is not applied or not a turn.
            misses = (next.x - current.x) * (left ? 1 : -1) < 0.25 * abs(expect) ? misses + 1 : 0
            if misses >= 2 { lease.cancel("no_visible_turn_response"); return nil }
            current = next
        }
        if abs(current.x) <= config.tolerance { return current }
        lease.cancel("centring_not_converged")
        return nil
    }

    let waitEnd = driver.now() + Limits.firstFrameWait
    var reason = check()
    while reason == "stale_or_stalled_frames" && driver.now() < waitEnd {
        await driver.sleep(Limits.poll)
        reason = check()
    }
    if let reason { lease.cancel(reason) }

    if lease.stopReason == nil, var current = await sighting(after: driver.now() - config.settle, nil) {
        driver.snapshot("p00-start")
        run: do {
            guard let centred = await centre(current, phase: "centre") else { break run }
            // Facing: camera centring alone does not show which way the avatar walks.
            guard let moved = await step(.forward, SeekLimits.forwardMs, phase: "facing", from: centred, expect: 0) else {
                break run
            }
            // M2's ground row is often unseen at range; then only the bearing can be judged.
            let known = config.stopRow == nil || (centred.y > -0.5 && moved.y > -0.5)
            let consistent = abs(moved.x) <= config.approachTolerance
                && (!known || config.progress(moved) >= config.progress(centred) - config.slack)
            let record: [String: Any] = ["x_before": r3(centred.x), "x_after": r3(moved.x), "progress_before": r3(config.progress(centred)),
                                         "progress_after": r3(config.progress(moved)),
                                         "verdict": !consistent ? "inconsistent" : known ? "consistent" : "bearing_only"]
            facing = record
            driver.emit("facing_check", record)
            guard consistent else { lease.cancel("facing_inconsistent"); break run }
            current = moved
            var seen = config.stopRow != nil && current.y > -0.5, unseen = 0
            while !config.reached(current) {
                // M2: once the circle has been seen, never walk on without it. Grass hides it
                // for a frame now and then (run 3), so two unseen sightings in a row stop the run.
                if config.stopRow != nil {
                    if current.y > -0.5 { seen = true; unseen = 0 } else if seen { unseen += 1 }
                    if unseen >= 2 { lease.cancel("ground_lost"); break run }
                }
                let next: Sighting?
                if abs(current.x) > config.approachTolerance { next = await centre(current, phase: "recentre") }
                else { next = await step(.forward, SeekLimits.forwardMs, phase: "approach", from: current, expect: 0) }
                guard let next else { break run }
                current = next
            }
            reached = true
        }
    }
    if lease.isHolding { lease.cancel("seek_end_holding") }

    let outcome: String
    if lease.isHolding { outcome = "HOLD_RELEASE_UNCONFIRMED" }
    else if reached { outcome = "VISIBLE_STOP_REACHED_PENDING_LABELS" }
    else { outcome = "STOPPED_" + (lease.stopReason ?? "unknown") }
    return SeekResult(outcome: outcome, pulses: pulses, facing: facing, final: latest, frameCounts: gate.counts)
}

/// Fake world for tests and the dry-run: one static target, avatar yaw and position, the
/// fitted dead time and a 90-degree field of view. It exercises the loop, not WoW: no
/// terrain, collisions, camera lag, other characters or tracker error.
final class SimWorld: KeySink {
    var turnRate = 180.0        // degrees per second
    var speed = 7.0             // yards per second
    var dead = 0.04
    var forwardSkew = 0.0       // degrees between facing and the direction forward moves
    var turnsApplied = true
    var groundVisibleWithin = Double.infinity  // M2: beyond this range the ground row is unseen (-0.5)
    var groundHidden: (Double) -> Bool = { _ in false }
    var hidden: (Double) -> Bool = { _ in false }
    private let lock = NSLock()
    private let profile: KeyProfile
    private let clock: () -> Double
    private let target: (x: Double, y: Double)
    private let distance: Double
    private var presses: [(primitive: Primitive, down: Double, up: Double?)] = []

    init(profile: KeyProfile, clock: @escaping () -> Double, bearing: Double, distance: Double) {
        self.profile = profile
        self.clock = clock
        self.distance = distance
        target = (distance * sin(bearing * .pi / 180), distance * cos(bearing * .pi / 180))
    }

    var held: [(primitive: Primitive, down: Double, up: Double?)] {
        lock.lock()
        defer { lock.unlock() }
        return presses
    }

    func post(_ code: UInt16, down: Bool) throws {
        guard let primitive = Primitive.allCases.first(where: { profile.code($0) == code }) else {
            throw ProbeError("sim: unmapped key \(code)")
        }
        lock.lock()
        defer { lock.unlock() }
        if down { presses.append((primitive, clock(), nil)) }
        else if let open = presses.lastIndex(where: { $0.primitive == primitive && $0.up == nil }) { presses[open].up = clock() }
    }

    func sighting(at t: Double) -> Sighting {
        var yaw = 0.0, x = 0.0, y = 0.0  // degrees, positive turned left; the avatar starts facing +y
        for press in held {
            let active = max(0, min(t, press.up ?? t) - (press.down + dead))
            switch press.primitive {
            case .turnLeft: if turnsApplied { yaw += turnRate * active }
            case .turnRight: if turnsApplied { yaw -= turnRate * active }
            case .forward:
                let heading = (yaw - forwardSkew) * .pi / 180
                x -= speed * active * sin(heading)
                y += speed * active * cos(heading)
            }
        }
        let facing = yaw * .pi / 180
        let dx = target.x - x, dy = target.y - y
        let ahead = -dx * sin(facing) + dy * cos(facing), right = dx * cos(facing) + dy * sin(facing)
        let bearing = atan2(right, ahead)
        let visible = ahead > 0 && abs(bearing) < .pi / 4 && !hidden(t)
        let range = (dx * dx + dy * dy).squareRoot()
        // y: a ground row that falls towards the middle as the unit gets closer (M2).
        return Sighting(pts: t, x: visible ? tan(bearing) / 2 : 0, y: range > groundVisibleWithin || groundHidden(t) ? -0.5 : -0.3 + 3 / range,
                        scale: distance / range, score: visible ? 0.95 : 0.2)
    }
}
