// The gate's own checks: routing, git integrity, contracts, the manifest, the learning contract, the proof
// runners' helpers and the merge decision. Built by `tools/sdlc check` with -D GATE_TESTS and counted.
import Foundation

#if GATE_TESTS
@main
struct GateTests {
    nonisolated(unsafe) static var checks = 0

    static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
        let passed = (try? condition()) ?? false
        guard passed else {
            FileHandle.standardError.write(Data("FAIL: \(name)\n".utf8))
            exit(1)
        }
        checks += 1
    }

    /// The body must be refused: a GateError or a Hold, nothing else.
    static func holds(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            check(false, name + ": not refused")
        } catch is GateError {
            check(true, name)
        } catch is Hold {
            check(true, name)
        } catch {
            check(false, name + ": \(error)")
        }
    }

    static func checks(_ changes: [Change]) throws -> [String] { try route(changes)["checks"]!.items!.compactMap(\.string) }

    static func main() {
        routing()
        gitIntegrity()
        contract()
        manifest()
        learningContract()
        visualRoute()
        runners()
        merge()
        print("gate checks passed: \(checks)")
    }

    // MARK: Routing (was tests/test_sdlc.py)

    static func routing() {
        check(try checks([("M", "README.md")]) == ["integrity", "governance"], "documentation only")
        check(!(try checks([("M", "docs/changes/note.md")])).contains("governance-tests"), "a modified change note is documentation")
        for path in gateCode.union(policy).sorted() {
            check(try checks([("M", path)]).contains("governance-tests"), "authority and code path \(path) gets the full contract")
        }
        for status in ["A", "D", "T"] {
            check(try checks([(status, "README.md")]).contains("automation-tests"), "added/deleted documentation gets the full contract")
        }
        check(try checks([("M", "README.md"), ("M", "tools/Gate.swift")]).contains("governance-tests"), "a mixed change keeps the strictest route")
        let refused: [[Change]] = [[], [("M", "foo.py")], [("M", "docs/anything.md")], [("R100", "README.md")],
                                   [("M", "../README.md")], [("M", "/README.md")], [("M", "docs//changes/a.md")],
                                   [("M", "docs/changes/../a.md")], [("M", "docs/changes/a\n.md")],
                                   [("M", "docs\\changes\\a.md")], [("M", ".env")], [("M", "README.md"), ("M", "surprise.sh")]]
        for change in refused {
            holds("unknown or malformed fails closed: \(change)") { _ = try route(change) }
        }
        for path in ["experiments/001_wow_fishing/live.swift", "experiments/001_wow_fishing/evidence/run/events.jsonl",
                     "data/001_wow_fishing/angles_20260921/far-02-detail.mp4"] {
            check(try checks([("M", path)]).contains("fishing-offline"), "fishing routes to its offline proof: \(path)")
        }
        for path in ["experiments/001_wow_fishing/unregistered.swift", "experiments/001_wow_fishing/evidence/payload.py",
                     "data/001_wow_fishing/payload.sh", "experiments/002_unknown/main.py"] {
            holds("an unregistered fishing path fails closed: \(path)") { _ = try route([("A", path)]) }
        }
        // inspect() routes the whole tree, so one unregistered file holds the gate.
        let tracked = (try? gitText("ls-files", "-z")) ?? ""
        let files = tracked.split(separator: "\0").map(String.init).filter { !required.contains($0) }
        check(files.count > 100, "the tree is listed")
        // One check, so the count does not follow the tree's size; the first unclassified path is named.
        let unclassified = files.first { (try? route([("M", $0)])) == nil }
        check(unclassified == nil, "every tracked path is classified" + (unclassified.map { ": not " + $0 } ?? ""))
        let omitted = (try? route([("M", "tools/Gate.swift")]))?["omitted"]
        check(omitted?["F3"] != nil && omitted?["F4"] != nil, "runtime proof is never inferred")
    }

    // MARK: Git integrity

    /// A fresh two-commit repository: README baseline, then README candidate.
    static func fixture(_ test: (URL, String, String) throws -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gate-fixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            func g(_ args: String...) throws -> String { try gitText(args, cwd: dir) }
            _ = try g("init", "-q")
            _ = try g("config", "user.name", "Fixture")
            _ = try g("config", "user.email", "fixture@example.invalid")
            try "baseline\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            _ = try g("add", ".")
            _ = try g("commit", "-qm", "fixture")
            let base = try g("rev-parse", "HEAD")
            try "candidate\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            _ = try g("add", ".")
            _ = try g("commit", "-qm", "fixture")
            try test(dir, base, try g("rev-parse", "HEAD"))
        } catch {
            check(false, "git fixture: \(error)")
        }
    }

    static func commit(_ dir: URL) throws -> String {
        _ = try gitText(["add", "-A"], cwd: dir)
        _ = try gitText(["commit", "-qm", "fixture"], cwd: dir)
        return try gitText(["rev-parse", "HEAD"], cwd: dir)
    }

    static func gitIntegrity() {
        fixture { dir, base, head in
            let result = try inspect(base: base, head: head, cwd: dir)
            check(result["head"] == .string(head), "exact head identity")
            check(result["tree"] == .string(try gitText(["rev-parse", "HEAD^{tree}"], cwd: dir)), "exact tree identity")
        }
        fixture { dir, base, head in
            for path in ["README.md", "untracked.txt"] {
                try "dirty".write(to: dir.appendingPathComponent(path), atomically: true, encoding: .utf8)
                holds("a dirty or untracked tree holds: \(path)") { _ = try inspect(base: base, head: head, cwd: dir) }
            }
        }
        fixture { dir, base, head in
            for (b, h) in [(base, base), (head, head), ("missing-ref", head), ("--help", head)] {
                holds("wrong head, empty diff or invalid base holds: \(b.prefix(8)) \(h.prefix(8))") { _ = try inspect(base: b, head: h, cwd: dir) }
            }
        }
        fixture { dir, base, _ in
            try FileManager.default.removeItem(at: dir.appendingPathComponent("README.md"))
            try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("README.md").path, withDestinationPath: "/etc/passwd")
            let head = try commit(dir)
            holds("a symlink is not a validated source surface") { _ = try inspect(base: base, head: head, cwd: dir) }
        }
        fixture { dir, base, _ in
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appendingPathComponent("README.md").path)
            let head = try commit(dir)
            holds("an executable document is not documentation only") { _ = try inspect(base: base, head: head, cwd: dir) }
        }
        fixture { dir, base, _ in
            _ = try gitText(["mv", "README.md", "payload.py"], cwd: dir)
            let head = try commit(dir)
            holds("a rename cannot hide an unknown destination") { _ = try inspect(base: base, head: head, cwd: dir) }
        }
        fixture { dir, base, _ in
            _ = try gitText(["rm", "-q", "README.md"], cwd: dir)
            let head = try commit(dir)
            check(try inspect(base: base, head: head, cwd: dir)["checks"]!.items!.contains(.string("governance-tests")),
                  "a removed required file routes to the full contract")
        }
    }

    // MARK: Contracts

    static func contract() {
        check((try? contracts()) != nil, "the current contract holds")
        let entry = (try? String(contentsOf: root.appendingPathComponent("CLAUDE.md"), encoding: .utf8)) ?? ""
        check(entry.matches(of: #/@([A-Za-z0-9_./-]+)/#).map { String($0.1) } == ["AGENTS.md"] && entry.utf8.count < 400,
              "Claude's start imports only the kernel")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gate-contract-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        for path in required {
            let target = tmp.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: root.appendingPathComponent(path), to: target)
        }
        let ci = ".github/workflows/ai-sdlc.yml"
        let mutations: [(String, (String) -> String)] = [
            ("AGENTS.md", { $0.replacingOccurrences(of: "No compromise", with: "Optional") }),
            ("AGENTS.md", { $0 + String(repeating: "x", count: 6501) }),
            ("CLAUDE.md", { $0.replacingOccurrences(of: "@AGENTS.md", with: "other.md") }),
            (ci, { $0.replacingOccurrences(of: #""contents": "read""#, with: #""contents": "write""#) }),
            (ci, { $0.replacingOccurrences(of: "macos-14", with: "self-hosted") }),
            (ci, { $0.replacingOccurrences(of: #""persist-credentials": false"#, with: #""persist-credentials": true"#) }),
            (ci, { $0.replacingOccurrences(of: "11d5960a326750d5838078e36cf38b85af677262", with: "v4") }),
            (ci, { $0.replacingOccurrences(of: #""Focus Gate""#, with: #""Optional""#) }),
            (ci, { $0.replacingOccurrences(of: #""pull_request""#, with: #""pull_request_target""#) }),
        ]
        check((try? contracts(tmp)) != nil, "the copied contract holds before any mutation")
        for (path, mutate) in mutations {
            let url = tmp.appendingPathComponent(path)
            let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? mutate(original).write(to: url, atomically: true, encoding: .utf8)
            holds("a security or instruction mutation of \(path) holds") { try contracts(tmp) }
            try? original.write(to: url, atomically: true, encoding: .utf8)
        }
        try? FileManager.default.removeItem(at: tmp.appendingPathComponent("REVIEW.md"))
        holds("a missing maintained contract holds") { try contracts(tmp) }

        let workflow = (try? JSON.parse(String(contentsOf: root.appendingPathComponent(ci), encoding: .utf8))) ?? .null
        let steps = workflow["jobs"]?["focus"]?["steps"]?.items ?? []
        check(workflow["on"]?["push"]?["branches"] == .array([.string("main")]), "CI runs on pushes to main")
        check(workflow["concurrency"]?["cancel-in-progress"] == .bool(true), "a newer push cancels the older run")
        check(steps.first?["with"]?["fetch-depth"] == .int(0) && (steps.first?["with"]?["ref"]?.string ?? "").contains("pull_request.head.sha"),
              "CI checks out the exact PR head with full history")
        let script = steps.count > 1 ? steps[1]["run"]?.string ?? "" : ""
        check(script.contains(#"sh tools/sdlc "${args[@]}""#) && script.contains("args+=(--full)"), "CI runs the Swift gate, --full on dispatch")
        check(!workflow.text().contains("secrets."), "CI reads no secret")
    }

    // MARK: The manifest

    static func manifest() {
        func report(_ fields: [(String, JSON)] = []) -> JSON {
            var r = JSON.object([("checks", .array([.string("integrity"), .string("governance")])),
                                 ("reason", .string("allowlisted documentation only")), ("base", .string(String(repeating: "a", count: 40))),
                                 ("head", .string(String(repeating: "b", count: 40))), ("tree", .string(String(repeating: "c", count: 40))),
                                 ("changes", .array([.array([.string("M"), .string("README.md")])]))])
            for (key, value) in fields { r = r.setting(key, value) }
            return r
        }
        let slow = seal(report(), elapsed: 59.5979), fast = seal(report(), elapsed: 0.0042)
        check(slow["elapsed_seconds"] != fast["elapsed_seconds"] && slow["manifest_sha256"] == fast["manifest_sha256"],
              "wall-clock time does not change the manifest")
        let reference = seal(report(), elapsed: 1)["manifest_sha256"]
        for (field, value) in [("tree", JSON.string(String(repeating: "d", count: 40))), ("head", .string(String(repeating: "e", count: 40))),
                               ("base", .string(String(repeating: "f", count: 40))), ("reason", .string("other")),
                               ("checks", .array([.string("integrity")])), ("changes", .array([.array([.string("A"), .string("README.md")])]))] {
            check(seal(report([(field, value)]), elapsed: 1)["manifest_sha256"] != reference, "the manifest covers \(field)")
        }
        let published = seal(report(), elapsed: 1)
        let decided = JSON.object((published.pairs ?? []).filter { $0.0 != "manifest_sha256" && $0.0 != "elapsed_seconds" })
        check(.string(sha256Hex(Data(decided.text(sorted: true).utf8))) == published["manifest_sha256"],
              "the manifest is recomputable from the published report")
        // The Python gate's manifest for this report (json.dumps(report, sort_keys=True), computed before it was deleted):
        // a manifest here hashes the same bytes.
        check(published["manifest_sha256"] == .string("d6d00dec7c602992b94728b47fd4cb37e4e074eb074ff4dc27eec4a95051e5ae"),
              "the manifest hashes the bytes the Python gate hashed")
    }

    // MARK: The learning contract

    static func learningContract() {
        func text(_ path: String) -> String {
            ((try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let agents = text("AGENTS.md")
        check(((try? Data(contentsOf: root.appendingPathComponent("AGENTS.md")))?.count ?? 9999) <= 6500, "the kernel stays bounded")
        for term in ["AI-SDLC DNA", "Minimise Wall Time", "Minimise Token Consumption", "No compromise", "Learning:", "Playing:",
                     "visual decoder", "JEV", "scripts", "held-out", "runtime consumer", "Source merge does NOT authorise",
                     "release held input", "docs/agents/ai-sdlc.md"] {
            check(agents.contains(term), "the kernel keeps \(term)")
        }
        let process = text("docs/agents/ai-sdlc.md")
        for term in ["Two connected loops", "Source grounding and frame-by-frame learning", "From evidence to a runtime capability",
                     "Evaluation and promotion", "Autonomous run envelope and human-above control", "Repository gates and integration",
                     "pre-action", "frame indices/PTS", "held-out", "candidate", "offline-validated", "runtime-qualified", "active",
                     "model weight training", "actual consumer", "knowledge consumed", "supervised", "unattended", "rollback",
                     "per-action confirmation"] {
            check(process.contains(term), "the learning contract covers \(term)")
        }
        for path in ["README.md", "AGENTS.md", "REVIEW.md", "experiments/README.md"] {
            check(text(path).contains("docs/agents/ai-sdlc.md"), "\(path) points at the learning home")
        }
        let readme = text("README.md")
        check(readme.contains("experiments/002_wow_visual/learning/README.md") && readme.contains("experiments/002_wow_visual/m4/README.md")
              && !readme.contains("Existing work remains on its branches"), "the README points at the current work")
        check(!process.contains("starts without product code on main"), "no stale claim of an empty main")
        let template = text(".github/pull_request_template.md")
        check(["held-out", "runtime consumer", "run envelope"].allSatisfy(template.contains), "the PR template asks for the learning evidence")
        for path in ["AGENTS.md", "REVIEW.md", "docs/agents/ai-sdlc.md", ".github/pull_request_template.md", "tools/GateTests.swift"] {
            check(try checks([("M", path)]).contains("governance-tests"), "\(path) gets no documentation-only bypass")
        }
        for path in ["knowledge/shaman.md", "zerocks1/part1_decisions.jsonl", "VideoJev.swift"] {
            check(try checks([("M", learnDir + path)]).contains("motor-offline"), "learning \(path) takes the motor lane")
        }
        holds("an unregistered learning script fails closed") { _ = try route([("A", learnDir + "unregistered.py")]) }
    }

    // MARK: Visual and proof routes (was tests/test_visual_route.py)

    static func visualRoute() {
        for status in ["A", "M", "D"] {
            check(try checks([(status, visualDir + "README.md")]).contains("motor-offline")
                  && !(try checks([(status, visualDir + "README.md")])).contains("fishing-offline"), "the 002 README selects the native proof")
        }
        for (path, proof) in retired.sorted(by: { $0.key < $1.key }) {
            check(try checks([("D", path)]).contains(proof), "retired \(path) may be deleted, running \(proof)")
            for status in ["A", "M"] {
                holds("retired \(path) may not come back (\(status))") { _ = try route([(status, path)]) }
            }
        }
        for path in [visualDir + "executor.py", visualDir + "nested/README.md", visualDir + "capture.swift", visualDir + "observations.py",
                     navDir + "tabletop.py", learnDir + "video_jev.py"] {
            holds("an unregistered visual path fails closed: \(path)") { _ = try route([("A", path)]) }
        }
        let shared = (try? checks([("M", sharedJSON)])) ?? []
        check(shared.contains("motor-offline") && shared.contains("fishing-offline") && shared.contains("governance-tests"),
              "the shared JSON runs every consumer: motor, fishing and the gate")
        let motion = (try? checks([("A", fishingDir + "tests/MotionChecks.swift")])) ?? []
        check(motion.contains("fishing-offline") && !motion.contains("motor-offline"), "a fishing regression selects the fishing proof")
        for name in ["Runtime.swift", "Input.swift", "RuntimeTests.swift", "IntegrationTests.swift", "DecisionGraph.swift", "GraphTests.swift",
                     "Experience.swift", "ExperienceTests.swift", "skyborne-hunt.graph.json", "skyborne-quest.graph.json", "README.md"] {
            check(try checks([("M", runtimeDir + name)]).contains("motor-offline"), "runtime \(name) selects its consumer's proof")
        }
        holds("an unregistered runtime file fails closed") { _ = try route([("A", runtimeDir + "Unregistered.swift")]) }
        for path in motorPaths.sorted() {
            for status in ["A", "M", "D"] {
                let selected = (try? checks([(status, path)])) ?? []
                check(selected.contains("motor-offline") && (path == sharedJSON || !selected.contains("fishing-offline")),
                      "motor path \(path) selects the motor proof")
            }
        }
        check(try checks([("M", "tools/MotorProof.swift")]).contains("motor-offline"), "a changed motor runner runs its own proof")
        check(try checks([("M", "tools/FishingProof.swift")]).contains("fishing-offline"), "a changed fishing runner runs its own proof")
        check(!(try checks([("M", "tools/Merge.swift")])).contains("motor-offline"), "the merge tool does not run the motor proof")
        for path in [motorDir + "Executor.swift", motorDir + "nested/Probe.swift", motorDir + "evidence.json", motorDir + "run.sh",
                     seekDir + "Executor.swift", seekDir + "look.png", seekDir + "run.sh", visualDir + "m2/Seek.swift",
                     fightDir + "Executor.swift", fightDir + "run.sh", fightDir + "evidence.json",
                     navDir + "Executor.swift", navDir + "run.sh", navDir + "frames.jpg", navDir + "nested/Nav.swift"] {
            holds("an unregistered motor path fails closed: \(path)") { _ = try route([("A", path)]) }
        }
        check(try checks([("M", "tools/Merge.swift"), ("M", fishingDir + "motion.swift"), ("M", visualDir + "README.md")])
              == ["integrity", "governance", "governance-tests", "automation-tests", "fishing-offline", "motor-offline"],
              "a combined change keeps both consumers and governance")
    }

    // MARK: The proof runners' helpers

    static func runners() {
        check((try? counted("header\nmotor checks passed: 114\n")) == 114, "a suite reports its counted checks")
        for output in ["", "motor checks passed: 5", "motor checks passed: 114 extra", "motor checks passed: 114\nmotor checks passed: 114"] {
            holds("a missing, short, garbled or repeated count holds: \(output.prefix(24))") { _ = try counted(output) }
        }
        check((try? counted("seek checks passed: 62", "seek", 60)) == 62, "a named suite reports its own count")
        for output in ["motor checks passed: 62", "seek checks passed: 59"] {
            holds("another suite's count, or too few, holds") { _ = try counted(output, "seek", 60) }
        }
        for (name, minimum) in [("runtime", 33), ("runtime integration", 41), ("decision graph", 56), ("experience", 34)] {
            check((try? counted("\(name) checks passed: \(minimum)", name, minimum)) == minimum, "\(name) reports \(minimum)")
            holds("\(name) below \(minimum) holds") { _ = try counted("\(name) checks passed: \(minimum - 1)", name, minimum) }
        }
        check((try? counted("learning regression checks: \(minLearningChecks)", "learning regression", minLearningChecks, label: "checks")) == minLearningChecks,
              "the video evaluator's own line reports its count")
        holds("the video evaluator below its floor holds") {
            _ = try counted("learning regression checks: \(minLearningChecks - 1)", "learning regression", minLearningChecks, label: "checks") }
        let down = JSON.object([("event", .string("key_down"))]), up = JSON.object([("event", .string("key_up"))])
        check((try? released([down, up], 1)) != nil, "a pulse released is released")
        for rows in [[], [down], [down, up, down], [down, up, .object([("event", .string("release_unconfirmed"))])]] {
            holds("an unreleased or unconfirmed key holds") { try released(rows, 1) }
        }
        check((try? released([down, up, down, up])) != nil, "M1: any number of pulses, each released")
        for rows in [[], [down], [down, up, down]] {
            holds("M1: an unreleased key holds") { try released(rows) }
        }
        let command = buildCommand("unused", [fightDir + "Fight.swift"])
        check(command.contains(runtimeDir + "DecisionGraph.swift") && command.contains(runtimeDir + "Experience.swift")
              && command.contains(fightDir + "Tactics.swift"), "a fight binary also builds its tactics and runtime")
        check(!buildCommand("unused", [motorDir + "Motor.swift"]).contains(fightDir + "Tactics.swift"), "a fightless binary does not")
        check((try? fightTrap()) != nil && (try? navTrap()) != nil, "the live shells trap SIGINT onto their key sweeps")
        // Integrity and governance are the inspection and the contracts; the other checks each have a proof.
        check(Set(proofs.keys) == Set(allChecks).subtracting(["integrity", "governance"]), "every selectable proof has a runner")
        var ran: [String] = []
        let fake = Dictionary(uniqueKeysWithValues: proofs.keys.map { name in (name, { () throws -> String in ran.append(name); return "" }) })
        check((try? run(["integrity", "governance", "motor-offline"], fake)) != nil && ran == ["motor-offline"], "the gate runs the motor proof it selected")
        ran = []
        check((try? run(allChecks, fake)) != nil && ran == ["governance-tests", "automation-tests", "fishing-offline", "motor-offline"],
              "every proof, in the report's order")
        let old: Readings = [("a.jpg", .object([("frame", .string("a.jpg")), ("sha256", .string("x")), ("player", .int(1))])),
                             ("b.jpg", .object([("frame", .string("b.jpg")), ("sha256", .string("y"))]))]
        check(shifts(old, old).isEmpty, "unchanged readings shift nothing")
        check(shifts(old, [old[0], ("b.jpg", old[1].row.setting("red", .array([])))]) == ["red 1 (b.jpg)"], "a new reading shifts its reader")
        check(shifts(old, [("a.jpg", old[0].row.setting("player", .double(1.0))), old[1]]).isEmpty, "1 and 1.0 are the same reading, as in Python")
        check(shifts(old, [old[1]]) == ["missing 1 (a.jpg)"] && shifts(old, [("a.jpg", old[0].row.setting("sha256", .string("z"))), old[1]])
              == ["frame bytes 1 (a.jpg)"], "a missing frame, and changed frame bytes, are named")
    }

    // MARK: The merge decision (was tests/test_merge_pr.py)

    static let head = String(repeating: "a", count: 40), base = String(repeating: "b", count: 40)

    static func snapshot() -> JSON {
        try! JSON.parse("""
            {"pr": {"number": 1, "state": "open", "draft": false, "merged": false,
                    "head": {"sha": "\(head)", "ref": "task", "repo": {"full_name": "\(repoName)"}},
                    "base": {"sha": "\(base)", "ref": "main", "repo": {"full_name": "\(repoName)"}},
                    "mergeable": true, "mergeable_state": "clean", "user": {"login": "owner"}},
             "integration": "\(base)", "compare": {"status": "ahead"}, "main_compare": {"status": "ahead"},
             "runs": [{"id": 10, "run_number": 1, "run_attempt": 1, "workflow_id": \(workflowID), "path": "\(workflowPath)",
                       "head_sha": "\(head)", "event": "pull_request", "head_repository": {"full_name": "\(repoName)"},
                       "pull_requests": [{"number": 1}], "status": "completed", "conclusion": "success"}],
             "jobs": [{"name": "Focus Gate", "status": "completed", "conclusion": "success", "run_id": 10}],
             "checks": [], "statuses": [], "threads": [],
             "reviews": [{"id": 1, "user": {"login": "owner"}, "state": "COMMENTED", "commit_id": "\(head)",
                          "submitted_at": "2026-09-21T12:00:00Z", "author_association": "OWNER",
                          "body": "AI-SDLC review: PASS\\nIndependence: author-review\\nHead: \(head)"}]}
            """)
    }

    /// The value at a dotted path set: `pr.head.sha`, `runs.0.event`.
    static func set(_ json: JSON, _ path: String, _ value: JSON) -> JSON {
        let keys = path.split(separator: ".").map(String.init)
        func go(_ node: JSON, _ rest: ArraySlice<String>) -> JSON {
            guard let key = rest.first else { return value }
            if case var .array(items) = node, let i = Int(key) {
                items[i] = go(items[i], rest.dropFirst())
                return .array(items)
            }
            return node.setting(key, go(node[key] ?? .null, rest.dropFirst()))
        }
        return go(json, keys[...])
    }

    static func review(_ changes: [(String, JSON)]) -> JSON {
        changes.reduce(snapshot()["reviews"]!.items![0]) { $0.setting($1.0, $1.1) }
    }

    static func appending(_ s: JSON, _ key: String, _ item: JSON, atStart: Bool = false) -> JSON {
        let items = s[key]?.items ?? []
        return s.setting(key, .array(atStart ? [item] + items : items + [item]))
    }

    static func eligible(_ s: JSON, _ into: String = "main") -> Bool {
        (try? evaluate(s, number: 1, head: head, into: into))?["decision"] == .string("ELIGIBLE")
    }

    static func merge() {
        check(eligible(snapshot()), "a clean exact-head PR is eligible")
        let blockers: [(String, JSON)] = [
            ("pr.state", .string("closed")), ("pr.draft", .bool(true)), ("pr.merged", .bool(true)), ("pr.head.sha", .string(base)),
            ("pr.head.repo", .object([("full_name", .string("other/repo"))])), ("pr.base.ref", .string("release")),
            ("pr.head.ref", .string("main")), ("integration", .string(String(repeating: "c", count: 40))), ("compare.status", .string("diverged")),
            ("main_compare.status", .string("behind")), ("main_compare.status", .string("diverged")), ("pr.mergeable", .null),
            ("pr.mergeable_state", .string("blocked")), ("runs", .array([])), ("jobs", .array([])), ("reviews", .array([])),
            ("checks", .array([.object([("status", .string("queued")), ("conclusion", .null)])])),
            ("checks", .array([.object([("status", .string("completed")), ("conclusion", .string("failure"))])])),
            ("statuses", .array([.object([("state", .string("pending"))])])), ("threads", .array([.object([("isResolved", .bool(false))])])),
        ]
        for (path, value) in blockers {
            holds("\(path) = \(value.text()) blocks") { _ = try evaluate(set(snapshot(), path, value), number: 1, head: head) }
        }
        for (field, value) in [("workflow_id", JSON.int(6)), ("path", .string(".github/workflows/fake.yml")), ("head_sha", .string(base)),
                               ("event", .string("push")), ("pull_requests", .array([])), ("head_repository", .object([("full_name", .string("other/repo"))])),
                               ("status", .string("in_progress")), ("conclusion", .string("failure"))] {
            holds("run \(field) must match") { _ = try evaluate(set(snapshot(), "runs.0." + field, value), number: 1, head: head) }
        }
        let rerun = snapshot()["runs"]!.items![0].setting("run_attempt", .int(2)).setting("status", .string("queued")).setting("conclusion", .null)
        holds("the latest attempt decides") { _ = try evaluate(appending(snapshot(), "runs", rerun), number: 1, head: head) }
        for (field, value) in [("commit_id", JSON.string(base)), ("author_association", .string("NONE")), ("state", .string("DISMISSED")),
                               ("state", .string("APPROVED")), ("body", .string("AI-SDLC review: PASS\nHead: \(head)")),
                               ("body", .string("AI-SDLC review: INCONCLUSIVE")), ("body", .string("AI-SDLC review: REQUEST_CHANGES"))] {
            holds("review \(field) = \(value.text().prefix(30)) is not a trusted PASS") {
                _ = try evaluate(set(snapshot(), "reviews.0." + field, value), number: 1, head: head)
            }
        }
        holds("a newer inconclusive verdict wins") {
            _ = try evaluate(appending(snapshot(), "reviews", review([("id", .int(2)), ("body", .string("AI-SDLC review: INCONCLUSIVE"))])),
                             number: 1, head: head)
        }
        var s = appending(snapshot(), "reviews", review([("id", .int(0)), ("state", .string("CHANGES_REQUESTED")), ("body", .string("Fix it"))]),
                          atStart: true)
        holds("comments do not clear native requested changes") { _ = try evaluate(s, number: 1, head: head) }
        s = set(s, "reviews.0.state", .string("DISMISSED"))  // GitHub mutates the dismissed review itself
        check(eligible(s), "a dismissed request no longer blocks")
        s = appending(appending(snapshot(), "reviews", review([("id", .int(2)), ("user", .object([("login", .string("reviewer"))])),
                                                               ("body", .string("AI-SDLC review: REQUEST_CHANGES"))])),
                      "reviews", review([("id", .int(3))]))
        holds("another reviewer cannot overrule open findings") { _ = try evaluate(s, number: 1, head: head) }
        for (field, value) in [("name", JSON.string("Optional")), ("conclusion", .string("skipped")), ("run_id", .int(11))] {
            holds("the Focus Gate cannot be skipped or forged: \(field)") { _ = try evaluate(set(snapshot(), "jobs.0." + field, value), number: 1, head: head) }
        }
        for (number, sha) in [(2, head), (1, String(head.prefix(7))), (1, "--help")] {
            holds("the PR number and full SHA must match") { _ = try evaluate(snapshot(), number: number, head: sha) }
        }

        // Pagination and threads, through a fake GitHub.
        var served: [JSON] = [.array((0..<100).map(JSON.int)), .array([.int(100)])], paths: [String] = []
        var github = GitHub { _, path, _ in paths.append(path); return served.removeFirst() }
        check((try? github.pages("test"))?.count == 101 && paths.last?.contains("page=2") == true, "pagination reads every page")
        github = GitHub { _, _, _ in .array((0..<100).map(JSON.int)) }
        holds("pagination is bounded") { _ = try github.pages("test") }
        func page(_ resolved: Bool, _ more: Bool, _ cursor: JSON) -> JSON {
            .object([("data", .object([("repository", .object([("pullRequest", .object([("reviewThreads", .object([
                ("nodes", .array([.object([("isResolved", .bool(resolved))])])),
                ("pageInfo", .object([("hasNextPage", .bool(more)), ("endCursor", cursor)]))]))]))]))]))])
        }
        served = [page(true, true, .string("next")), page(false, false, .null)]
        github = GitHub { _, _, _ in served.removeFirst() }
        check((try? github.threads(1)) == [.object([("isResolved", .bool(true))]), .object([("isResolved", .bool(false))])],
              "thread pagination checks every page")
        github = GitHub { _, _, _ in page(true, true, .string("repeat")) }
        holds("thread pagination must advance") { _ = try github.threads(1) }

        // The CLI: read-only by default; --execute guards the head and base and verifies the readback.
        var calls: [(String, String)] = []
        let quiet: (String) -> Void = { _ in }
        let untouched = GitHub { method, path, _ in calls.append((method, path)); return .null }
        check(mergeMain(["1", head], github: untouched, collect: { _, _, _, _ in snapshot() }, say: quiet) == 0 && calls.isEmpty,
              "read-only by default: no request, no merge")
        var reads: [JSON] = [snapshot()["pr"]!, .object([("commit", .object([("sha", .string(base))]))]),
                             .object([("merged", .bool(true)), ("sha", .string(String(repeating: "c", count: 40)))]),
                             .object([("merged", .bool(true)), ("merge_commit_sha", .string(String(repeating: "c", count: 40)))])]
        var put: JSON?
        github = GitHub { method, _, body in if method == "PUT" { put = body }; return reads.removeFirst() }
        check(mergeMain(["1", head, "--execute"], github: github, collect: { _, _, _, _ in snapshot() }, say: quiet) == 0
              && put?["sha"] == .string(head) && put?["merge_method"] == .string("squash"), "--execute merges the exact head, squashed")
        reads = [snapshot()["pr"]!, .object([("commit", .object([("sha", .string(String(repeating: "d", count: 40)))]))])]
        put = nil
        check(mergeMain(["1", head, "--execute"], github: github, collect: { _, _, _, _ in snapshot() }, say: quiet) == 1 && put == nil,
              "a base that moved before the write stops the merge")

        // Review ordering regressions.
        holds("a delayed draft verdict is ordered by submission, not id") {
            _ = try evaluate(appending(snapshot(), "reviews", review([("id", .int(0)), ("submitted_at", .string("2026-09-21T12:01:00Z")),
                                                                      ("body", .string("AI-SDLC review: REQUEST_CHANGES"))])), number: 1, head: head)
        }
        s = appending(appending(snapshot(), "reviews", review([("id", .int(3)), ("user", .object([("login", .string("reviewer"))])),
                                                               ("state", .string("APPROVED")), ("body", .string("Reviewed"))])),
                      "reviews", review([("id", .int(2)), ("user", .object([("login", .string("reviewer"))])), ("state", .string("CHANGES_REQUESTED")),
                                         ("body", .string("Blocking defect")), ("submitted_at", .string("2026-09-21T12:01:00Z"))]))
        holds("a delayed native veto is not cleared by an older approval") { _ = try evaluate(s, number: 1, head: head) }
        s = appending(appending(snapshot(), "reviews", review([("id", .int(2)), ("user", .object([("login", .string("reviewer"))])),
                                                               ("state", .string("CHANGES_REQUESTED")), ("body", .string("Unresolved defect"))])),
                      "reviews", review([("id", .int(3)), ("user", .object([("login", .string("reviewer"))])), ("state", .string("DISMISSED")),
                                         ("body", .string("Other review")), ("submitted_at", .string("2026-09-21T12:01:00Z"))]))
        holds("dismissing another review does not clear an active veto") { _ = try evaluate(s, number: 1, head: head) }
        check(eligible(appending(snapshot(), "reviews", review([("id", .int(9)), ("state", .string("PENDING")), ("submitted_at", .null)]))),
              "an unsubmitted draft is not a verdict")
        for value in [JSON.null, .string(""), .string("bad-time"), .string("2026-99-21T12:00:00Z")] {
            holds("an unverifiable submission time blocks: \(value.text())") {
                _ = try evaluate(set(snapshot(), "reviews.0.submitted_at", value), number: 1, head: head)
            }
        }
        holds("conflicting verdict lines block") {
            _ = try evaluate(set(snapshot(), "reviews.0.body", .string("AI-SDLC review: PASS\nIndependence: author-review\nHead: \(head)\nAI-SDLC review: REQUEST_CHANGES")),
                             number: 1, head: head)
        }
        holds("a same-second negative verdict cannot be overruled by id") {
            _ = try evaluate(appending(snapshot(), "reviews", review([("id", .int(0)), ("body", .string("AI-SDLC review: INCONCLUSIVE"))])),
                             number: 1, head: head)
        }
        check(!eligible(set(snapshot(), "reviews.0.body", .string("AI-SDLC review: PASS\r\nIndependence: author-review\r\nHead: \(head)"))),
              "a CRLF verdict line does not count, as in Python's re.M")

        // A non-main target must be named; it can never be reached by default.
        s = set(snapshot(), "pr.base.ref", .string("experiment/test-b-parity"))
        holds("main is the default: another target holds") { _ = try evaluate(s, number: 1, head: head) }
        check(eligible(s, "experiment/test-b-parity"), "a named target is eligible")
        holds("a named target still requires current main") {
            _ = try evaluate(set(s, "main_compare", .object([("status", .string("behind"))])), number: 1, head: head, into: "experiment/test-b-parity")
        }
        check((try? evaluate(set(snapshot(), "pr.base.ref", .string("topic")), number: 1, head: head, into: "topic"))?["integration_ref"] == .string("topic"),
              "the named target is recorded in the decision")
        for bad in ["", "a b", String(repeating: "x", count: 101), "refs/heads/../main", "/main", "main/", "a//b", ".."] {
            var collected = false
            check(mergeMain(["1", head, "--into", bad], github: untouched, collect: { _, _, _, _ in collected = true; return snapshot() }, say: quiet) != 0
                  && !collected, "a malformed integration branch is refused before any read: \(bad.prefix(20))")
        }
    }
}
#endif
