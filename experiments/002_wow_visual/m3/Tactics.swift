// M3b for issue #5: what Jev is offered in a fight, and what runs without asking it. The bar's skills
// with their numbers (the live tooltip first, the skills dictionary second), the chain book's accepted
// chains for this class, level and bar, the break rules that return a running chain to Jev, and the
// numbers the script works out for it. Pure Foundation: runFight (Fight.swift) runs it and
// FightProbe.swift reads the bar. The owner, 25 Sept: "not every move needs JEV. but JEV can decide to
// break the chain"; "in the fight, jev can also choose specific skill ... if jev want micro-control".
import Foundation

enum ChainLimits {
    static let healthBreak = 0.2  // the character lost this much health since Jev last chose: ask again
    static let checkIn = 8.0      // seconds a chain runs before Jev is asked whether to go on
    static let slots = 4          // CHAIN_1 ... CHAIN_4, as the quest graph's HAND_IN_n
    static let recent = 8         // this fight's steps kept for READ:recent
}

/// One skills-dictionary row (learning/knowledge/shaman-skills.jsonl): a source claim, not a live reading.
struct SkillEntry: Decodable {
    let name: String
    let rank: Int?
    let level: Int
    let conflict: String?

    static func dictionary(_ text: String) throws -> [SkillEntry] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try text.split(separator: "\n").map { try decoder.decode(SkillEntry.self, from: Data($0.utf8)) }
    }
}

/// A bar skill as Jev sees it. The numbers are the live tooltip's; the dictionary adds the level it is
/// learned at and any disagreement between its sources and a live tooltip.
struct SkillCard: Equatable {
    let role: SkillRole
    let slot: String  // the hotkey, as the bar shows it
    let skill: Skill
    var learnedAt: Int?
    var note: String?

