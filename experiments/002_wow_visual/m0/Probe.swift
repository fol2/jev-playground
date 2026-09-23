// M0 native probe for issue #5: can process-targeted keys make bounded avatar turn/move/stop
// actions without taking focus? Modes, from no effect to live effect:
//   (none) | --preflight        read-only facts; no capture, input or permission request
//   --dry-run [PULSE...]        the same batch and release queue with synthetic frames and
//                               a no-effect sink; no capture, OS input or files
//   --execute --keys K PULSE... WoW window-only capture (audio off) and pid-targeted keys
//   --release --keys K          key-up only, to recover after a crash or kill
// Key route: fishing live.swift key(), a private event source posted to one pid.
// Capture: fishing's ScreenCaptureKit latest-frame pattern. No model or provider calls.
import AppKit
import ApplicationServices
import CoreMedia
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import VideoToolbox

let wowBundle = "com.blizzard.worldofwarcraft"
let escapeKey: CGKeyCode = 53
let usage = """
    usage: m0-probe [--preflight]
           m0-probe --dry-run [PULSE...]
           m0-probe --execute --keys arrows|wasd|wqe PULSE...
           m0-probe --release --keys arrows|wasd|wqe
    PULSE: turn-left|turn-right|forward:100|200, at most \(Limits.maxPulses)
    """

func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
func orNull(_ value: Any?) -> Any { value ?? NSNull() }

final class Log {
    private let lock = NSLock()
    private let file: FileHandle?

    init(file url: URL?) throws {
        if let url {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            file = try FileHandle(forWritingTo: url)
        } else {
            file = nil
        }
    }

    /// Unbuffered JSON lines to stdout and the run log, so a kill loses at most one line.
    func emit(_ event: String, _ fields: [String: Any]) {
        var row = fields
        row["event"] = event
        if !JSONSerialization.isValidJSONObject(row) { row = ["event": event, "unencodable": "\(fields)"] }
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        lock.lock()
        defer { lock.unlock() }
        try? file?.write(contentsOf: data + Data([10]))
        FileHandle.standardOutput.write(data + Data([10]))
    }
}

/// Fishing's background key route: a private event source, stamped and posted to one pid.
final class PidKeySink: KeySink {
    let pid: pid_t
    init(pid: pid_t) { self.pid = pid }
    func post(_ code: UInt16, down: Bool) throws {
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == wowBundle,
              let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),
                                  virtualKey: code, keyDown: down) else {
            throw ProbeError("target process gone or key event not created")
        }
        event.flags = []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.postToPid(pid)
    }
}

/// Dry-run sink: the lease log records intent; nothing is sent anywhere.
final class NoEffectSink: KeySink {
    func post(_ code: UInt16, down: Bool) throws {}
}

func thumbnail(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: 64 * 36)
    pixels.withUnsafeMutableBytes { raw in
        guard let context = CGContext(data: raw.baseAddress, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 64,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 36))
    }
    return pixels
}

/// Fishing's latest-frame pattern plus each frame's grey change against its predecessor.
final class FrameFeed: NSObject, SCStreamOutput {
    let streamID = "sc-" + UUID().uuidString
    private let lock = NSLock()
    private var pending: [Frame] = []
    private var previous: [UInt8]?
    private var image: CGImage?
    private var imagePTS = -Double.infinity

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid, let buffer = sample.imageBuffer,
              let info = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = info.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete else { return }
        var decoded: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &decoded) == noErr, let decoded else { return }
        let grey = thumbnail(decoded)
        lock.lock()
        defer { lock.unlock() }
        if let previous {
            pending.append(Frame(stream: streamID, pts: sample.presentationTimeStamp.seconds, width: decoded.width,
                                 height: decoded.height, diff: meanAbsoluteDifference(previous, grey)))
        }
        previous = grey
        image = decoded
        imagePTS = sample.presentationTimeStamp.seconds
    }

    func drain() -> [Frame] {
        lock.lock()
        defer { pending = []; lock.unlock() }
        return pending
    }

    var latest: CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return image
    }

    /// The newest complete frame with its capture PTS, for M1's tracker.
    var latestFrame: (pts: Double, image: CGImage)? {
        lock.lock()
        defer { lock.unlock() }
        return image.map { (imagePTS, $0) }
    }
}

struct LiveTarget {
    let pid: pid_t
    let windowID: CGWindowID
    let bounds: CGRect
    let frontPID: pid_t
    let feed: FrameFeed
    let directory: URL
}

func windowBounds(_ window: CGWindowID) -> CGRect? {
    guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, window) as? [[String: Any]],
          let bounds = info.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: bounds)
}

