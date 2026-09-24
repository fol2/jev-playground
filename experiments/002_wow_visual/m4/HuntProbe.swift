// M4b native shell for issue #5: a supervised hunt for the creatures that quest objectives name. Jev
// chooses each hunt action (Hunt.swift) and, inside each fight, each M3 action (a fresh M3 LiveHost per
// fight). Modes, reached through m4-nav:
//   --hunt-dry-run          SimHunt field + ScriptedJev; no capture, OS input or network
//   --hunt-sim-jev          SimHunt field + Jev via TypeSafe; no capture or OS input
//   --hunt --keys wqe       window capture, pid-targeted keys (W Q E Tab Esc, and M3's 1-4), Jev via TypeSafe
// Recovery after a crash or kill: m0-probe --release --keys wqe, and tap W, Q, E, 2 and Esc in WoW.
import AppKit
import Vision

/// Capture-pixel boxes of the 2560x1320 layout, read by OCR after a x3 upscale.
enum HuntHUD {
    static let tracker = CGRect(x: 2200, y: 400, width: 360, height: 300)  // objectives, below "All Objectives"
    static let targetName = CGRect(x: 1590, y: 950, width: 330, height: 50)
    static let gameMenu = CGRect(x: 1150, y: 440, width: 260, height: 70)  // the Game Menu's title
}

let hunterPreference: [HuntAction] = [.fight, .eatDrink, .rest, .toCreature, .toArea, .nextTarget, .lookAround, .detourRight90, .detourRight45,
                                      .detourLeft90, .detourLeft45, .backTrack] + HuntAction.compass

/// The name above an untargeted plate bar (about 20 px text over a 15 px bar), OCR'd after a x3 upscale.
func plateName(_ image: CGImage, _ bar: PlateBar) -> String {
    upscaledText(image, CGRect(x: bar.x0 - 20, y: bar.y0 - 34, width: bar.x1 - bar.x0 + 70, height: 32)).joined(separator: " ")
}

/// The fields read from pixels alone: the M3 bars and ring, the minimap arrow and the quest area.
func pixelObs(_ pixels: RGBA) -> HuntObs {
    let hud = observe(pixels, plates: false)
    return HuntObs(player: hud.player, mana: hud.mana, combat: hud.combat, facing: arrowFacing(pixels), area: questArea(pixels))
}

final class LiveHuntHost: HuntHost {
    let session: Session
    let feed: FrameFeed
    let sink: PidKeySink
    let directory: URL
    let log: Log
    let keys: LiveKeys
    private let watchdog: DispatchSourceTimer
    private let lock = NSLock()
    private var fighting: LiveHost?  // read by the signal handler's thread
    private var frameNo = 0
    private var walkNo = 0
    private var fights = 0
    private var lastTarget: String?
    let fightJev: JevClient  // M3's 4 s timeout, whatever the hunt's own decisions wait

