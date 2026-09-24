// Bounded episodic memory. Records outcomes, not new policy rules or model weights.
import Foundation

struct ExperienceFrame: Codable {
    let context: [String: String]  // Coarse exact buckets; no hidden learned similarity.
    let progress: [String: Int]
    let capturedAt: Double
    let stream: String
    let geometry: String
}

struct ExperienceCase: Codable {
    let id: String
    let run: String
    let action: String
    let before: ExperienceFrame
    let after: ExperienceFrame?
    let reported: String
    let blocked: Bool?
    let elapsed: Double

    // Missing tracker lines / a lost frame are NOT completion or negative reward.
    var progressDelta: Int? {
        guard let after, !before.progress.isEmpty,
              before.progress.keys.allSatisfy({ after.progress[$0] != nil }) else { return nil }
        let differences = before.progress.map { after.progress[$0.key]! - $0.value }
        guard differences.allSatisfy({ $0 >= 0 }) else { return nil }
        return differences.reduce(0, +)
    }
    var json: [String: Any] {
        ["id": id, "run": run, "action": action, "context": before.context,
         "reported_result": reported, "blocked": blocked as Any? ?? NSNull(),
         "objective_counter_delta": progressDelta as Any? ?? NSNull(), "elapsed_s": elapsed,
         "before": ["stream": before.stream, "geometry": before.geometry, "captured_at": before.capturedAt],
         "after": after.map { ["stream": $0.stream, "geometry": $0.geometry, "captured_at": $0.capturedAt] } as Any? ?? NSNull()]
    }
}

struct ExperienceReview: Codable {
    let caseID: String
    let topic: String
    // A Jev-selected investigation label, NEVER a verified cause or promoted rule.
    var json: [String: Any] { ["case_id": caseID, "topic": topic, "status": "hypothesis", "author": "JEV"] }
    static let topics: [String: String] = [
        "perception": "Request offline study of missing, ambiguous or contradictory observations.",
        "movement": "Request offline study of a blocked or ineffective movement skill.",
        "tactics": "Request offline comparison of tactical alternatives; the cause is not established.",
        "retain_example": "Bookmark this useful episode for later evaluation, not as a universal rule.",
        "unclear": "Record that the available evidence does not identify what should be improved."
    ]
    static let toolTopics: [String: String] = [
        "REVIEW_PERCEPTION": "perception",
        "REVIEW_MOVEMENT": "movement",
        "REVIEW_TACTICS": "tactics",
        "RETAIN_EXAMPLE": "retain_example",
        "REVIEW_UNCLEAR": "unclear"
    ]
    static var tools: [String: String] {
        Dictionary(uniqueKeysWithValues: toolTopics.map { ($0.key, topics[$0.value]!) })
    }
    static func topic(for tool: String) -> String? { toolTopics[tool] }
}

enum ExperienceError: Error { case incompatibleStore, invalidRecord }

final class ExperienceStore {
    private struct Archive: Codable {
        let schema: String
        let scope: String
        let cases: [ExperienceCase]
        let reviews: [ExperienceReview]
    }
    let scope: String
    let url: URL?
    private(set) var cases: [ExperienceCase] = []
    private(set) var reviews: [ExperienceReview] = []
    private(set) var persistenceError: String?
    private let capacity = 256  // Retrieval cache. Full evidence stays in the run event log.

    init(scope: String, url: URL? = nil) throws {
        guard !scope.isEmpty else { throw ExperienceError.incompatibleStore }
        self.scope = scope; self.url = url
        if let url, FileManager.default.fileExists(atPath: url.path) {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
            guard archive.schema == "jev-experience/v1", archive.scope == scope,
                  archive.cases.count <= capacity, archive.reviews.count <= capacity,
                  Set(archive.cases.map(\.id)).count == archive.cases.count else { throw ExperienceError.incompatibleStore }
            for item in archive.cases { try Self.check(item) }
            guard archive.reviews.allSatisfy({ review in
                ExperienceReview.topics[review.topic] != nil && archive.cases.contains { $0.id == review.caseID }
            }) else { throw ExperienceError.incompatibleStore }
            cases = archive.cases; reviews = archive.reviews
        }
    }

