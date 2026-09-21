// Pure observation and action state. No capture, UI, provider or wall-clock access.
import Foundation

struct Blob {
    var x: Double
    var y: Double
    var area: Int
    var novelty: Double = 0
    var matchCorrelation: Double = 1
}

func distance(_ a: Blob, _ b: Blob) -> Double { hypot(a.x - b.x, a.y - b.y) }
func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

func isBite(_ history: [Blob], _ current: Blob, _ background: Double,
            missingFrames: Int = 0, missingSeconds: Double = 0, missingBackground: Double = 0) -> Bool {
    guard history.count == 6, missingFrames == 0, missingSeconds == 0 else { return false }
    // Keep the newest two observations out of the stable reference: they may
    // already contain the onset of the movement we are trying to detect.
    let baseline = Array(history.prefix(4))
    let minimumDrop = 2.0
    let step = current.y-history.last!.y
    let baseY = median(baseline.map(\.y)), baseX = median(baseline.map(\.x))
    // Missing tracker output is uncertainty, not image evidence of submersion.
    return baseline.map(\.y).max()! - baseline.map(\.y).min()! < 2
        && current.y-baseY >= minimumDrop && step >= minimumDrop && step >= (current.y-baseY)*0.75
        && abs(current.x-baseX) < 6 && background < 4
}

func floatRecovered(_ current: Blob, _ previous: Blob, _ x: Double, _ y: Double,
                    _ area: Double, _ background: Double) -> Bool {
    abs(current.y-y) < 2.5 && abs(current.x-x) < 4
        && current.matchCorrelation >= 0.7 && background < 4
        && distance(current, previous) < 1
}

struct FloatObservation {
    let target: Blob
    let capturedAt: Double
    let background: Double
}

struct MotionWindow {
    let generation: Int
    let observations: [FloatObservation]
    var current: FloatObservation { observations.last! }
    var history: [Blob] { observations.dropLast().map(\.target) }
    var reference: Blob {
        let baseline = observations.prefix(4).map(\.target)
        return Blob(x: median(baseline.map(\.x)), y: median(baseline.map(\.y)),
                    area: Int(median(baseline.map { Double($0.area) })))
    }
    var drop: Double { current.target.y-reference.y }
    var changed: Bool { abs(drop) > 1.5 }
    var rulesReel: Bool { isBite(history, current.target, current.background) }
    var state: [String: Any] {
        func rounded(_ x: Double) -> Double { (x*1000).rounded()/1000 }
        let base = reference, start = observations[0].capturedAt
        return ["sequence_seconds_dx_downward_dy_match": observations.map {
            [rounded($0.capturedAt-start), rounded($0.target.x-base.x),
             rounded($0.target.y-base.y), rounded($0.target.matchCorrelation)]
        }, "background_change": rounded(current.background)]
    }
}

// One state machine owns evidence continuity, response validity and one-shot input.
// All time comes from the caller's monotonic capture clock, so tests need no sleeps.
struct FishingLoop {
    private enum Phase {
        case watching
        case recovering(reference: Blob, expiresAt: Double, confirmations: Int, lastFrame: Double)
        case finished
    }
    private var phase = Phase.watching
    private var observations: [FloatObservation] = []
    private var since: Double?
    private(set) var generation = 0
    private(set) var window: MotionWindow?
    var armed: Bool { if case .recovering = phase { return true }; return false }

    mutating func invalidate() {
        generation += 1
        observations.removeAll(keepingCapacity: true)
        since = nil; window = nil
        if case .finished = phase { return }
        phase = .watching
    }

    mutating func observe(_ target: Blob?, capturedAt: Double, now: Double, background: Double) {
        guard let target, capturedAt.isFinite, now.isFinite, background.isFinite, background >= 0,
              target.x.isFinite, target.y.isFinite, target.area > 0,
              target.matchCorrelation.isFinite, (0.55...1).contains(target.matchCorrelation),
              (0..<0.35).contains(now-capturedAt) else { invalidate(); return }
        if let previous = observations.last {
            let gap = capturedAt-previous.capturedAt
            guard gap > 0 else { invalidate(); return }
            // A missing stream frame is just as invalidating as a failed tracker.
            if gap > 0.25 { invalidate() }
        }
        since = since ?? capturedAt
        observations.append(FloatObservation(target: target, capturedAt: capturedAt, background: background))
        if observations.count > 7 { observations.removeFirst() }
        window = observations.count == 7 && capturedAt-since! >= 1
            ? MotionWindow(generation: generation, observations: observations) : nil
    }

    mutating func arm(_ evidence: MotionWindow, now: Double) -> Bool {
        guard case .watching = phase, window != nil,
              evidence.generation == generation, now.isFinite,
              (0...1.5).contains(now-evidence.current.capturedAt) else { return false }
        phase = .recovering(reference: evidence.reference,
                            expiresAt: evidence.current.capturedAt+2, confirmations: 0, lastFrame: -.infinity)
        return true
    }

    func expired(at now: Double) -> Bool {
        if case let .recovering(_, deadline, _, _) = phase { return now > deadline }
        return false
    }

    mutating func takeClick(at now: Double) -> Blob? {
        guard case let .recovering(reference, deadline, confirmations, lastFrame) = phase,
              let window, now.isFinite, now <= deadline,
              (0..<0.2).contains(now-window.current.capturedAt),
              window.current.capturedAt > lastFrame else { return nil }
        let current = window.current.target
        let recovered = floatRecovered(current, window.history.last!, reference.x, reference.y,
                                       Double(reference.area), window.current.background)
        let count = recovered ? confirmations+1 : 0
        if count == 2 { phase = .finished; return current }
        phase = .recovering(reference: reference, expiresAt: deadline,
                            confirmations: count, lastFrame: window.current.capturedAt)
        return nil
    }
}
