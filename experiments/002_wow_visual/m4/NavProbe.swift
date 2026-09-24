// M4a native shell for issue #5: Jev chooses each move of a supervised walk to zone-map
// coordinates. Perception, admissibility, the walk skill and safety stops are local (Nav.swift);
// keys go through M3's LiveKeys on a pid-targeted sink. Modes, from no effect to live effect:
//   (none) | --preflight            M0's read-only facts; no capture, input, network or files
//   --dry-run                       SimNav "wall" + ScriptedJev; no capture, OS input or network
//   --replay DIR                    arrow, coordinates, tracker, target and Game Menu readers on saved frames
//   --sim-jev --scenario NAME       SimNav + Jev via TypeSafe; no capture or OS input
//   --execute --keys wqe --to X,Y   window capture, pid-targeted W/Q/E, Jev via TypeSafe
//   --hunt-dry-run | --hunt-sim-jev | --hunt --keys wqe   M4b hunts (HuntProbe.swift)
// Recovery after a crash or kill: m0-probe --release --keys wqe, and tap W, Q and E in WoW.
import AppKit
import Vision

let navUsage = """
    usage: m4-nav [--preflight]
           m4-nav --dry-run
           m4-nav --replay DIR
           m4-nav --sim-jev --scenario open|wall|pocket
           m4-nav --execute --keys wqe --to X,Y [--arrive R] [--label TEXT] [--ghost]
           m4-nav --hunt-dry-run | --hunt-sim-jev | --hunt --keys wqe
                    [--graph PATH] [--experience PATH]
           m4-nav --turn-in --keys wqe --quest NAME   at the quest's NPC; no Jev call
           m4-nav --plan --keys wqe                   read the quest log and map pins; print the zone-first order
           m4-nav --quests --graph PATH --keys wqe    Jev chooses each hand-in within one walk (quest graph)
    Live keys: W, Q, E, F10; a hunt adds Tab, Esc and the bar's skills, a turn-in Enter and chat commands.
    Recovery: m0-probe --release --keys wqe
    """

/// OCR lines of one HUD box, top to bottom, after a x3 upscale: Vision misreads ~10 px text at 1x.
func upscaledText(_ image: CGImage, _ box: CGRect) -> [String] {
    guard let crop = image.cropping(to: box),
          let context = CGContext(data: nil, width: Int(box.width) * 3, height: Int(box.height) * 3, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
    context.interpolationQuality = .high
    context.draw(crop, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
    guard let scaled = context.makeImage() else { return [] }
    return ocr(scaled).sorted { $0.1.maxY > $1.1.maxY }.map(\.0)  // Vision's boxes grow upwards
}

/// The coordinates under the minimap.
func coordsText(_ image: CGImage) -> String {
    upscaledText(image, CGRect(x: NavHUD.coordsX, y: NavHUD.coordsY, width: NavHUD.coordsWidth, height: NavHUD.coordsHeight))
        .joined(separator: " ")
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
    var ghost = false  // a ghost's health bar is empty: report full health so the walk does not stop for it

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
        guard let frame = runtimeFrame(session, feed) else { return nil }
        let image = frame.image
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
        emit("look", ["frame": frameNo - 1, "x": at.x, "y": at.y, "facing": Int(facing.rounded()), "combat": hud.combat])
        return NavObs(stamp: frame.stamp, x: at.x, y: at.y, facing: facing, combat: hud.combat, player: ghost ? 1 : hud.player)
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
        let target = upscaledText(image, HuntHUD.targetName).joined(separator: " ")
        let hud = observe(rgba(image), plates: true)
        log.emit("frame", ["file": name, "facing": orNull(arrowFacing(rgba(image)).map { Int($0.rounded()) }),
                           "coords_text": text, "x": orNull(at?.x), "y": orNull(at?.y),
                           "objectives": parseTracker(upscaledText(image, HuntHUD.tracker)).map { "\($0.quest): \($0.done)/\($0.need) \($0.text)" },
                           "target": target, "target_health": Int(hud.target * 100),
                           "player": Int(hud.player * 100), "mana": Int(hud.mana * 100), "combat": hud.combat,
                           "target_plate": orNull(hud.plate.map { [$0.x0, $0.x1, $0.top, $0.bottom] }),
                           "plates": nameplates(rgba(image)).map { ["hostile": $0.hostile, "x": Int($0.centre), "y": $0.y0, "name": plateName(image, $0)] },
                           "area": orNull(questArea(rgba(image)).map { ["bearing": Int($0.bearing.rounded()), "distance": roundTo($0.distance), "inside": $0.inside] }),
                           "game_menu": upscaledText(image, HuntHUD.gameMenu).joined(separator: " ").lowercased().contains("game menu")])
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
    let result = await runNav(body: world, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout), destination: destination)
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
    body.ghost = command.ghost
    defer { body.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { body.releaseAll() }, holding: { body.holding })
    await zoomOut(body.keys, log)
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
        "ghost": command.ghost,
    ]
    body.emit("start", ["run_id": run.id, "mode": "execute", "x": start.x, "y": start.y, "facing": start.facing])
    guard await warmJev(key) != nil else { throw ProbeError("Jev did not answer a warm-up question within 30 s") }
    let result = await runNav(body: body, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout), destination: destination)
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
            case .huntDryRun, .huntSimJev, .hunt:
                let graph = try command.graph.map { try GraphSession.load(URL(fileURLWithPath: $0)) }
                let experience = try huntExperience(command.experience, graph: graph)
                switch command.mode {
                case .huntDryRun: exit(try await huntDryRun(graph: graph, experience: experience))
                case .huntSimJev: exit(try await huntSimJev(graph: graph, experience: experience))
                case .hunt: exit(try await huntExecute(graph: graph, experience: experience))
                default: fatalError("unreachable")
                }
            case .turnIn: exit(try await questExecute(command))
            case .plan: exit(try await planExecute())
            case .quests: exit(try await questsExecute(graph: try GraphSession.load(URL(fileURLWithPath: command.graph!))))
            }
        } catch {
            fputs("HOLD: \(error)\n", stderr)
            exit(2)
        }
    }
}
#endif
