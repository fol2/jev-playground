// Registered M0/M1/M3/M4 motor proof: counted fake-time checks plus each real binary's no-effect modes.
// Never captures, posts OS input, runs --look/--execute/--release/--sim-jev or contacts a provider.
import CoreGraphics
import Foundation
import ImageIO

let minChecks = 100  // the suite must not silently lose its cases
let minSeekChecks = 103  // the current count: removing a check must lower this on purpose
let minFightChecks = 216  // the current count: removing a check must lower this on purpose
let minNavChecks = 283  // the current count: removing a check must lower this on purpose
let minLearningChecks = 81  // the video evaluator's self-test: 67 on the evaluator, 14 on the JSON format
let lateMS = 100.0  // dry-runs stall their observer 400 ms per pulse; an observer-bound release fails
let clickDir = "experiments/001_wow_fishing/probes/background-click/"
let perceptionFile = navDir + "perception.jsonl"  // the accepted readings of the perception regression set
let minPerceptionFrames = 2453  // the current count: dropping frames from the set must lower this on purpose

/// Exactly one "NAME checks passed: N" line, with N at least `minimum`.
func counted(_ output: String, _ name: String = "motor", _ minimum: Int = minChecks, label: String = "checks passed") throws -> Int {
    let prefix = "\(name) \(label): "
    let found = output.components(separatedBy: "\n").compactMap { line -> Int? in
        guard line.hasPrefix(prefix) else { return nil }
        let digits = line.dropFirst(prefix.count)
        return !digits.isEmpty && digits.allSatisfy({ $0.isASCII && $0.isNumber }) ? Int(digits) : nil
    }
    guard found.count == 1, found[0] >= minimum else {
        throw GateError("\(name) suite reported \(found.isEmpty ? "no" : found.map(String.init).joined(separator: ", ")) checks; at least \(minimum) required")
    }
    return found[0]
}

func event(_ row: JSON) -> String? { row["event"]?.string }

func released(_ rows: [JSON], _ pulses: Int? = nil) throws {
    // Python read every row as r["event"]: a row without one holds, rather than going uncounted.
    guard rows.allSatisfy({ event($0) != nil }) else { throw GateError("a dry-run row has no event") }
    let downs = rows.filter { event($0) == "key_down" }.count, ups = rows.filter { event($0) == "key_up" }.count
    if downs != ups || downs == 0 || (pulses.map { downs != $0 } ?? false) || rows.contains(where: { event($0) == "release_unconfirmed" }) {
        throw GateError("dry-run dispatched \(downs) key-downs and \(ups) key-ups for \(pulses.map(String.init) ?? "any") pulses")
    }
}

/// A binary with a Fight in it also needs the fight's tactics and the runtime it runs on.
func buildCommand(_ output: String, _ sources: [String], flags: [String] = []) -> [String] {
    let sources = sources.contains(fightDir + "Fight.swift")
        ? sources + [fightDir + "Tactics.swift", runtimeDir + "Runtime.swift", runtimeDir + "Input.swift",
                     runtimeDir + "DecisionGraph.swift", runtimeDir + "Experience.swift"]
        : sources
    // -j: the driver's own default ran one compiler job at a time; the jobs, not the output, change.
    return ["swiftc", "-parse-as-library", "-j", String(ProcessInfo.processInfo.activeProcessorCount)] + flags + sources + ["-o", output]
}

struct Build { let output: String; let sources: [String]; var flags: [String] = [] }

/// Every binary at once: the builds are independent. The -O builds, then the larger ones, start first because they
/// take longest; the order changes only when each starts, never what is built. The checks run after all of them,
/// on an idle machine: the dry-runs time their key-ups.
func buildAll(_ builds: [Build]) throws {
    let order = builds.enumerated().sorted {
        let a = ($0.element.flags.contains("-O") ? 0 : 1, -$0.element.sources.count, $0.offset)
        let b = ($1.element.flags.contains("-O") ? 0 : 1, -$1.element.sources.count, $1.offset)
        return a < b
    }.map(\.element)
    var failures = [String?](repeating: nil, count: order.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: order.count) { i in
        let failure: String?
        do {
            try sh(buildCommand(order[i].output, order[i].sources, flags: order[i].flags), timeout: 300).checked("swiftc " + order[i].output)
            failure = nil
        } catch {
            failure = "\(error)"
        }
        lock.withLock { failures[i] = failure }
    }
    if let first = failures.compactMap({ $0 }).first { throw GateError(first) }
}

