// M4a native shell for issue #5: Jev chooses each move of a supervised walk to zone-map
// coordinates. Perception, admissibility, the walk skill and safety stops are local (Nav.swift);
// keys go through M3's LiveKeys on a pid-targeted sink. Modes, from no effect to live effect:
//   (none) | --preflight            M0's read-only facts; no capture, input, network or files
//   --dry-run                       SimNav "wall" + ScriptedJev; no capture, OS input or network
//   --replay DIR                    arrow and coordinates readers on saved frames; no input or network
//   --sim-jev --scenario NAME       SimNav + Jev via TypeSafe; no capture or OS input
//   --execute --keys wqe --to X,Y   window capture, pid-targeted W/Q/E, Jev via TypeSafe
// Recovery after a crash or kill: m0-probe --release --keys wqe, and tap W, Q and E in WoW.
import AppKit
import Vision

let navUsage = """
    usage: m4-nav [--preflight]
           m4-nav --dry-run
           m4-nav --replay DIR
           m4-nav --sim-jev --scenario open|wall|pocket
           m4-nav --execute --keys wqe --to X,Y [--arrive R] [--label TEXT]
    Live keys: W, Q, E. Recovery: m0-probe --release --keys wqe
    """

/// The coordinates under the minimap, upscaled x3: Vision misreads the ~10 px digits at 1x.
func coordsText(_ image: CGImage) -> String {
    let box = CGRect(x: NavHUD.coordsX, y: NavHUD.coordsY, width: NavHUD.coordsWidth, height: NavHUD.coordsHeight)
    guard let crop = image.cropping(to: box),
          let context = CGContext(data: nil, width: Int(box.width) * 3, height: Int(box.height) * 3, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "" }
    context.interpolationQuality = .high
    context.draw(crop, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
    guard let scaled = context.makeImage() else { return "" }
    return ocr(scaled).map(\.0).joined(separator: " ")
}

func apiKey() throws -> String {
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
        throw ProbeError("TYPESAFE_API_KEY missing")
    }
    return key
}

/// Live body: the latest window frame, pid keys through LiveKeys and a 0.2 s watchdog timer.
final class LiveNavBody: NavBody {
    let session: Session
    let feed: FrameFeed
    let directory: URL
    let log: Log
    let keys: LiveKeys
    private let watchdog: DispatchSourceTimer
    private var frameNo = 0

    init(session: Session, feed: FrameFeed, sink: KeySink, directory: URL, log: Log) {
        self.session = session
        self.feed = feed
        self.directory = directory
        self.log = log
        let keys = LiveKeys(sink: sink, releaseCodes: NavLimits.releaseCodes, clock: hostNow) { event, fields in
            var row = fields
            row["t"] = hostNow()
            log.emit(event, row)
        }
        self.keys = keys
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "m4.watchdog", qos: .userInteractive))
        watchdog = timer
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { keys.sweepExpired() }
        timer.resume()
    }

    deinit { watchdog.cancel() }

    func now() -> Double { hostNow() }
    func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
    func emit(_ event: String, _ fields: [String: Any]) {
        var row = fields
        row["t"] = hostNow()
        log.emit(event, row)
    }
    func ownerTookFocus() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == session.app.processIdentifier
    }

    func look() -> NavObs? {
        guard let image = feed.latest else { return nil }
        if frameNo % 2 == 0 {
            write(image, to: directory.appendingPathComponent(String(format: "f%03d.jpg", frameNo)), type: .jpeg)
        }
        frameNo += 1
        let pixels = rgba(image)
        let text = coordsText(image)
        guard let at = parseCoords(text), let facing = arrowFacing(pixels) else {
            emit("unreadable", ["coords_text": text, "frame": frameNo - 1])
            return nil
        }
        let hud = observe(pixels, plates: false)
        return NavObs(x: at.x, y: at.y, facing: facing, combat: hud.combat, player: hud.player)
    }

    var holding: Bool { keys.holding }

    /// The exit sweep over NavLimits.releaseCodes; no key goes down afterwards (LiveKeys).
    func releaseAll() {
        watchdog.cancel()
        keys.releaseAll()
    }
}