func escapeHeld() -> Bool { CGEventSource.keyState(.combinedSessionState, key: escapeKey) }

/// Without a live target this is the dry-run: synthetic flat 30 Hz frames and a simulated
/// 400 ms observer stall after each key-down, so the release queue must work on its own.
/// M1's shell subclasses it for tracking and annotated snapshots.
class ShellDriver: ProbeDriver {
    let log: Log
    let live: LiveTarget?
    private let releases = DispatchQueue(label: "m0.release", qos: .userInteractive)
    let origin = hostNow()
    private var tick = 0

    init(log: Log, live: LiveTarget?) {
        self.log = log
        self.live = live
    }

    var dispatchLabel: String { live == nil ? "no_effect_sink" : "posted_to_pid" }
    func now() -> Double { hostNow() }
    func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    func frames() -> [Frame] {
        if let live { return live.feed.drain() }
        var out: [Frame] = []
        while origin + Double(tick) / 30 <= hostNow() {
            out.append(Frame(stream: "synthetic", pts: origin + Double(tick) / 30, width: 64, height: 36,
                             diff: 0.2 + Double(tick % 3) * 0.05))
            tick += 1
        }
        return out
    }

    func scheduleRelease(_ lease: InputLease, at deadline: Double) {
        // Strict zero-leeway timer on its own queue: measured ~0.1 ms late here, usleep up to 8 ms.
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: releases)
        timer.schedule(deadline: .now() + max(0, deadline - hostNow()), leeway: .nanoseconds(0))
        timer.setEventHandler {
            while hostNow() < deadline {}  // never before the lease deadline
            lease.expire()
            timer.cancel()
        }
        timer.resume()
        if live == nil {
            emit("simulated_observer_stall", ["ms": 400])
            usleep(400_000)
        }
    }

    func fault() -> String? {
        if escapeHeld() { return "operator_escape" }
        guard let live else { return nil }
        guard NSRunningApplication(processIdentifier: live.pid)?.isTerminated == false else { return "target_process_gone" }
        guard let bounds = windowBounds(live.windowID) else { return "window_unavailable" }
        guard bounds == live.bounds else { return "geometry_changed" }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == live.frontPID else { return "focus_changed" }
        return nil
    }

    func snapshot(_ name: String) {
        guard let live, let image = live.feed.latest,
              let destination = CGImageDestinationCreateWithURL(live.directory.appendingPathComponent(name + ".jpg") as CFURL,
                                                                UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    func emit(_ event: String, _ fields: [String: Any]) {
        var row = fields
        row["t"] = hostNow()
        log.emit(event, row)
    }
}

/// Human emergency stop by Ctrl-C/kill: release on a queue the batch cannot block.
/// SIGKILL, crashes and power loss cannot run this; use --release or the key in WoW.
func trapSignals(_ lease: InputLease, _ log: Log, also: (() -> Void)? = nil) -> [DispatchSourceSignal] {
    let queue = DispatchQueue(label: "m0.signals", qos: .userInteractive)
    return [("SIGINT", SIGINT), ("SIGTERM", SIGTERM), ("SIGHUP", SIGHUP)].map { name, number in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
        source.setEventHandler {
            also?()  // M2: Tab's key-up, which is not under the lease
            lease.cancel(name)
            log.emit("exit", ["reason": name, "holding": lease.isHolding])
            exit(lease.isHolding ? 3 : 130)
        }
        source.resume()
        return source
    }
}

func sysctl(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
}

func bundleFacts(_ url: URL?) -> [String: Any] {
    let info = url.flatMap { Bundle(url: $0)?.infoDictionary } ?? [:]
    return ["client_folder": orNull(url?.deletingLastPathComponent().lastPathComponent),
            "app": orNull(url?.lastPathComponent),
            "version": orNull(info["CFBundleShortVersionString"]), "build": orNull(info["CFBundleVersion"])]
}

func machineFacts() -> [String: Any] {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return ["macos": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", "macos_build": orNull(sysctl("kern.osversion")),
            "hardware_model": orNull(sysctl("hw.model")), "arch": orNull(sysctl("hw.machine"))]
}

/// Read-only: no capture, input, permission request, window titles or game-file reads.
func preflight() -> [String: Any] {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == wowBundle }
    let pids = Set(apps.map(\.processIdentifier))
    let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                   as? [[String: Any]] ?? [])
        .filter { pids.contains(($0[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) ?? -1) }
        .map { ["window_id": orNull($0[kCGWindowNumber as String]), "layer": orNull($0[kCGWindowLayer as String]),
                "bounds": orNull($0[kCGWindowBounds as String])] }
    let root = URL(fileURLWithPath: "/Applications/World of Warcraft")
    let installed = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
        .flatMap { folder in ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" } }
        .sorted { $0.path < $1.path }
        .map(bundleFacts)
    return [
        "schema": "m0-preflight/v1",
        "effects": "read-only: no capture, input, permission request, install, game launch or game-file read",
        "machine": machineFacts(),
        "permissions_of_this_launch_context": [
            "screen_recording": CGPreflightScreenCaptureAccess(), "accessibility": AXIsProcessTrusted(),
            "post_events": CGPreflightPostEventAccess(), "listen_events": CGPreflightListenEventAccess(),
            "note": "preflight checks only, never requested; macOS attributes them to the launching app"],
        "frontmost_bundle": orNull(NSWorkspace.shared.frontmostApplication?.bundleIdentifier),
        "wow_processes": apps.map { app -> [String: Any] in
            var facts = bundleFacts(app.bundleURL)
            facts["pid"] = Int(app.processIdentifier)
            facts["active"] = app.isActive
            facts["hidden"] = app.isHidden
            return facts
        },
        "wow_windows_on_screen": windows,
        "installed_clients_at_standard_path": installed,
        "unknown": ["session client build/realm/character/location", "movement bindings (owner confirms in-game)",
                    "camera mode", "background frame rate", "chat edit box state", "whether WoW applies background held keys"],
    ]
}

func git(_ arguments: String...) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil
}

