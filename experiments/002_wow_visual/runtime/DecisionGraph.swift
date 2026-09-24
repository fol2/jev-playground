// Jev chooses graph edges: read a reference, enter a question, or invoke a skill.
// This is an in-process policy, not a second input owner or a general agent framework.
import Foundation

struct ToolGraph: Decodable {
    struct Node: Decodable {
        let question: String
        let skills: [String]
        let branches: [String: String]
        let reads: [String]
    }
    struct Resource: Decodable {
        let summary: String
        let keys: [String]?
        let file: String?
        let heading: String?
    }
    let id: String
    let profile: String
    let root: String
    let nodes: [String: Node]
    let resources: [String: Resource]

    // File/schema errors are programming errors, checked once, not by extra model calls.
    func check() throws {
        guard !id.isEmpty, !profile.isEmpty, nodes[root] != nil else { throw GraphError.definition }
        for node in nodes.values {
            guard !node.question.isEmpty, Set(node.skills).count == node.skills.count,
                  node.branches.keys.allSatisfy({ nodes[$0] != nil }),
                  node.reads.allSatisfy({ resources[$0] != nil }) else { throw GraphError.definition }
        }
        var reachable: Set<String> = [], pending = [root]
        while let id = pending.popLast() {
            if reachable.insert(id).inserted { pending += nodes[id]!.branches.keys }
        }
        guard reachable == Set(nodes.keys) else { throw GraphError.definition }
        for r in resources.values {
            guard !r.summary.isEmpty, (r.keys != nil) != (r.file != nil),
                  r.keys.map({ Set($0).count == $0.count && !$0.isEmpty }) ?? true,
                  r.file == nil || (r.heading?.hasPrefix("#") == true) else { throw GraphError.definition }
        }
    }