/// jev.jsonl rows and the manifest's outcome, usage and latency fields, shared by --sim-jev and --execute.
func recordRun(_ result: NavResult, into run: URL, manifest base: [String: Any]) throws {
    var lines = Data()
    var prompt = 0, completion = 0
    for record in result.records where JSONSerialization.isValidJSONObject(record) {
        lines += try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) + Data([10])
        if let response = record["response"] as? [String: Any] {
            let used = tokenUsage(response)
            prompt += used.prompt
            completion += used.completion
        }
    }
    try lines.write(to: run.appendingPathComponent("jev.jsonl"))
    var manifest = base
    manifest["outcome"] = result.outcome
    manifest["decisions"] = result.decisions
    manifest["jev_calls"] = result.jevCalls
    manifest["moves"] = result.episode.attempts.map(\.json)
    manifest["token_usage"] = ["prompt": prompt, "completion": completion, "total": prompt + completion]
    manifest["latency_s"] = ["p50": latencyPercentile(result.latencies, 0.5), "p95": latencyPercentile(result.latencies, 0.95)]
    manifest["keys_used"] = Array(Set(result.codesPosted.map { Int($0) })).sorted()
    manifest["holding_at_end"] = result.holding
    if let start = result.start { manifest["start"] = ["x": start.x, "y": start.y, "facing": start.facing] }
    if let end = result.end { manifest["end"] = ["x": end.x, "y": end.y, "facing": end.facing] }
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: run.appendingPathComponent("manifest.json"))
}

func navLimits() -> [String: Any] {
    ["max_decisions": NavLimits.maxDecisions, "max_seconds": NavLimits.maxSeconds,
     "no_progress_decisions": NavLimits.noProgressDecisions, "move_seconds": NavLimits.moveSeconds,
     "repeat_cap": NavLimits.repeatCap, "forward_watchdog_s": NavLimits.forwardWatchdog,
     "blocked_window_s": NavLimits.blockedWindow, "player_safety": FightLimits.playerSafety,
     "jev_timeout_s": FightLimits.jevTimeout]
}

func navDryRun() async throws -> Int32 {
    let log = try Log(file: nil)
    let clock = FightClock(pace: 0.005)
    guard let scene = SimNav.scenario("wall", clock: clock) else { throw ProbeError("no wall scenario") }
    let (world, destination) = scene
    world.emitHandler = { event, fields in
        var row = fields
        row["t"] = clock.now()
        log.emit(event, row)
    }
    let dummy = InputLease(profile: .wqe, sink: NoEffectSink(), clock: { clock.now() }, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { world.keys.releaseAll() }, holding: { world.keys.holding })
    // After the trap: a SIGINT sent on "start" must never fall between SIG_IGN and the handler.
    log.emit("start", ["mode": "dry-run", "effects": "none: SimNav wall + ScriptedJev; no capture, OS input or network"])
    usleep(400_000)  // as M3's dry-run: a SIGINT sent on "start" lands before the loop ends, even on a slow runner
    let result = await runNav(body: world, jev: ScriptedJev(preference: NavAction.allCases), destination: destination)
    withExtendedLifetime(signals) {}
    log.emit("summary", ["outcome": result.outcome, "decisions": result.decisions, "holding": result.holding,
                         "moves": result.episode.attempts.map(\.action.rawValue), "provider_calls": 0,
                         "meaning": "proves the decision loop and the walk skill against a simulated map, not WoW"])
    return result.outcome == "ARRIVED" && !result.holding ? 0 : 2
}

/// Perception replay on saved frames: prints what the live loop would read, with no input or network.
func navReplay(_ directory: String) throws -> Int32 {
    let url = URL(fileURLWithPath: directory)
    let names = try FileManager.default.contentsOfDirectory(atPath: directory)
        .filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".png") }.sorted()
    let log = try Log(file: nil)
    for name in names {
        guard let source = CGImageSourceCreateWithURL(url.appendingPathComponent(name) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
        guard image.width == HUD.width, image.height == HUD.height else {
            log.emit("frame", ["file": name, "skipped": "\(image.width)x\(image.height) is not the calibrated layout"])
            continue
        }
        let text = coordsText(image)
        let at = parseCoords(text)
        log.emit("frame", ["file": name, "facing": orNull(arrowFacing(rgba(image)).map { Int($0.rounded()) }),
                           "coords_text": text, "x": orNull(at?.x), "y": orNull(at?.y)])
    }
    log.emit("summary", ["frames": names.count, "effects": "none: saved frames only"])
    return 0
}

