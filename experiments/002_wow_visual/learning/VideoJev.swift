import CryptoKit
import Foundation

// Replay video annotations, not gameplay ability or model training.
//
//   video-jev --check       # offline regressions + registered corpus
//   video-jev --self-test   # offline regressions only
//   video-jev FILE [...]    # explicit live replay; TYPESAFE_API_KEY; KB=1 optional
//
// All inputs are validated before any provider call. Unknown observations stay unknown.
// Historical replay totals predate the provenance-preserving loader; do not reuse them
// as evidence for this version. No capture, game input, or weight updates happen here.
// Build: swiftc -parse-as-library learning/VideoJev.swift runtime/JSON.swift -o video-jev

enum VideoJev {
    static let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let model = "jev-1.13.0"
    static let expectedCounts = [("zerocks1/part1_decisions.jsonl", 93),
                                 ("zerocks1/part2_decisions.jsonl", 75),
                                 ("zerocks1/part3_decisions.jsonl", 68)]
    // The historical table's agreements: decisions minus the committed mismatch rows of each run.
    static let history = [("part1_facts", 67), ("part2_facts", 48), ("part3_facts", 36),
                          ("part1_kb", 65), ("part2_kb", 48), ("part3_kb", 40)]
    // Historical hand-written baseline, NOT independently verified mechanics. Kept
    // verbatim so that a research change is not disguised as a mechanics correction.
    static let facts = "Mechanics a skilled player knows: a same-level fight takes about 10 s and 15-30% health; melee costs no "
        + "mana; each Lightning Bolt costs about 15% mana and each hit taken pushes a cast back 0.5-1 s; a melee "
        + "creature runs as fast as the character, so walking away only gives it free hits; eating and drinking "
        + "restore both to full in about 20 s, standing still takes minutes; creatures attack when approached "
        + "within about 20 yards (less if lower level); grey nameplates are creatures another player has tagged and "
        + "give no credit; a hotkey digit turns red while the target is out of that spell's range. Out of combat, health and mana regenerate while standing or walking once 5 s pass without casting; at levels 1-5 the pools are small and refill in about 10-20 s, so sitting to drink costs more time than it saves unless mana is below about 30%; a skilled player uses those seconds to turn the camera and find the next target."
    static let goal = "Level up a new Shaman by finishing quests quickly and safely, like a skilled human; never die."
}

struct Invalid: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

typealias Options = [(String, String)]

func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

/// Accept the three historical formats; never drop or stringify bad options.
func optionsOf(_ d: JSON) throws -> Options {
    var items: [(String, JSON)] = []
    switch d["options"] {
    case let .object(pairs)?: items = pairs
    case let .array(options)?:
        for option in options {
            if case let .object(pairs) = option, !pairs.isEmpty {
                items += pairs
            } else if case let .string(s) = option, let colon = s.firstIndex(of: ":") {
                items.append((trimmed(String(s[..<colon])), .string(trimmed(String(s[s.index(after: colon)...])))))
            } else {
                throw Invalid("malformed option")
            }
        }
    default: throw Invalid("options must be an object or list")
    }
    var out: Options = []
    for (key, value) in items {
        guard !trimmed(key).isEmpty, key == trimmed(key) else { throw Invalid("action ID must be a non-empty, trimmed string") }
        guard let text = value.string, !trimmed(text).isEmpty else { throw Invalid("action description must be a non-empty string") }
        guard !out.contains(where: { $0.0 == key }) else { throw Invalid("duplicate action ID: " + key) }
        out.append((key, text))
    }
    guard out.count >= 2 else { throw Invalid("at least two distinct options required") }
    return out
}

