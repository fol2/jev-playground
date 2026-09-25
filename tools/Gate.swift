// Dependency-free, source-only evidence routing. Unknown coverage is a failure.
//
//   tools/sdlc route|check --base BASE [--head HEAD] [--full]
//   tools/sdlc motor [--update-perception]     # the M0-M4 motor proof alone
//   tools/sdlc fishing                         # the fishing proof alone
//   tools/sdlc merge PR FULL_HEAD_SHA [--execute] [--into BRANCH]
//
// Built and run by the tools/sdlc launcher with runtime/JSON.swift, whose ordered JSON writes the bytes
// Python's json.dumps wrote, so a manifest hashes as the Python gate's did.
import CryptoKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

struct GateError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

// MARK: Registry

let fishingDir = "experiments/001_wow_fishing/"
let visualDir = "experiments/002_wow_visual/"
let motorDir = visualDir + "m0/", seekDir = visualDir + "m1/", fightDir = visualDir + "m3/", navDir = visualDir + "m4/"
let runtimeDir = visualDir + "runtime/"
let learnDir = visualDir + "learning/"  // video/research evidence; VideoJev.swift --check proves it offline
let sharedJSON = runtimeDir + "JSON.swift"

let gateCode: Set<String> = ["tools/sdlc", "tools/Gate.swift", "tools/MotorProof.swift", "tools/FishingProof.swift",
                             "tools/Merge.swift", "tools/GateTests.swift", "tests/test_maintenance.cjs"]
let policy: Set<String> = ["AGENTS.md", "CLAUDE.md", "REVIEW.md", ".gitignore", ".github/pull_request_template.md",
                           "docs/agents/ai-sdlc.md", ".github/workflows/ai-sdlc.yml", ".github/workflows/ai-sdlc-maintain.yml"]
let fishingCode: Set<String> = Set("""
    analyse.swift background.swift build.sh decision.swift dotenv.swift jev.swift live.swift loot.swift motion.swift
    probes/background-click/Adapter.swift probes/background-click/NativeBackgroundClickTransport.swift
    probes/background-click/NativeWindowServerPreparation.swift probes/background-click/Probe.swift
    record.swift run_test_a.swift self_tests.swift setup_camera.sh setup_camera.swift
    test_core.sh tests/CoreTests.swift tests/MotionChecks.swift tests/RunnerTests.swift
    """.split(whereSeparator: \.isWhitespace).map { fishingDir + $0 }).union(["data/001_wow_fishing/pilot_20260921/recorder.swift"])
let motorPaths: Set<String> = Set(
    ["Motor.swift", "MotorTests.swift", "Probe.swift", "README.md"].map { motorDir + $0 }
    + ["Seek.swift", "Plate.swift", "SeekTests.swift", "SeekProbe.swift", "README.md"].map { seekDir + $0 }
    + ["Fight.swift", "Tactics.swift", "FightTests.swift", "FightProbe.swift", "README.md"].map { fightDir + $0 }
    + ["Runtime.swift", "Input.swift", "RuntimeTests.swift", "IntegrationTests.swift", "DecisionGraph.swift", "GraphTests.swift",
       "Experience.swift", "ExperienceTests.swift", "JSON.swift", "skyborne-hunt.graph.json", "skyborne-quest.graph.json",
       "skyborne-fight.graph.json", "README.md"].map { runtimeDir + $0 }
    + ["Nav.swift", "NavTests.swift", "NavProbe.swift", "Hunt.swift", "HuntTests.swift", "HuntProbe.swift", "Quest.swift",
       "QuestProbe.swift", "Tabletop.swift", "perception.jsonl", "README.md"].map { navDir + $0 }
    + [visualDir + "README.md", learnDir + "VideoJev.swift"])
/// Replaced by Swift (25 Sept): deleting one runs the proof that replaced it; none may come back.
let retired: [String: String] = Dictionary(uniqueKeysWithValues:
    ["observations.py", "test_observations.py", "m4/tabletop.py", "learning/video_jev.py"].map { (visualDir + $0, "motor-offline") }
    + ["analyse.py", "record.py", "run_test_a.py", "test_analyse.py", "test_run_test_a.py"].map { (fishingDir + $0, "fishing-offline") }
    + ["tools/sdlc.py", "tools/merge_pr.py", "tools/motor_offline.py", "tools/fishing_offline.py", "tests/test_sdlc.py",
       "tests/test_merge_pr.py", "tests/test_visual_route.py"].map { ($0, "governance-tests") })