    init(session: Session, feed: FrameFeed, sink: PidKeySink, directory: URL, log: Log, fightJev: JevClient) {
        self.fightJev = fightJev
        self.session = session
        self.feed = feed
        self.sink = sink
        self.directory = directory
        self.log = log
        let keys = LiveKeys(sink: sink, releaseCodes: HuntLimits.releaseCodes, clock: hostNow) { event, fields in
            var row = fields
            row["t"] = hostNow()
            log.emit(event, row)
        }
        self.keys = keys
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "m4.hunt.watchdog", qos: .userInteractive))
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

    /// The newest frame, or nil when there is none or it is older than `HuntLimits.maxFrameAge`: a stalled
    /// capture must not pass for a calm, healthy scene.
    private func freshImage() -> CGImage? {
        guard let frame = feed.latestFrame, hostNow() - frame.pts <= HuntLimits.maxFrameAge else { return nil }
        return frame.image
    }

    func vitals() -> HuntObs? {
        freshImage().map { pixelObs(rgba($0)) }
    }

    /// The walk skill's reading, as M4a's: coordinates, the minimap arrow and the M3 bars. Every other
    /// frame is kept as w###.jpg.
    func look() -> NavObs? {
        guard let image = freshImage() else { return nil }
        if walkNo % 2 == 0 { write(image, to: directory.appendingPathComponent(String(format: "w%03d.jpg", walkNo)), type: .jpeg) }
        walkNo += 1
        let pixels = rgba(image)
        let text = coordsText(image)
        guard let at = parseCoords(text), let facing = arrowFacing(pixels) else {
            emit("unreadable", ["coords_text": text, "walk_frame": walkNo - 1])
            return nil
        }
        let hud = observe(pixels, plates: false)
        emit("walk_look", ["walk_frame": walkNo - 1, "x": at.x, "y": at.y, "facing": Int(facing.rounded()), "combat": hud.combat])
        return NavObs(x: at.x, y: at.y, facing: facing, combat: hud.combat, player: hud.player)
    }

    /// Everything a decision needs: the tracker, target, Game Menu, position, and the creatures whose
    /// plates are in view with their names. Nil when the tracker is unreadable.
    func survey() -> HuntObs? {
        guard let image = freshImage() else { return nil }
        write(image, to: directory.appendingPathComponent(String(format: "h%03d.jpg", frameNo)), type: .jpeg)
        frameNo += 1
        let lines = upscaledText(image, HuntHUD.tracker)
        guard !lines.isEmpty else {
            emit("unreadable", ["frame": frameNo - 1])
            return nil
        }
        let pixels = rgba(image)
        let name = upscaledText(image, HuntHUD.targetName).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        var o = pixelObs(pixels)
        o.objectives = parseTracker(lines)
        o.target = name.isEmpty ? nil : name
        o.targetAlive = !name.isEmpty && observe(pixels, plates: false).target > 0.005
        o.gameMenu = upscaledText(image, HuntHUD.gameMenu).joined(separator: " ").lowercased().contains("game menu")
        if let at = parseCoords(coordsText(image)), let facing = o.facing {
            o.here = NavObs(x: at.x, y: at.y, facing: facing, combat: o.combat, player: o.player)
        }
        if let facing = o.facing {
            o.seen = nameplates(pixels).compactMap { bar in
                let label = plateName(image, bar)
                return label.filter(\.isLetter).count >= 4 ? sighting(bar, name: label, facing: facing, width: image.width, height: image.height) : nil
            }
        }
        lastTarget = o.target
        emit("look", ["frame": frameNo - 1, "tracker": lines, "target": orNull(o.target), "alive": o.targetAlive,
                      "health": Int(o.player * 100), "mana": Int(o.mana * 100), "combat": o.combat, "game_menu": o.gameMenu,
                      "facing": orNull(o.facing.map { Int($0.rounded()) }), "x": orNull(o.here?.x), "y": orNull(o.here?.y),
                      "area": orNull(o.area.map { ["bearing": Int($0.bearing.rounded()), "distance": roundTo($0.distance), "inside": $0.inside] }),
                      "seen": o.seen.map { ["name": $0.name, "hostile": $0.hostile, "bearing": Int($0.bearing.rounded()), "near": $0.near] }])
        return o
    }

    /// One M3 episode on its own LiveHost: its clock, budgets and watchdog start fresh, and its frames go
    /// to their own directory. Its corpse search also looks for the creature being fought.
    func fight(jev: JevClient, inCombat: Bool) async -> FightResult {
        fights += 1
        let folder = directory.appendingPathComponent(String(format: "fight%d", fights))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let host = LiveHost(session: session, feed: feed, sink: sink, directory: folder, log: log)
        if let name = lastTarget { host.corpseNames.append(name.lowercased()) }
        lock.withLock { fighting = host }
        defer { lock.withLock { fighting = nil } }
        emit("fight_start", ["fight": fights, "target": orNull(lastTarget), "in_combat": inCombat])
        return await runFight(host: host, jev: fightJev, startHealth: inCombat ? 0 : FightLimits.startHealth)
    }

    var holding: Bool { keys.holding || lock.withLock { fighting?.holdingKeys ?? false } }

    /// The exit sweep over both key sets; no key goes down afterwards (LiveKeys).
    func releaseAll() {
        watchdog.cancel()
        keys.releaseAll()
        lock.withLock { fighting }?.releaseAll()
    }
}