func jsonRows(_ text: String, skipBlank: Bool = false) throws -> [JSON] {
    try text.components(separatedBy: "\n").dropLast(text.hasSuffix("\n") ? 1 : 0)
        .filter { !skipBlank || !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { try JSON.parse($0) }
}

func suite(_ binary: String, _ name: String, _ minimum: Int) throws -> Int {
    try counted(try sh([binary], timeout: 60).checked(binary).out, name, minimum)
}

func refuses(_ binary: String, _ cases: [[String]]) throws {
    for args in cases {
        let outcome = try sh([binary] + args, timeout: 30)
        if outcome.code != 64 || !outcome.err.hasPrefix("HOLD:") || !outcome.data.isEmpty {
            throw GateError("invalid arguments \(args) were not refused before any effect")
        }
    }
}

/// The latest key-up's lateness. Every key-up is timed, as max(r["lateness_ms"] ...) required.
func lateness(_ ups: [JSON]) throws -> JSON {
    let timed = try ups.map { up -> (JSON, Double) in
        guard let value = up["lateness_ms"], let ms = value.number else { throw GateError("a dry-run key-up has no lateness") }
        return (value, ms)
    }
    guard let late = timed.max(by: { $0.1 < $1.1 }) else { throw GateError("a dry-run released no key") }
    return late.0
}

func onTime(_ binary: String, _ pulses: Int?) throws -> (rows: [JSON], late: JSON) {
    let rows = try jsonRows(try sh([binary, "--dry-run"], timeout: 90).checked(binary).out)
    try released(rows, pulses)
    let ups = rows.filter { event($0) == "key_up" }
    let late = try lateness(ups)
    if (late.number ?? .infinity) >= lateMS || ups.contains(where: { $0["reason"] != .string("expired") }) {
        throw GateError("dry-run key-up waited for the stalled observer (\(late.text()) ms late)")
    }
    return (rows, late)
}

/// Starts `command`, reads its JSON lines, sends SIGINT after the first row `when` accepts, then reads to the end.
func interruptWhen(_ command: [String], skipBlank: Bool, _ when: (JSON) -> Bool) throws -> (rows: [JSON], code: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command[0])
    process.arguments = Array(command.dropFirst())
    process.currentDirectoryURL = root
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.standardError
    try process.run()
    var rows: [JSON] = [], pending = Data(), signalled = false
    let deadline = ProcessInfo.processInfo.systemUptime + 90
    while true {
        let chunk = pipe.fileHandleForReading.availableData
        if chunk.isEmpty { break }
        pending.append(chunk)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
            pending.removeSubrange(pending.startIndex...newline)
            if skipBlank && line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            rows.append(try JSON.parse(line))
            if !signalled && when(rows.last!) {
                kill(process.processIdentifier, SIGINT)
                signalled = true
            }
        }
        if ProcessInfo.processInfo.systemUptime > deadline {
            process.terminate()
            throw GateError("\(command[0]) did not finish within 90 s")
        }
    }
    let wait = ProcessInfo.processInfo.systemUptime + 10
    while process.isRunning && ProcessInfo.processInfo.systemUptime < wait { usleep(10_000) }
    if process.isRunning {
        process.terminate()
        throw GateError("\(command[0]) did not exit within 10 s of SIGINT")
    }
    return (rows, process.terminationStatus)
}