let required = gateCode.union(policy).union(["README.md"])
let allChecks = ["integrity", "governance", "governance-tests", "automation-tests", "fishing-offline", "motor-offline"]

func isFishingPath(_ path: String) -> Bool {
    if fishingCode.contains(path) || path == ".github/workflows/fishing-offline.yml" { return true }
    let suffix = (path as NSString).pathExtension
    if path.hasPrefix(fishingDir) {
        return ["md", "png", "jpg", "json", "jsonl", "log"].contains(suffix) || path == fishingDir + "probes/background-click/LICENSE"
    }
    return path.hasPrefix("data/001_wow_fishing/") && ["mp4", "mov", "png", "json", "md"].contains(suffix)
}

// MARK: Routing

typealias Change = (status: String, path: String)

func route(_ changes: [Change]) throws -> JSON {
    if changes.isEmpty { throw GateError("empty diff: no acceptance claim to validate") }
    var full = false, fishing = false, motor = false
    for (status, path) in changes {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        if path.isEmpty || path.hasPrefix("/") || path.contains("\\") || segments.contains(where: { ["", ".", ".."].contains($0) })
            || path.unicodeScalars.contains(where: { $0.value < 32 }) || !["A", "M", "D", "T"].contains(status) {
            throw GateError("malformed diff path/status")
        }
        if gateCode.contains(path) || policy.contains(path) {
            full = true
            // A changed proof runner must run its own proof; the launcher and Gate.swift hold what both runners use.
            motor = motor || ["tools/MotorProof.swift", "tools/Gate.swift", "tools/sdlc"].contains(path)
            fishing = fishing || ["tools/FishingProof.swift", "tools/Gate.swift", "tools/sdlc"].contains(path)
        } else if let proof = retired[path], status == "D" {
            motor = motor || proof == "motor-offline"
            fishing = fishing || proof == "fishing-offline"
            full = full || proof == "governance-tests"
        } else if motorPaths.contains(path) || (path.hasPrefix(learnDir) && ["md", "jsonl"].contains((path as NSString).pathExtension)) {
            motor = true
            if path == sharedJSON { fishing = true; full = true }  // the fishing tools and the gate compile it too
        } else if isFishingPath(path) {
            fishing = true
        } else if ["README.md", "experiments/README.md"].contains(path)
                    || (segments.count == 3 && segments[0] == "docs" && segments[1] == "changes" && path.hasSuffix(".md")) {
            full = full || status != "M"  // added/deleted documentation gets the full contract
        } else {
            throw GateError("unclassified path: \(path); register actual offline proof before promotion")
        }
    }
    let checks = ["integrity", "governance"] + (full ? ["governance-tests", "automation-tests"] : [])
        + (fishing ? ["fishing-offline"] : []) + (motor ? ["motor-offline"] : [])
    let reason = motor ? "registered M0-M4 motor probes" : fishing ? "registered fishing source/evidence"
        : full ? "authority/code/addition/deletion" : "allowlisted documentation only"
    return .object([("checks", .array(checks.map(JSON.string))), ("reason", .string(reason)),
                    ("omitted", .object([("F3", .string("no real-runtime claim or live observation authority")),
                                         ("F4", .string("source delivery grants no live-effect authority")),
                                         ("model_calls", .string("deterministic proof; no provider or model runtime"))]))])
}

// MARK: Processes

struct Ran {
    let code: Int32
    let data: Data
    let err: String
    var out: String { String(decoding: data, as: UTF8.self) }

    @discardableResult
    func checked(_ what: String) throws -> Ran {
        guard code == 0 else { throw GateError("\(what) exited \(code)" + (err.isEmpty ? "" : ": " + String(err.suffix(400)))) }
        return self
    }
}