func dryRun(_ command: Command, profile: KeyProfile) async throws -> Int32 {
    let log = try Log(file: nil)
    let driver = ShellDriver(log: log, live: nil)
    let lease = InputLease(profile: profile, sink: NoEffectSink(), clock: hostNow, emit: driver.emit)
    let signals = trapSignals(lease, log)
    driver.emit("start", ["mode": "dry-run", "plan": command.plan.map(\.token), "keys": profile.rawValue,
                          "effects": "none: synthetic frames, no-effect sink, no capture, OS input or files"])
    let result = await runBatch(command.plan, lease: lease, gate: FrameGate(stream: "synthetic", width: 64, height: 36), driver: driver)
    withExtendedLifetime(signals) {}
    driver.emit("summary", ["outcome": result.outcome, "pulses_used": lease.pulsesUsed, "frames": result.frameCounts,
                            "model_calls": 0,
                            "meaning": "proves release timing and stop paths in this process only; a flat synthetic scene has no visual effect"])
    return lease.isHolding ? 3 : (lease.stopReason == nil ? 0 : 2)
}

@MainActor
func execute(_ command: Command, profile: KeyProfile) async throws -> Int32 {
    NSApplication.shared.setActivationPolicy(.prohibited)
    guard CGPreflightScreenCaptureAccess(), AXIsProcessTrusted() else {
        throw ProbeError("Screen Recording and Accessibility must already be granted to this launch context; nothing was requested")
    }
    guard !escapeHeld() else { throw ProbeError("Escape is held") }
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == wowBundle }
    guard apps.count == 1, let app = apps.first else { throw ProbeError("expected exactly one running WoW process, found \(apps.count)") }
    guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != app.processIdentifier else {
        throw ProbeError("WoW is frontmost or the foreground app is unknown; M0 tests background input and never switches apps")
    }
    let content = try await SCShareableContent.current
    let windows = content.windows.filter {
        $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 && $0.isOnScreen && $0.frame.width > 300
    }
    guard windows.count == 1, let window = windows.first, let bounds = windowBounds(window.windowID) else {
        throw ProbeError("expected exactly one on-screen WoW game window, found \(windows.count)")
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let runID = "m0_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6).lowercased())"
    let directory = URL(fileURLWithPath: "runs/002_wow_visual").appendingPathComponent(runID)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let log = try Log(file: directory.appendingPathComponent("events.jsonl"))

    let scale = min(1, 640 / window.frame.width)
    let config = SCStreamConfiguration()
    config.width = max(2, Int(window.frame.width * scale))
    config.height = max(2, Int(window.frame.height * scale))
    config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    config.queueDepth = 3
    config.showsCursor = false
    config.capturesAudio = false
    let feed = FrameFeed()
    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
    try stream.addStreamOutput(feed, type: .screen, sampleHandlerQueue: DispatchQueue(label: "m0.frames"))

    let target = LiveTarget(pid: app.processIdentifier, windowID: window.windowID, bounds: bounds,
                            frontPID: front.processIdentifier, feed: feed, directory: directory)
    let driver = ShellDriver(log: log, live: target)
    let lease = InputLease(profile: profile, sink: PidKeySink(pid: app.processIdentifier), clock: hostNow, emit: driver.emit)
    let signals = trapSignals(lease, log)
    var manifest: [String: Any] = [
        "schema": "m0-run/v1", "run_id": runID, "mode": "execute", "started_utc": ISO8601DateFormatter().string(from: Date()),
        "source": ["git_head": orNull(git("rev-parse", "HEAD")), "git_dirty": orNull(git("status", "--porcelain").map { !$0.isEmpty })],
        "machine": machineFacts(),
        "target": bundleFacts(app.bundleURL).merging(["pid": Int(app.processIdentifier), "window_id": Int(window.windowID),
                                                      "window_bounds": NSStringFromRect(bounds), "capture_stream": feed.streamID,
                                                      "capture_size": [config.width, config.height]]) { current, _ in current },
        "focus_at_start": ["frontmost_bundle": orNull(front.bundleIdentifier), "frontmost_pid": Int(front.processIdentifier)],
        "keys": ["profile": profile.rawValue, "codes": Dictionary(uniqueKeysWithValues: Primitive.allCases.map { ($0.rawValue, Int(profile.code($0))) })],
        "plan": command.plan.map(\.token),
        "capture": "window-only ScreenCaptureKit, audio off, cursor hidden; only pNN-before/after JPEGs are kept",
        "model_calls": 0, "provider_calls": 0,
    ]
    driver.emit("start", manifest)
    try await stream.startCapture()
    let result = await runBatch(command.plan, lease: lease,
                                gate: FrameGate(stream: feed.streamID, width: config.width, height: config.height), driver: driver)
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}

    manifest["focus_at_end"] = ["frontmost_bundle": orNull(NSWorkspace.shared.frontmostApplication?.bundleIdentifier),
                                "wow_frontmost": NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier]
    manifest["outcome"] = result.outcome
    manifest["stop_reason"] = orNull(lease.stopReason)
    manifest["pulses"] = result.pulses
    manifest["frames"] = result.frameCounts
    manifest["meaning"] = "dispatch and heuristic visual effect only; avatar movement needs labels.json"
    let labels: [String: Any] = [
        "instructions": "Fill from the pNN-before/after JPEGs and what the owner saw live. null means not assessed.",
        "pulses": result.pulses.map { pulse -> [String: Any] in
            ["index": orNull(pulse["index"]), "pulse": orNull(pulse["pulse"]), "avatar_turned": NSNull(),
             "avatar_moved_forward": NSNull(), "camera_only_change": NSNull(), "stopped_after_release": NSNull(),
             "misrouted_input_seen": NSNull(), "human_reset": NSNull(), "notes": ""]
        },
    ]
    for (name, object) in [("manifest.json", manifest), ("labels.json", labels)] {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name))
    }
    driver.emit("summary", ["outcome": result.outcome, "run_directory": directory.path])
    return lease.isHolding ? 3 : (lease.stopReason == nil ? 0 : 2)
}