/// jev.jsonl rows (hunt decisions, then each fight's decisions) and the manifest's outcome, usage and latency.
func recordHunt(_ result: HuntResult, into run: URL, manifest base: [String: Any]) throws {
    var lines = Data()
    var prompt = 0, completion = 0
    let rows = result.records + result.fights.flatMap(\.jevRecords)
    for record in rows where JSONSerialization.isValidJSONObject(record) {
        lines += try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) + Data([10])
        if let response = record["response"] as? [String: Any] {
            let used = tokenUsage(response)
            prompt += used.prompt
            completion += used.completion
        }
    }
    try lines.write(to: run.appendingPathComponent("jev.jsonl"))
    let objectives = { (list: [Objective]) in list.map { ["quest": $0.quest, "objective": $0.text, "done": $0.done, "need": $0.need] } }
    var manifest = base
    manifest["outcome"] = result.outcome
    manifest["hunt_decisions"] = result.decisions
    manifest["steps"] = result.steps.map(\.json)
    manifest["fights"] = result.fights.map { ["outcome": $0.outcome, "decisions": $0.decisions] }
    manifest["objectives_start"] = objectives(result.start)
    manifest["objectives_end"] = objectives(result.end)
    manifest["jev_calls"] = rows.count
    manifest["token_usage"] = ["prompt": prompt, "completion": completion, "total": prompt + completion]
    let latencies = result.latencies + result.fights.flatMap(\.latencies)
    manifest["latency_s"] = ["p50": latencyPercentile(latencies, 0.5), "p95": latencyPercentile(latencies, 0.95)]
    manifest["keys_used"] = Array(Set((result.codesPosted + result.fights.flatMap(\.codesPosted)).map { Int($0) })).sorted()
    manifest["holding_at_end"] = result.holding
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: run.appendingPathComponent("manifest.json"))
}

/// One tiny question before the hunt: TypeSafe's first call after a pause took 5.9 s (then 0.3 s), and
/// live hunts 2 and 4 ended JEV_FAILED on a first call past its timeout. Not a decision; nothing moves.
func warmJev(_ key: String) async -> Double? {
    let began = hostNow()
    let question: [String: Any] = ["type": "choice", "instructions": "Warm-up: choose either.", "criteria": ["A": "first", "B": "second"]]
    guard (try? await LiveJev(key: key, timeout: 30).ask(state: ["warm_up": true], question: question)) != nil else { return nil }
    return hostNow() - began
}

func huntLimits() -> [String: Any] {
    ["max_decisions": HuntLimits.maxDecisions, "max_seconds": HuntLimits.maxSeconds, "max_fights": HuntLimits.maxFights,
     "search_limit": HuntLimits.searchLimit, "rest_s": HuntLimits.restSeconds, "max_walks": HuntLimits.maxMoves, "walk_s": NavLimits.moveSeconds,
     "player_safety": FightLimits.playerSafety, "heal_mana": FightLimits.healMana, "fight_start_health": FightLimits.startHealth,
     "eat_below_health": HuntLimits.eatBelowHealth, "eat_below_mana": HuntLimits.eatBelowMana, "walk_health": HuntLimits.walkHealth,
     "fight_max_decisions": FightLimits.maxDecisions, "fight_max_seconds": FightLimits.maxSeconds,
     "hunt_jev_timeout_s": HuntLimits.jevTimeout, "fight_jev_timeout_s": FightLimits.jevTimeout]
}

func huntDryRun() async throws -> Int32 {
    let log = try Log(file: nil)
    let clock = FightClock(pace: 0.005)
    let world = SimHunt.field(clock: clock)
    world.world.emitHandler = { event, fields in
        var row = fields
        row["t"] = clock.now()
        log.emit(event, row)
    }
    let dummy = InputLease(profile: .wqe, sink: NoEffectSink(), clock: { clock.now() }, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { world.keys.releaseAll() }, holding: { world.keys.holding })
    log.emit("start", ["mode": "hunt-dry-run", "effects": "none: SimHunt field + ScriptedJev; no capture, OS input or network"])
    usleep(400_000)  // as the walk's dry-run: a SIGINT sent on "start" lands inside the loop
    let result = await runHunt(host: world, jev: ScriptedJev(preference: hunterPreference))
    withExtendedLifetime(signals) {}
    log.emit("summary", ["outcome": result.outcome, "decisions": result.decisions, "fights": result.fights.count,
                         "holding": result.holding, "actions": result.steps.map(\.action.rawValue), "provider_calls": 0,
                         "meaning": "proves the hunt loop, targeting keys and stops against a simulated field, not WoW"])
    return !result.fights.isEmpty && !result.holding ? 0 : 2
}

