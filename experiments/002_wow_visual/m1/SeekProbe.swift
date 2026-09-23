// M1 native shell for issue #5: the designated-target loop over M0's window capture, pid key
// route, release timer, signal trap and preflight (m0/Probe.swift built with -D SEEK).
// Modes, from no effect to live effect:
//   (none) | --preflight   M0's read-only facts; no capture, input or permission request
//   --dry-run              the loop, lease and release timer against SimWorld; no capture,
//                          OS input or files
//   --look                 one WoW-window frame (audio off) saved under runs/ for designating
//                          a target; no input
//   --execute --keys K --look FRAME --box X,Y,W,H [--stop-growth G]   M1: manual designation
//   --target --keys K [--stop-row R]   M2: one Tab, then WoW's white-outlined target nameplate
// Recovery after a crash or kill: m0-probe --release --keys K. No model or provider calls.
import AppKit
import CoreMedia
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

let seekUsage = """
    usage: m1-seek [--preflight]
           m1-seek --dry-run
           m1-seek --look
           m1-seek --execute --keys arrows|wasd|wqe --look FRAME.png --box X,Y,W,H [--stop-growth \(SeekLimits.growth)]
           m1-seek --target --keys arrows|wasd|wqe [--stop-row \(SeekLimits.stopRow)]
    X,Y,W,H: the designated target in FRAME pixels. Recovery: m0-probe --release --keys K
    """
let trackWidth = 320  // tracking resolution: half of M0's 640-pixel capture

/// Grey pixels drawn upright into a bitmap context: row 0 is the image's top row.
func grey(_ image: CGImage, width: Int) -> Grey {
    let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
    var bytes = [UInt8](repeating: 0, count: width * height)
    bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return Grey(width: width, height: height, pixels: bytes.map(Float.init))
}

/// RGBA pixels drawn upright, row 0 at the top, for the M2 nameplate detector.
func rgba(_ image: CGImage) -> RGBA {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return RGBA(width: image.width, height: image.height, pixels: bytes)
}

/// The image with a box (top-left pixel coordinates) and a centre line, for manual labels.
func annotated(_ image: CGImage, box: CGRect?) -> CGImage? {
    guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let height = CGFloat(image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.setLineWidth(1)
    context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.5)
    context.stroke(CGRect(x: CGFloat(image.width) / 2, y: 0, width: 0, height: height))
    if let box {
        context.setLineWidth(2)
        context.setStrokeColor(red: 1, green: 0.1, blue: 0.9, alpha: 1)
        context.stroke(CGRect(x: box.minX, y: height - box.maxY, width: box.width, height: box.height))
    }
    return context.makeImage()
}

func write(_ image: CGImage, to url: URL, type: UTType) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
    CGImageDestinationFinalize(destination)
}

/// M0's shell plus the M1 tracker or M2 nameplate detector (live), or the simulated world (dry-run).
final class SeekShell: ShellDriver, SeekDriver {
    let tracker: Tracker?
    let world: SimWorld?
    let plates: Bool
    private var cached: (pts: Double, sighting: Sighting)?
    private var shown: Match?
    private var shownPlate: Plate?

    init(log: Log, live: LiveTarget?, tracker: Tracker?, world: SimWorld?, plates: Bool = false) {
        self.tracker = tracker
        self.world = world
        self.plates = plates
        super.init(log: log, live: live)
    }