    private static func check(_ item: ExperienceCase) throws {
        func valid(_ f: ExperienceFrame) -> Bool {
            f.capturedAt.isFinite && !f.stream.isEmpty && !f.geometry.isEmpty && !f.context.isEmpty
                && f.progress.values.allSatisfy { $0 >= 0 }
        }
        guard !item.id.isEmpty, !item.run.isEmpty, !item.action.isEmpty, valid(item.before),
              item.elapsed.isFinite, item.elapsed >= 0 else { throw ExperienceError.invalidRecord }
        if let after = item.after {
            guard valid(after), after.stream == item.before.stream, after.geometry == item.before.geometry,
                  after.capturedAt > item.before.capturedAt else { throw ExperienceError.invalidRecord }
        }
    }

    @discardableResult func record(_ item: ExperienceCase) throws -> Bool {
        try Self.check(item)
        guard !cases.contains(where: { $0.id == item.id }) else { return false }
        cases.append(item)
        if cases.count > capacity { cases.removeFirst(cases.count - capacity) }
        reviews.removeAll { review in !cases.contains { $0.id == review.caseID } }
        save()
        return true
    }

    // No extra model call or causal classifier in the outcome-recording path.
    func matches(_ context: [String: String]) -> [ExperienceCase] {
        cases.filter { $0.before.context == context }
    }
    func hint(_ context: [String: String]) -> [String: Any] {
        let found = matches(context)
        return ["enabled": true, "scope": scope, "matching_cases": found.count, "stored_cases": cases.count,
                "blocked_cases": found.filter { $0.blocked == true }.count,
                "counter_increased_cases": found.filter { ($0.progressDelta ?? 0) > 0 }.count,
                "counter_unknown_cases": found.filter { $0.progressDelta == nil }.count,
                "review_requests": reviews.filter { r in found.contains { $0.id == r.caseID } }.count,
                "persistence_error": persistenceError as Any? ?? NSNull()]
    }
    func recall(_ context: [String: String]) -> [String: Any] {
        let found = matches(context)
        // Include contrasting outcomes rather than selecting only the best recent run.
        var chosen: [ExperienceCase] = []
        for candidate in [found.last, found.last(where: { $0.blocked == true }),
                          found.last(where: { ($0.progressDelta ?? 0) > 0 })].compactMap({ $0 }) {
            if !chosen.contains(where: { $0.id == candidate.id }) { chosen.append(candidate) }
        }
        let stats = Set(found.map(\.action)).sorted().map { action -> [String: Any] in
            let rows = found.filter { $0.action == action }
            return ["action": action, "attempts": rows.count,
                    "blocked": rows.filter { $0.blocked == true }.count,
                    "counter_increased": rows.filter { ($0.progressDelta ?? 0) > 0 }.count,
                    "counter_unknown": rows.filter { $0.progressDelta == nil }.count]
        }
        return ["scope": scope, "matching": "exact coarse pre-action buckets; not causal or calibrated success probabilities",
                "cases": chosen.map(\.json), "counts": stats,
                "reviews": reviews.filter { r in chosen.contains { $0.id == r.caseID } }.map(\.json)]
    }

    func availableReviewTools(_ context: [String: String]) -> [String: String] {
        guard let last = matches(context).last else { return [:] }
        return ExperienceReview.tools.filter { tool, _ in
            guard let topic = ExperienceReview.topic(for: tool) else { return false }
            return !reviews.contains { $0.caseID == last.id && $0.topic == topic }
        }
    }

    @discardableResult func reviewLatest(_ topic: String, context: [String: String]? = nil) -> ExperienceReview? {
        guard ExperienceReview.topics[topic] != nil else { return nil }
        let last = context.map { matches($0).last } ?? cases.last
        guard let last else { return nil }
        let note = ExperienceReview(caseID: last.id, topic: topic)
        if !reviews.contains(where: { $0.caseID == note.caseID && $0.topic == topic }) {
            reviews.append(note)
            if reviews.count > capacity { reviews.removeFirst() }
            save()
        }
        return note
    }

    var summary: [String: Any] {
        ["scope": scope, "cases": cases.count, "reviews": reviews.count,
         "persistence_error": persistenceError as Any? ?? NSNull()]
    }

    private func save() {
        guard let url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Archive(schema: "jev-experience/v1", scope: scope, cases: cases, reviews: reviews))
                .write(to: url, options: .atomic)
            persistenceError = nil
        } catch { persistenceError = String(describing: error) } // In-memory cases survive; report the failure.
    }
}
