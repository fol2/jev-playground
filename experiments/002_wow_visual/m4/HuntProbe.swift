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
    static let tracker = CGRect(x: 2200, y: 400, width: 360, height: 440)  // objectives below "All Objectives"; six tracked quests reach y 700
    static let targetName = CGRect(x: 1590, y: 950, width: 330, height: 50)
    static let gameMenu = CGRect(x: 1150, y: 440, width: 260, height: 70)  // the Game Menu's title
}

let hunterPreference: [HuntAction] = [.fight, .pickUp, .eatDrink, .rest, .toCreature, .toArea, .nextTarget, .lookAround, .detourRight90, .detourRight45,
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
    private var lastObjectives: [Objective] = []  // the last survey's, for a fight's target cue
    let fightJev: JevClient  // M3's 4 s timeout, whatever the hunt's own decisions wait
    let fightTactics: FightTactics?  // M3b's chains for each fight; nil: the legacy flat policy

    init(session: Session, feed: FrameFeed, sink: PidKeySink, directory: URL, log: Log, fightJev: JevClient,
         fightTactics: FightTactics? = nil) {
        self.fightJev = fightJev
        self.fightTactics = fightTactics
        self.session = session
        self.feed = feed
        self.sink = sink
        self.directory = directory
        self.log = log
        log.emit("object_reader", ["loaded": LiveHuntHost.objectReader != nil, "t": hostNow()])
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

    /// The newest frame, or nil when there is none or it is older than `FightLimits.maxFrameAge`: a stalled
    /// capture must not pass for a calm, healthy scene.
    private func freshImage() -> CGImage? {
        runtimeFrame(session, feed)?.image
    }

    func vitals() -> HuntObs? {
        guard let frame = runtimeFrame(session, feed) else { return nil }
        var o = pixelObs(rgba(frame.image))
        o.stamp = frame.stamp
        return o
    }

    /// The walk skill's reading, as M4a's: coordinates, the minimap arrow and the M3 bars. Every other
    /// frame is kept as w###.jpg.
    func look() -> NavObs? {
        guard let frame = runtimeFrame(session, feed) else { return nil }
        let image = frame.image
        if walkNo % 2 == 0 { write(image, to: directory.appendingPathComponent(String(format: "w%03d.jpg", walkNo)), type: .jpeg) }
        walkNo += 1
        let pixels = rgba(image)
        let (text, read) = readCoords(image)
        let seen = seenFacing(image, pixels)
        guard let at = read, let facing = seen.bearing else {
            emit("unreadable", ["coords_text": text, "walk_frame": walkNo - 1].merging(seen.fields) { a, _ in a })
            return nil
        }
        let hud = observe(pixels, plates: false)
        emit("walk_look", ["walk_frame": walkNo - 1, "x": at.x, "y": at.y, "facing": Int(facing.rounded()), "combat": hud.combat]
            .merging(seen.fields) { a, _ in a })
        return NavObs(stamp: frame.stamp, x: at.x, y: at.y, facing: facing, combat: hud.combat, player: hud.player)
    }

    /// Everything a decision needs: the tracker, target, Game Menu, position, and the creatures whose
    /// plates are in view with their names. Nil when the tracker is unreadable.
    func survey() -> HuntObs? {
        guard let frame = runtimeFrame(session, feed) else { return nil }
        let image = frame.image
        write(image, to: directory.appendingPathComponent(String(format: "h%03d.jpg", frameNo)), type: .jpeg)
        frameNo += 1
        let lines = upscaledText(image, HuntHUD.tracker)
        guard !lines.isEmpty else {
            emit("unreadable", ["frame": frameNo - 1])
            return nil
        }
        let objectives = parseTracker(lines)
        // The object detector (0.24-0.63 s offline) runs beside the reads below (0.34-0.49 s live), not after them: after
        // them it was skipped as too old on every frame of live run 51 (27 Sept).
        var found: [SeenObject] = []
        let detect = Self.objectReader != nil && objectives.contains(where: collects)
        var o = HuntObs(), facingFields: [String: Any] = [:]
        DispatchQueue.concurrentPerform(iterations: detect ? 2 : 1) { i in
            if i == 1 { found = objectsSeen(image, objectives: objectives); return }
            (o, facingFields) = surveyReads(frame, objectives: objectives)
        }
        o.objects = found
        lastTarget = o.target
        lastObjectives = o.objectives
        emit("look", ["frame": frameNo - 1, "ms": Int((hostNow() - frame.stamp.capturedAt) * 1000), "tracker": lines,
                      "target": orNull(o.target), "alive": o.targetAlive,
                      "health": Int(o.player * 100), "mana": Int(o.mana * 100), "combat": o.combat, "game_menu": o.gameMenu,
                      "facing": orNull(o.facing.map { Int($0.rounded()) }), "x": orNull(o.here?.x), "y": orNull(o.here?.y),
                      "area": orNull(o.area.map { ["bearing": Int($0.bearing.rounded()), "distance": roundTo($0.distance), "inside": $0.inside] }),
                      "seen": o.seen.map { ["name": $0.name, "hostile": $0.hostile, "bearing": Int($0.bearing.rounded()), "near": $0.near] }]
                .merging(facingFields) { a, _ in a })
        return o
    }

    /// A survey's reads of one frame but the tracker's and the objects', with the facing's readings for the log.
    private func surveyReads(_ frame: (image: CGImage, stamp: ObservationStamp), objectives: [Objective]) -> (HuntObs, [String: Any]) {
        let image = frame.image
        let pixels = rgba(image)
        let name = upscaledText(image, HuntHUD.targetName).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        var o = pixelObs(pixels)
        let seen = seenFacing(image, pixels)
        o.facing = seen.bearing
        o.objectives = objectives
        o.target = name.isEmpty ? nil : name
        o.stamp = frame.stamp
        o.stamp?.target = targetCue(o.target, o.objectives)  // one creature, however its name reads
        let hud = observe(pixels, plates: false)
        o.targetAlive = !name.isEmpty && hud.target > 0.005
        o.targetInRange = o.targetAlive ? !hud.rangeRed : nil  // the bolt key's digit, as M3 reads it
        o.gameMenu = upscaledText(image, HuntHUD.gameMenu).joined(separator: " ").lowercased().contains("game menu")
        if let at = readCoords(image).at, let facing = o.facing {
            o.here = NavObs(stamp: frame.stamp, x: at.x, y: at.y, facing: facing, combat: o.combat, player: o.player)
        }
        if let facing = o.facing {
            o.seen = nameplates(pixels).compactMap { bar in
                let label = plateName(image, bar)
                return label.filter(\.isLetter).count >= 4 ? sighting(bar, name: label, facing: facing, width: image.width, height: image.height) : nil
            }
        }
        return (o, seen.fields)
    }

    /// The object detector (M5, ObjectReader), loaded once, before any hunt moves; nil without its private model.
    static let objectReader: ObjectReader? = try? ObjectReader()

    /// The objects the detector sees in a frame, as screen centres; none without its model or an open collect objective. A
    /// survey runs it beside its other reads; one that ends too old for the hunt's age limit is refused as any stale
    /// survey is (the `look` event logs each survey's ms).
    func objectsSeen(_ image: CGImage, objectives: [Objective]) -> [SeenObject] {
        guard let reader = Self.objectReader, objectives.contains(where: collects) else { return [] }
        let began = hostNow()
        let found = ((try? reader.objects(image)) ?? []).map {
            SeenObject(x: ($0.box[0] + $0.box[2]) / 2, y: ($0.box[1] + $0.box[3]) / 2, confidence: $0.confidence)
        }
        emit("objects", ["count": found.count, "ms": Int((hostNow() - began) * 1000),
                         "at": found.prefix(5).map { [Int($0.x), Int($0.y), ($0.confidence * 100).rounded() / 100] }])
        return found
    }

    /// A frame captured after `t`, or nil within 2.5 s.
    private func frame(after t: Double) async -> CGImage? {
        let start = hostNow()
        while hostNow() - start < 2.5 {
            if let latest = feed.latestFrame, latest.pts > t { return latest.image }
            await sleep(0.05)
        }
        return nil
    }

    /// PICK_UP_OBJECT (M5): the object the detector sees nearest the character's feet is hovered, as a human rests the
    /// pointer before clicking. Only a tooltip that names an unfinished collect objective, and is not a unit's, is
    /// right-clicked; Click-to-Move walks there and picks it up. First the pointer waits off every unit until two fresh
    /// frames show no tooltip (tooltipGone), so a fading one cannot confirm the wrong place; the pointer then jumps to the
    /// object (one move event, no path across the view), and two fresh reads there must name one objective
    /// (confirmedObject). Combat is read again before the click. Its count rising within 8 s is the evidence; an attack,
    /// or no count by then, ends the wait, and a tap of forward stops the walk (review of #59).
    func pickUp(objectives: [Objective]) async -> String {
        guard let image = freshImage() else { return "no fresh frame" }
        let feetY = 800.0 * Double(image.height) / Double(HUD.height)
        guard let near = objectsSeen(image, objectives: objectives)
                .min(by: { hypot($0.x - 1280, $0.y - feetY) < hypot($1.x - 1280, $1.y - feetY) }) else { return "no object in view" }
        let bounds = session.window.frame
        let routed: RoutedClickTarget
        do { routed = try routedTarget(pid: session.app.processIdentifier, window: session.window.windowID, bounds: bounds) } catch {
            return "no click target: \(error)"
        }
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: bounds.minX + bounds.width * x / Double(HUD.width), y: bounds.minY + bounds.height * y / Double(HUD.height))
        }
        func move(_ x: Double, _ y: Double) -> Bool {
            keys.withControl { Result { try NativeBackgroundClickTransport().move(target: routed, point: point(x, y)) } }.map { (try? $0.get()) != nil } ?? false
        }
        func tip(after t: Double) async -> [String]? { (await frame(after: t)).map { upscaledText($0, QuestHUD.unitTip) } }
        guard move(1280, 60) else { return "cancelled: input ownership revoked" }
        var fades: [Bool?] = []  // true: a tooltip is still up; nil: no fresh frame
        let parked = hostNow()
        while !tooltipGone(fades) && hostNow() - parked < 4 {
            fades.append((await tip(after: hostNow() + 0.2)).map { !$0.isEmpty })
        }
        guard tooltipGone(fades) else { return "a tooltip stayed up with the pointer off every unit; not hovered" }
        guard move(near.x, near.y) else { return "cancelled: input ownership revoked" }
        var reads: [[String]] = []
        for wait in [0.4, 0.3] { reads.append(await tip(after: hostNow() + wait) ?? []) }
        let lines = reads.last ?? []
        emit("pick_up_hover", ["at": [Int(near.x), Int(near.y)], "tooltips": reads.map { Array($0.prefix(3)) }])
        guard let counted = confirmedObject(reads, in: objectives) else {
            _ = move(1280, 60)
            return "the tooltip read \"\(lines.first ?? "nothing")\", which names no unfinished objective; not clicked"
        }
        guard vitals()?.combat == false else {
            _ = move(1280, 60)
            return "in combat, or unreadable, before the click; not clicked"
        }
        let request = NativeBackgroundClickDispatchRequest(target: routed, eventTapPointTopLeft: point(near.x, near.y),
                                                           appKitPoint: point(near.x, near.y), clickCount: 1, mouseButton: .right)
        guard let dispatched = keys.withControl({ Result { try NativeBackgroundClickTransport().dispatch(request) } }),
              (try? dispatched.get()) != nil else { return "right-click failed or input ownership revoked" }
        _ = move(1280, 60)
        let clicked = hostNow()
        func stopWalking() async {
            keys.grant(FightLimits.forward, seconds: HuntLimits.tap + NavLimits.forwardWatchdog)  // lifted if this stalls
            await tap(self, FightLimits.forward)  // a movement key ends Click-to-Move
        }
        while hostNow() - clicked < 8 {
            await sleep(0.5)
            if vitals()?.combat == true {
                await stopWalking()
                return "attacked while picking up \(counted.text); the walk there stopped"
            }
            guard let seen = freshImage() else { continue }
            let tracker = parseTracker(upscaledText(seen, HuntHUD.tracker))
            if let now = tracker.first(where: { $0.quest == counted.quest && $0.text == counted.text }), now.done > counted.done {
                return "picked up \(counted.text): \(now.done)/\(now.need)"
            }
            // the last one: the quest's lines give way to "Ready for turn-in"
            if tracker.contains(where: { $0.quest == counted.quest && $0.text == Objective.ready }) { return "picked up \(counted.text): quest ready" }
        }
        await stopWalking()
        return "right-clicked \(counted.text); its count did not rise within 8 s"
    }

    /// One M3 episode on a child input capability: its clock and budgets start fresh, and its frames go
    /// to their own directory. Its corpse search also looks for the creature being fought.
    func fight(jev: JevClient, inCombat: Bool) async -> FightResult {
        fights += 1
        let folder = directory.appendingPathComponent(String(format: "fight%d", fights))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let childKeys = keys.takeChild(releaseCodes: FightLimits.releaseCodes) else {
            return FightResult(outcome: "INPUT_HANDOFF_FAILED", decisions: 0, jevCalls: 0, latencies: [],
                               episode: Episode(), walkedMs: 0, turnedMs: 0, holdingKeys: keys.holding,
                               codesPosted: [], jevRecords: [])
        }
        let host = LiveHost(session: session, feed: feed, sink: sink, directory: folder, log: log, input: childKeys)
        if let name = lastTarget { host.corpseNames.append(name.lowercased()) }
        let objectives = lastObjectives
        host.cue = { targetCue($0, objectives) ?? $0 }
        lock.withLock { fighting = host }
        defer { lock.withLock { fighting = nil } }
        emit("fight_start", ["fight": fights, "target": orNull(lastTarget), "in_combat": inCombat])
        var result = await runFight(host: host, jev: fightJev, startHealth: inCombat ? 0 : FightLimits.startHealth, tactics: fightTactics)
        if !keys.resume(after: childKeys) {
            result.outcome = "INPUT_HANDOFF_FAILED"
            result.runtime = SkillResult(skill: "combat", status: .failed, code: result.outcome,
                                         evidence: result.runtime?.evidence, holdingInput: keys.holding)
        }
        result.holdingKeys = keys.holding
        return result
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
    let rows = (result.graphID == nil ? result.records : result.graphRecords) + result.fights.flatMap(\.jevRecords)
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
    manifest["decision_graph"] = result.graphID as Any? ?? NSNull()
    if result.graphID != nil {
        manifest["graph_requests"] = result.graphRecords.count
        manifest["graph_usage_missing"] = result.graphRecords.filter {
            ($0["response"] as? [String: Any])?["usage"] == nil
        }.count
        manifest["graph_budget_scope"] = "Hunt tool-choice requests only, no HTTP retry; warm-up and nested Fight are separate. Token totals sum returned usage, not unknown failed-call usage."
    }
    manifest["steps"] = result.steps.map(\.json)
    manifest["fights"] = result.fights.map { ["outcome": $0.outcome, "decisions": $0.decisions] }
    manifest["objectives_start"] = objectives(result.start)
    manifest["objectives_end"] = objectives(result.end)
    manifest["jev_calls"] = rows.count
    manifest["token_usage"] = ["prompt": prompt, "completion": completion, "total": prompt + completion]
    let latencies = result.latencies + result.fights.flatMap(\.latencies)
    manifest["latency_s"] = ["p50": latencyPercentile(latencies, 0.5), "p95": latencyPercentile(latencies, 0.95)]
    manifest["keys_used"] = Array(Set((result.codesPosted + result.fights.flatMap(\.codesPosted)).map { Int($0) })).sorted()
    manifest["experience"] = result.experience as Any? ?? NSNull()
    manifest["experience_records_this_run"] = result.experienceRecords.count
    manifest["experience_reviews_this_run"] = result.experienceReviews.count
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

func huntExperience(_ path: String?, graph: GraphSession?) throws -> ExperienceStore? {
    guard let path else { return nil }
    let scope = graph?.graph.id ?? "hunt-legacy-v1"
    return try ExperienceStore(scope: scope, url: URL(fileURLWithPath: path))
}

func huntDryRun(graph: GraphSession? = nil, experience: ExperienceStore? = nil) async throws -> Int32 {
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
    let client: JevClient = graph == nil ? ScriptedJev(preference: hunterPreference) : HuntGraphDemo()
    let result = await runHunt(host: world, jev: client, graph: graph, experience: experience)
    withExtendedLifetime(signals) {}
    log.emit("summary", ["outcome": result.outcome, "decisions": result.decisions, "fights": result.fights.count,
                         "holding": result.holding, "actions": result.steps.map(\.action.rawValue), "provider_calls": 0, "graph_calls": result.graphRecords.count,
                         "experience_cases": result.experience?["cases"] ?? 0, "experience_reviews": result.experience?["reviews"] ?? 0,
                         "meaning": "proves the hunt loop, targeting keys and stops against a simulated field, not WoW"])
    return !result.fights.isEmpty && !result.holding ? 0 : 2
}

/// Rehearsal: the real Jev against the simulated field, before any live hunt.
func huntSimJev(graph: GraphSession? = nil, experience: ExperienceStore? = nil) async throws -> Int32 {
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
    let result = await runHunt(host: world, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout, retries: graph == nil ? 2 : 0),
                               graph: graph, experience: experience, experienceRun: run.id)
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
func huntExecute(graph: GraphSession? = nil, experience: ExperienceStore? = nil, fightGraph: String? = nil) async throws -> Int32 {
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
    let bar = try await readSkillBar(session, feed, log, required: huntRoles)
    applyRoles(bar.keys)
    HuntLimits.drink = bar.keys[.drink] ?? HuntLimits.drink
    HuntLimits.eat = bar.keys[.food] ?? HuntLimits.eat
    let host = LiveHuntHost(session: session, feed: feed, sink: sink, directory: run.url, log: log, fightJev: LiveJev(key: key),
                            fightTactics: try fightTactics(fightGraph, bar, log))
    defer { host.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { host.releaseAll() }, holding: { host.holding })
    await setZoom(host.keys, log)  // the engine's zoom, not whatever the camera had (owner, 26 Sept)
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
    let result = await runHunt(host: host, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout, retries: graph == nil ? 2 : 0),
                               graph: graph, experience: experience, experienceRun: run.id)
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    try recordHunt(result, into: run.url, manifest: manifest)
    host.emit("summary", ["outcome": result.outcome, "run_directory": run.url.path, "decisions": result.decisions,
                          "fights": result.fights.map(\.outcome), "actions": result.steps.map(\.action.rawValue)])
    return host.holding ? 3 : (result.fights.contains { $0.outcome.hasPrefix("KILLED") } ? 0 : 2)
}

