// The goal planner: a utility ranking over what the world model and the knowledge files say is
// possible, with the owner's rules as explicit terms. Deterministic. The judge breaks near-ties only.
// Pure Foundation. Linux and macOS.
import Foundation

enum GoalKind: String, Equatable, CaseIterable {
    case handIn, accept, hunt, useAt, road, train, sell, explore
}

struct GoalCandidate: Equatable {
    var kind: GoalKind
    var subject: String        // the quest's title, the giver's name, the NPC's name
    var distance: Double?      // y units from the character; nil when unknown
    var utility: Double
    var reasons: [String]      // each term that moved the utility, for the log and for the judge's state
}

/// The owner's rules as numbers. The values are a starting point to tune against the run metrics, not
/// authority: the rules themselves are in learning/knowledge/owner-rules.md.
struct OwnerRules: Equatable {
    var thisZoneFirst = 40.0          // a goal in another zone loses this much (24 Sept)
    var acceptAllQuests = true        // "always accept quests" (24 Sept)
    var surviveFirst = 30.0           // a goal whose place had a recorded danger stop loses this much
    var repeatFailurePenalty = 15.0   // per earlier failure of the same step since it last worked (M4y)
    var roadPreference = 5.0          // a goal reached by road gains this much over a straight walk (24 Sept)
    var sellAtBagItems = 8            // a human empties the bags before they fill (M4u)
    var maxLeg = 12.0                 // one walk; farther is zone travel by road (M4e)
    var huntLevelMargin = 2           // a quest more than this many levels above the character waits

    static let standard = OwnerRules()
}

struct GiverBelief: Equatable {
    var name: String
    var pin: WorldPoint
    var questInLog: Bool  // its tooltip named a quest already in the log: it is that quest's "?", not a giver
}

struct TownServiceBelief: Equatable {
    var name: String
    var role: String  // "vendor" or "trainer"
    var at: WorldPoint
}

struct PlannerInputs: Equatable {
    var quests: [QuestBelief]
    var givers: [GiverBelief]
    var services: [TownServiceBelief]
    var player: WorldPoint?
    var level: Int?
    var bagItems: Int?
    var lastTrainedLevel: Int?
    var pastFailures: [String: Int]     // step key -> failures since it last worked (character memory)
    var dangerStops: [WorldPoint]        // where walks stopped for a hostile (world memory)
    var roadsReach: Set<String>          // quest titles the road graph can route to from here
    var usableItems: [String: String]    // quest title -> item or ability in the bags or on the bar
}

enum GoalPlanner {
    static func stepKey(_ kind: GoalKind, _ subject: String) -> String { "\(kind.rawValue.uppercased()) \(subject)" }

    /// Rank every possible goal. Nothing here is a model call; every term is named in `reasons`.
    static func rank(_ i: PlannerInputs, rules: OwnerRules = .standard) -> [GoalCandidate] {
        var out: [GoalCandidate] = []
        func distance(_ p: WorldPoint?) -> Double? {
            guard let p, let player = i.player else { return nil }
            return player.distance(to: p)
        }
        func common(_ kind: GoalKind, _ subject: String, _ pin: WorldPoint?, base: Double, inZone: Bool) -> GoalCandidate {
            var u = base
            var reasons = ["\(kind.rawValue) base \(Int(base))"]
            let d = distance(pin)
            if let d {
                u -= d
                reasons.append("distance -\(Int(d.rounded()))")
                if d > rules.maxLeg {
                    if i.roadsReach.contains(subject) {
                        u += rules.roadPreference
                        reasons.append("by road +\(Int(rules.roadPreference))")
                    } else {
                        u -= 1000
                        reasons.append("beyond one walk and no road")
                    }
                }
            }
            if !inZone {
                u -= rules.thisZoneFirst
                reasons.append("other zone -\(Int(rules.thisZoneFirst))")
            }
            let fails = i.pastFailures[stepKey(kind, subject)] ?? 0
            if fails > 0 {
                u -= Double(fails) * rules.repeatFailurePenalty
                reasons.append("failed \(fails) time(s) before -\(Int(Double(fails) * rules.repeatFailurePenalty))")
            }
            if let pin, i.dangerStops.contains(where: { $0.distance(to: pin) <= 3 }) {
                u -= rules.surviveFirst
                reasons.append("a walk there stopped for a hostile -\(Int(rules.surviveFirst))")
            }
            return GoalCandidate(kind: kind, subject: subject, distance: d, utility: u, reasons: reasons)
        }
        for q in i.quests {
            let kinds = Set(q.objectives.map(\.kind))
            if q.readyToHandIn || kinds == [.handIn] || kinds == [.talk] {
                out.append(common(.handIn, q.title, q.pin, base: 100, inZone: q.inThisZone))
            } else if let item = i.usableItems[q.title], kinds.contains(.useAt) {
                var c = common(.useAt, q.title, q.pin, base: 70, inZone: q.inThisZone)
                c.reasons.append("uses \(item)")
                out.append(c)
            } else if kinds.contains(.kill) || kinds.contains(.collect) {
                var c = common(.hunt, q.title, q.pin, base: 60, inZone: q.inThisZone)
                if let level = i.level, let ql = q.level, ql > level + rules.huntLevelMargin {
                    c.utility -= 50
                    c.reasons.append("quest level \(ql) above \(level + rules.huntLevelMargin) -50")
                }
                out.append(c)
            } else if kinds.contains(.travel) {
                out.append(common(.handIn, q.title, q.pin, base: 90, inZone: q.inThisZone))
            }
        }
        if rules.acceptAllQuests {
            for g in i.givers where !g.questInLog {
                out.append(common(.accept, g.name, g.pin, base: 80, inZone: true))
            }
        }
        for s in i.services {
            if s.role == "vendor", let n = i.bagItems, n >= rules.sellAtBagItems {
                var c = common(.sell, s.name, s.at, base: 50, inZone: true)
                c.reasons.append("\(n) bag items")
                out.append(c)
            }
            if s.role == "trainer", let level = i.level, level > (i.lastTrainedLevel ?? 0) {
                var c = common(.train, s.name, s.at, base: 75, inZone: true)
                c.reasons.append("level \(level) above last trained \(i.lastTrainedLevel ?? 0)")
                out.append(c)
            }
        }
        return out.sorted { ($0.utility, $0.subject) > ($1.utility, $1.subject) }
    }

    /// The candidates the judge may choose between: the top ones within `margin` of the best, at most three.
    /// One candidate means no call.
    static func tieBreak(_ ranked: [GoalCandidate], margin: Double = 10) -> [GoalCandidate] {
        guard let best = ranked.first else { return [] }
        return Array(ranked.filter { best.utility - $0.utility <= margin }.prefix(3))
    }
}
