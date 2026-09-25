// Provider-free checks of Test A/B budgeting and stop behaviour: a fake live helper, a fake clock and no sleep.
// Built with run_test_a.swift, dotenv.swift and ../002_wow_visual/runtime/JSON.swift under -D RUNNER_TESTS.
import Foundation

@main
struct RunnerTests {
    nonisolated(unsafe) static var checks = 0

    static func check(_ condition: Bool, _ name: String) {
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(name)\n".utf8))
            exit(1)
        }
        checks += 1
    }

    static func events(_ names: [String]) -> [JSON] { names.map { .object([("event", .string($0))]) } }

    /// A run over a temporary root that holds the hashed sources; each cycle's events come from `cycles`.
    static func run(_ prego: [JSON], _ cycles: [[JSON]] = [], arguments: [String] = ["--background", "--jev"],
                    interruptAfter: Int? = nil, timeoutAt: Int? = nil) -> (record: JSON, calls: [[String]], budgets: [String?]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("runner-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for name in hashedSources {
            let path = root.appendingPathComponent("experiments/001_wow_fishing/" + name)
            try! FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! "fixture".write(to: path, atomically: true, encoding: .utf8)
        }
        var results = [prego] + cycles
        // monotonic() as Python's run saw it: the start, each cycle's loop test and elapsed time, then the end.
        var clock: [Double] = [0]
        for i in cycles.indices { clock += [Double(i * 10), Double(i * 10 + 5)] }
        clock += [301, 301]
        var calls: [[String]] = []
        var budgets: [String?] = []
        var interrupted = false
        let host = RunnerHost(
            invoke: { arguments, _, environment in
                calls.append(arguments)
                budgets.append(environment["JEV_CALL_LIMIT"])
                check(environment["TYPESAFE_API_KEY"] == "offline-fixture", "Test B hands the key to the helper")
                if calls.count == timeoutAt { throw RunnerTimeout() }
                if calls.count == interruptAfter { interrupted = true }
                return Invocation(code: 0, log: "", events: results.removeFirst())
            },
            now: { clock.removeFirst() }, sleep: { _ in }, say: { _ in }, interrupted: { interrupted })
        try! runTestA(arguments, root: root, environment: ["TYPESAFE_API_KEY": "offline-fixture"], host: host)
        let folder = try! FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("runs/001_wow_fishing").path)
        let summary = root.appendingPathComponent("runs/001_wow_fishing/\(folder[0])/summary.json")
        return (try! JSON.parse(String(contentsOf: summary, encoding: .utf8)), calls, budgets)
    }

    static func outcomes(_ record: JSON) -> [String] { record["cycles"]?.items?.compactMap { $0["outcome"]?.string } ?? [] }

    static func main() {
        let pass = events(["pre_go_pass"])
        let loot = JSON.object([("event", .string("loot_collected")), ("item", .string("<unreadable>"))])

        var (record, calls, budgets) = run(events(["jev_request", "pre_go_pass"]), [[
            .object([("event", .string("jev_request"))]),
            .object([("event", .string("jev_response")), ("request_seconds", .double(0.3)),
                     ("response", .object([("usage", .object([("input_tokens", .int(100)), ("output_tokens", .int(20))]))]))]),
            .object([("event", .string("loot_collected")), ("item", .string("Fresh fish"))])]])
        check(record["provider_calls"] == .int(2) && record["input_tokens"] == .int(100), "counts actual requests and usage")
        check(record["perfect_run"] == .bool(true), "a caught fish over the whole interval is a perfect run")
        check(calls[1].contains("--prepared") && !calls[0].contains("--jev") && calls[1].contains("--jev"),
              "pre-go is shared; only the cycles use Jev")
        check(budgets == ["120", "119"], "each helper call gets the budget the requests so far have left")
        check(record["comparison_scope"] == .string("bite_policy_only") && record["source_hashes"]?["decision.swift"] != nil
              && record["source_hashes"]?["self_tests.swift"] != nil && record["source_hashes"]?["run_test_a.swift"] != nil,
              "the sources behind the result are hashed")

        (record, calls, _) = run(pass, [events(["stopped_jev_error"])])
        check(record["status"] == .string("stopped_for_review") && record["perfect_run"] == .bool(false) && calls.count == 2,
              "a provider failure stops without a rules fallback")

        (record, calls, _) = run(pass, [events(["retrieval_unverified"])])
        check(record["status"] == .string("stopped_for_review") && record["unverified_retrievals"] == .int(1)
              && record["perfect_run"] == .bool(false), "an unverified retrieval stops for review")

        (record, calls, _) = run(pass, [[.object([("event", .string("loot_collected")), ("item", .string("<unreadable>")),
                                               ("labels_observed", .array([])), ("loot_clicks", .int(0))])]])
        check(record["verified_loot_cycles"] == .int(1) && record["perfect_run"] == .bool(true)
              && record["cycles"]?.items?.first?["loot_clicks"] == .int(0), "an unreadable label is not a collection failure")

        (record, calls, _) = run([.object([("event", .string("focus_observed")), ("game_foreground", .bool(true))])] + pass,
                              [[.object([("event", .string("focus_observed")), ("game_foreground", .bool(false))]),
                                .object([("event", .string("loot_collected")), ("item", .string("<unreadable>")), ("loot_clicks", .int(0))])]])
        check(record["mode"] == .string("targeted_mixed_focus") && record["input_mode"] == .string("targeted_without_activation")
              && record["perfect_run"] == .bool(true) && record["focus_observations"] == .int(2),
              "the owner's foreground choice neither fails the run nor claims full background")

        (record, calls, _) = run(pass, [events(["stopped_camera_motion"])])
        check(record["status"] == .string("stopped_for_review") && calls.count == 2, "a camera change does not trigger another cast")

        (record, calls, _) = run(pass, [events(["stopped_before_cast_verification"])])
        check(record["status"] == .string("stopped_for_review") && record["perfect_run"] == .bool(false),
              "an interruption before cast verification is terminal")

        (record, calls, _) = run(pass, [events(["stopped_no_visible_float"]), events(["stopped_target_lost"]), [loot]])
        check(calls.count == 4 && outcomes(record).prefix(2) == ["target_unconfirmed", "target_unconfirmed"]
              && record["cycles"]?.items?.first?["native_outcome"] == .string("stopped_no_visible_float")
              && record["verified_loot_cycles"] == .int(1) && record["perfect_run"] == .bool(false),
              "unconfirmed targets recast within the existing limit")

        (record, calls, _) = run(pass, Array(repeating: events(["stopped_no_visible_float"]), count: 3))
        check(record["status"] == .string("stopped_after_three_consecutive_failures") && calls.count == 4, "three unconfirmed casts stop")

        (record, calls, _) = run(pass, [events(["bite_detected_waiting_for_return", "stopped_bite_not_recovered"]), [loot]])
        check(calls.count == 3 && outcomes(record).first == "target_unconfirmed"
              && record["cycles"]?.items?.first?["native_outcome"] == .string("stopped_bite_not_recovered")
              && record["perfect_run"] == .bool(false), "an unrecovered bite before any click recasts")

        (record, calls, _) = run(pass, [events(["right_click", "stopped_bite_not_recovered"])])
        check(record["status"] == .string("stopped_for_review") && calls.count == 2, "an unrecovered bite after a click never recasts")

        (record, calls, _) = run(pass, [events(["right_click", "stopped_target_lost"])])
        check(record["status"] == .string("stopped_for_review") && calls.count == 2, "a target lost after a click never recasts")

        for seconds in ["30", "1801"] {
            let host = RunnerHost(invoke: { _, _, _ in check(false, "no helper before the interval is valid"); return Invocation() },
                                  now: { 0 }, sleep: { _ in }, say: { _ in }, interrupted: { false })
            do {
                try runTestA(["--seconds", seconds], root: URL(fileURLWithPath: "/nonexistent"), environment: [:], host: host)
                check(false, "the interval is bounded")
            } catch {
                check(error is RunnerUsage, "the interval length is configurable and bounded: \(seconds) refused")
            }
        }

        (record, calls, _) = run(events(["pre_go_jev_not_ready"]))
        check(record["status"] == .string("pre_go_failed") && calls.count == 1, "a failed preparation never casts")

        // Beyond the Python checks: the owner's Ctrl-C and a stuck helper both end the run and keep its summary.
        (record, calls, _) = run(pass, [[loot], [loot]], interruptAfter: 2)
        check(record["status"] == .string("interrupted") && calls.count == 2 && record["perfect_run"] == .bool(false),
              "Ctrl-C during a cycle ends the run as interrupted, its summary written")
        (record, calls, _) = run(pass, [[loot]], timeoutAt: 2)
        check(record["status"] == .string("process_timeout") && calls.count == 2, "a helper past its timeout ends the run as process_timeout")

        check(checks >= 55, "the runner suite kept its checks")
        print("runner checks passed: \(checks)")
    }
}