    var mana: Int? { tooltipNumber(skill.text, #"(\d+) Mana"#).map(Int.init) }
    var range: Int? { tooltipNumber(skill.text, #"(\d+) yd range"#).map(Int.init) }
    var cooldown: Double? {
        tooltipNumber(skill.text, #"([0-9.]+) sec cooldown"#) ?? tooltipNumber(skill.text, #"([0-9.]+) min cooldown"#).map { $0 * 60 }
    }
    var json: [String: Any] {
        ["slot": slot, "name": skill.name, "rank": orNull(skill.rank), "role": role.rawValue, "mana": orNull(mana),
         "cast_s": orNull(skill.cast), "cooldown_s": orNull(cooldown), "range_yd": orNull(range), "tooltip": skill.text,
         "learned_at_level": orNull(learnedAt), "dictionary_note": orNull(note)]
    }
}

/// The first number a pattern's group captures in a tooltip's text.
func tooltipNumber(_ text: String, _ pattern: String) -> Double? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return Double(text[range])
}

/// A chain from the chain book (learning/knowledge/fight-chains.jsonl): steps the script runs one after
/// another without asking Jev, each until its condition holds. Only `accepted` chains are offered; a
/// `candidate` (a new idea, from experience or the author) waits for review outside any fight.
struct FightChain: Decodable, Equatable {
    struct Step: Decodable, Equatable {
        let skill: String  // a role: bolt, shock, melee, heal, buff, face, approach or wait
        let until: String  // once; contact (the creature reached the character); dead
        let max: Int?      // at most this many uses of the step

        enum CodingKeys: String, CodingKey { case skill = "do", until, max }
    }
    let id: String
    let className: String
    let levels: [Int]
    let requires: [String]
    let steps: [Step]
    let summary: String
    let source: String
    let status: String

    enum CodingKeys: String, CodingKey { case id, className = "class", levels, requires, steps, summary, source, status }

    static let skills: Set<String> = ["bolt", "shock", "melee", "heal", "buff", "face", "approach", "wait"]

    /// Book errors are programming errors, checked once at load, as the graph's.
    static func book(_ text: String) throws -> [FightChain] {
        let chains = try text.split(separator: "\n").map { try JSONDecoder().decode(FightChain.self, from: Data($0.utf8)) }
        func valid(_ c: FightChain) -> Bool {
            guard !c.id.isEmpty, !c.summary.isEmpty, !c.source.isEmpty, ["accepted", "candidate"].contains(c.status),
                  c.levels.count == 2, c.levels[0] >= 1, c.levels[0] <= c.levels[1], !c.steps.isEmpty else { return false }
            return c.requires.allSatisfy { SkillRole(rawValue: $0) != nil }
                && c.steps.allSatisfy { skills.contains($0.skill) && ["once", "contact", "dead"].contains($0.until) && ($0.max ?? 1) >= 1 }
        }
        guard Set(chains.map(\.id)).count == chains.count, chains.allSatisfy(valid) else { throw GraphError.definition }
        return chains
    }

    static let untilText = ["once": "once", "contact": "until the creature reaches the character", "dead": "until the creature dies"]

    var text: String {
        let parts = steps.map { s -> String in
            let most = s.max.map { ", at most \($0) times" } ?? ""
            return "\(s.skill) \(Self.untilText[s.until] ?? s.until)\(most)"
        }
        return "\(summary) Steps: \(parts.joined(separator: "; then ")). For levels \(levels[0])-\(levels[1]). Source: \(source)."
    }
}

/// The skills on this character's bar, the level if it was read, and the chains that fit both.
struct FightKit {
    var cards: [SkillRole: SkillCard] = [:]
    var level: Int?
    var chains: [FightChain] = []

    /// Interact With Target (F9) swings the weapon, so melee needs no slot.
    func has(_ role: SkillRole) -> Bool { role == .melee || cards[role] != nil }

    init(bar: [(slot: String, skill: Skill)], dictionary: [SkillEntry], book: [FightChain], className: String, level: Int?) {
        self.level = level
        for (slot, skill) in bar {
            guard let r = role(skill), cards[r] == nil else { continue }
            let entry = dictionary.first { $0.name == skill.name && $0.rank == skill.rank }
            cards[r] = SkillCard(role: r, slot: slot, skill: skill, learnedAt: entry?.level, note: entry?.conflict)
        }
        let cards = self.cards
        func fits(_ c: FightChain) -> Bool {
            guard c.status == "accepted", c.className == className else { return false }
            if let level, !(c.levels[0]...c.levels[1]).contains(level) { return false }
            return c.requires.allSatisfy { r in r == "melee" || SkillRole(rawValue: r).map { cards[$0] != nil } == true }
        }
        chains = book.filter(fits)
    }
}

/// The action a chain step takes now. Melee is one Interact With Target press; its swings then go on by
/// themselves, so the step waits while they land.
func stepAction(_ step: FightChain.Step, _ e: Episode) -> FightAction {
    switch step.skill {
    case "bolt": return .castLightningBolt
    case "shock": return .castShock
    case "heal": return .heal
    case "buff": return .buffWeapon
    case "face": return .faceTarget
    case "approach": return .approachToRange
    case "wait": return .wait
    default: return e.meleeOn ? .wait : .startMelee
    }
}

/// A chain Jev chose, run step by step by the script until it is done or a break returns it to Jev.
struct ChainRun {
    let chain: FightChain
    var stage = 0
    var uses = 0          // of the current step
    var ran = 0           // steps performed since Jev chose or continued it
    var askedAt: Double   // when Jev last chose it
    var askedHealth: Double

    init(_ chain: FightChain, at now: Double, health: Double) {
        self.chain = chain
        askedAt = now
        askedHealth = health
    }

    var step: FightChain.Step? { stage < chain.steps.count ? chain.steps[stage] : nil }

    /// Count the step that ran on `before` and move on when its condition holds in `after`. Contact is a hit
    /// on the character, or, for melee, the creature losing health to the swings.
    mutating func observe(before: Obs, after: Obs, killed: Bool) {
        guard let step else { return }
        uses += 1
        let contact = after.player < before.player - FightLimits.healthDrop
            || (step.skill == "melee" && after.target < before.target - FightLimits.healthDrop)
        let limit = uses >= (step.max ?? (step.until == "contact" ? 3 : Int.max))
        if killed { stage = chain.steps.count }
        else if step.until == "once" || limit || (step.until == "contact" && contact) { stage += 1; uses = 0 }
    }

    mutating func resume(at now: Double, health: Double) { askedAt = now; askedHealth = health; ran = 0 }
}

/// Results that mean a step did not do what it was for (the hosts' own wording); a break asks Jev. After the
/// F9 turn only the retry counts: a first "not cast" the turn put right is not a failure.
func stepFailed(_ result: String) -> Bool {
    let last = result.lowercased().components(separatedBy: "retried: ").last ?? ""
    return ["not cast", "did not start", "not seen", "still out of range", "budget spent", "failed", "not done:"].contains {
        last.contains($0)
    }
}

/// Why the script must ask Jev before the running chain's next step; nil when the step runs without a call.
func chainBreak(_ run: ChainRun, _ o: Obs, _ e: Episode, allowed: [FightAction], lastResult: String, now: Double) -> String? {
    if o.combat && o.player < FightLimits.playerSafety {
        return "the character's health is below \(Int(FightLimits.playerSafety * 100))% in combat: healing comes first"
    }
    if e.killed { return "the target died: the chain is done" }
    guard let step = run.step else { return "the chain's steps are done" }
    if run.ran > 0 && stepFailed(lastResult) { return "the last step did not work: \(lastResult)" }
    let next = stepAction(step, e)
    if !allowed.contains(next) {
        let why = next == .castLightningBolt && o.rangeRed ? " (out of Lightning Bolt range)"
            : next == .castShock ? " (the shock is out of range or cooling down)" : ""
        return "the next step, \(next.rawValue), cannot be done now\(why)"
    }
    let lost = run.askedHealth - o.player
    if lost >= ChainLimits.healthBreak { return "the character lost \(Int((lost * 100).rounded()))% health since the last decision" }
    if now - run.askedAt >= ChainLimits.checkIn { return "check-in: \(Int(now - run.askedAt)) s since the last decision" }
    return nil
}

/// What each skill did in this fight, measured from the frame a step ran on to the next fresh one.
struct FightTally {
    struct Use { let target: Double; let mana: Double; let seconds: Double }
    private(set) var uses: [FightAction: [Use]] = [:]
    private(set) var engaged: (t: Double, player: Double)?

    /// A wait while the swings go on counts as melee. A new target cue is a different creature: not counted.
    mutating func record(_ action: FightAction, before: Obs, after: Obs, seconds: Double, meleeOn: Bool) {
        let key = action == .wait && meleeOn ? FightAction.startMelee : action
        guard [.castLightningBolt, .castShock, .startMelee, .heal, .buffWeapon].contains(key),
              before.stamp?.target == after.stamp?.target, seconds > 0 else { return }
        uses[key, default: []].append(Use(target: max(0, before.target - after.target), mana: max(0, before.mana - after.mana),
                                          seconds: seconds))
    }

    mutating func engage(_ o: Obs, now: Double) { if engaged == nil && o.combat { engaged = (now, o.player) } }
}

/// The numbers the script works out for Jev: from this fight's frames and the bar's tooltips, never
/// guessed. A value no frame has shown yet is null.
func fightCalculations(_ o: Obs, _ e: Episode, kit: FightKit, tally: FightTally, now: Double) -> [String: Any] {
    func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    func percent(_ v: Double?) -> Any { orNull(v.map { Int(($0 * 100).rounded()) }) }
    var skills: [String: Any] = [:]
    let alive = Episode.alive(o)
    for (action, role) in [(FightAction.castLightningBolt, SkillRole.bolt), (.castShock, .shock), (.heal, .heal), (.startMelee, .melee)]
    where kit.has(role) {
        let uses = tally.uses[action] ?? []
        var row: [String: Any] = ["name": kit.cards[role]?.skill.name ?? "Interact With Target (melee)", "uses_this_fight": uses.count]
        if action == .startMelee {
            let seconds = uses.map(\.seconds).reduce(0, +)
            let rate = seconds >= 1 ? uses.map(\.target).reduce(0, +) / seconds : nil
            row["target_percent_per_second"] = orNull(rate.map { roundTo($0 * 100, 10) })
            row["seconds_to_kill"] = orNull(alive ? rate.flatMap { $0 > 0 ? Int((o.target / $0).rounded(.up)) : nil } : nil)
        } else {
            let perUse = mean(uses.map(\.target)), mana = mean(uses.map(\.mana))
            row["target_percent_per_use"] = percent(action == .heal ? nil : perUse)
            row["mana_percent_per_use"] = percent(mana)
            row["uses_affordable"] = orNull(mana.flatMap { $0 > 0.005 ? Int(o.mana / $0) : nil })
            row["uses_to_kill"] = orNull(alive && action != .heal ? perUse.flatMap { $0 > 0.005 ? Int((o.target / $0).rounded(.up)) : nil } : nil)
            row["seconds_per_use"] = orNull(mean(uses.map(\.seconds)).map { roundTo($0, 10) })
        }
        if action == .castShock {
            let cooldown = kit.cards[.shock]?.cooldown ?? 6
            row["ready_in_s"] = e.lastShock.map { roundTo(max(0, cooldown - (now - $0)), 10) } ?? 0
        }
        skills[action.rawValue] = row
    }
    var character: [String: Any] = ["health_percent": Int(o.player * 100), "mana_percent": Int(o.mana * 100)]
    if let (t, p) = tally.engaged, now - t >= 2 {
        let rate = (p - o.player) / (now - t)
        character["health_lost_percent_per_second"] = roundTo(rate * 100, 10)
        character["seconds_to_zero_health_at_that_rate"] = orNull(rate > 0.001 ? Int(o.player / rate) : nil)
    }
    return ["meaning": "measured from this fight's frames: a skill's effect is the change from the frame it ran on to the next; null until seen",
            "character": character, "skills": skills]
}

/// One option Jev may choose: a single skill (micro-control), a chain, or CONTINUE for the running chain.
struct FightOffer {
    let name: String
    let text: String
    let action: FightAction?  // a single skill; nil for a chain or CONTINUE
    let chain: FightChain?    // nil for a single skill or CONTINUE
}

/// The offer text for one skill: its live tooltip numbers, and the mechanics that bear on choosing it.
func skillText(_ action: FightAction, kit: FightKit) -> String {
    func card(_ role: SkillRole) -> String {
        guard let c = kit.cards[role] else { return "" }
        return " \(c.skill.name)\(c.skill.rank.map { " rank \($0)" } ?? ""): " + [c.mana.map { "\($0) mana" },
            c.skill.cast.map { "\($0) s cast" } ?? "instant", c.range.map { "\($0) yd" }, c.cooldown.map { "\(Int($0)) s cooldown" }]
            .compactMap { $0 }.joined(separator: ", ") + "."
    }
    switch action {
    case .castLightningBolt:
        return "Cast the bolt at the target." + card(.bolt) + " Each melee hit taken during a cast pushes it back, so a bolt in melee often breaks and its mana is lost. Holding it queues the next cast."
    case .castShock:
        return "Cast the shock at the target." + card(.shock) + " Instant, so hits cannot push it back; its range is shorter than the bolt's."
    case .heal:
        return "Cast the heal on the character." + card(.heal) + " Melee hits push it back like any cast."
    case .buffWeapon:
        return "Apply the weapon enchant." + card(.buff) + " Every melee swing does more damage while it lasts."
    case .startMelee:
        return "Press Interact With Target: automatic weapon swings at the target, walking up to it first if it is not adjacent. No mana. A melee creature runs as fast as the character, so walking away only gives it free hits."
    default:
        return action.facts
    }
}

/// What Jev may choose now. A chain is offered while its first step can be done; CONTINUE while the
/// running chain's next step can.
func fightOffers(_ o: Obs, _ e: Episode, allowed: [FightAction], kit: FightKit, running: ChainRun?) -> [FightOffer] {
    var offers: [FightOffer] = []
    if let run = running, let step = run.step, allowed.contains(stepAction(step, e)) {
        offers.append(FightOffer(name: "CONTINUE", text: "Go on with the running chain \(run.chain.id): step \(run.stage + 1) of \(run.chain.steps.count) is next. \(run.chain.text)",
                                 action: nil, chain: nil))
    }
    let startable = kit.chains.filter { $0.id != running?.chain.id && allowed.contains(stepAction($0.steps[0], e)) }
    for (i, chain) in startable.prefix(ChainLimits.slots).enumerated() {
        offers.append(FightOffer(name: "CHAIN_\(i + 1)", text: "Run the chain \(chain.id). \(chain.text) It stops early and asks again when the character loses health fast, a step fails or cannot be done, the target dies, or every \(Int(ChainLimits.checkIn)) s.",
                                 action: nil, chain: chain))
    }
    for action in allowed { offers.append(FightOffer(name: action.rawValue, text: skillText(action, kit: kit), action: action, chain: nil)) }
    return offers
}

/// The running chain as Jev's input shows it, and why Jev is asked now.
func chainState(_ run: ChainRun?, reason: String?) -> [String: Any] {
    guard let run else { return ["running": NSNull(), "asked_because": reason ?? "no chain is running"] }
    return ["running": run.chain.id, "steps_done": run.stage, "steps": run.chain.steps.count,
            "asked_because": reason ?? "no break: the chain would go on"]
}

/// The fight graph (runtime/skyborne-fight.graph.json), the data files it names, and this bar's kit.
struct FightTactics {
    let graph: ToolGraph
    let references: [String: [String: Any]]
    let kit: FightKit

    private struct Files: Decodable { let dictionary: String; let chains: String; let className: String
        enum CodingKeys: String, CodingKey { case dictionary, chains, className = "class" } }

    static let offerNames = ["CONTINUE"] + (1...ChainLimits.slots).map { "CHAIN_\($0)" } + FightAction.allCases.map(\.rawValue)

    /// A fresh session per fight: its reads and call budget start again, as the fight's own clock does.
    func session() throws -> GraphSession {
        try GraphSession(graph: graph, references: references, maxCallsPerDecision: 2, maxCalls: 2 * FightLimits.maxDecisions)
    }

    static func load(_ url: URL, bar: [(slot: String, skill: Skill)], level: Int?) throws -> FightTactics {
        let loaded = try GraphSession.load(url)
        guard Set(offerNames).isSubset(of: Set(loaded.graph.nodes.values.flatMap(\.skills))) else { throw GraphError.definition }
        let files = try JSONDecoder().decode(Files.self, from: Data(contentsOf: url))
        let folder = url.deletingLastPathComponent()
        let dictionary = try SkillEntry.dictionary(String(contentsOf: folder.appendingPathComponent(files.dictionary), encoding: .utf8))
        let book = try FightChain.book(String(contentsOf: folder.appendingPathComponent(files.chains), encoding: .utf8))
        return FightTactics(graph: loaded.graph, references: loaded.references,
                            kit: FightKit(bar: bar, dictionary: dictionary, book: book, className: files.className, level: level))
    }
}

/// The main bar as Vision read it live on 24 Sept, for the simulations: Lightning Bolt, Earth Shock,
/// Healing Wave and Rockbiter Weapon on keys 2, 3, 4 and 8.
let simBar: [(slot: String, skill: Skill)] = [
    ("2", Skill(name: "Lightning Bolt", text: "15 Mana 30 yd range 1.5 sec cast Casts a bolt of lightning at the target for 14 to 17 Nature damage.", cast: 1.5, rank: 1)),
    ("3", Skill(name: "Earth Shock", text: "30 Mana 20 yd range 6 sec cooldown Instant Instantly shocks the target with concussive force, causing 17 to 20 Nature damage.", cast: nil, rank: 1)),
    ("4", Skill(name: "Healing Wave", text: "25 Mana 40 yd range 1.5 sec cast Heals a friendly target for 36 to 47.", cast: 1.5, rank: 1)),
    ("8", Skill(name: "Rockbiter Weapon", text: "15 Mana Instant Imbue the Shaman's weapon, increasing melee attack power by 45 Lasts for 60 minutes.", cast: nil, rank: 1)),
]