    // Render the actual definition; the overview roadmap is separately labelled in README.
    func mermaid() -> String {
        let names = nodes.keys.sorted()
        let ids = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, "n\($0.offset)") })
        var lines = ["flowchart TD"]
        for name in names {
            let node = nodes[name]!, id = ids[name]!
            let label = name.replacingOccurrences(of: "\"", with: "'")
            lines.append("  \(id)[\"Jev: \(label)\"]")
            for child in node.branches.keys.sorted() { lines.append("  \(id) --> \(ids[child]!)") }
            for (i, read) in node.reads.enumerated() {
                lines.append("  \(id) --> \(id)r\(i)[\"READ \(read)\"] --> \(id)")
            }
            for (i, skill) in node.skills.enumerated() {
                lines.append("  \(id) --> \(id)s\(i)[\"SKILL \(skill)\"]")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum GraphError: Error, Equatable {
    case definition, referenceMissing(String), noSkills, callLimit, deadline, ownerStop, invalidReply
}

struct GraphDecision {
    let action: String
    let state: [String: Any]
    let question: [String: Any]
    let response: [String: Any] // Original tool-choice distribution, never padded/projected as action probabilities.
}

final class GraphSession {
    let graph: ToolGraph
    let references: [String: [String: Any]]
    let maxCallsPerDecision: Int
    let maxCalls: Int
    private(set) var path: [String]
    private(set) var loaded: [String] = []
    private(set) var calls = 0
    private(set) var lastTrace: [[String: Any]] = []

    init(graph: ToolGraph, references: [String: [String: Any]] = [:],
         maxCallsPerDecision: Int = 4, maxCalls: Int = 120) throws {
        try graph.check()
        guard maxCallsPerDecision > 0, maxCalls > 0 else { throw GraphError.definition }
        for (id, resource) in graph.resources where resource.file != nil {
            guard references[id] != nil else { throw GraphError.referenceMissing(id) }
        }
        self.graph = graph; self.references = references
        self.maxCallsPerDecision = maxCallsPerDecision; self.maxCalls = maxCalls
        path = [graph.root]
    }

    // Snapshot local reference sections once per episode. Preserve source text and its qualifications.
    // No memory dump, vector search, background retrieval or model call. Paths are trusted repo config.
    static func load(_ url: URL) throws -> GraphSession {
        let graph = try JSONDecoder().decode(ToolGraph.self, from: Data(contentsOf: url))
        try graph.check()
        var refs: [String: [String: Any]] = [:]
        for (id, resource) in graph.resources {
            guard let file = resource.file, let heading = resource.heading else { continue }
            let source = url.deletingLastPathComponent().appendingPathComponent(file).standardizedFileURL
            let lines = try String(contentsOf: source, encoding: .utf8).components(separatedBy: "\n")
            guard let start = lines.firstIndex(of: heading) else { throw GraphError.referenceMissing(id) }
            let level = heading.prefix(while: { $0 == "#" }).count
            let end = lines.indices.dropFirst(start + 1).first {
                let n = lines[$0].prefix(while: { $0 == "#" }).count
                return n > 0 && n <= level && lines[$0].dropFirst(n).first == " "
            } ?? lines.count
            refs[id] = ["kind": "reference", "source": file, "lines": [start + 1, end],
                        "text": lines[start..<end].joined(separator: "\n")]
        }
        return try GraphSession(graph: graph, references: refs)
    }

    private func memory(_ id: String, state: [String: Any]) -> [String: Any] {
        if let keys = graph.resources[id]?.keys {
            // Re-read the NEW input snapshot, not a cached position/inventory from a previous decision.
            return ["kind": "snapshot", "values": Dictionary(uniqueKeysWithValues:
                keys.map { ($0, state[$0] ?? NSNull()) })]
        }
        return references[id]!
    }

    func next(state: [String: Any], skills: [String: String], jev: JevClient,
              now: () -> Double, deadline: Double, stopped: () -> Bool = { false }) async throws -> GraphDecision {
        lastTrace = []
        guard !skills.isEmpty else { throw GraphError.noSkills }
        // A catalogue must expose every supplied skill somewhere. It may organise, not silently drop them.
        guard Set(skills.keys).isSubset(of: Set(graph.nodes.values.flatMap(\.skills))) else { throw GraphError.definition }
        for _ in 0..<maxCallsPerDecision {
            if stopped() { throw GraphError.ownerStop }
            guard now().isFinite, now() < deadline else { throw GraphError.deadline }
            guard calls < maxCalls else { throw GraphError.callLimit }
            let nodeID = path.last!, node = graph.nodes[nodeID]!
            var options: [String: String] = [:]
            for skill in node.skills { if let text = skills[skill] { options["DO:" + skill] = text } }
            for (child, text) in node.branches { options["ENTER:" + child] = text }
            for read in node.reads where !loaded.contains(read) { options["READ:" + read] = graph.resources[read]!.summary }
            if path.count > 1 { options["BACK"] = "Return to the parent decision to choose a different goal or skill family." }
            guard !options.isEmpty else { throw GraphError.noSkills }
            var input = state
            for resource in graph.resources.values { for key in resource.keys ?? [] { input.removeValue(forKey: key) } }
            input["decision_graph"] = ["id": graph.id, "profile": graph.profile, "path": path,
                "loaded_ids": loaded, "calls_left_this_turn": maxCallsPerDecision - lastTrace.count,
                "calls_left_episode": maxCalls - calls]
            input["tool_memory"] = Dictionary(uniqueKeysWithValues: loaded.map { ($0, memory($0, state: state)) })
            let question: [String: Any] = ["type": "choice", "instructions": node.question,
                "criteria": options]
            let began = now()
            calls += 1
            let response: [String: Any]
            do { response = try await jev.ask(state: input, question: question) }
            catch {
                lastTrace.append(["call": calls, "node": nodeID, "state": input, "question": question,
                                  "error": String(describing: error), "latency_s": now() - began])
                throw error
            }
            let choice = parseNamedChoice(response, candidates: Array(options.keys), model: FightLimits.model)
            lastTrace.append(["call": calls, "node": nodeID, "state": input, "question": question,
                              "response": response, "latency_s": now() - began])
            if stopped() { throw GraphError.ownerStop }
            guard now() < deadline else { throw GraphError.deadline }
            guard let choice else { throw GraphError.invalidReply }
            if choice.name.hasPrefix("DO:") {
                return GraphDecision(action: String(choice.name.dropFirst(3)), state: input,
                                     question: question, response: response)
            }
            if choice.name == "BACK" { path.removeLast() }
            else if choice.name.hasPrefix("ENTER:") { path.append(String(choice.name.dropFirst(6))) }
            else { loaded.append(String(choice.name.dropFirst(5))) }
        }
        throw GraphError.callLimit // No hidden rules fallback or unbounded planning conversation.
    }
}