/// Operator Ctrl-C during a held key must still release before exit.
func interrupted(_ command: [String]) throws {
    let (rows, code) = try interruptWhen(command, skipBlank: false) { event($0) == "key_down" }
    let last = rows.last
    if code != 130 || last.map({ event($0) != "exit" || $0["reason"] != .string("SIGINT") || $0["holding"] != .bool(false) }) ?? true {
        throw GateError("SIGINT did not end \(command[0]) cleanly")
    }
    try released(rows, 1)
}

/// SIGINT of the M3/M4 --dry-run, sent on "start" (emitted after the trap), must stop the paced loop with exit 130
/// and holding false. No OS keys are posted.
func interruptedDry(_ command: [String]) throws {
    let (rows, code) = try interruptWhen(command, skipBlank: true) { event($0) == "start" }
    if code != 130 { throw GateError("SIGINT of \(command[0]) dry-run exited \(code)") }
    if !rows.contains(where: { event($0) == "exit" && $0["holding"] == .bool(false) }) {
        throw GateError("SIGINT of \(command[0]) dry-run did not report holding false")
    }
}

/// The saved-frame corpus, shared by every worktree of this clone. A hosted runner has none: it stays local.
func savedFrames() throws -> URL? {
    let common = try gitText("rev-parse", "--path-format=absolute", "--git-common-dir")
    let frames = URL(fileURLWithPath: common).deletingLastPathComponent().appendingPathComponent("runs/002_wow_visual")
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: frames.path, isDirectory: &directory) && directory.boolValue ? frames : nil
}

/// Readings keyed by frame, in the order read.
typealias Readings = [(frame: String, row: JSON)]

func frame(_ row: JSON) throws -> String {
    guard let name = row["frame"]?.string else { throw GateError("a perception reading names no frame") }
    return name
}

func pixels(_ nav: String, _ frames: URL) throws -> Readings {
    try jsonRows(try sh([nav, "--pixels", frames.path], timeout: 300).checked("m4-nav --pixels").out).map { (try frame($0), $0) }
}

func accepted(update: Bool = false) throws -> Readings {
    let file = root.appendingPathComponent(perceptionFile)
    if update && !FileManager.default.fileExists(atPath: file.path) { return [] }
    let rows = try jsonRows(try String(contentsOf: file, encoding: .utf8)).map { (try frame($0), $0) }
    if !update && (Set(rows.map(\.0)).count != rows.count || rows.count < minPerceptionFrames
                   || rows.contains { $0.1["sha256"]?.string?.wholeMatch(of: #/[0-9a-f]{64}/#) == nil }) {
        throw GateError("\(perceptionFile) lost frames or holds a malformed row; at least \(minPerceptionFrames) required")
    }
    return rows
}

/// Python's ==: a whole number equals the same float; otherwise structural.
func same(_ a: JSON?, _ b: JSON?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x?, y?):
        if let m = x.number, let n = y.number { return m == n }
        switch (x, y) {
        case let (.array(p), .array(q)): return p.count == q.count && zip(p, q).allSatisfy { same($0, $1) }
        case let (.object(p), .object(q)):
            return p.count == q.count && p.allSatisfy { pair in q.contains { $0.0 == pair.0 && same($0.1, pair.1) } }
        default: return x == y
        }
    default: return false
    }
}

func codePointOrder(_ a: String, _ b: String) -> Bool { a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) }

/// What differs from the accepted readings, reader by reader, with up to three example frames each.
func shifts(_ old: Readings, _ new: Readings) -> [String] {
    let now = Dictionary(new.map { ($0.frame, $0.row) }, uniquingKeysWith: { _, last in last })
    var changed: [String: [String]] = [:]
    for (frame, row) in old {
        let keys: [String]
        if let current = now[frame] {
            if !same(current["sha256"], row["sha256"]) {
                keys = ["frame bytes"]
            } else {
                let names = Set((row.pairs ?? []).map(\.0)).union((current.pairs ?? []).map(\.0))
                keys = names.filter { !same(row[$0], current[$0]) }.sorted(by: codePointOrder)
            }
        } else {
            keys = ["missing"]
        }
        for key in keys { changed[key, default: []].append(frame) }
    }
    return changed.keys.sorted(by: codePointOrder).map { key in
        "\(key) \(changed[key]!.count) (\(changed[key]!.prefix(3).joined(separator: ", ")))"
    }
}