func timestampSeconds(_ value: JSON?) throws -> Int {
    guard let value = value?.string else { throw Invalid("timestamp must be a string") }
    if let m = value.wholeMatch(of: #/([0-9]+)m([0-5][0-9])s/#) { return Int(m.1)! * 60 + Int(m.2)! }
    if value.wholeMatch(of: #/[0-9]+:[0-5][0-9](?::[0-5][0-9])?/#) != nil {
        return value.split(separator: ":").reversed().enumerated().reduce(0) { total, part in
            var place = 1
            for _ in 0..<part.offset { place *= 60 }
            return total + Int(part.element)! * place
        }
    }
    throw Invalid("timestamp must be MMmSSs, MM:SS or HH:MM:SS")
}

func validateDecision(_ d: JSON) throws -> Options {
    guard d.pairs != nil else { throw Invalid("decision must be an object") }
    guard d.isFinite else { throw Invalid("out of range float values are not JSON compliant") }
    _ = try timestampSeconds(d["t"])
    guard let state = d["state"]?.pairs, !state.isEmpty else { throw Invalid("state must be a non-empty object") }
    // The annotation is an observation, not an authority over the experiment.
    if state.contains(where: { $0.0 == "goal" || $0.0 == "facts" }) { throw Invalid("state must not override goal or facts") }
    guard let evidence = d["evidence"]?.string, !trimmed(evidence).isEmpty else { throw Invalid("non-empty evidence required") }
    let options = try optionsOf(d)
    guard let human = d["human"]?.string, options.contains(where: { $0.0 == human }) else {
        throw Invalid("human choice must name an offered action")
    }
    return options
}

/// Lines as Python's `str.splitlines` gives them, with their 1-based numbers.
func numberedLines(_ text: String) -> [(Int, Substring)] {
    Array(text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated().map { ($0.offset + 1, $0.element) })
}

func loadDecisions(_ path: URL) throws -> [JSON] {
    var rows: [JSON] = []
    var seen = Set<String>()
    for (number, line) in numberedLines(try String(contentsOf: path, encoding: .utf8)) where !trimmed(String(line)).isEmpty {
        do {
            let row = try JSON.parse(String(line))
            _ = try validateDecision(row)
            guard seen.insert(row.text(sorted: true, ascii: false)).inserted else { throw Invalid("duplicate decision row") }
            rows.append(row)
        } catch {
            throw Invalid("\(path.lastPathComponent):\(number): \(error)")
        }
    }
    if rows.isEmpty { throw Invalid("\(path.lastPathComponent): empty decision file") }
    return rows
}

/// Load flat Markdown facts, preserving their complete trust/source suffixes. The fenced YAML class
/// schema is documentation, not an executed policy. This loader does not certify the tags or resolve
/// knowledge/conflicts.md.
func knowledge(_ here: URL = VideoJev.here) throws -> JSON {
    var out: [(String, JSON)] = []
    for name in ["general.md", "shaman.md"] {
        let stem = String(name.dropLast(3))
        var section = stem, fenced = false
        for (number, line) in numberedLines(try String(contentsOf: here.appendingPathComponent("knowledge/" + name), encoding: .utf8)) {
            if line.drop(while: \.isWhitespace).hasPrefix("```") {
                fenced.toggle()
            } else if !fenced && line.hasPrefix("## ") {
                section = stem + ": " + trimmed(String(line.dropFirst(3)))
            } else if !fenced && line.hasPrefix("- ") {
                let fact = trimmed(String(line.dropFirst(2)))
                guard !fact.isEmpty else { continue }
                let entry = JSON.string("\(fact) [knowledge/\(name):\(number)]")
                if let i = out.firstIndex(where: { $0.0 == section }), case let .array(a) = out[i].1 {
                    out[i].1 = .array(a + [entry])
                } else {
                    out.append((section, .array([entry])))
                }
            }
        }
    }
    return .object(out)
}

func factCount(_ k: JSON) -> Int { k.pairs?.reduce(0) { $0 + ($1.1.items?.count ?? 0) } ?? 0 }

func payload(_ state: JSON, _ options: Options, _ facts: JSON) -> JSON {
    .object([("model", .string(VideoJev.model)),
             ("state", state.setting("goal", .string(VideoJev.goal)).setting("facts", facts)),
             ("questions", .object([("action", .object([
                 ("type", .string("choice")),
                 ("instructions", .string("Which action should the character take next?")),
                 ("criteria", .object(options.map { ($0.0, .string($0.1)) }))]))]))])
}

func checkCorpus(_ here: URL = VideoJev.here, expected: [(String, Int)] = VideoJev.expectedCounts, minimumFacts: Int = 100) throws -> Int {
    let files = FileManager.default
    var found = Set<String>()
    for folder in (try? files.contentsOfDirectory(atPath: here.path)) ?? [] where !folder.hasPrefix(".") {
        for file in (try? files.contentsOfDirectory(atPath: here.appendingPathComponent(folder).path)) ?? []
        where file.hasPrefix("part") && file.hasSuffix("_decisions.jsonl") {
            found.insert(folder + "/" + file)
        }
    }
    let registered = Set(expected.map(\.0))
    guard !expected.isEmpty, found == registered else {
        throw Invalid("corpus manifest mismatch: missing=\(registered.subtracting(found).sorted()), unregistered=\(found.subtracting(registered).sorted())")
    }
    var total = 0
    for (relative, count) in expected {
        let rows = try loadDecisions(here.appendingPathComponent(relative))
        guard rows.count == count else { throw Invalid("\(relative): expected \(count) decisions, found \(rows.count)") }
        // Also exercises the exact request constructor without contacting Jev.
        for row in rows where !payload(row["state"]!, try optionsOf(row), .string(VideoJev.facts)).isFinite {
            throw Invalid("\(relative): a request would not be JSON compliant")
        }
        total += rows.count
    }
    let facts = factCount(try knowledge(here))
    guard facts >= minimumFacts else { throw Invalid("knowledge base lost its facts (\(facts); minimum \(minimumFacts))") }
    return total
}

/// Each historical run's mismatch rows are real decisions (same time and human choice) and reproduce the
/// README table: agreement = decisions - mismatches.
func checkHistory(_ here: URL = VideoJev.here) throws -> Int {
    for (run, agree) in VideoJev.history {
        let part = String(run.split(separator: "_")[0])
        let rows = try loadDecisions(here.appendingPathComponent("zerocks1/\(part)_decisions.jsonl"))
        let decisions = Set(rows.map { "\($0["t"]!.text())\u{0}\($0["human"]!.text())" })
        let text = try String(contentsOf: here.appendingPathComponent("zerocks1/replay_mismatches/\(run).mismatches.jsonl"), encoding: .utf8)
        let misses = try numberedLines(text).dropLast(text.hasSuffix("\n") ? 1 : 0).map { try JSON.parse(String($0.1)) }
        let total = VideoJev.expectedCounts.first { $0.0 == "zerocks1/\(part)_decisions.jsonl" }!.1
        let wrong = try misses.contains { m in
            guard let t = m["t"], let human = m["human"], let jev = m["jev"] else { throw Invalid("\(run): a mismatch row lacks t, human or jev") }
            return !decisions.contains("\(t.text())\u{0}\(human.text())") || jev == human
        }
        if misses.count != total - agree || wrong { throw Invalid("\(run): mismatch rows do not reproduce \(agree)/\(total)") }
    }
    return VideoJev.history.count
}

func probabilitiesOf(_ answer: JSON, _ options: Options) throws -> [(String, Double)] {
    guard let probs = answer["probabilities"]?.pairs, !probs.isEmpty,
          probs.allSatisfy({ p in options.contains { $0.0 == p.0 } }) else {
        throw Invalid("provider probabilities are empty or contain an unoffered action")
    }
    let values = probs.map { $0.1.number }
    guard values.allSatisfy({ $0.map { $0.isFinite && 0 <= $0 && $0 <= 1 } ?? false }), values.compactMap({ $0 }).max()! > 0 else {
        throw Invalid("provider probabilities must be finite numbers in [0, 1] with a positive maximum")
    }
    return probs.map { ($0.0, $0.1.number!) }
}

typealias Ask = (_ key: String, _ state: JSON, _ options: Options, _ facts: JSON) async throws -> JSON

func askJev(_ key: String, _ state: JSON, _ options: Options, _ facts: JSON) async throws -> JSON {
    var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!, timeoutInterval: 25)
    request.httpMethod = "POST"
    request.httpBody = Data(payload(state, options, facts).text().utf8)
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for attempt in 0..<3 {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
                throw URLError(.badServerResponse)
            }
            guard let answer = try JSON.parse(String(decoding: data, as: UTF8.self))["answers"]?["action"] else {
                throw Invalid("provider reply has no answers.action")
            }
            _ = try probabilitiesOf(answer, options)
            return answer
        } catch let error as URLError {
            if attempt == 2 { throw error }
        }
    }
    throw Invalid("unreachable")
}

