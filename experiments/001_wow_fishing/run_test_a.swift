// Compare bite policies with identical preparation, observations and input checks.
//
//   run-test-a [--background] [--jev] [--seconds 60..1800]
//
// Pre-go runs the live helper (/tmp/jev-fishing-live, from build.sh) once with --check; the autonomous
// interval then repeats --execute --prepared. Test B (--jev) is provider-backed bite decisions with the
// same deterministic preparation. Built by build.sh with dotenv.swift and ../002_wow_visual/runtime/JSON.swift.
import CryptoKit
import Foundation

let runnerRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let liveBinary = "/tmp/jev-fishing-live"
let hashedSources = ["live.swift", "decision.swift", "self_tests.swift", "motion.swift", "motion-fixtures.png", "jev.swift", "loot.swift",
                     "loot-close.png", "loot-layout.png", "build.sh", "page-two.png", "rod-icon.png", "split-bobber.png",
                     "split-bobber-before.png", "bobber-no-red.png", "bobber-no-red-before.png", "run_test_a.swift",
                     "probes/background-click/Adapter.swift", "probes/background-click/NativeWindowServerPreparation.swift",
                     "probes/background-click/NativeBackgroundClickTransport.swift"]
// A held bite that never returns is still an unconfirmed target before any click.
let retryable: Set<String> = ["stopped_no_visible_float", "stopped_target_lost", "stopped_bite_not_recovered"]
let terminalEvents: Set<String> = ["loot_item_unconfirmed", "loot_not_cleared", "loot_layout_unconfirmed", "loot_batch_limit",
                                   "retrieval_unverified"]

struct Invocation {
    var code: Int32 = 0
    var log = ""
    var events: [JSON] = []
}

struct RunnerUsage: Error, CustomStringConvertible { let description: String }
struct RunnerTimeout: Error {}
struct RunnerInterrupted: Error {}

/// Everything the runner does to the world, so the checks can replace it.
struct RunnerHost {
    var invoke: (_ arguments: [String], _ timeout: Double, _ environment: [String: String]) throws -> Invocation
    var now: () -> Double
    var sleep: (Double) -> Void
    var say: (String) -> Void
    var interrupted: () -> Bool
}

func utcNow() -> String {
    let format = DateFormatter()
    format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSxxxxx"
    format.timeZone = TimeZone(identifier: "UTC")
    format.locale = Locale(identifier: "en_US_POSIX")
    return format.string(from: Date())
}

func rounded2(_ x: Double) -> JSON { .double(JSON.round(x, 2)) }

func event(_ e: JSON) -> String { e["event"]?.string ?? "" }