    func sight(_ prediction: Prediction?, notBefore: Double) -> Sighting? {
        if let world { return world.sighting(at: origin + (((hostNow() - origin) * 30).rounded(.down)) / 30) }
        guard let live, let frame = live.feed.latestFrame, frame.pts >= notBefore else { return nil }
        if let cached, cached.pts == frame.pts { return cached.sighting }
        let started = hostNow()
        if plates {  // M2: detected afresh in every frame; nothing to drift, nothing to predict
            let image = rgba(frame.image)
            let plate = findTargetPlate(image)
            let ground = plate.flatMap { findGround(image, below: $0) }
            if let plate { shownPlate = plate }
            // x from the nameplate (the unit's bearing); y from its selection circle, -0.5 while unseen.
            let sighting = Sighting(pts: frame.pts, x: plate.map { $0.centre / Double(image.width) - 0.5 } ?? 0,
                                    y: ground.map { Double($0) / Double(image.height) - 0.5 } ?? -0.5, scale: 1,
                                    score: plate == nil ? 0 : 1)
            cached = (frame.pts, sighting)
            var row = fields(sighting)
            row["plate"] = plate.map { [$0.x0, $0.x1, $0.top, $0.bottom] } ?? NSNull()
            row["ground_row"] = orNull(ground)
            row["track_ms"] = ms(hostNow() - started)
            emit("sighting", row)
            return sighting
        }
        guard let tracker else { return nil }
        let image = grey(frame.image, width: trackWidth)
        guard let match = tracker.sight(image, prediction) else { return nil }
        shown = match
        let sighting = Sighting(pts: frame.pts, x: match.x / Double(image.width) - 0.5, y: match.y / Double(image.height) - 0.5,
                                scale: match.scale, score: match.score)
        cached = (frame.pts, sighting)
        var row = fields(sighting)
        row["runner_up"] = r3(match.runnerUp)
        row["track_ms"] = ms(hostNow() - started)
        emit("sighting", row)
        return sighting
    }

    /// The newest frame with the tracker's latest match (or the last detected plate) drawn on it.
    override func snapshot(_ name: String) {
        guard let live, let image = live.feed.latest else { return }
        if plates {
            let box = shownPlate.map { CGRect(x: $0.x0, y: $0.top, width: $0.x1 - $0.x0, height: $0.bottom - $0.top) }
            if let marked = annotated(image, box: box) { write(marked, to: live.directory.appendingPathComponent(name + ".jpg"), type: .jpeg) }
            return
        }
        guard let tracker else { return }
        let factor = Double(image.width) / Double(trackWidth)
        let box = shown.map { match -> CGRect in
            let width = Double(tracker.template.width) * match.scale * factor, height = Double(tracker.template.height) * match.scale * factor
            return CGRect(x: match.x * factor - width / 2, y: match.y * factor - height / 2, width: width, height: height)
        }
        guard let marked = annotated(image, box: box) else { return }
        write(marked, to: live.directory.appendingPathComponent(name + ".jpg"), type: .jpeg)
    }
}

struct Session {
    let app: NSRunningApplication
    let front: NSRunningApplication
    let window: SCWindow
    let bounds: CGRect
    let config: SCStreamConfiguration
}

/// M0's target checks: existing grants only, one WoW process and game window, WoW in the
/// background. Unlike M0, the window need not be on screen: window-only capture delivered
/// ~57 fps with WoW on another Space (23 September 2026), and the frame gate still stops a
/// run whose frames go stale.
@MainActor
func wowSession(input: Bool, full: Bool = false) async throws -> Session {
    NSApplication.shared.setActivationPolicy(.prohibited)
    guard CGPreflightScreenCaptureAccess(), !input || AXIsProcessTrusted() else {
        throw ProbeError("Screen Recording\(input ? " and Accessibility" : "") must already be granted to this launch context; nothing was requested")
    }
    guard !escapeHeld() else { throw ProbeError("Escape is held") }
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == wowBundle }
    guard apps.count == 1, let app = apps.first else { throw ProbeError("expected exactly one running WoW process, found \(apps.count)") }
    guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != app.processIdentifier else {
        throw ProbeError("WoW is frontmost or the foreground app is unknown; M1 uses background input and never switches apps")
    }
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    let windows = content.windows.filter {  // off screen, WoW also lists 30-pixel menu-bar strips
        $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 300 && $0.frame.height > 300
    }
    guard windows.count == 1, let window = windows.first, let bounds = windowBounds(window.windowID) else {
        throw ProbeError("expected exactly one WoW game window, found \(windows.count)")
    }
    let scale = full ? 1 : min(1, 640 / window.frame.width)  // M2 reads nameplate outlines 2-3 pixels thick
    let config = SCStreamConfiguration()
    config.width = max(2, Int(window.frame.width * scale))
    config.height = max(2, Int(window.frame.height * scale))
    config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    config.queueDepth = 3
    config.showsCursor = false
    config.capturesAudio = false
    return Session(app: app, front: front, window: window, bounds: bounds, config: config)
}

func capture(_ session: Session, into feed: FrameFeed) throws -> SCStream {
    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: session.window), configuration: session.config, delegate: nil)
    try stream.addStreamOutput(feed, type: .screen, sampleHandlerQueue: DispatchQueue(label: "m1.frames"))
    return stream
}