/// Runs a tool to completion within `timeout`, output in files (a full pipe could stall it). With `passthrough`
/// its output goes to this process's stderr, so a gate report on stdout stays clean.
@discardableResult
func sh(_ args: [String], cwd: URL = root, timeout: Double = 600, environment: [String: String]? = nil,
        passthrough: Bool = false, input: Data? = nil) throws -> Ran {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("gate-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let outURL = scratch.appendingPathComponent("out"), errURL = scratch.appendingPathComponent("err")
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    FileManager.default.createFile(atPath: errURL.path, contents: nil)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: args[0].contains("/") ? args[0] : "/usr/bin/env")
    process.arguments = args[0].contains("/") ? Array(args.dropFirst()) : args
    process.currentDirectoryURL = cwd
    if let environment { process.environment = environment }
    process.standardOutput = passthrough ? FileHandle.standardError : try FileHandle(forWritingTo: outURL)
    process.standardError = passthrough ? FileHandle.standardError : try FileHandle(forWritingTo: errURL)
    let stdin = Pipe()
    if input != nil { process.standardInput = stdin }
    try process.run()
    if let input {
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()
    }
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while process.isRunning {
        if ProcessInfo.processInfo.systemUptime > deadline {
            process.terminate()
            process.waitUntilExit()
            throw GateError("\(args[0]) timed out after \(Int(timeout)) s")
        }
        usleep(5_000)
    }
    return Ran(code: process.terminationStatus, data: (try? Data(contentsOf: outURL)) ?? Data(),
               err: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "")
}

func git(_ args: String..., cwd: URL = root) throws -> Data {
    let ran = try sh(["git"] + args, cwd: cwd, timeout: 30)
    guard ran.code == 0 else { throw GateError("git command failed: " + args.prefix(2).joined(separator: " ")) }
    return ran.data
}

func gitText(_ args: String..., cwd: URL = root) throws -> String { try gitText(args, cwd: cwd) }