func blackPNG(_ url: URL, _ width: Int, _ height: Int) throws {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let image = context.makeImage(),  // a new bitmap context is zero-filled: black
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw GateError("could not draw a black frame")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw GateError("could not write a black frame") }
}

/// The perception regression set: every pixel reader on every saved frame must read as accepted. The frames stay
/// local, so a hosted runner checks the accepted file and a black-frame negative control only.
func perception(_ nav: String, _ tmp: URL, update: Bool = false) throws -> String {
    let control = tmp.appendingPathComponent("control")
    try FileManager.default.createDirectory(at: control, withIntermediateDirectories: false)
    try blackPNG(control.appendingPathComponent("black.png"), 2560, 1320)
    try blackPNG(control.appendingPathComponent("small.png"), 1280, 660)  // not the calibrated layout: skipped
    let read = try pixels(nav, control)
    let black = JSON.object((read.first?.row.pairs ?? []).filter { $0.0 != "sha256" })
    let expected = JSON.object([("frame", .string("black.png")), ("player", .int(0)), ("mana", .int(0)), ("target", .int(0)), ("cast", .int(0))])
    if read.map(\.frame) != ["black.png"] || !same(black, expected) {
        throw GateError("a black frame read something, or a wrong-size frame was read: \(read.map { $0.row.text() })")
    }
    let old = try accepted(update: update)
    if let first = old.map(\.frame).min(by: codePointOrder) {
        func with(_ change: (JSON) -> JSON?) -> Readings { old.compactMap { $0.frame == first ? change($0.row).map { (first, $0) } : $0 } }
        if shifts(old, with { $0.setting("red", .array([.array([.int(1), .int(2), .int(3), .int(4)])])) }) != ["red 1 (\(first))"]
            || shifts(old, with { $0.setting("sha256", .string(String(repeating: "0", count: 64))) }) != ["frame bytes 1 (\(first))"]
            || shifts(old, with { _ in nil }) != ["missing 1 (\(first))"] {
            throw GateError("the perception comparer missed a planted shift")
        }
    }
    guard let frames = try savedFrames() else {
        if update { throw GateError("no saved frames here to accept readings from") }
        return "perception: \(old.count) accepted frames well-formed, black frame reads nothing; replay not run (no saved frames here)"
    }
    let new = try pixels(nav, frames)
    let added = Set(new.map(\.frame)).subtracting(old.map(\.frame)).count
    if update {
        let text = new.sorted { codePointOrder($0.frame, $1.frame) }.map { $0.row.text(sorted: true, compact: true) + "\n" }.joined()
        try text.write(to: root.appendingPathComponent(perceptionFile), atomically: true, encoding: .utf8)
        let changes = shifts(old, new)
        return "accepted \(new.count) frames into \(perceptionFile); changed from before: "
            + (changes.isEmpty ? "nothing" : changes.joined(separator: "; ")) + "; new \(added)"
    }
    let changes = shifts(old, new)
    if !changes.isEmpty {
        throw GateError("perception shifted from the accepted readings: \(changes.joined(separator: "; ")). Review the frames, "
                        + "then accept with tools/sdlc motor --update-perception")
    }
    return "perception: \(old.count) saved frames read as accepted, black frame reads nothing"
        + (added > 0 ? "; \(added) newer frames not yet in the set" : "")
}

func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }

/// The text after the first `marker`, or all of it (Python's `split(marker, 1)[-1]`).
func after(_ marker: String, _ text: String) -> Substring { text.range(of: marker).map { text[$0.upperBound...] } ?? text[...] }