/// Rehearsal: the real Jev against the simulated field, before any live hunt.
func huntSimJev() async throws -> Int32 {
    let key = try apiKey()
    let world = SimHunt.field(clock: FightClock())
    let run = try runDirectory("m4_hunt_sim")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    world.world.emitHandler = { event, fields in
        var row = fields
        row["t"] = world.clock.now()
        log.emit(event, row)
    }
    guard let warm = await warmJev(key) else { throw ProbeError("Jev did not answer a warm-up question within 30 s") }
    log.emit("start", ["run_id": run.id, "mode": "hunt-sim-jev", "effects": "SimHunt + Jev via TypeSafe; no capture or OS input",
                       "jev_warm_up_s": roundTo(warm)])
    let result = await runHunt(host: world, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout))
    try recordHunt(result, into: run.url, manifest: [
        "schema": "m4-hunt-run/v1", "run_id": run.id, "mode": "hunt-sim-jev", "scenario": "field",
        "started_utc": ISO8601DateFormatter().string(from: Date()),
        "source": ["git_head": orNull(git("rev-parse", "HEAD")), "git_dirty": orNull(git("status", "--porcelain").map { !$0.isEmpty })],
        "limits": huntLimits(), "model": FightLimits.model,
    ])
    log.emit("summary", ["outcome": result.outcome, "decisions": result.decisions, "fights": result.fights.count,
                         "run_directory": run.url.path, "actions": result.steps.map(\.action.rawValue)])
    return result.fights.isEmpty ? 2 : 0
}

@MainActor
func huntExecute() async throws -> Int32 {
    let key = try apiKey()
    let session = try await wowSession(input: true, full: true)
    guard session.config.width == HUD.width, session.config.height == HUD.height else {
        throw ProbeError("capture is \(session.config.width)x\(session.config.height); M4 is calibrated for \(HUD.width)x\(HUD.height)")
    }
    let run = try runDirectory("m4_hunt")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    guard let first = await firstFrame(feed), first.image.width == HUD.width else {
        try? await stream.stopCapture()
        throw ProbeError("no \(HUD.width)-wide frame within \(Limits.firstFrameWait) s")
    }
    _ = await Task.detached { upscaledText(first.image, HuntHUD.tracker) }.value  // Vision's first OCR takes ~30 s
    guard let warm = await warmJev(key) else {
        try? await stream.stopCapture()
        throw ProbeError("Jev did not answer a warm-up question within 30 s")
    }
    let sink = PidKeySink(pid: session.app.processIdentifier)
    let host = LiveHuntHost(session: session, feed: feed, sink: sink, directory: run.url, log: log, fightJev: LiveJev(key: key))
    defer { host.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { host.releaseAll() }, holding: { host.holding })
    guard let start = host.survey(), !start.objectives.isEmpty else {
        try? await stream.stopCapture()
        throw ProbeError("the objectives tracker is unreadable or empty at the start")
    }
    let manifest: [String: Any] = [
        "schema": "m4-hunt-run/v1", "run_id": run.id, "mode": "hunt",
        "started_utc": ISO8601DateFormatter().string(from: Date()),
        "source": ["git_head": orNull(git("rev-parse", "HEAD")), "git_dirty": orNull(git("status", "--porcelain").map { !$0.isEmpty })],
        "machine": machineFacts(), "limits": huntLimits(), "model": FightLimits.model,
        "keys": ["profile": "wqe", "codes": Set(HuntLimits.releaseCodes + FightLimits.releaseCodes).map { Int($0) }.sorted()],
        "capture": "window-only ScreenCaptureKit at \(HUD.width)x\(HUD.height), audio off, cursor hidden",
    ]
    host.emit("start", ["run_id": run.id, "mode": "hunt", "objectives": start.objectives.count, "jev_warm_up_s": roundTo(warm)])
    let result = await runHunt(host: host, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout))
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    try recordHunt(result, into: run.url, manifest: manifest)
    host.emit("summary", ["outcome": result.outcome, "run_directory": run.url.path, "decisions": result.decisions,
                          "fights": result.fights.map(\.outcome), "actions": result.steps.map(\.action.rawValue)])
    return host.holding ? 3 : (result.fights.contains { $0.outcome.hasPrefix("KILLED") } ? 0 : 2)
}
