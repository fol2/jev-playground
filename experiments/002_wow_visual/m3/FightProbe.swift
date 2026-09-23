// M3 native shell for issue #5: Jev chooses each next action of a supervised fight from
// screen-derived state. Perception, admissibility, skills and safety stops are local.
// Modes, from no effect to live effect:
//   (none) | --preflight   M0's read-only facts; no capture, input, network or files
//   --dry-run              SimFight + ScriptedJev; no capture, OS input or network
//   --execute --keys wqe   full-resolution WoW-window capture, pid-targeted keys, one
//                          background right-click to loot, Jev via TypeSafe
// Recovery after a crash or kill: m0-probe --release --keys wqe, and tap 1-4 / Tab in WoW.
import AppKit
import Vision

let fightUsage = """
    usage: m3-fight [--preflight]
           m3-fight --dry-run
           m3-fight --execute --keys wqe
    Live keys: Tab, 1-4, Q/W/E. Recovery: m0-probe --release --keys wqe
    """

let fightNames = ["juvenile vuldren", "pesky cirrusfly"]

func ocr(_ image: CGImage) -> [(String, CGRect)] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { observation in
        observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
    }
}

func chatLines(_ image: CGImage) -> [String] {
    let rect = CGRect(x: 0, y: 0.62 * Double(HUD.height), width: 0.25 * Double(HUD.width), height: 0.32 * Double(HUD.height))
    guard let crop = image.cropping(to: rect) else { return [] }
    return ocr(crop).map(\.0)
}

func corpseLabel(_ image: CGImage, _ names: [String]) -> CGRect? {
    let view = CGRect(x: 0.2 * Double(HUD.width), y: 0.2 * Double(HUD.height),
                      width: 0.6 * Double(HUD.width), height: 0.45 * Double(HUD.height))
    guard let crop = image.cropping(to: view) else { return nil }
    let boxes = ocr(crop).compactMap { text, box -> CGRect? in
        guard fuzzyNameMatch(text, names) else { return nil }
        return CGRect(x: view.minX + box.minX * view.width,
                      y: view.minY + (1 - box.maxY) * view.height,
                      width: box.width * view.width, height: box.height * view.height)
    }
    return boxes.filter { $0.height >= 22 }.max { $0.height < $1.height }
}

func tokenUsage(_ body: [String: Any]) -> (prompt: Int, completion: Int) {
    let usage = body["usage"] as? [String: Any] ?? [:]
    let prompt = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int) ?? 0
    let completion = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int) ?? 0
    return (prompt, completion)
}

/// TypeSafe's System One. The same question is asked again, up to twice and 2 s apart, after HTTP 529
/// (overloaded) or a timeout: on 23 Sept both ended live walks and hunts, and a fight that stops
/// leaves the character standing in combat. Any other failure, or a third, is the caller's to handle.
struct LiveJev: JevClient {
    let key: String
    var timeout = FightLimits.jevTimeout
    var retries = 2
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["model": FightLimits.model, "state": state, "questions": ["action": question]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        for attempt in 0...retries {
            let transient: Error
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] { return body }
                guard status == 529 else { throw ProbeError("Jev HTTP \(status)") }
                transient = ProbeError("Jev HTTP 529")
            } catch let error as URLError where error.code == .timedOut {
                transient = error
            }
            if attempt == retries { throw transient }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw ProbeError("unreachable")
    }
}

/// Live skills: pid-targeted taps/holds, a held Lightning Bolt with a 4 s watchdog, OCR, loot click.
final class LiveHost: FightHost {
    let origin: Double
    let session: Session
    let feed: FrameFeed
    let directory: URL
    let log: Log
    let keys: LiveKeys
    private let watchdog: DispatchSourceTimer
    private var frameNo = 0
    var walkedMs = 0
    var corpseNames = fightNames  // M4b adds the creature a hunt fights
    var turnedMs = 0