func firstFrame(_ feed: FrameFeed) async -> (pts: Double, image: CGImage)? {
    let end = hostNow() + Limits.firstFrameWait
    while feed.latestFrame == nil && hostNow() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
    return feed.latestFrame
}

func runDirectory(_ prefix: String) throws -> (id: String, url: URL) {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let id = "\(prefix)_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6).lowercased())"
    let url = URL(fileURLWithPath: "runs/002_wow_visual").appendingPathComponent(id)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return (id, url)
}

@MainActor
func look() async throws -> Int32 {
    let session = try await wowSession(input: false)
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    let frame = await firstFrame(feed)
    try? await stream.stopCapture()
    guard let frame else { throw ProbeError("no complete frame within \(Limits.firstFrameWait) s") }
    let directory = try runDirectory("m1_look")
    let url = directory.url.appendingPathComponent("look.png")
    write(frame.image, to: url, type: .png)
    try Log(file: nil).emit("look", ["path": url.path, "size": [frame.image.width, frame.image.height],
                                     "window_on_screen": session.window.isOnScreen,
                                     "effects": "one window-only frame, audio off; no input"])
    return 0
}

func seekDryRun() async throws -> Int32 {
    let log = try Log(file: nil)
    let world = SimWorld(profile: .wqe, clock: hostNow, bearing: -20, distance: 20)
    let driver = SeekShell(log: log, live: nil, tracker: nil, world: world)
    let lease = InputLease(profile: .wqe, sink: world, clock: hostNow, emit: driver.emit, budget: SeekLimits.budget)
    let signals = trapSignals(lease, log)
    driver.emit("start", ["mode": "dry-run", "world": "SimWorld: target 20 deg left, 20 yd",
                          "effects": "none: the simulated world is the key sink; no capture, OS input or files"])
    let result = await runSeek(SeekConfig(), lease: lease, gate: FrameGate(stream: "synthetic", width: 64, height: 36), driver: driver)
    withExtendedLifetime(signals) {}
    driver.emit("summary", ["outcome": result.outcome, "pulses_used": lease.pulsesUsed,
                            "spent_ms": Dictionary(uniqueKeysWithValues: lease.spentMs.map { ($0.key.rawValue, $0.value) }),
                            "facing": orNull(result.facing), "final": orNull(result.final.map(fields)), "frames": result.frameCounts,
                            "model_calls": 0, "meaning": "proves the loop, lease and release timer against a simulated world, not WoW"])
    return lease.isHolding ? 3 : (result.outcome.hasPrefix("VISIBLE_STOP") ? 0 : 2)
}

/// One Tab tap (target nearest enemy). It moves nothing, so it is not under the lease; its
/// key-up is retried like the lease's, and a failure stops before any movement.
func tap(_ sink: KeySink, _ code: UInt16) throws {
    try sink.post(code, down: true)
    usleep(60_000)
    var failure: Error?
    for _ in 1...Limits.releaseAttempts {
        do { try sink.post(code, down: false); return } catch { failure = error }
    }
    throw ProbeError("Tab key-up unconfirmed (\(failure.map { "\($0)" } ?? "")); tap Tab in WoW")
}