// Demonstration fixture only: prefer existing hunting skills; navigate the sample catalogue to find them.
// It proves graph plumbing, not Jev quality. Real modes always use LiveJev with no fallback.
final class HuntGraphDemo: JevClient {
    private var read = false
    private var readExperience = false
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        let options = question["criteria"] as? [String: String] ?? [:]
        var preference = hunterPreference.map { "DO:" + $0.rawValue }
        let target = state["target"] as? [String: Any] ?? [:]
        if target["alive"] as? Bool == true && target["counts_for_objective"] as? String != "none" {
            preference = ["DO:FIGHT_TARGET", "BACK"] + preference
        }
        if !read { preference.insert("READ:recent", at: 0) }
        let index = state["experience_index"] as? [String: Any]
        if (index?["matching_cases"] as? Int ?? 0) > 0 && !readExperience { preference.insert("READ:experience", at: 0) }
        preference += ["ENTER:search", "ENTER:travel", "ENTER:compass", "BACK"]
        guard let name = preference.first(where: { options[$0] != nil }) else { throw GraphError.noSkills }
        if name == "READ:recent" { read = true }
        if name == "READ:experience" { readExperience = true }
        return ["model": FightLimits.model, "answers": ["action": ["choice": name, "confidence": 1.0,
            "probabilities": Dictionary(uniqueKeysWithValues: options.keys.map { ($0, $0 == name ? 1.0 : 0.0) })]]]
    }
}