/// M4 execute must trap SIGINT onto the body's LiveKeys sweep; this is not OS-key proof.
func navTrap() throws {
    let probe = try source(navDir + "NavProbe.swift")
    let execute = after("func navExecute", probe)
    if !execute.contains("also: { body.releaseAll() }, holding: { body.holding }") {
        throw GateError("navExecute does not trap signals onto body.releaseAll and body.holding")
    }
    if !execute.contains("defer { body.releaseAll() }") { throw GateError("navExecute does not defer body.releaseAll") }
    if !probe.contains("LiveKeys(sink: sink, releaseCodes: NavLimits.releaseCodes") {
        throw GateError("M4 keys do not go through LiveKeys with NavLimits.releaseCodes")
    }
    let hunt = try source(navDir + "HuntProbe.swift")
    let huntExecute = after("func huntExecute", hunt)
    if !huntExecute.contains("also: { host.releaseAll() }, holding: { host.holding }") || !huntExecute.contains("defer { host.releaseAll() }") {
        throw GateError("huntExecute does not trap signals and defer onto host.releaseAll and host.holding")
    }
    if !hunt.contains("keys.releaseAll()\n        lock.withLock { fighting }?.releaseAll()") {
        throw GateError("the hunt's release does not sweep both its own keys and the current fight's")
    }
    let quest = try source(navDir + "QuestProbe.swift")
    let questsExecute = after("func questsExecute", quest)
    if !questsExecute.contains("also: { body.releaseAll(); host.releaseAll() },")
        || !questsExecute.contains("holding: { body.holding || host.holding }")
        || !questsExecute.contains("defer { body.releaseAll(); host.releaseAll() }") {
        throw GateError("questsExecute does not trap signals and defer onto its body's and its host's keys")
    }
    let host = after("final class LiveQuestHost", quest).components(separatedBy: "func fightBack")[0]
    if !host.contains("walker?.releaseAll()") || !host.contains("lock.withLock { fighting }?.releaseAll()")
        || !host.contains("(walker?.holding ?? false) || lock.withLock { fighting?.holdingKeys ?? false }") {
        throw GateError("the quest host's exit sweep and holding do not cover the current walk and fight")
    }
    if !quest.contains("if walker?.holding == true { return \"WALK_KEYS_HELD\" }")
        || !quest.contains("guard !legs.holding else { return \"WALK_KEYS_HELD\" }") {
        throw GateError("a quest walk whose key release is unconfirmed does not end the run")
    }
}

/// Execute must trap SIGINT onto a retrying host.releaseAll; this is not OS-key proof.
func fightTrap() throws {
    let probe = try source(fightDir + "FightProbe.swift")
    let core = try source(runtimeDir + "Input.swift")
    if !core.contains("struct HeldKey") || !core.contains("func expired(now:") { throw GateError("watchdog decision is not HeldKey") }
    let execute = after("func fightExecute", probe)
    if !execute.contains("also: { host.releaseAll() }, holding: { host.holdingKeys }") {
        throw GateError("fightExecute does not trap signals onto host.releaseAll and host.holdingKeys")
    }
    if !execute.contains("defer { host.releaseAll() }") { throw GateError("fightExecute does not defer host.releaseAll") }
    if !probe.contains("FightLimits.releaseCodes") { throw GateError("M3 release does not sweep FightLimits.releaseCodes") }
}

/// The last JSON row of a dry-run, or an empty object.
func dryRun(_ command: [String]) throws -> (rows: [JSON], summary: JSON) {
    let rows = try jsonRows(try sh(command, timeout: 90).checked(command.joined(separator: " ")).out, skipBlank: true)
    return (rows, rows.last ?? .object([]))
}