/// M1 finds the target from a manual designation (the oracle); M2 presses Tab once and
/// follows WoW's white-outlined target nameplate. Either way nothing moves unless the
/// target is confirmed in a live frame first.
@MainActor
func seekExecute(_ command: SeekCommand, profile: KeyProfile) async throws -> Int32 {
    let plates = command.mode == .target
    let session = try await wowSession(input: true, full: plates)
    let (width, height) = (session.config.width, session.config.height)
    var config = SeekConfig()
    config.growth = command.growth
    if plates { config.stopRow = command.stopRow - 0.5 }

    var designationFrame: CGImage?
    var template: Grey?
    var trackBox: Box?
    if !plates, let box = command.box, let lookPath = command.look {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: lookPath) as CFURL, nil),
              let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ProbeError("cannot read the look frame") }
        guard frame.width == width, frame.height == height else {
            throw ProbeError("look frame is \(frame.width)x\(frame.height) but live capture is \(width)x\(height); look again")
        }
        let factor = Double(trackWidth) / Double(width)
        func track(_ value: Int) -> Int { Int((Double(value) * factor).rounded()) }
        let scaled = Box(x: track(box.x), y: track(box.y), width: track(box.width), height: track(box.height))
        guard let cut = cropped(grey(frame, width: trackWidth), scaled) else { throw ProbeError("box lies outside the look frame") }
        (designationFrame, template, trackBox) = (frame, cut, scaled)
    }

    let run = try runDirectory(plates ? "m2" : "m1")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    if let designationFrame, let box = command.box,
       let marked = annotated(designationFrame, box: CGRect(x: box.x, y: box.y, width: box.width, height: box.height)) {
        write(marked, to: run.url.appendingPathComponent("designation.jpg"), type: .jpeg)
    }
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    let sink = PidKeySink(pid: session.app.processIdentifier)

    let confirmed: Bool
    let acquisition: [String: Any]
    var tracker: Tracker?
    if plates {
        _ = await firstFrame(feed)
        try tap(sink, 48)
        let tabbed = hostNow()
        var plate: Plate?
        while plate == nil && hostNow() < tabbed + 1 {
            if let frame = feed.latestFrame, frame.pts > tabbed + 0.1 { plate = findTargetPlate(rgba(frame.image)) }
            if plate == nil { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        confirmed = plate != nil
        acquisition = ["method": "one Tab (key 48), then the white-outlined target nameplate", "tab_at": tabbed,
                       "plate": orNull(plate.map { [$0.x0, $0.x1, $0.top, $0.bottom] }), "confirmed": confirmed]
    } else if let template, let trackBox, let box = command.box {
        // The designation must be found in place and unique in the first live frame, before any
        // input: this also proves the look frame and the live frame share one coordinate system.
        let designated = (x: Double(trackBox.x) + Double(trackBox.width) / 2, y: Double(trackBox.y) + Double(trackBox.height) / 2)
        let found = await firstFrame(feed).flatMap { frame -> Match? in
            let image = grey(frame.image, width: trackWidth)
            return locate(template, in: image, scales: [0.95, 1, 1.05], near: designated, reach: (Double(image.width), Double(image.height)))
        }
        confirmed = found.map { $0.score >= 0.8 && $0.score - $0.runnerUp >= 0.1
            && hypot($0.x - designated.x, $0.y - designated.y) <= 6 } ?? false
        tracker = found.map { Tracker(template: template, start: $0, minScore: config.minScore) }
        acquisition = ["look_frame": orNull(command.look), "box": [box.x, box.y, box.width, box.height],
                       "track_box": [trackBox.x, trackBox.y, trackBox.width, trackBox.height],
                       "found": orNull(found.map { ["x": r3($0.x), "y": r3($0.y), "scale": r3($0.scale), "score": r3($0.score),
                                                     "runner_up": r3($0.runnerUp)] }),
                       "confirmed": confirmed]
    } else {
        throw ProbeError("--execute needs --look and --box")
    }

    let target = LiveTarget(pid: session.app.processIdentifier, windowID: session.window.windowID, bounds: session.bounds,
                            frontPID: session.front.processIdentifier, feed: feed, directory: run.url)
    let driver = SeekShell(log: log, live: target, tracker: tracker, world: nil, plates: plates)
    let lease = InputLease(profile: profile, sink: sink, clock: hostNow, emit: driver.emit, budget: SeekLimits.budget)
    let signals = trapSignals(lease, log)
    var manifest: [String: Any] = [
        "schema": plates ? "m2-run/v1" : "m1-run/v1", "run_id": run.id, "mode": command.mode.rawValue,
        "started_utc": ISO8601DateFormatter().string(from: Date()),
        "source": ["git_head": orNull(git("rev-parse", "HEAD")), "git_dirty": orNull(git("status", "--porcelain").map { !$0.isEmpty })],
        "machine": machineFacts(),
        "target": bundleFacts(session.app.bundleURL).merging(["pid": Int(session.app.processIdentifier), "window_id": Int(session.window.windowID),
                                                               "window_bounds": NSStringFromRect(session.bounds), "capture_stream": feed.streamID,
                                                               "capture_size": [width, height]]) { current, _ in current },
        "focus_at_start": ["frontmost_bundle": orNull(session.front.bundleIdentifier), "frontmost_pid": Int(session.front.processIdentifier),
                           "wow_window_on_screen": session.window.isOnScreen],
        "keys": ["profile": profile.rawValue, "codes": Dictionary(uniqueKeysWithValues: Primitive.allCases.map { ($0.rawValue, Int(profile.code($0))) }),
                 "tab": orNull(plates ? 48 : nil)],
        plates ? "acquisition" : "designation": acquisition,
        "config": ["turn_rate": config.turnRate, "dead_s": config.dead, "gain": config.gain, "tolerance": config.tolerance,
                   "approach_tolerance": config.approachTolerance, "stop_growth": orNull(plates ? nil : config.growth),
                   "stop_row_from_top": orNull(plates ? command.stopRow : nil), "min_score": config.minScore,
                   "settle_s": config.settle, "loss_wait_s": config.lossWait, "max_centring": config.maxCentring],
        "budget": ["max_pulses": 20, "turn_ms": "\(SeekLimits.turnMs)", "forward_ms": SeekLimits.forwardMs,
                   "max_total_ms": ["turn-left": 1200, "turn-right": 1200, "forward": 2500]],
        "capture": "window-only ScreenCaptureKit, audio off, cursor hidden; only annotated pNN JPEGs are kept",
        "model_calls": 0, "provider_calls": 0,
    ]
    driver.emit("start", manifest)
    let result: SeekResult
    if confirmed {
        result = await runSeek(config, lease: lease, gate: FrameGate(stream: feed.streamID, width: width, height: height), driver: driver)
    } else {
        let outcome = plates ? "HOLD_NO_TARGET_PLATE" : "HOLD_DESIGNATION_NOT_CONFIRMED"
        driver.snapshot("p00-refused")
        driver.emit("target_refused", ["acquisition": acquisition, "movement_keys_sent": 0])
        result = SeekResult(outcome: outcome, pulses: [], facing: nil, final: nil, frameCounts: [:])
    }
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}

    manifest["focus_at_end"] = ["frontmost_bundle": orNull(NSWorkspace.shared.frontmostApplication?.bundleIdentifier),
                                "wow_frontmost": NSWorkspace.shared.frontmostApplication?.processIdentifier == session.app.processIdentifier]
    manifest["outcome"] = result.outcome
    manifest["stop_reason"] = orNull(lease.stopReason)
    manifest["pulses"] = result.pulses
    manifest["facing"] = orNull(result.facing)
    manifest["final"] = orNull(result.final.map(fields))
    manifest["spent_ms"] = Dictionary(uniqueKeysWithValues: lease.spentMs.map { ($0.key.rawValue, $0.value) })
    manifest["frames"] = result.frameCounts
    manifest["meaning"] = "dispatch, detected image position and the visible stop measure only; facing, approach and identity need labels.json"
    let labels: [String: Any] = [
        "instructions": "Fill from the pNN JPEGs (and designation.jpg for M1) and what was seen live. null means not assessed.",
        "trial": ["tracker_stayed_on_designated_object": NSNull(), "target_centred_visibly": NSNull(), "avatar_faced_target": NSNull(),
                  "avatar_approached_target": NSNull(), "stopped_at_visible_condition": NSNull(), "camera_only_change": NSNull(),
                  "collision_or_obstruction": NSNull(), "misrouted_input_seen": NSNull(), "combat_or_interaction": NSNull(),
                  "human_reset": NSNull(), "notes": ""],
    ]
    for (name, object) in [("manifest.json", manifest), ("labels.json", labels)] {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: run.url.appendingPathComponent(name))
    }
    driver.emit("summary", ["outcome": result.outcome, "run_directory": run.url.path])
    return lease.isHolding ? 3 : (result.outcome.hasPrefix("VISIBLE_STOP") ? 0 : 2)
}

@main
struct M1Seek {
    static func main() async {
        let command: SeekCommand
        do { command = try parseSeek(Array(CommandLine.arguments.dropFirst())) } catch {
            fputs("HOLD: \(error)\n\(seekUsage)\n", stderr)
            exit(64)
        }
        do {
            switch command.mode {
            case .preflight:
                let data = try JSONSerialization.data(withJSONObject: preflight(), options: [.prettyPrinted, .sortedKeys])
                FileHandle.standardOutput.write(data + Data([10]))
            case .dryRun: exit(try await seekDryRun())
            case .look: exit(try await look())
            case .execute, .target: exit(try await seekExecute(command, profile: command.profile!))
            }
        } catch {
            fputs("HOLD: \(error)\n", stderr)
            exit(2)
        }
    }
}