func release(_ profile: KeyProfile) throws {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == wowBundle }
    guard apps.count == 1, let app = apps.first, AXIsProcessTrusted() else {
        throw ProbeError("release needs exactly one running WoW process and existing Accessibility permission")
    }
    let sink = PidKeySink(pid: app.processIdentifier)
    let codes = Primitive.allCases.map { profile.code($0) } + [48]  // 48: Tab, from M2's --target
    for code in codes { try sink.post(code, down: false) }
    try Log(file: nil).emit("release_sent", ["pid": Int(app.processIdentifier), "keys": profile.rawValue,
                                             "codes": codes.map { Int($0) }, "key_down_sent": 0])
}

#if !SEEK  // M1 builds this shell with -D SEEK and its own entry point
@main
struct M0Probe {
    static func main() async {
        let command: Command
        do { command = try parseCommand(Array(CommandLine.arguments.dropFirst())) } catch {
            fputs("HOLD: \(error)\n\(usage)\n", stderr)
            exit(64)
        }
        do {
            switch command.mode {
            case .preflight:
                let data = try JSONSerialization.data(withJSONObject: preflight(), options: [.prettyPrinted, .sortedKeys])
                FileHandle.standardOutput.write(data + Data([10]))
            case .dryRun: exit(try await dryRun(command, profile: command.profile ?? .arrows))
            case .execute: exit(try await execute(command, profile: command.profile!))
            case .release: try release(command.profile!)
            }
        } catch {
            fputs("HOLD: \(error)\n", stderr)
            exit(2)
        }
    }
}
#endif