/// Python's `round(x, 2)`; a whole number stays whole.
func rounded(_ x: JSON) -> JSON {
    if case let .double(d) = x { return .double(JSON.round(d, 2)) }
    return x
}

func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

struct Output {
    var out: (String) -> Void = { print($0); fflush(stdout) }
    var err: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
}

struct Usage: Error, CustomStringConvertible { let description: String }

func videoJev(_ args: [String], env: [String: String] = ProcessInfo.processInfo.environment,
              ask: Ask = askJev, io: Output = Output()) async throws -> Int32 {
    let check = args.contains("--check"), selfTest = args.contains("--self-test")
    let files = args.filter { $0 != "--check" && $0 != "--self-test" }
    if let flag = files.first(where: { $0.hasPrefix("-") }) { throw Usage(description: "unknown option " + flag) }
    if check && selfTest { throw Usage(description: "--check and --self-test are exclusive") }
    if check || selfTest {
        if !files.isEmpty { throw Usage(description: "offline modes do not accept replay files") }
        io.out("learning regression checks: \(try await selfTestChecks())")
        if check {
            io.out("askable decision points: \(try checkCorpus())")
            io.out("historical replays reconciled: \(try checkHistory())")
        }
        return 0
    }
    if files.isEmpty { throw Usage(description: "choose --check, --self-test, or explicit files for a live replay") }
    // Validate EVERY input first: no silent skips or partial provider spend on bad data.
    let urls = files.map { URL(fileURLWithPath: $0) }
    if Set(urls.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }).count != files.count {
        throw Usage(description: "a replay file must not be counted twice")
    }
    var rows: [(String, Int, JSON)] = []
    for (path, url) in zip(files, urls) {
        for (index, row) in try loadDecisions(url).enumerated() { rows.append((path, index + 1, row)) }
    }
    let kbMode = env["KB"] == "1"
    let facts = kbMode ? try knowledge() : .string(VideoJev.facts)
    guard let key = env["TYPESAFE_API_KEY"], !key.isEmpty else {
        throw Usage(description: "live replay requires TYPESAFE_API_KEY; --check is offline")
    }
    var inputs: [(String, JSON)] = []
    for (path, url) in zip(files, urls) { inputs.append((path, .string(sha256(try Data(contentsOf: url))))) }
    let metadata = JSON.object([
        ("model", .string(VideoJev.model)),
        ("evaluator_sha256", .string(sha256(try Data(contentsOf: URL(fileURLWithPath: #filePath))))),
        ("mode", .string(kbMode ? "provenance-kb" : "legacy-hand-written")),
        ("facts_sha256", .string(sha256(Data(facts.text(sorted: true).utf8)))),
        ("inputs", .object(inputs)),
        ("metric", .string("annotation agreement; not gameplay competence"))])
    io.err(metadata.text())
    var agree = 0
    var misses: [JSON] = []
    for (source, index, d) in rows {
        let options = try optionsOf(d)
        let answer = try await ask(key, d["state"]!, options, facts)
        let probs = try probabilitiesOf(answer, options)
        let pick = probs.reduce(probs[0]) { $1.1 > $0.1 ? $1 : $0 }
        let human = d["human"]!.string!
        if pick.0 == human { agree += 1 }
        io.out(JSON.object([("source", .string(source)), ("decision_index", .int(index)), ("t", d["t"]!),
                            ("jev", .string(pick.0)), ("human", .string(human)), ("p", rounded(answer["probabilities"]![pick.0]!)),
                            ("probabilities", answer["probabilities"]!)]).text())
        if pick.0 != human {
            misses.append(d.setting("jev", .string(pick.0)).setting("p", .object(answer["probabilities"]!.pairs!.map { ($0.0, rounded($0.1)) })))
        }
    }
    io.out("agreement \(agree)/\(rows.count)")
    try misses.map { $0.text() + "\n" }.joined().write(toFile: files[0] + ".mismatches.jsonl", atomically: true, encoding: .utf8)
    return 0
}

/// Counted, provider-free regressions, colocated on the registered code path.
func selfTestChecks() async throws -> Int {
    var checks = 0
    func require(_ condition: Bool, _ label: String) throws {
        guard condition else { throw Invalid("self-test failed: " + label) }
        checks += 1
    }
    func refuses(_ label: String, _ call: () throws -> Void) throws {
        do { try call() } catch is Invalid { return try require(true, label) } catch is JSON.ParseError { return try require(true, label) }
        try require(false, label)
    }
    func refusesAsync(_ label: String, _ call: () async throws -> Void) async throws {
        do { try await call() } catch is Invalid { return try require(true, label) }
        try require(false, label)
    }
    func with(_ row: JSON, _ key: String, _ value: JSON) -> JSON { row.setting(key, value) }
    func same(_ a: Options, _ b: Options) -> Bool { a.count == b.count && zip(a, b).allSatisfy { $0 == $1 } }

    // The request bytes Python's json.dumps wrote, checked against it before video_jev.py was deleted.
    try require([0.4, 1.0, 100.0, 1e-05, 0.0001, 1e16, 1234567890123456.0, -2.5e-07, -0.0].map(JSON.pythonRepr)
                == ["0.4", "1.0", "100.0", "1e-05", "0.0001", "1e+16", "1234567890123456.0", "-2.5e-07", "-0.0"], "Python float repr")
    try require(JSON.string("\u{E9}\u{1F600}\u{01}\u{7F}\"\\\n").text() == #""\u00e9\ud83d\ude00\u0001\u007f\"\\\n""#
                && JSON.string("\u{E9}\u{7F}").text(ascii: false) == "\"\u{E9}\u{7F}\"", "Python string escapes")
    try require(try JSON.parse(#"{"b": [1, 2.50, true, null], "a": {}}"#).text() == #"{"b": [1, 2.5, true, null], "a": {}}"#
                && (try JSON.parse(#"{"b": 1, "a": 2}"#).text(sorted: true)) == #"{"a": 2, "b": 1}"#, "key order kept; sorted on request")
    try require((try JSON.parse(#"{"a": [], "b": {}, "c": [1, {"d": null}]}"#)).text(indent: 2)
                == "{\n  \"a\": [],\n  \"b\": {},\n  \"c\": [\n    1,\n    {\n      \"d\": null\n    }\n  ]\n}",
                "indent=2 as Python writes it: one item a line, empty containers inline")
    try require((try JSON.parse("[9223372036854775807, 9223372036854775808, -18446744073709551616]")).text()
                == "[9223372036854775807, 9223372036854775808, -18446744073709551616]"
                && (try validateDecision(with(try JSON.parse(#"{"t": "01m02s", "state": {"x": 9223372036854775808}, "options": {"A": "a", "B": "b"}, "human": "A", "evidence": "e"}"#), "t", .string("01m02s")))).count == 2,
                "a whole number past Int keeps its digits and is finite, as Python's int is")
    try require(JSON.round(0.612345, 2) == 0.61 && JSON.round(2.675, 2) == 2.67 && JSON.round(0.125, 2) == 0.12 && JSON.round(0.375, 2) == 0.38,
                "round as Python's round does: from the exact binary value, exact ties to even")
    for bad in [#"{"a": 1,}"#, #"["a"#, #""\ud800""#, "01", "1.", #"{"a" 1}"#, "tru", "\"tab\tin\""] {
        try refuses("strict JSON") { _ = try JSON.parse(bad) }
    }
    let row = try JSON.parse(#"{"t": "01m02s", "state": {"level": "unreadable", "counts_for_objective": null}, "options": {"A": "Observe", "B": "Move"}, "human": "A", "evidence": "synthetic fixture"}"#)
    let rowOptions: Options = [("A", "Observe"), ("B", "Move")]
    for options in [#"{"A": "Observe", "B": "Move"}"#, #"["A: Observe", "B: Move"]"#, #"[{"A": "Observe"}, {"B": "Move"}]"#] {
        try require(same(try validateDecision(with(row, "options", try JSON.parse(options))), rowOptions), "historical option format")
    }
    for options in ["null", "[]", "{}", #"["A: Observe"]"#, #"["A: Observe", "A: Move"]"#,
                    #"[{"A": "Observe"}, {"A": "Move"}]"#, #"["broken", "B: Move"]"#,
                    #"{"A": 2, "B": "Move"}"#, #"{"": "Observe", "B": "Move"}"#,
                    #"{"A": " ", "B": "Move"}"#, #"{" A": "Observe", "B": "Move"}"#, #"[true, "B: Move"]"#] {
        try refuses("invalid options") { _ = try validateDecision(with(row, "options", try JSON.parse(options))) }
    }
    for (key, value) in [("state", "null"), ("state", "{}"), ("state", "[]"), ("state", #"{"goal": "override"}"#),
                         ("state", #"{"facts": "override"}"#), ("state", #"{"health": 1e999}"#),
                         ("human", #""C""#), ("human", "[]"),
                         ("evidence", #""""#), ("t", #""0:88:00""#), ("t", #""01m99s""#), ("t", "null")] {
        try refuses("invalid decision field") { _ = try validateDecision(with(row, key, try JSON.parse(value))) }
    }
    try refuses("non-object decision") { _ = try validateDecision(.array([])) }
    try refuses("duplicate JSON keys") { _ = try JSON.parse(#"{"a":1,"a":2}"#) }
    try refuses("NaN JSON") { _ = try JSON.parse(#"{"a":NaN}"#) }
    for (value, seconds) in [("01m02s", 62), ("01:02", 62), ("01:02:03", 3723)] {
        try require(try timestampSeconds(.string(value)) == seconds, "timestamp conversion")
    }
    let before = row
    let packet = payload(row["state"]!, rowOptions, .string("facts"))
    try require(row == before && packet["state"]?["counts_for_objective"] == .null, "unknown and input preserved")
    try require(packet["state"]?["human"] == nil && packet["state"]?["evidence"] == nil, "labels withheld")
    try require(payload(try JSON.parse(#"{"goal": "bad", "facts": "bad"}"#), [], .string("good"))["state"]?["facts"] == .string("good"),
                "reserved precedence")
    let big = try JSON.parse("1" + String(repeating: "0", count: 500))  // Python's 10 ** 500
    for probs in [JSON.object([]), .object([("C", .int(1))]), .object([("A", .double(.nan))]), .object([("A", .double(.infinity))]),
                  .object([("A", .double(-0.1))]), .object([("A", .double(1.1))]), .object([("A", big)]),
                  .object([("A", .bool(true))]), .object([("A", .string("1"))]), .object([("A", .int(0))])] {
        try refuses("bad response") { _ = try probabilitiesOf(.object([("probabilities", probs)]), rowOptions) }
    }
    try require(try probabilitiesOf(try JSON.parse(#"{"probabilities": {"A": 0.6, "B": 0.4}}"#), rowOptions).first?.1 == 0.6, "good response")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-jev-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("knowledge"), withIntermediateDirectories: true)
    try "## Test\n- Low confidence [classic-transfer] source-x\n".write(to: root.appendingPathComponent("knowledge/general.md"), atomically: true, encoding: .utf8)
    try "```yaml\n- not a flat fact\n```\n## Test\n- Observed [owner-live] source-y\n".write(to: root.appendingPathComponent("knowledge/shaman.md"), atomically: true, encoding: .utf8)
    let facts = try knowledge(root)
    try require(factCount(facts) == 2, "fenced YAML not counted")
    let general = facts["general: Test"]?.items?.first?.string ?? ""
    try require(general.contains("[classic-transfer] source-x"), "trust and source preserved")
    try require(general.contains("knowledge/general.md:2"), "source location preserved")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("video"), withIntermediateDirectories: true)
    let path = root.appendingPathComponent("video/part1_decisions.jsonl")
    try (row.text() + "\n").write(to: path, atomically: true, encoding: .utf8)
    let manifest = [("video/part1_decisions.jsonl", 1)]
    try require(try checkCorpus(root, expected: manifest, minimumFacts: 2) == 1, "offline corpus request construction")
    try refuses("lost knowledge facts") { _ = try checkCorpus(root, expected: manifest, minimumFacts: 3) }
    try refuses("deleted row") { _ = try checkCorpus(root, expected: [("video/part1_decisions.jsonl", 2)], minimumFacts: 2) }
    try refuses("empty manifest") { _ = try checkCorpus(root, expected: [], minimumFacts: 2) }
    try refuses("missing file") { _ = try checkCorpus(root, expected: [("missing/part1_decisions.jsonl", 1)], minimumFacts: 2) }
    for text in ["", "not JSON\n", row.text() + "\n" + row.text(), with(row, "human", .string("C")).text(), #"{"t":"00m00s","t":"01m00s"}"#] {
        try text.write(to: path, atomically: true, encoding: .utf8)
        try refuses("corrupt/empty/duplicate row") { _ = try loadDecisions(path) }
    }
    try (row.text() + "\n").write(to: path, atomically: true, encoding: .utf8)
    var lines: [String] = [], errors: [String] = []
    var calls = 0
    let io = Output(out: { lines.append($0) }, err: { errors.append($0) })
    let model: Ask = { _, _, _, _ in calls += 1; return try JSON.parse(#"{"probabilities": {"A": 0.612345, "B": 0.387655}}"#) }
    let env = ["TYPESAFE_API_KEY": "offline-test-not-a-secret", "KB": "0"]
    try require(try await videoJev([path.path], env: env, ask: model, io: io) == 0, "mock replay CLI")
    let prediction = try JSON.parse(lines.first ?? "")
    try require(prediction["probabilities"]?["A"] == .double(0.612345), "unrounded probabilities retained")
    try require(prediction["source"] == .string(path.path) && prediction["decision_index"] == .int(1), "stable replay identity")
    try require((try JSON.parse(errors.first ?? "")["evaluator_sha256"]?.string?.count) == 64, "replay evaluator identity")
    calls = 0
    let bad = root.appendingPathComponent("bad.jsonl")
    try with(row, "human", .string("C")).text().write(to: bad, atomically: true, encoding: .utf8)
    try await refusesAsync("validate all files before replay") { _ = try await videoJev([path.path, bad.path], env: env, ask: model, io: io) }
    try require(calls == 0, "bad later file spends no provider calls")
    try row.text().write(to: root.appendingPathComponent("video/part2_decisions.jsonl"), atomically: true, encoding: .utf8)
    try refuses("unregistered file") { _ = try checkCorpus(root, expected: manifest, minimumFacts: 2) }
    guard checks >= 81 else { throw Invalid("self-test suite lost checks (\(checks))") }  // the current count
    return checks
}

@main
struct VideoJevMain {
    static func main() async {
        do {
            exit(try await videoJev(Array(CommandLine.arguments.dropFirst())))
        } catch let usage as Usage {
            FileHandle.standardError.write(Data("usage: video-jev [--check | --self-test] [FILE ...]\nerror: \(usage)\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
            exit(1)
        }
    }
}
