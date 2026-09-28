// The judge: Jev asked the way TypeSafe documents it. Several independent questions in one request,
// a state slice of only the fields they need, typed answers, and a cache. Pure Foundation.
//
// Jev is a System One judge (docs.typesafe.ai/model-jaggedness/jev-1.13): calibrated on semantic
// questions over a small state; not a planner, not a calculator, not a text generator. So the engine
// asks it yes/no, which-level and which-of-these questions about one situation, in one call, and never
// whether to read more, where to go next in a menu, or what to do over several steps.
import Foundation

enum JudgeQuestion: Equatable {
    /// "Which of these?" Criteria are the options with what each means. Answer: choice, probabilities, confidence.
    case choice(id: String, instructions: String, options: [String: String])
    /// "Which level?" Criteria are ordered levels, low to high. Answer: score (may fall between levels), probabilities, confidence.
    case score(id: String, instructions: String, levels: [String])
    /// "Is this true?" Answer: noul, a probability of yes in 0...1.
    case noul(id: String, instructions: String)

    var id: String {
        switch self {
        case let .choice(id, _, _), let .score(id, _, _), let .noul(id, _): return id
        }
    }

    /// The request shape from docs.typesafe.ai/primitives, checked 27 September 2026.
    var json: [String: Any] {
        switch self {
        case let .choice(_, instructions, options):
            return ["type": "choice", "instructions": instructions, "criteria": options]
        case let .score(_, instructions, levels):
            return ["type": "score", "instructions": instructions, "criteria": levels]
        case let .noul(_, instructions):
            return ["type": "noul", "instructions": instructions]
        }
    }

    /// Definition errors are programming errors, found once offline, not by a failed call.
    func check() throws {
        guard !id.isEmpty else { throw JudgeError.definition("empty id") }
        switch self {
        case let .choice(id, instructions, options):
            guard !instructions.isEmpty, options.count >= 2, options.values.allSatisfy({ !$0.isEmpty }) else {
                throw JudgeError.definition("choice \(id) needs instructions and at least two described options")
            }
        case let .score(id, instructions, levels):
            guard !instructions.isEmpty, levels.count >= 2, Set(levels).count == levels.count else {
                throw JudgeError.definition("score \(id) needs instructions and at least two distinct levels")
            }
        case let .noul(id, instructions):
            guard !instructions.isEmpty else { throw JudgeError.definition("noul \(id) needs instructions") }
        }
    }
}

enum JudgeAnswer: Equatable {
    case choice(name: String, probabilities: [String: Double], confidence: Double)
    case score(value: Double, probabilities: [Double], confidence: Double)
    case noul(Double)

    var noul: Double? { if case let .noul(p) = self { return p }; return nil }
    var choice: String? { if case let .choice(name, _, _) = self { return name }; return nil }
    var score: Double? { if case let .score(v, _, _) = self { return v }; return nil }
}

enum JudgeError: Error, Equatable {
    case definition(String)
    case emptyRequest
    case badReply(String)
}

/// One request: the state slice and the questions asked of it. Questions must be independent of each
/// other's answers (TypeSafe: a second request only when the first answer changes what to fetch).
struct JudgeRequest: Equatable {
    var state: [String: String]  // flat and small on purpose: the caller filters in code first
    var questions: [JudgeQuestion]

    func check() throws {
        guard !questions.isEmpty else { throw JudgeError.emptyRequest }
        guard Set(questions.map(\.id)).count == questions.count else { throw JudgeError.definition("duplicate question id") }
        for q in questions { try q.check() }
    }

    var payloadQuestions: [String: [String: Any]] {
        Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0.json) })
    }

    /// A stable key for the cache: the same state and questions ask the same thing.
    var cacheKey: String {
        var parts: [String] = []
        for (k, v) in state.sorted(by: { $0.key < $1.key }) { parts.append("\(k)=\(v)") }
        for q in questions.sorted(by: { $0.id < $1.id }) {
            switch q {
            case let .choice(id, instructions, options):
                parts.append("C:\(id):\(instructions):" + options.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ";"))
            case let .score(id, instructions, levels):
                parts.append("S:\(id):\(instructions):" + levels.joined(separator: ";"))
            case let .noul(id, instructions):
                parts.append("N:\(id):\(instructions)")
            }
        }
        return fnv1a(parts.joined(separator: "\u{1F}"))
    }
}