/// Rehearsal: the real Jev against a simulated map, before any live walk.
func navSimJev(_ command: NavCommand) async throws -> Int32 {
    let key = try apiKey()
    guard let name = command.scenario, let scene = SimNav.scenario(name, clock: FightClock()) else {
        throw ProbeError("unknown scenario")
    }
    let (world, destination) = scene
    let run = try runDirectory("m4_sim")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    world.emitHandler = { event, fields in
        var row = fields
        row["t"] = world.clock.now()
        log.emit(event, row)
    }
    log.emit("start", ["run_id": run.id, "mode": "sim-jev", "scenario": name,
                       "effects": "SimNav + Jev via TypeSafe; no capture or OS input"])
    let result = await runNav(body: world, jev: LiveJev(key: key), destination: destination)
    let manifest: [String: Any] = [
        "schema": "m4-run/v1", "run_id": run.id, "mode": "sim-jev", "scenario": name,
        "started_utc": ISO8601DateFormatter().string(from: Date()),
        "source": ["git_head": orNull(git("rev-parse", "HEAD")), "git_dirty": orNull(git("status", "--porcelain").map { !$0.isEmpty })],
        "limits": navLimits(), "model": FightLimits.model,
        "destination": ["label": destination.label, "x": destination.x, "y": destination.y, "arrive": destination.arrive],
    ]
    try recordRun(result, into: run.url, manifest: manifest)
    log.emit("summary", ["outcome": result.outcome, "decisions": result.decisions, "run_directory": run.url.path,
                         "moves": result.episode.attempts.map(\.action.rawValue)])
    return result.outcome == "ARRIVED" ? 0 : 2
}

@MainActor
func navExecute(_ command: NavCommand) async throws -> Int32 {
    let key = try apiKey()
    guard let x = command.toX, let y = command.toY else { throw ProbeError("--to missing") }
    let destination = NavDestination(label: command.label, x: x, y: y, arrive: command.arrive)
    let session = try await wowSession(input: true, full: true)
    guard session.config.width == HUD.width, session.config.height == HUD.height else {
        throw ProbeError("capture is \(session.config.width)x\(session.config.height); M4 is calibrated for \(HUD.width)x\(HUD.height)")
    }
    let run = try runDirectory("m4")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    guard let first = await firstFrame(feed), first.image.width == HUD.width else {
        try? await stream.stopCapture()
        throw ProbeError("no \(HUD.width)-wide frame within \(Limits.firstFrameWait) s")
    }
    _ = await Task.detached { coordsText(first.image) }.value  // Vision's first OCR in a process takes ~30 s
    let sink = PidKeySink(pid: session.app.processIdentifier)
    let body = LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    defer { body.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { body.releaseAll() }, holding: { body.holding })
    guard let start = body.look() else {
        try? await stream.stopCapture()
        throw ProbeError("coordinates or minimap arrow unreadable at the start")
    }
    guard distance(start.point, destination.point) <= NavLimits.maxStartDistance else {
        try? await stream.stopCapture()
        throw ProbeError("destination is more than \(Int(NavLimits.maxStartDistance)) units away")
    }
    let manifest: [String: Any] = [
        "schema": "m4-run/v1", "run_id": run.id, "mode": "execute",
        "started_utc": ISO8601DateFormatter().string(from: Date()),
        "source": ["git_head": orNull(git("rev-parse", "HEAD")), "git_dirty": orNull(git("status", "--porcelain").map { !$0.isEmpty })],
        "machine": machineFacts(), "limits": navLimits(), "model": FightLimits.model,
        "keys": ["profile": "wqe", "codes": NavLimits.releaseCodes.map { Int($0) }],
        "capture": "window-only ScreenCaptureKit at \(HUD.width)x\(HUD.height), audio off, cursor hidden",
        "destination": ["label": destination.label, "x": destination.x, "y": destination.y, "arrive": destination.arrive],
    ]
    body.emit("start", ["run_id": run.id, "mode": "execute", "x": start.x, "y": start.y, "facing": start.facing])
    let result = await runNav(body: body, jev: LiveJev(key: key), destination: destination)
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    try recordRun(result, into: run.url, manifest: manifest)
    body.emit("summary", ["outcome": result.outcome, "run_directory": run.url.path, "decisions": result.decisions,
                          "moves": result.episode.attempts.map(\.action.rawValue)])
    return result.holding ? 3 : (result.outcome == "ARRIVED" ? 0 : 2)
}

#if NAV
@main
struct M4Nav {
    static func main() async {
        let command: NavCommand
        do { command = try parseNav(Array(CommandLine.arguments.dropFirst())) } catch {
            fputs("HOLD: \(error)\n\(navUsage)\n", stderr)
            exit(64)
        }
        do {
            switch command.mode {
            case .preflight:
                var facts = preflight()
                facts["schema"] = "m4-preflight/v1"
                let data = try JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys])
                FileHandle.standardOutput.write(data + Data([10]))
            case .dryRun: exit(try await navDryRun())
            case .replay: exit(try navReplay(command.directory ?? "."))
            case .simJev: exit(try await navSimJev(command))
            case .execute: exit(try await navExecute(command))
            }
        } catch {
            fputs("HOLD: \(error)\n", stderr)
            exit(2)
        }
    }
}
#endif