func motorProof(update: Bool) throws -> String {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("motor-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    func out(_ name: String) -> String { tmp.appendingPathComponent(name).path }
    let coreTests = out("runtime-tests"), experienceTests = out("experience-tests"), integration = out("integration-tests")
    let graphTests = out("graph-tests"), tests = out("motor-tests"), probe = out("m0-probe")
    let fightTests = out("fight-tests"), fight = out("m3-fight"), tabletop = out("tabletop"), video = out("video-jev")
    let navTests = out("nav-tests"), nav = out("m4-nav"), memory = out("hunt-experience.json")
    let seekTests = out("seek-tests"), seek = out("m1-seek")
    let fightSources = [motorDir + "Motor.swift", seekDir + "Plate.swift", fightDir + "Fight.swift"]
    let navSources = fightSources + [navDir + "Nav.swift", navDir + "Hunt.swift", navDir + "Quest.swift"]
    let seekShell = [motorDir + "Motor.swift", motorDir + "Probe.swift", seekDir + "Seek.swift", seekDir + "Plate.swift", seekDir + "SeekProbe.swift"]
    let clicks = [clickDir + "Adapter.swift", clickDir + "NativeWindowServerPreparation.swift", clickDir + "NativeBackgroundClickTransport.swift"]
    let navBuild = Build(output: nav, sources: seekShell + [fightDir + "Fight.swift", fightDir + "FightProbe.swift", navDir + "Nav.swift",
                                                            navDir + "NavProbe.swift", navDir + "Hunt.swift", navDir + "HuntProbe.swift",
                                                            navDir + "Quest.swift", navDir + "QuestProbe.swift"] + clicks,
                         flags: ["-O", "-D", "SEEK", "-D", "FIGHT", "-D", "NAV"])
    if update {
        try buildAll([navBuild])
        return try perception(nav, tmp, update: true)
    }
    try buildAll([
        Build(output: coreTests, sources: [runtimeDir + "Runtime.swift", runtimeDir + "RuntimeTests.swift"]),
        Build(output: experienceTests, sources: [runtimeDir + "Experience.swift", runtimeDir + "ExperienceTests.swift"]),
        Build(output: integration, sources: navSources + [runtimeDir + "IntegrationTests.swift"]),
        Build(output: graphTests, sources: navSources + [runtimeDir + "GraphTests.swift"]),
        Build(output: tests, sources: [motorDir + "Motor.swift", motorDir + "MotorTests.swift"]),
        Build(output: probe, sources: [motorDir + "Motor.swift", motorDir + "Probe.swift"]),
        Build(output: seekTests, sources: [motorDir + "Motor.swift", seekDir + "Seek.swift", seekDir + "Plate.swift", seekDir + "SeekTests.swift"]),
        Build(output: seek, sources: seekShell, flags: ["-O", "-D", "SEEK"]),
        Build(output: fightTests, sources: fightSources + [fightDir + "FightTests.swift"]),
        Build(output: fight, sources: seekShell + [fightDir + "Fight.swift", fightDir + "FightProbe.swift"] + clicks,
              flags: ["-O", "-D", "SEEK", "-D", "FIGHT"]),
        Build(output: navTests, sources: fightSources + [navDir + "Nav.swift", navDir + "NavTests.swift", navDir + "Hunt.swift",
                                                         navDir + "HuntTests.swift", navDir + "Quest.swift"]),
        navBuild,
        Build(output: tabletop, sources: [navDir + "Tabletop.swift", sharedJSON]),
        Build(output: video, sources: [learnDir + "VideoJev.swift", sharedJSON]),
    ])
    _ = try suite(coreTests, "runtime", 33)
    let experienceChecks = try suite(experienceTests, "experience", 34)
    _ = try suite(integration, "runtime integration", 43)
    let graphChecks = try suite(graphTests, "decision graph", 56)
    let checks = try suite(tests, "motor", minChecks)
    try refuses(probe, [["--bogus"], ["--execute"], ["--execute", "--keys", "arrows"], ["--execute", "turn-left:100"],
                        ["--execute", "--keys", "arrows", "turn-left:300"], ["--release"], ["--preflight", "extra"]])
    let late = try onTime(probe, 6).late
    try interrupted([probe, "--dry-run", "forward:200"])

    let seekChecks = try suite(seekTests, "seek", minSeekChecks)
    try refuses(seek, [["--bogus"], ["--dry-run", "x"], ["--look", "x"], ["--execute"],
                       ["--execute", "--keys", "wqe", "--look", "f.png"], ["--execute", "--keys", "wqe", "--box", "1,1,20,20"],
                       ["--execute", "--keys", "wqe", "--look", "f.png", "--box", "1,1,20,20", "--stop-growth", "9"],
                       ["--target"], ["--target", "--keys", "wqe", "--stop-row", "0.9"], ["--target", "--keys", "wqe", "--look", "f.png"]])
    let (seekRows, seekLate) = try onTime(seek, nil)
    guard let summary = seekRows.last, event(summary) == "summary", summary["outcome"] == .string("VISIBLE_STOP_REACHED_PENDING_LABELS"),
          let pulses = summary["pulses_used"] else {
        throw GateError("M1 dry-run did not reach the simulated visible stop")
    }
    try interrupted([seek, "--dry-run"])

    let fightChecks = try suite(fightTests, "fight", minFightChecks)
    try refuses(fight, [["--bogus"], ["--dry-run", "x"], ["--execute"], ["--execute", "--keys", "arrows"],
                        ["--execute", "--keys", "wqe", "extra"], ["--preflight", "extra"], ["--dry-run", "--graph"],
                        ["--dry-run", "--keys", "wqe"], ["--execute", "--graph", "g.json"]])
    let fightSummary = try dryRun([fight, "--dry-run"]).summary
    if event(fightSummary) != "summary" || fightSummary["outcome"] != .string("KILLED_AND_LOOTED") {
        throw GateError("M3 dry-run did not reach KILLED_AND_LOOTED")
    }
    let chainSummary = try dryRun([fight, "--dry-run", "--graph", runtimeDir + "skyborne-fight.graph.json"]).summary
    let performed = chainSummary["performed"]?.items?.compactMap(\.string) ?? []
    if chainSummary["outcome"] != .string("KILLED_AND_LOOTED") || chainSummary["policy"] != .string("skyborne-fight-v1")
        || (chainSummary["chain_steps"]?.number ?? 0) < 3 || chainSummary["holding"] != .bool(false)
        || !same(chainSummary["provider_calls"], .int(0)) || !performed.contains("CAST_LIGHTNING_BOLT") || !performed.contains("START_MELEE")
        || performed.firstIndex(of: "CAST_LIGHTNING_BOLT")! > performed.firstIndex(of: "START_MELEE")!
        || (chainSummary["decisions"]?.number ?? 99) >= (fightSummary["decisions"]?.number ?? 0) {
        throw GateError("M3b dry-run did not kill and loot through a chain of 3+ unasked steps, bolt before melee, in fewer Jev decisions")
    }
    try fightTrap()
    try interruptedDry([fight, "--dry-run"])

    let navChecks = try suite(navTests, "nav", minNavChecks)
    try refuses(nav, [["--bogus"], ["--dry-run", "x"], ["--preflight", "x"], ["--replay"], ["--pixels"], ["--sim-jev"],
                      ["--sim-jev", "--scenario", "maze"], ["--execute", "--keys", "wqe"], ["--execute", "--to", "47.1,21.8"],
                      ["--execute", "--keys", "arrows", "--to", "47.1,21.8"], ["--execute", "--keys", "wqe", "--to", "47.1"],
                      ["--execute", "--keys", "wqe", "--to", "47.1,21.8", "--arrive", "5"], ["--hunt"],
                      ["--hunt", "--keys", "arrows"], ["--hunt", "--keys", "wqe", "extra"], ["--hunt-dry-run", "x"],
                      ["--hunt-sim-jev", "x"], ["--hunt-dry-run", "--experience"],
                      ["--dry-run", "--experience", "/tmp/x"], ["--hunt", "--keys", "wqe", "--to", "47.1,21.8"],
                      ["--plan"], ["--quests", "--keys", "wqe"], ["--quests", "--graph", "g.json"],
                      ["--quests", "--graph", "g.json", "--keys", "arrows"], ["--hunt-dry-run", "--fight-graph", "f.json"],
                      ["--quests", "--graph", "g.json", "--keys", "wqe", "--fight-graph"]])
    let navSummary = try dryRun([nav, "--dry-run"]).summary
    if event(navSummary) != "summary" || navSummary["outcome"] != .string("ARRIVED") || navSummary["holding"] != .bool(false) {
        throw GateError("M4 dry-run did not reach ARRIVED with keys released")
    }
    let huntSummary = try dryRun([nav, "--hunt-dry-run"]).summary
    if event(huntSummary) != "summary" || !truthy(huntSummary["fights"]) || huntSummary["holding"] != .bool(false)
        || !same(huntSummary["provider_calls"], .int(0)) {
        throw GateError("M4 hunt dry-run did not fight with keys released and no provider call")
    }
    let graph = [nav, "--hunt-dry-run", "--graph", runtimeDir + "skyborne-hunt.graph.json", "--experience", memory]
    let graphSummary = try dryRun(graph).summary
    if !truthy(graphSummary["graph_calls"]) || !truthy(graphSummary["fights"]) || graphSummary["holding"] != .bool(false)
        || !same(graphSummary["provider_calls"], .int(0)) || !truthy(graphSummary["experience_cases"]) {
        throw GateError("graph dry-run did not exercise tools, experience recording and real Hunt skills")
    }
    if !(try dryRun(graph).rows).contains(where: { event($0) == "graph_call" && ($0["question"]?.text() ?? "").contains("READ:experience") }) {
        throw GateError("second graph run did not proactively retrieve retained experience")
    }
    try navTrap()
    let path = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? ""]
    let checked = try sh([tabletop, "--check"], timeout: 60, environment: path).checked("tabletop --check").out
    if !(13...99).contains((try? counted(checked, "tabletop scenarios", 13, label: "checked")) ?? 0) {
        throw GateError("tabletop --check reported \(checked.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    let replay = try sh([video, "--check"], timeout: 60, environment: path).checked("video-jev --check").out
    let lines = replay.components(separatedBy: "\n")
    if (try? counted(replay, "learning regression", minLearningChecks, label: "checks")) == nil
        || !lines.contains("askable decision points: 236") || !lines.contains("historical replays reconciled: 6") {
        throw GateError("video-jev --check reported \(replay.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    try interruptedDry([nav, "--dry-run"])
    try interruptedDry([nav, "--hunt-dry-run"])
    let seen = try perception(nav, tmp)  // last: it loads every core, and the dry-runs above time their key-ups
    func show(_ value: JSON?) -> String { value?.text() ?? "None" }
    let slowest = (late.number ?? 0) >= (seekLate.number ?? 0) ? late : seekLate
    return "Experience: \(experienceChecks) checks. Decision graph: \(graphChecks) checks and native tool/skill/recall dry-run passed. "
        + "M0/M1/M3/M4 motor proof passed: \(checks) + \(seekChecks) + \(fightChecks) + \(navChecks) fake-time checks, argument refusal, "
        + "release under a 400 ms observer stall (max \(slowest.text()) ms late), SIGINT release, the simulated "
        + "M1 loop (\(pulses.text()) pulses), the simulated M3 fight (\(show(fightSummary["decisions"])) "
        + "decisions; M3b's chains \(show(chainSummary["decisions"])) decisions and \(show(chainSummary["chain_steps"])) unasked steps) "
        + "and the simulated M4 walk (\(show(navSummary["decisions"])) decisions); M3/M4 dry-run SIGINT stops the "
        + "loop (130, holding false) with no OS keys; \(seen); zero capture, OS input or live model calls."
}

/// Python's truthiness for a JSON value: absent, null, false, zero, "" and empty containers are false.
func truthy(_ value: JSON?) -> Bool {
    switch value {
    case nil, .null?: return false
    case let .bool(b)?: return b
    case let .int(i)?: return i != 0
    case .big?: return true  // too large for Int, so never zero
    case let .double(d)?: return d != 0
    case let .string(s)?: return !s.isEmpty
    case let .array(a)?: return !a.isEmpty
    case let .object(o)?: return !o.isEmpty
    }
}