/// FNV-1a, 64-bit, as a hex string. No CryptoKit: this is a cache key, not a signature.
func fnv1a(_ text: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return String(hash, radix: 16)
}

/// The transport: one request with several questions. `LiveJev` (m3/FightProbe.swift) sends one question
/// as `{"action": ...}`; a live client of this protocol sends the whole `questions` object.
protocol JudgeClient {
    func ask(state: [String: Any], questions: [String: [String: Any]]) async throws -> [String: Any]
}

/// Parse the answers against the questions asked. Anything not exactly as asked is a bad reply: the
/// probabilities must be over exactly the options asked and sum to one within `slack`.
func parseJudgeAnswers(_ body: [String: Any], for request: JudgeRequest, model: String, slack: Double = 0.02) throws -> [String: JudgeAnswer] {
    guard let got = body["model"] as? String, got == model else { throw JudgeError.badReply("model") }
    guard let answers = body["answers"] as? [String: Any] else { throw JudgeError.badReply("no answers") }
    func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
    var out: [String: JudgeAnswer] = [:]
    for q in request.questions {
        guard let a = answers[q.id] as? [String: Any] else { throw JudgeError.badReply("no answer for \(q.id)") }
        switch q {
        case let .choice(id, _, options):
            guard let name = a["choice"] as? String, options[name] != nil else { throw JudgeError.badReply("\(id): choice not offered") }
            guard let raw = a["probabilities"] as? [String: Any], Set(raw.keys) == Set(options.keys) else {
                throw JudgeError.badReply("\(id): probabilities not over the options")
            }
            var probabilities: [String: Double] = [:], sum = 0.0
            for (k, v) in raw {
                guard let p = number(v), (0...1).contains(p) else { throw JudgeError.badReply("\(id): probability") }
                probabilities[k] = p; sum += p
            }
            guard abs(sum - 1) <= slack, let confidence = number(a["confidence"]), (0...1).contains(confidence) else {
                throw JudgeError.badReply("\(id): sum or confidence")
            }
            out[id] = .choice(name: name, probabilities: probabilities, confidence: confidence)
        case let .score(id, _, levels):
            guard let value = number(a["score"]), value >= 0, value <= Double(levels.count - 1) else { throw JudgeError.badReply("\(id): score") }
            let raw = (a["probabilities"] as? [Any]) ?? []
            let probabilities = raw.compactMap(number)
            guard probabilities.count == raw.count, raw.isEmpty || probabilities.count == levels.count else {
                throw JudgeError.badReply("\(id): probabilities not over the levels")
            }
            guard let confidence = number(a["confidence"]), (0...1).contains(confidence) else { throw JudgeError.badReply("\(id): confidence") }
            out[id] = .score(value: value, probabilities: probabilities, confidence: confidence)
        case let .noul(id, _):
            guard let p = number(a["noul"]), (0...1).contains(p) else { throw JudgeError.badReply("\(id): noul") }
            out[id] = .noul(p)
        }
    }
    return out
}

/// What one call cost and took, for the run report.
struct JudgeReceipt: Equatable {
    var cached: Bool
    var latency: Double
    var promptTokens: Int?
    var completionTokens: Int?
}

/// The judge: checks the request, serves identical requests from the cache, and returns typed answers.
final class Judge {
    let client: JudgeClient
    let model: String
    let cacheSeconds: Double
    private var cache: [String: (at: Double, answers: [String: JudgeAnswer])] = [:]
    private(set) var receipts: [JudgeReceipt] = []

    init(client: JudgeClient, model: String = "jev-1.13.0", cacheSeconds: Double = 2.0) {
        self.client = client; self.model = model; self.cacheSeconds = cacheSeconds
    }