func gitText(_ args: [String], cwd: URL = root) throws -> String {
    let ran = try sh(["git"] + args, cwd: cwd, timeout: 30)
    guard ran.code == 0 else { throw GateError("git command failed: " + args.prefix(2).joined(separator: " ")) }
    return ran.out.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: Inspection

func inspect(base: String, head: String, cwd: URL = root) throws -> JSON {
    func resolve(_ ref: String) throws -> String { try gitText("rev-parse", "--verify", "--end-of-options", ref + "^{commit}", cwd: cwd) }
    let base = try resolve(base), head = try resolve(head)
    if try resolve("HEAD") != head { throw GateError("checkout does not match requested head") }
    if !(try git("status", "--porcelain", "--untracked-files=all", cwd: cwd)).isEmpty {
        throw GateError("dirty tree: commit or isolate changes before final evidence")
    }
    _ = try git("merge-base", "--is-ancestor", base, head, cwd: cwd)
    let fields = String(decoding: try git("diff", "--no-ext-diff", "--no-renames", "--name-status", "-z", base, head, cwd: cwd), as: UTF8.self)
        .split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
    guard fields.last == "", (fields.count - 1) % 2 == 0 else { throw GateError("malformed git diff") }
    let changes = stride(from: 0, to: fields.count - 1, by: 2).map { Change(status: fields[$0], path: fields[$0 + 1]) }
    var result = try route(changes)
    let changed = Set(changes.map(\.path))
    for entry in String(decoding: try git("ls-tree", "-rz", head, cwd: cwd), as: UTF8.self).split(separator: "\0") {
        guard let tab = entry.firstIndex(of: "\t") else { throw GateError("malformed git tree") }
        let mode = entry[..<tab].split(separator: " ").first.map(String.init) ?? "", name = String(entry[entry.index(after: tab)...])
        guard ["100644", "100755"].contains(mode) else { throw GateError("symlink/submodule is not a validated source surface") }
        if mode == "100755" && !gateCode.contains(name) && !fishingCode.contains(name) { throw GateError("unregistered executable mode") }
        if !required.contains(name) && !changed.contains(name) {
            _ = try route([("M", name)])  // do not hide pre-existing unknown executable inputs
        }
    }
    _ = try git("diff", "--check", base, head, cwd: cwd)
    let tree = try gitText("rev-parse", head + "^{tree}", cwd: cwd)
    result = result.setting("base", .string(base)).setting("head", .string(head)).setting("tree", .string(tree))
        .setting("changes", .array(changes.map { .array([.string($0.status), .string($0.path)]) }))
    return result
}

// MARK: Contracts

func contracts(_ at: URL = root) throws {
    let missing = required.sorted().filter { !FileManager.default.fileExists(atPath: at.appendingPathComponent($0).path) }
    if !missing.isEmpty { throw GateError("missing maintained contracts: " + missing.joined(separator: ", ")) }
    func read(_ p: String) throws -> String { try String(contentsOf: at.appendingPathComponent(p), encoding: .utf8) }
    let agents = try read("AGENTS.md")
    if agents.utf8.count > 6500 { throw GateError("AGENTS.md exceeds the bounded always-loaded context") }
    for phrase in ["AI-SDLC DNA", "Minimise Wall Time", "Minimise Token Consumption", "No compromise"] where !agents.contains(phrase) {
        throw GateError("missing governing rule: " + phrase)
    }
    if !(try read("CLAUDE.md")).contains("@AGENTS.md") { throw GateError("Claude entry point drift") }
    let changesDir = at.appendingPathComponent("docs/changes")
    let notes = ((try? FileManager.default.contentsOfDirectory(atPath: changesDir.path)) ?? []).filter { $0.hasSuffix(".md") }.map { "docs/changes/" + $0 }
    let credential = #/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36,}/#
    for p in required.union(notes).sorted() where (try read(p)).contains(credential) {
        throw GateError("possible credential in " + p)  // never echo matched data
    }
    for name in ["ai-sdlc", "ai-sdlc-maintain"] {
        let workflow = try JSON.parse(try read(".github/workflows/\(name).yml"))
        let expected: JSON = name == "ai-sdlc" ? .object([("contents", .string("read"))])
            : .object([("contents", .string("read")), ("issues", .string("write")), ("actions", .string("read"))])
        guard let permissions = workflow["permissions"]?.pairs, let wanted = expected.pairs,
              Set(permissions.map { $0.0 }) == Set(wanted.map { $0.0 }), wanted.allSatisfy({ w in permissions.contains { $0 == w } }) else {
            throw GateError("workflow permission drift")
        }
        let events = Set(workflow["on"]?.pairs?.map { $0.0 } ?? [])
        if events != (name == "ai-sdlc" ? ["pull_request", "push", "workflow_dispatch"] : ["workflow_run"]) {
            throw GateError("workflow trigger drift")
        }
        // Read as the Python gate read them, workflow["jobs"] and job["steps"]: absent, they hold rather than go unchecked.
        guard let jobs = workflow["jobs"]?.pairs else { throw GateError("workflow has no jobs") }
        for (_, job) in jobs {
            if job["runs-on"] != .string(name == "ai-sdlc" ? "macos-14" : "ubuntu-24.04") || job["permissions"] != nil || job["container"] != nil {
                throw GateError("workflow runner/permission drift")
            }
            guard let steps = job["steps"]?.items else { throw GateError("workflow job has no steps") }
            for step in steps {
                guard let uses = step["uses"].map({ $0.string }) ?? "" else { throw GateError("unapproved or unpinned action") }
                if !uses.isEmpty && uses.wholeMatch(of: #/actions/(checkout|github-script)@[0-9a-f]{40}/#) == nil {
                    throw GateError("unapproved or unpinned action")
                }
                if name.hasSuffix("maintain") && (step["run"] != nil || uses.contains("checkout@")) {
                    throw GateError("privileged maintenance must not execute a checkout")
                }
                if uses.contains("checkout@") && step["with"]?["persist-credentials"] != .bool(false) {
                    throw GateError("checkout must not persist credentials")
                }
            }
        }
    }
    let ci = try JSON.parse(try read(".github/workflows/ai-sdlc.yml"))
    if ci["jobs"]?["focus"]?["name"] != .string("Focus Gate") { throw GateError("stable gate name changed") }
}

// MARK: The report

/// The gate's own tests: built from these sources with -D GATE_TESTS and counted.
let minimumGateTests = 523  // the current count: removing a check must lower this on purpose
func governanceTests() throws -> Int {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gate-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let sources = ["tools/Gate.swift", "tools/MotorProof.swift", "tools/FishingProof.swift", "tools/Merge.swift",
                   "tools/GateTests.swift", sharedJSON].map { root.appendingPathComponent($0).path }
    try sh(["swiftc", "-parse-as-library", "-D", "GATE_TESTS"] + sources + ["-o", tmp.path], timeout: 300).checked("swiftc gate tests")
    return try counted(try sh([tmp.path], timeout: 120).checked("gate tests").out, "gate", minimumGateTests)
}

/// What each selected check runs; integrity and governance are the inspection and contracts themselves.
let proofs: [String: () throws -> String] = [
    "governance-tests": { "gate checks passed: \(try governanceTests())" },
    "automation-tests": { try sh(["node", "--test", "tests/test_maintenance.cjs"], passthrough: true).checked("automation tests"); return "" },
    "fishing-offline": { try fishingProof() },
    "motor-offline": { try motorProof(update: false) },
]

/// Runs the report's checks in order, each through its proof; the proofs' own lines go to stderr.
func run(_ checks: [String], _ proofs: [String: () throws -> String]) throws {
    for check in checks {
        if let proof = proofs[check] {
            let line = try proof()
            if !line.isEmpty { log(line) }
        }
    }
}

/// Model tokens, then the manifest over everything decided, then the time taken, which the manifest leaves out:
/// a manifest nobody can reproduce on a second run anchors nothing.
func seal(_ report: JSON, elapsed: Double) -> JSON {
    let decided = report.setting("model_tokens", .int(0))  // this deterministic command only, not the author session
    return decided.setting("manifest_sha256", .string(sha256Hex(Data(decided.text(sorted: true).utf8))))
        .setting("elapsed_seconds", .double(JSON.round(elapsed, 4)))
}

func report(_ command: String, base: String, head: String, full: Bool) throws -> JSON {
    let started = ProcessInfo.processInfo.systemUptime
    var report = try inspect(base: base, head: head)
    if full {
        var checks = report["checks"]!.items!.compactMap(\.string)
        for check in allChecks where !checks.contains(check) { checks.append(check) }
        report = report.setting("checks", .array(checks.map(JSON.string))).setting("reason", .string("explicit full offline verification"))
    }
    if command == "check" {
        try contracts()
        try run(report["checks"]!.items!.compactMap(\.string), proofs)
        report = report.setting("result", .string("PASS"))
    }
    return seal(report, elapsed: ProcessInfo.processInfo.systemUptime - started)
}

func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

func log(_ line: String) { FileHandle.standardError.write(Data((line + "\n").utf8)) }

#if !GATE_TESTS
@main
struct Sdlc {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        let command = args.isEmpty ? "" : args.removeFirst()
        do {
            switch command {
            case "route", "check":
                var base: String?, head = "HEAD", full = false
                while !args.isEmpty {
                    let flag = args.removeFirst()
                    switch flag {
                    case "--base" where !args.isEmpty: base = args.removeFirst()
                    case "--head" where !args.isEmpty: head = args.removeFirst()
                    case "--full": full = true
                    default: usage()
                    }
                }
                guard let base else { usage() }
                print(try report(command, base: base, head: head, full: full).text(indent: 2))
            case "motor":
                guard args == [] || args == ["--update-perception"] else { usage() }
                print(try motorProof(update: !args.isEmpty))
            case "fishing":
                guard args.isEmpty else { usage() }
                print(try fishingProof())
            case "merge":
                exit(mergeMain(args))
            default:
                usage()
            }
        } catch {
            FileHandle.standardError.write(Data("HOLD: \(error)\n".utf8))
            exit(1)
        }
    }

    static func usage() -> Never {
        FileHandle.standardError.write(Data("""
            usage: tools/sdlc route|check --base BASE [--head HEAD] [--full]
                   tools/sdlc motor [--update-perception] | tools/sdlc fishing
                   tools/sdlc merge PR FULL_HEAD_SHA [--execute] [--into BRANCH]

            """.utf8))
        exit(2)
    }
}
#endif