/// Run Test A (rules) or B (Jev) and return the summary it wrote. A timeout or an interruption ends the
/// run with that status; any other error still writes the summary, then propagates.
@discardableResult
func runTestA(_ arguments: [String], root: URL, environment: [String: String], host: RunnerHost) throws -> JSON {
    var background = false, jev = false, seconds = 300
    var rest = arguments[...]
    while let flag = rest.popFirst() {
        switch flag {
        case "--background": background = true
        case "--jev": jev = true
        case "--seconds":
            guard let value = rest.popFirst().flatMap(Int.init) else { throw RunnerUsage(description: "--seconds needs a whole number") }
            seconds = value
        default: throw RunnerUsage(description: "unknown argument " + flag)
        }
    }
    // A live-input duration, so reject a typo rather than dispatch input for hours.
    guard (60...1800).contains(seconds) else { throw RunnerUsage(description: "--seconds must be between 60 and 1800") }
    var env = environment
    if jev {
        guard let key = typesafeKey(root: root, environment: environment) else {
            throw RunnerUsage(description: "Set TYPESAFE_API_KEY locally before Test B")
        }
        env["TYPESAFE_API_KEY"] = key
        env["JEV_CALL_LIMIT"] = "120"
    }
    let label = jev ? "B" : "A"
    let mode = background ? ["--background"] : []
    let policyMode = mode + (jev ? ["--jev"] : [])
    let clock = DateFormatter()
    clock.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    clock.timeZone = TimeZone(identifier: "UTC")
    clock.locale = Locale(identifier: "en_US_POSIX")
    let id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(6)
    let folder = root.appendingPathComponent("runs/001_wow_fishing/test_\(label.lowercased())_\(clock.string(from: Date()))_\(id)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var record = JSON.object([
        ("protocol", .string("anchored-pixel-bite-only-v1")), ("comparison_scope", .string("bite_policy_only")),
        ("policy", .string(jev ? "jev" : "rules")), ("call_budget", .int(jev ? 120 : 0)), ("status", .string("running")),
        ("mode", .string(background ? "targeted" : "foreground")),
        ("input_mode", .string(background ? "targeted_without_activation" : "foreground_without_activation")),
        ("game_foreground_observed", .bool(false)), ("focus_observations", .int(0)), ("target_seconds", .int(seconds)),
        ("pre_go_runs", .int(1)), ("provider_calls", .int(0)), ("started_at_utc", .string(utcNow())), ("cycles", .array([]))])
    let source = root.appendingPathComponent("experiments/001_wow_fishing")
    record = record.setting("source_hashes", .object(try hashedSources.map { name in
        (name, .string(SHA256.hash(data: try Data(contentsOf: source.appendingPathComponent(name))).map { String(format: "%02x", $0) }.joined()))
    }))
    host.say("Test \(label) \(record["mode"]!.string!); results: \(folder.path)")

    func int(_ key: String) -> Int { if case let .int(i) = record[key] { return i }; return 0 }
    func account(_ events: [JSON]) {
        record = record.setting("provider_calls", .int(int("provider_calls") + events.filter { event($0) == "jev_request" }.count))
        for e in events {
            if event(e) == "focus_observed" {
                record = record.setting("focus_observations", .int(int("focus_observations") + 1))
                record = record.setting("game_foreground_observed",
                                        .bool(record["game_foreground_observed"] == .bool(true) || e["game_foreground"] == .bool(true)))
            }
            if event(e) == "jev_response" {
                record = record.setting("request_seconds", .array((record["request_seconds"]?.items ?? []) + [e["request_seconds"] ?? .null]))
                for (name, count) in e["response"]?["usage"]?.pairs ?? [] {
                    switch (record[name], count) {
                    case let (.int(a)?, .int(b)): record = record.setting(name, .int(a + b))
                    case (nil, _): record = record.setting(name, count)
                    default: record = record.setting(name, .double((record[name]?.number ?? 0) + (count.number ?? 0)))
                    }
                }
            }
        }
        if jev { env["JEV_CALL_LIMIT"] = String(max(0, 120 - int("provider_calls"))) }
    }
    func call(_ arguments: [String], _ timeout: Double) throws -> Invocation {
        let result = try host.invoke(arguments, timeout, env)
        if host.interrupted() { throw RunnerInterrupted() }
        return result
    }
    var cycles: [JSON] = []
    var started: Double?
    var failure: Error?
    do {
        let prego = try call(["--check"] + mode, 120)
        account(prego.events)
        try prego.log.write(to: folder.appendingPathComponent("pre-go.log"), atomically: true, encoding: .utf8)
        if prego.code != 0 || !prego.events.contains(where: { event($0) == "pre_go_pass" }) {
            record = record.setting("status", .string("pre_go_failed"))
        } else {
            started = host.now()
            host.say("Pre-go passed once; autonomous \(seconds)-second test started.")
            var failures = 0, stopped = false
            // Finish an in-flight cast rather than kill it with a mouse button held. This bounds normal
            // completion to the interval plus at most one 45-second cycle.
            while host.now() - started! < Double(seconds) {
                let number = cycles.count + 1
                let result = try call(["--execute", "--prepared"] + policyMode, 45)
                account(result.events)
                try result.log.write(to: folder.appendingPathComponent(String(format: "cycle-%02d.log", number)), atomically: true, encoding: .utf8)
                let events = result.events
                let loot = events.first { event($0) == "loot_collected" }
                let native = loot != nil ? "loot_collected" : events.last.map(event) ?? "process_failed"
                let unconfirmed = result.code == 0 && retryable.contains(native) && !events.contains { event($0) == "right_click" }
                let cycle = JSON.object([
                    ("number", .int(number)), ("outcome", .string(unconfirmed ? "target_unconfirmed" : native)),
                    ("native_outcome", .string(native)), ("exit_code", .int(Int(result.code))),
                    ("elapsed_seconds", rounded2(host.now() - started!)),
                    ("run_path", events.first { event($0) == "ready" }?["output"] ?? .null),
                    ("item", loot?["item"] ?? .null), ("labels_observed", loot.map { $0["labels_observed"] ?? .array([]) } ?? .array([])),
                    ("loot_clicks", loot.map { $0["loot_clicks"] ?? .int(1) } ?? .int(0))])
                cycles.append(cycle)
                record = record.setting("cycles", .array(cycles))
                host.say(cycle.text())
                failures = loot != nil ? 0 : failures + 1
                if failures >= 3 {
                    record = record.setting("status", .string("stopped_after_three_consecutive_failures"))
                    stopped = true
                    break
                }
                // Only unconfirmed targets before input may retry within the three-failure bound.
                // Camera, geometry, provider and input stops remain terminal.
                if result.code != 0 || events.contains(where: { e in
                    (event(e).hasPrefix("stopped_") && !(unconfirmed && retryable.contains(event(e)))) || terminalEvents.contains(event(e))
                }) {
                    record = record.setting("status", .string("stopped_for_review"))
                    stopped = true
                    break
                }
                host.sleep(0.5)
                if host.interrupted() { throw RunnerInterrupted() }
            }
            if !stopped {
                let caught = cycles.contains { $0["outcome"] == .string("loot_collected") }
                record = record.setting("status", .string(caught ? "completed" : "no_verified_catches"))
            }
        }
    } catch is RunnerInterrupted {
        record = record.setting("status", .string("interrupted"))
    } catch is RunnerTimeout {
        record = record.setting("status", .string("process_timeout"))
    } catch {
        failure = error
    }
    if background {
        record = record.setting("mode", .string(record["game_foreground_observed"] == .bool(true) ? "targeted_mixed_focus"
                                                : int("focus_observations") > 0 ? "background" : "targeted_focus_unobserved"))
    }
    let autonomous = started.map { rounded2(host.now() - $0) } ?? .int(0)
    let verified = cycles.filter { $0["outcome"] == .string("loot_collected") }.count
    record = record.setting("autonomous_seconds", autonomous)
        .setting("verified_loot_cycles", .int(verified))
        .setting("unverified_retrievals", .int(cycles.filter { $0["outcome"] == .string("retrieval_unverified") }.count))
    record = record.setting("perfect_run", .bool(record["status"] == .string("completed") && (autonomous.number ?? 0) >= Double(seconds)
                                                 && !cycles.isEmpty && verified == cycles.count))
        .setting("finished_at_utc", .string(utcNow()))
    try (record.text(indent: 2) + "\n").write(to: folder.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
    host.say(JSON.object(["status", "mode", "pre_go_runs", "autonomous_seconds", "verified_loot_cycles", "unverified_retrievals",
                          "provider_calls", "perfect_run"].map { ($0, record[$0]!) }).text())
    if let failure { throw failure }
    return record
}

