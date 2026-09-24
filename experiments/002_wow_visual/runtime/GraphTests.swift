// Canned provider replies, actual graph and Hunt core. No network, capture or OS input.
import Foundation

final class GraphReplies: JevClient {
    var choices: [String]
    var states: [[String: Any]] = []
    var questions: [[String: Any]] = []
    var after: (() -> Void)?
    var malformed = false
    init(_ choices: [String]) { self.choices = choices }
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        states.append(state); questions.append(question)
        guard !choices.isEmpty else { throw GraphError.callLimit }
        let name = choices.removeFirst()
        after?()
        if malformed { return [:] }
        let options = question["criteria"] as! [String: String]
        return ["model": FightLimits.model, "usage": ["prompt_tokens": 10, "completion_tokens": 2],
            "answers": ["action": ["choice": name, "confidence": 0.9,
            "probabilities": Dictionary(uniqueKeysWithValues: options.keys.map { ($0, $0 == name ? 1.0 : 0.0) })]]]
    }
}

@main struct GraphTests {
    static func main() async throws {
        var n = 0
        func check(_ ok: Bool, _ message: String) { n += 1; precondition(ok, message) }
        let path = "experiments/002_wow_visual/runtime/skyborne-hunt.graph.json"
        func load() throws -> GraphSession { try GraphSession.load(URL(fileURLWithPath: path)) }
        let all = Dictionary(uniqueKeysWithValues: HuntAction.allCases.map { ($0.rawValue, $0.facts) })
        let state: [String: Any] = ["goal": "test", "character": ["health_percent": 55],
            "recent_actions": ["first"], "objectives": ["quest A"], "units": "test units"]
        var graph = try load()
        check(graph.path == ["hunt"], "start from declared root")
        check(graph.references["class_conflicts"]?["text"] as? String != nil, "load actual qualified source section")
        check((graph.references["class_conflicts"]?["text"] as! String).contains("Live check"), "retain uncertainty/qualification")
        check(!(graph.references["class_conflicts"]?["text"] as! String).contains("## Mana and rest"), "read only requested section")
        check(graph.graph.mermaid().contains("SKILL FIGHT_TARGET"), "graph export uses real skills")
        check(graph.graph.mermaid().contains("READ recent"), "graph export includes information actions")

        let provider = GraphReplies(["READ:recent", "READ:class_conflicts", "DO:REST"])
        let chosen = try await graph.next(state: state, skills: all, jev: provider, now: { 0 }, deadline: 10)
        check(chosen.action == "REST", "information queries precede actual skill")
        check(graph.calls == 3 && graph.lastTrace.count == 3, "count each call, not just final action")
        check(provider.states[0]["recent_actions"] == nil, "do not eagerly send unrequested memory")
        check((provider.states[0]["tool_memory"] as! [String: Any]).isEmpty, "first request has index, not documents")
        let secondMemory = provider.states[1]["tool_memory"] as! [String: [String: Any]]
        check(secondMemory["recent"] != nil && secondMemory["class_conflicts"] == nil, "no future lookup result in earlier request")
        check((provider.states[2]["tool_memory"] as! [String: Any])["class_conflicts"] != nil, "next request sees actual lookup")
        let offered = provider.questions[2]["criteria"] as! [String: String]
        check(offered["READ:recent"] == nil && offered["READ:class_conflicts"] == nil, "loaded data is not repeatedly fetched")
        let raw = (chosen.response["answers"] as! [String: Any])["action"] as! [String: Any]
        check(raw["choice"] as? String == "DO:REST", "return actual provider distribution, not fabricated action-only answer")
        check((raw["probabilities"] as! [String: Double])["ENTER:search"] != nil, "keep non-action probability options")
        var changed = state; changed["recent_actions"] = ["second"]
        _ = try await graph.next(state: changed, skills: all, jev: GraphReplies(["DO:REST"]), now: { 1 }, deadline: 10)
        let currentMemory = graph.lastTrace[0]["state"] as! [String: Any]
        let recent = (currentMemory["tool_memory"] as! [String: [String: Any]])["recent"]!["values"] as! [String: Any]
        check(recent["recent_actions"] as? [String] == ["second"], "loaded snapshot IDs re-read current input, not stale values")
        check(recent["fights_so_far"] is NSNull, "missing memory is unknown, not invented empty history")
        check(graph.lastTrace.count == 1, "references don't force another call on every turn")

        graph = try load()
        var experienceState = state
        experienceState["experience_index"] = ["enabled": true, "matching_cases": 2]
        experienceState["experience_recall"] = ["scope": "fixture", "counts": [["action": "GO_N", "attempts": 2]]]
        let recallProvider = GraphReplies(["READ:experience", "DO:REST"])
        _ = try await graph.next(state: experienceState, skills: all, jev: recallProvider, now: { 0 }, deadline: 10)
        check(recallProvider.states[0]["experience_recall"] == nil, "experience detail is progressive disclosure")
        let recalledMemory = recallProvider.states[1]["tool_memory"] as! [String: [String: Any]]
        check(recalledMemory["experience"] != nil, "Jev can explicitly retrieve accumulated experience")
        let recalledValues = recalledMemory["experience"]!["values"] as! [String: Any]
        check((recalledValues["experience_recall"] as! [String: Any])["scope"] as? String == "fixture",
              "retrieved evidence enters the next Jev request")

        graph = try load()
        let deep = GraphReplies(["ENTER:search", "ENTER:travel", "ENTER:detour", "DO:DETOUR_LEFT_45"])
        let moved = try await graph.next(state: state, skills: all, jev: deep, now: { 0 }, deadline: 10)
        check(moved.action == "DETOUR_LEFT_45", "arbitrarily deeper data-defined branch uses existing skill")
        check(graph.path == ["hunt", "search", "travel", "detour"], "retain chosen subgoal after a skill")
        let back = GraphReplies(["BACK", "BACK", "BACK", "DO:REST"])
        _ = try await graph.next(state: state, skills: all, jev: back, now: { 0 }, deadline: 10)
        check(graph.path == ["hunt"], "Jev can reconsider and return from nested goal")
        graph = try load()
        _ = try await graph.next(state: state, skills: ["REST": "rest"], jev: GraphReplies(["DO:REST"]), now: { 0 }, deadline: 10)
        check(graph.calls == 1 && graph.loaded.isEmpty, "direct action remains one call, retrieval is optional")

        graph = try load()
        do {
            _ = try await graph.next(state: state, skills: all,
                jev: GraphReplies(["ENTER:search", "BACK", "ENTER:search", "BACK"]), now: { 0 }, deadline: 10)
            check(false, "loop should end")
        } catch { check(error as? GraphError == .callLimit && graph.calls == 4, "planning loop has a fixed call budget") }
        let limited = try GraphSession(graph: graph.graph, references: graph.references, maxCalls: 1)
        do {
            _ = try await limited.next(state: state, skills: all, jev: GraphReplies(["READ:recent", "DO:REST"]), now: { 0 }, deadline: 10)
            check(false, "episode budget should end")
        } catch { check(error as? GraphError == .callLimit && limited.calls == 1, "information requests consume episode quota") }
        let bad = GraphReplies(["DO:NOT_A_SKILL"])
        graph = try load()
        do { _ = try await graph.next(state: state, skills: all, jev: bad, now: { 0 }, deadline: 10); check(false, "unknown output") }
        catch { check(error as? GraphError == .invalidReply, "bad tool ID never dispatches") }
        check(graph.lastTrace.count == 1, "rejected reply remains evidence")
        var t = 0.0
        graph = try load()
        let late = GraphReplies(["READ:recent", "DO:REST"]); late.after = { t = 11 }
        do { _ = try await graph.next(state: state, skills: all, jev: late, now: { t }, deadline: 10); check(false, "late result") }
        catch { check(error as? GraphError == .deadline && graph.calls == 1, "deadline not extended by a lookup") }
        graph = try load()
        do { _ = try await graph.next(state: state, skills: all, jev: late, now: { 0 }, deadline: 10, stopped: { true }); check(false, "stop") }
        catch { check(error as? GraphError == .ownerStop && graph.calls == 0, "existing stop checked before next call") }
        graph = try load()
        let fails = GraphReplies([])
        do { _ = try await graph.next(state: state, skills: all, jev: fails, now: { 0 }, deadline: 10); check(false, "provider failure") }
        catch { check(graph.calls == 1 && graph.lastTrace[0]["error"] != nil, "failed attempts counted without a rules fallback") }

        // Actual Hunt integration: a model-selected LOOK_AROUND is the existing compound skill (four turns + Tab).
        let world = SimHunt.field(clock: FightClock())
        graph = try load()
        let steps = GraphReplies(["READ:recent", "ENTER:search", "DO:LOOK_AROUND"])
        let memory = try ExperienceStore(scope: graph.graph.id)
        let result = await runHunt(host: world, jev: steps, graph: graph, experience: memory, experienceRun: "graph-test")
        check(result.steps.contains(where: { $0.action == .lookAround }), "real runHunt executes selected composite skill")
        check(memory.cases.count == 1 && memory.cases[0].action == "LOOK_AROUND", "actual Hunt records an executed episode")
        check(result.experienceRecords.count == 1, "recorded experience is exposed in run evidence")
        let repeatWorld = SimHunt.field(clock: FightClock())
        graph = try load()
        let repeatProvider = GraphReplies(["READ:experience", "ENTER:search", "DO:LOOK_AROUND"])
        _ = await runHunt(host: repeatWorld, jev: repeatProvider, graph: graph,
                          experience: memory, experienceRun: "graph-test-repeat")
        let repeatMemory = repeatProvider.states[1]["tool_memory"] as! [String: [String: Any]]
        let repeatValues = repeatMemory["experience"]!["values"] as! [String: Any]
        let repeatRecall = repeatValues["experience_recall"] as! [String: Any]
        check((repeatRecall["cases"] as! [[String: Any]]).count == 1,
              "actual Hunt graph recalls a previous comparable episode")
        check(!result.codesPosted.isEmpty && !result.holding, "existing simulated key skill, released at end")
        check(result.graphRecords.count == 4, "including failed follow-up request in Hunt accounting")
        let terminal = result.records.first?["question"] as! [String: Any]
        check((terminal["criteria"] as! [String: String])["DO:LOOK_AROUND"] != nil, "record actual terminal tool menu")
        check(result.memory?.goal == "complete the initial unfinished objectives", "task survives graph tool calls")
        check(result.graphID == "skyborne-hunt-tools-v2", "actual policy identity in result")
        let frozenWorld = SimHunt.field(clock: FightClock())
        graph = try load()
        let freeze = GraphReplies(["ENTER:search", "DO:LOOK_AROUND"])
        freeze.after = { frozenWorld.frozen = true }
        let frozen = await runHunt(host: frozenWorld, jev: freeze, graph: graph)
        check(frozen.codesPosted.isEmpty, "lost vision after graph reply still uses existing executive check")
        check(!frozen.holding, "graph introduces no second input owner")

        // Jev can call the learning branch while hunting; it labels evidence, then returns to normal tools.
        let reviewWorld = SimHunt.field(clock: FightClock())
        let reviewMemory = try ExperienceStore(scope: "skyborne-hunt-tools-v2")
        let reviewFrame = huntExperienceFrame(reviewWorld.survey()!, blocked: [])!
        try reviewMemory.record(ExperienceCase(id: "seed", run: "prior", action: "GO_N", before: reviewFrame,
            after: nil, reported: "blocked in prior fixture", blocked: true, elapsed: 1))
        graph = try load()
        let reviewer = GraphReplies(["ENTER:improve", "DO:REVIEW_MOVEMENT", "ENTER:search", "DO:LOOK_AROUND"])
        var cleanBeforeGameSkill = false
        reviewer.after = { if reviewer.states.count == 2 { cleanBeforeGameSkill = reviewWorld.world.keys.codesPosted.isEmpty } }
        let reviewed = await runHunt(host: reviewWorld, jev: reviewer, graph: graph,
                                     experience: reviewMemory, experienceRun: "review-test")
        check(cleanBeforeGameSkill, "review branch itself posts no game input")
        check(reviewMemory.reviews.contains { $0.caseID == "seed" && $0.topic == "movement" },
              "Jev review remains tied to the exact retained case")
        check(reviewed.experienceReviews.count == 1, "run evidence records the improvement request")
        check(reviewer.questions.count >= 3 && (reviewer.questions[2]["criteria"] as! [String: String])["ENTER:search"] != nil,
              "after review the graph returns to the root decision")
        check(reviewed.steps.contains { $0.action == .lookAround }, "ordinary Hunt continues after the learning branch")

        // New class/skill and extra depth are data, not a change to graph traversal code.
        let extensionJSON = """
        {"id":"fixture-other-class","profile":"synthetic, not implemented in Hunt","root":"r",
         "nodes":{"r":{"question":"Choose branch","skills":[],"branches":{"child":"next"},"reads":[]},
                  "child":{"question":"Choose skill","skills":["CUSTOM"],"branches":{},"reads":[]}},"resources":{}}
        """
        let definition = try JSONDecoder().decode(ToolGraph.self, from: Data(extensionJSON.utf8))
        let extended = try GraphSession(graph: definition)
        let custom = try await extended.next(state: state, skills: ["CUSTOM":"a supplied host capability"],
            jev: GraphReplies(["ENTER:child", "DO:CUSTOM"]), now: { 0 }, deadline: 10)
        check(custom.action == "CUSTOM", "wider profiles/deeper questions require no traversal rewrite")
        check(extended.calls == 2, "only selected branch evaluated")
        do {
            _ = try await extended.next(state: state, skills: ["MISSING":"not in graph"],
                jev: GraphReplies([]), now: { 0 }, deadline: 10)
            check(false, "missing skill must not be silently dropped")
        } catch { check(error as? GraphError == .definition, "catalogue must cover the actual supplied skill menu") }

        let command = try parseNav(["--hunt-dry-run", "--graph", path, "--experience", "/tmp/episodes.json"])
        check(command.graph == path && command.experience == "/tmp/episodes.json" && command.mode == .huntDryRun,
              "catalogue and persistent experience selected explicitly in native CLI")
        check(try parseNav(["--hunt", "--keys", "wqe"]).graph == nil, "legacy mode still default")
        if CommandLine.arguments.contains("--graph") { print(try load().graph.mermaid()) }
        print("decision graph checks passed: \(n)")
    }
}