    init(session: Session, feed: FrameFeed, sink: PidKeySink, directory: URL, log: Log) {
        self.origin = hostNow()
        self.session = session
        self.feed = feed
        self.directory = directory
        self.log = log
        let keys = LiveKeys(sink: sink, releaseCodes: FightLimits.releaseCodes, clock: hostNow) { event, fields in
            var row = fields
            row["t"] = hostNow()
            log.emit(event, row)
        }
        self.keys = keys
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "m3.watchdog", qos: .userInteractive))
        self.watchdog = timer
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { keys.sweepExpired() }
        timer.resume()
    }

    deinit { watchdog.cancel() }

    func now() -> Double { hostNow() - origin }
    func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
    func emit(_ event: String, _ fields: [String: Any]) {
        var row = fields
        row["t"] = hostNow()
        log.emit(event, row)
    }
    var holdingKeys: Bool { keys.holding }
    var codesPosted: [UInt16] { keys.codesPosted }
    func wowFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == session.app.processIdentifier
    }

    func latestImage() -> CGImage? { feed.latest }

    func refreshNotice() -> Bool {
        guard let image = latestImage() else { return false }
        let rect = CGRect(x: 0.3 * Double(HUD.width), y: 0.05 * Double(HUD.height),
                          width: 0.4 * Double(HUD.width), height: 0.25 * Double(HUD.height))
        guard let crop = image.cropping(to: rect) else { return false }
        let top = ocr(crop).map(\.0).joined(separator: " ")
        return top.lowercased().contains("refresh")
    }

    func startCorpseVisible() -> Bool {
        guard let image = latestImage(), let label = corpseLabel(image, corpseNames) else { return false }
        write(image, to: directory.appendingPathComponent("start-corpse.jpg"), type: .jpeg)
        emit("start_corpse", ["x": Int(label.midX), "y": Int(label.maxY), "height": Int(label.height)])
        return true
    }

    func errorText() -> String? {
        guard let image = latestImage() else { return nil }
        let rect = CGRect(x: 1000, y: 130, width: 560, height: 80)
        guard let crop = image.cropping(to: rect) else { return nil }
        let text = ocr(crop).map(\.0).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    func observe(plates: Bool) -> Obs { look("obs", plates: plates) }

    func look(_ tag: String, plates: Bool) -> Obs {
        guard let image = latestImage() else { return Obs() }
        if frameNo % 2 == 0 {
            write(image, to: directory.appendingPathComponent(String(format: "f%03d-%@.jpg", frameNo, tag)), type: .jpeg)
        }
        frameNo += 1
        return main.observe(rgba(image), plates: plates)
    }

    func releaseBolt() { keys.lift(FightLimits.bolt) }

    /// The exit sweep over FightLimits.releaseCodes; no key goes down afterwards (LiveKeys).
    func releaseAll() {
        watchdog.cancel()
        keys.releaseAll()
    }

    private func tap(_ code: UInt16) async {
        keys.press(code)
        await sleep(0.06)
        keys.lift(code)
    }

    private func hold(_ code: UInt16, _ ms: Int) async {
        keys.press(code)
        await sleep(Double(ms) / 1000)
        keys.lift(code)
        if code == FightLimits.forward { walkedMs += ms } else { turnedMs += ms }
    }

    private func face() async -> String {
        for _ in 0..<6 {
            let o = look("face", plates: true)
            guard let dx = offset(o) else { return "target nameplate not visible" }
            if abs(dx) <= FightLimits.faceTolerance { return "target centred" }
            guard turnedMs < FightLimits.turnBudgetMs else { return "turn budget spent" }
            let ms = Int(min(250, max(60, abs(dx) / 2.1 * 800)))
            await hold(dx < 0 ? FightLimits.turnLeft : FightLimits.turnRight, ms)
            await sleep(0.35)
        }
        return "not centred after 6 turns"
    }

    private func approach() async -> String {
        for _ in 0..<14 {
            let o = look("approach", plates: true)
            if !o.rangeRed { return "within Lightning Bolt range" }
            if let dx = offset(o), abs(dx) > 0.08, turnedMs < FightLimits.turnBudgetMs {
                let ms = Int(min(250, max(60, abs(dx) / 2.1 * 800)))
                await hold(dx < 0 ? FightLimits.turnLeft : FightLimits.turnRight, ms)
                await sleep(0.3)
                continue
            }
            guard walkedMs < FightLimits.walkBudgetMs else { return "walking budget spent, still out of range" }
            await hold(FightLimits.forward, 250)
            await sleep(0.2)
        }
        return "still out of range after 14 steps"
    }

    private func castHeld() async -> String {
        let pre = look("cast", plates: false)
        keys.grant(FightLimits.bolt, seconds: FightLimits.watchdogSeconds)
        if !keys.isDown(FightLimits.bolt) { keys.press(FightLimits.bolt) }
        var watch = CastWatch(pre: pre)
        let until = now() + 3.0
        while now() < until {
            await sleep(0.1)
            keys.grant(FightLimits.bolt, seconds: FightLimits.watchdogSeconds)
            let o = look("cast", plates: false)
            if o.errorRed && !pre.errorRed && !o.casting && !watch.seen {
                releaseBolt()
                return "Lightning Bolt not cast: a new red error message appeared (key released)"
            }
            watch.feed(o)
            if watch.reached75 {
                return "Lightning Bolt cast at 75 %; the key stays held, so the next cast follows unless another action is chosen"
            }
        }
        releaseBolt()
        return watch.seen ? "Lightning Bolt still casting (key released)" : "Lightning Bolt did not start (key released)"
    }

    private func castSpell(_ code: UInt16, _ name: String) async -> String {
        let pre = look("cast", plates: false)
        var watch = CastWatch(pre: pre)
        let staleError = pre.errorRed
        let until = now() + 2.8
        var lastPress = -9.0
        while now() < until {
            if now() - lastPress >= 0.3 { await tap(code); lastPress = now() }
            await sleep(0.1)
            let o = look("cast", plates: false)
            if o.errorRed && !staleError && !o.casting && !watch.seen {
                return "\(name) not cast: a new red error message appeared"
            }
            watch.feed(o)
            if watch.reached75 { return "\(name) cast at 75 % and finishing" }
            if watch.seen && !o.casting { return "\(name) cast finished or broken" }
        }
        return watch.seen ? "\(name) still casting" : "\(name) did not start"
    }

    private func loot(_ episode: inout Episode) async -> String {
        guard let image = latestImage(), let label = corpseLabel(image, corpseNames) else {
            return "no corpse label visible"
        }
        let fx = label.midX / Double(HUD.width), fy = (label.maxY + 200) / Double(HUD.height)
        guard (0.2...0.8).contains(fx), (0.35...0.8).contains(fy) else { return "corpse point outside the view" }
        let before = chatLines(image)
        let bounds = session.window.frame
        do {
            let routed = try routedTarget(pid: session.app.processIdentifier, window: session.window.windowID, bounds: bounds)
            let at = CGPoint(x: bounds.minX + bounds.width * fx, y: bounds.minY + bounds.height * fy)
            let request = NativeBackgroundClickDispatchRequest(
                target: routed, eventTapPointTopLeft: at, appKitPoint: at, clickCount: 1, mouseButton: .right)
            _ = try NativeBackgroundClickTransport().dispatch(request)
        } catch {
            return "loot click failed: \(error)"
        }
        var fresh: [String] = []
        for _ in 0..<FightLimits.lootPolls where fresh.isEmpty {
            await sleep(FightLimits.lootPollSeconds)
            guard let after = latestImage() else { continue }
            write(after, to: directory.appendingPathComponent("loot-after.jpg"), type: .jpeg)
            fresh = chatLines(after).filter { ($0.contains("receive loot") || $0.contains("You loot")) && !before.contains($0) }
        }
        episode.looted = !fresh.isEmpty
        return episode.looted ? "looted: \(fresh.joined(separator: "; "))" : "right-clicked the corpse; no new loot line in chat"
    }

    func perform(_ action: FightAction, observation: Obs, episode: inout Episode) async -> String {
        switch action {
        case .buffWeapon:
            await tap(FightLimits.buff)
            await sleep(1.5)
            return look("buff", plates: false).buff ? "enchant active" : "enchant not seen"
        case .selectTarget:
            await tap(FightLimits.tab)
            await sleep(1.0)
            episode.meleeOn = false
            return look("tab", plates: true).plate != nil ? "a target is selected" : "no target selected"
        case .faceTarget:
            return await face()
        case .approachToRange:
            return await approach()
        case .castLightningBolt:
            return await castHeld()
        case .startMelee:
            await tap(FightLimits.melee)
            episode.meleeOn = true
            return "automatic swings on"
        case .heal:
            return await castSpell(FightLimits.heal, "Healing Wave")
        case .lootCorpse:
            return await loot(&episode)
        case .wait:
            await sleep(1)
            return "waited one second"
        case .stop:
            return "stop"
        }
    }
}