// Set by SIGINT. A handler, not SIG_IGN: an ignored signal would stay ignored in the live helper, which must
// get the owner's Ctrl-C itself to release its input.
nonisolated(unsafe) var sigint: sig_atomic_t = 0

/// The live helper, its output in files (a pipe could fill and stall it), bounded by `timeout`.
func invokeLive(_ arguments: [String], _ timeout: Double, _ environment: [String: String]) throws -> Invocation {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("run-test-a-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let outURL = scratch.appendingPathComponent("out"), errURL = scratch.appendingPathComponent("err")
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    FileManager.default.createFile(atPath: errURL.path, contents: nil)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: liveBinary)
    process.arguments = arguments
    process.currentDirectoryURL = runnerRoot
    process.environment = environment
    process.standardOutput = try FileHandle(forWritingTo: outURL)
    process.standardError = try FileHandle(forWritingTo: errURL)
    try process.run()
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while process.isRunning {
        if ProcessInfo.processInfo.systemUptime > deadline {
            process.terminate()
            let grace = ProcessInfo.processInfo.systemUptime + 5
            while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { usleep(50_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw RunnerTimeout()
        }
        usleep(20_000)
    }
    let out = (try? String(contentsOf: outURL, encoding: .utf8)) ?? "", err = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
    let events = out.split(whereSeparator: \.isNewline).compactMap { try? JSON.parse(String($0)) }.filter { $0["event"] != nil }
    return Invocation(code: process.terminationStatus, log: out + err, events: events)
}

#if !RUNNER_TESTS
@main
struct RunTestA {
    static func main() {
        signal(SIGINT) { _ in sigint = 1 }
        let host = RunnerHost(invoke: invokeLive, now: { ProcessInfo.processInfo.systemUptime }, sleep: { usleep(UInt32($0 * 1_000_000)) },
                              say: { print($0); fflush(stdout) }, interrupted: { sigint != 0 })
        do {
            try runTestA(Array(CommandLine.arguments.dropFirst()), root: runnerRoot, environment: ProcessInfo.processInfo.environment, host: host)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
#endif