    func ask(_ request: JudgeRequest, now: () -> Double) async throws -> [String: JudgeAnswer] {
        try request.check()
        let key = request.cacheKey
        let began = now()
        if cacheSeconds > 0, let hit = cache[key], began - hit.at <= cacheSeconds {
            receipts.append(JudgeReceipt(cached: true, latency: 0, promptTokens: nil, completionTokens: nil))
            return hit.answers
        }
        let body = try await client.ask(state: request.state, questions: request.payloadQuestions)
        let answers = try parseJudgeAnswers(body, for: request, model: model)
        let usage = body["usage"] as? [String: Any]
        receipts.append(JudgeReceipt(cached: false, latency: now() - began,
                                     promptTokens: usage?["prompt_tokens"] as? Int, completionTokens: usage?["completion_tokens"] as? Int))
        cache[key] = (now(), answers)
        return answers
    }

    var calls: Int { receipts.filter { !$0.cached }.count }
}

// MARK: The first questions

/// The question library is versioned data: a change here is a behaviour change (AGENTS.md). Each question
/// states the whole judgement in `instructions`, with no double negatives and no arithmetic.
enum QuestionLibrary {
    static let version = "questions-v1"

    /// Replaces `fuzzyNameMatch`, `sameTitle` and `townNameHit`: does an OCR line name this thing?
    static func namesThing(_ id: String, kind: String, name: String) -> JudgeQuestion {
        .noul(id: id, instructions: "Is the text in `\(id)` the \(kind) named \"\(name)\", allowing for a few letters misread by OCR, "
              + "extra characters at either end, and a second line such as a level or a title? Answer no if it names a different \(kind).")
    }

    /// Replaces `questKind`'s keyword rules: what does this objective ask the player to do?
    static func objectiveKind(_ id: String) -> JudgeQuestion {
        .choice(id: id, instructions: "What does the quest objective text in `\(id)` ask the player to do?", options: [
            "kill": "Defeat or slay creatures, usually with a count such as 0/8.",
            "collect": "Gather, harvest or loot items or objects, usually with a count.",
            "useAt": "Use, examine, activate or cast a named item or ability, often at a named place.",
            "talk": "Speak with, talk to, meet or report to a named character.",
            "travel": "Go to, reach or find a named place, with no one to speak to.",
            "handIn": "The quest is complete or ready for turn-in.",
        ])
    }

    /// The fight's grey zone, asked every decision tick as one batch with the tactical questions.
    static func healNow(_ id: String = "heal_now") -> JudgeQuestion {
        .noul(id: id, instructions: "Given `health_percent`, `target_health_percent`, `mana_percent` and `incoming_damage_per_second`, "
              + "should the character cast its heal now rather than keep attacking? Yes when the character would otherwise drop "
              + "below a third of its health before the target dies.")
    }

    static func pullDanger(_ id: String = "pull_danger") -> JudgeQuestion {
        .score(id: id, instructions: "How dangerous is it to attack the selected creature now, given `target_level_offset`, "
               + "`hostiles_near`, `health_percent` and `mana_percent`?", levels: [
            "Safe: one creature, level at or below the character's, full health and mana.",
            "Fair: one creature up to two levels above, or health or mana below two thirds.",
            "Risky: a second hostile within reach, or health below half.",
            "Reckless: two or more hostiles near, or health below a third.",
        ])
    }

    /// The planner's tie-break: only the top candidates within its margin, with the planner's reasons as state.
    static func tieBreak(_ candidates: [GoalCandidate], id: String = "next_goal") -> JudgeQuestion? {
        guard candidates.count >= 2 else { return nil }
        var options: [String: String] = [:]
        for c in candidates {
            options["\(c.kind.rawValue):\(c.subject)"] = "\(c.kind.rawValue) \"\(c.subject)\""
                + (c.distance.map { String(format: ", %.1f units away", $0) } ?? "") + ". " + c.reasons.joined(separator: "; ") + "."
        }
        return .choice(id: id, instructions: "The planner ranks these goals within a few points of each other. Which is the better next step "
                       + "for a player levelling this character, given `character` and `danger`?", options: options)
    }
}