func fightDryRun() async throws -> Int32 {
    let log = try Log(file: nil)
    let clock = FightClock(pace: 0.02)
    let world = SimFight(clock: clock)
    world.emitHandler = { event, fields in
        var row = fields
        row["t"] = clock.now()
        log.emit(event, row)
    }
    let dummy = InputLease(profile: .wqe, sink: NoEffectSink(), clock: { clock.now() }, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { world.releaseAll() }, holding: { world.holdingKeys })
    // After the trap: a SIGINT sent on "start" must never fall between SIG_IGN and the handler.
    log.emit("start", ["mode": "dry-run",
                       "effects": "none: SimFight + ScriptedJev; no capture, OS input or network"])
    usleep(400_000)  // as M0's observer stall: a SIGINT sent on "start" lands before the loop ends, even on a slow runner
    let result = await runFight(host: world, jev: ScriptedJev())
    withExtendedLifetime(signals) {}
    let summary: [String: Any] = [
        "outcome": result.outcome, "decisions": result.decisions, "jev_calls": result.jevCalls,
        "walked_ms": result.walkedMs, "turned_ms": result.turnedMs, "holding": result.holdingKeys,
        "latency_p50": latencyPercentile(result.latencies, 0.5),
        "latency_p95": latencyPercentile(result.latencies, 0.95),
        "model_calls": result.jevCalls, "provider_calls": 0,
        "meaning": "proves the decision loop against a simulated fight, not WoW",
    ]
    log.emit("summary", summary)
    return result.outcome == "KILLED_AND_LOOTED" && !result.holdingKeys ? 0 : 2
}

@MainActor
func fightExecute() async throws -> Int32 {
    guard let apiKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !apiKey.isEmpty else {
        throw ProbeError("TYPESAFE_API_KEY missing")
    }
    let session = try await wowSession(input: true, full: true)
    guard session.config.width == HUD.width, session.config.height == HUD.height else {
        throw ProbeError("capture is \(session.config.width)x\(session.config.height); M3 is calibrated for \(HUD.width)x\(HUD.height)")
    }
    let run = try runDirectory("m3")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    FileManager.default.createFile(atPath: run.url.appendingPathComponent("jev.jsonl").path, contents: nil)
    let jevFile = try FileHandle(forWritingTo: run.url.appendingPathComponent("jev.jsonl"))
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    guard let first = await firstFrame(feed), first.image.width == HUD.width else {
        try? await stream.stopCapture()
        throw ProbeError("no \(HUD.width)-wide frame within \(Limits.firstFrameWait) s")
    }
    let warm = Task.detached { _ = ocr(first.image.cropping(to: CGRect(x: 0, y: 0, width: 400, height: 100)) ?? first.image) }
    let sink = PidKeySink(pid: session.app.processIdentifier)
    _ = await warm.value
    let host = LiveHost(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    defer { host.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { host.releaseAll() }, holding: { host.holdingKeys })
    var manifest: [String: Any] = [
        "schema": "m3-run/v1", "run_id": run.id, "mode": "execute",
        "started_utc": ISO8601DateFormatter().string(from: Date()),
        "source": ["git_head": orNull(git("rev-parse", "HEAD")),
                   "git_dirty": orNull(git("status", "--porcelain").map { !$0.isEmpty })],
        "machine": machineFacts(),
        "limits": ["max_decisions": FightLimits.maxDecisions, "max_seconds": FightLimits.maxSeconds,
                   "player_safety": FightLimits.playerSafety, "walk_budget_ms": FightLimits.walkBudgetMs,
                   "turn_budget_ms": FightLimits.turnBudgetMs, "watchdog_s": FightLimits.watchdogSeconds,
                   "jev_timeout_s": FightLimits.jevTimeout, "loot_polls": FightLimits.lootPolls],
        "keys": ["profile": "wqe", "codes": FightLimits.releaseCodes.map { Int($0) }],
        "capture": "window-only ScreenCaptureKit at \(HUD.width)x\(HUD.height), audio off, cursor hidden",
        "model": FightLimits.model,
    ]
    host.emit("start", ["run_id": run.id, "mode": "execute"])
    let result = await runFight(host: host, jev: LiveJev(key: apiKey))
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}

    for record in result.jevRecords {
        if JSONSerialization.isValidJSONObject(record),
           let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
            try? jevFile.write(contentsOf: data + Data([10]))
        }
    }
    var prompt = 0, completion = 0
    for record in result.jevRecords {
        if let response = record["response"] as? [String: Any] {
            let used = tokenUsage(response)
            prompt += used.prompt
            completion += used.completion
        }
    }
    manifest["outcome"] = result.outcome
    manifest["decisions"] = result.decisions
    manifest["jev_calls"] = result.jevCalls
    manifest["token_usage"] = ["prompt": prompt, "completion": completion, "total": prompt + completion]
    manifest["latency_s"] = ["p50": latencyPercentile(result.latencies, 0.5),
                             "p95": latencyPercentile(result.latencies, 0.95)]
    manifest["keys_used"] = Array(Set(result.codesPosted.map { Int($0) })).sorted()
    manifest["walked_ms"] = result.walkedMs
    manifest["turned_ms"] = result.turnedMs
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: run.url.appendingPathComponent("manifest.json"))
    host.emit("summary", ["outcome": result.outcome, "run_directory": run.url.path,
                          "decisions": result.decisions, "jev_calls": result.jevCalls])
    return result.holdingKeys ? 3 : (result.outcome == "KILLED_AND_LOOTED" ? 0 : 2)
}

#if FIGHT && !NAV  // M4's NavProbe.swift reuses this file's helpers under -D NAV
@main
struct M3Fight {
    static func main() async {
        let command: FightCommand
        do { command = try parseFight(Array(CommandLine.arguments.dropFirst())) } catch {
            fputs("HOLD: \(error)\n\(fightUsage)\n", stderr)
            exit(64)
        }
        do {
            switch command.mode {
            case .preflight:
                var facts = preflight()
                facts["schema"] = "m3-preflight/v1"
                let data = try JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys])
                FileHandle.standardOutput.write(data + Data([10]))
            case .dryRun: exit(try await fightDryRun())
            case .execute: exit(try await fightExecute())
            }
        } catch {
            fputs("HOLD: \(error)\n", stderr)
            exit(2)
        }
    }
}
#endif
